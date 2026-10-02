#!/usr/bin/env python3
"""Dependency-free macOS AX inspection and guarded UI primitives.

The CLI is read-only. Task adapters import UI/unique and own all mutations,
page/dialog semantics, duplicate lookup, logging, and reconciliation.
"""

import argparse
import ctypes as C
import json
import math
import os
import re
import subprocess
import sys
import time
from collections import deque
from contextlib import contextmanager


class UIError(RuntimeError):
    pass


class Point(C.Structure):
    _fields_ = [('x', C.c_double), ('y', C.c_double)]


def libraries():
    if sys.platform != 'darwin':
        raise UIError('Native UI access requires macOS')
    cf = C.CDLL('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation')
    ax = C.CDLL('/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices')
    p = C.c_void_p
    signatures = [
        (cf, 'CFStringCreateWithCString', [p, C.c_char_p, C.c_uint32], p),
        (cf, 'CFStringGetCString', [p, C.c_char_p, C.c_long, C.c_uint32], C.c_bool),
        (cf, 'CFGetTypeID', [p], C.c_ulong),
        (cf, 'CFStringGetTypeID', [], C.c_ulong),
        (cf, 'CFBooleanGetTypeID', [], C.c_ulong),
        (cf, 'CFNumberGetTypeID', [], C.c_ulong),
        (cf, 'CFArrayGetTypeID', [], C.c_ulong),
        (cf, 'CFBooleanGetValue', [p], C.c_bool),
        (cf, 'CFNumberGetValue', [p, C.c_int, p], C.c_bool),
        (cf, 'CFArrayGetCount', [p], C.c_long),
        (cf, 'CFArrayGetValueAtIndex', [p, C.c_long], p),
        (cf, 'CFRetain', [p], p),
        (cf, 'CFRelease', [p], None),
        (ax, 'AXIsProcessTrusted', [], C.c_bool),
        (ax, 'AXUIElementCreateApplication', [C.c_int], p),
        (ax, 'AXUIElementSetMessagingTimeout', [p, C.c_float], C.c_int),
        (ax, 'AXUIElementCopyAttributeValue', [p, p, C.POINTER(p)], C.c_int),
        (ax, 'AXUIElementSetAttributeValue', [p, p, p], C.c_int),
        (ax, 'AXValueGetValue', [p, C.c_int, p], C.c_bool),
        (ax, 'CGEventCreateMouseEvent', [p, C.c_uint32, Point, C.c_uint32], p),
        (ax, 'CGEventSetIntegerValueField', [p, C.c_uint32, C.c_int64], None),
        (ax, 'CGEventPost', [C.c_uint32, p], None),
    ]
    for lib, name, args, result in signatures:
        fn = getattr(lib, name)
        fn.argtypes, fn.restype = args, result
    return cf, ax


def process_id(bundle):
    if not re.fullmatch(r'[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)+', bundle):
        raise UIError('Use a literal bundle identifier, not an AppleScript expression')
    script = f'tell application "System Events" to get unix id of first application process whose bundle identifier is "{bundle}"'
    try:
        return int(subprocess.check_output(['osascript', '-e', script], text=True, timeout=10))
    except (subprocess.SubprocessError, ValueError) as error:
        raise UIError(f'Cannot identify the running app {bundle}') from error


def ancestry():
    """Executable names only: never expose command-line arguments/environment."""
    result, pid = [], os.getpid()
    for _ in range(16):
        text = subprocess.check_output(['ps', '-p', str(pid), '-o', 'pid=,ppid=,comm='], text=True, timeout=3).strip()
        if not text:
            break
        fields = text.split(None, 2)
        if len(fields) != 3:
            break
        result.append({'pid': int(fields[0]), 'executable': fields[2]})
        pid = int(fields[1])
        if pid <= 1:
            break
    return result


class Node:
    def __init__(self, ui, ref, parent):
        self.ui, self.ref, self.parent = ui, ref, parent
        self.children, self.alive = [], True
        if parent:
            parent.children.append(self)
        self.role = ui.get(ref, 'AXRole')
        self.title = ui.get(ref, 'AXTitle')
        self.description = ui.get(ref, 'AXDescription')
        self.placeholder = ui.get(ref, 'AXPlaceholderValue')
        self.subrole = ui.get(ref, 'AXSubrole')
        self.enabled = ui.get(ref, 'AXEnabled')
        self.selected = ui.get(ref, 'AXSelected')
        self.protected = (
            self.role == 'AXSecureTextField' or self.subrole == 'AXSecureTextField'
            or ui.get(ref, 'AXProtectedContent') is True
        )
        self.value = None if self.protected else ui.get(ref, 'AXValue')

    def descendants(self):
        pending = list(self.children)
        while pending:
            node = pending.pop()
            yield node
            pending.extend(node.children)


def unique(nodes, **attributes):
    matches = [node for node in nodes if all(getattr(node, key) == value for key, value in attributes.items())]
    if len(matches) != 1:
        raise UIError(f'Expected one control {attributes}; found {len(matches)}')
    return matches[0]


class UI:
    def __init__(self, bundle, window=None):
        self.cf, self.ax = libraries()
        self.keys, self.app, self.window = {}, None, None
        self.windows = []
        try:
            if not self.ax.AXIsProcessTrusted():
                raise UIError('Accessibility access denied. Run --preflight and check the hosting app; no UI input sent')
            self.app = self.ax.AXUIElementCreateApplication(process_id(bundle))
            if not self.app:
                raise UIError('Cannot create the AX application reference')
            self.ax.AXUIElementSetMessagingTimeout(self.app, 0.4)
            refs = self.raw(self.app, 'AXWindows')
            candidates = []
            try:
                if refs and self.cf.CFGetTypeID(refs) == self.cf.CFArrayGetTypeID():
                    for i in range(self.cf.CFArrayGetCount(refs)):
                        ref = self.cf.CFArrayGetValueAtIndex(refs, i)
                        title = self.get(ref, 'AXTitle')
                        self.windows.append(title)
                        if window is not None and title == window:
                            candidates.append(ref)
                    if window is not None:
                        if len(candidates) != 1:
                            raise UIError(f'Expected one window {window!r}; found {len(candidates)}. Available: {self.windows}')
                        self.window = self.cf.CFRetain(candidates[0])
            finally:
                if refs:
                    self.cf.CFRelease(refs)
        except BaseException:
            self.close()
            raise

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self.close()

    def key(self, name):
        if name not in self.keys:
            self.keys[name] = self.cf.CFStringCreateWithCString(None, name.encode('utf-8'), 0x08000100)
        return self.keys[name]

    def raw(self, ref, name):
        result = C.c_void_p()
        code = self.ax.AXUIElementCopyAttributeValue(ref, self.key(name), C.byref(result))
        return result.value if code == 0 else None

    def get(self, ref, name):
        value = self.raw(ref, name)
        if not value:
            return None
        try:
            kind = self.cf.CFGetTypeID(value)
            if kind == self.cf.CFStringGetTypeID():
                buffer = C.create_string_buffer(16384)
                if self.cf.CFStringGetCString(value, buffer, len(buffer), 0x08000100):
                    return buffer.value.decode('utf-8')
            if kind == self.cf.CFBooleanGetTypeID():
                return bool(self.cf.CFBooleanGetValue(value))
            if kind == self.cf.CFNumberGetTypeID():
                number = C.c_int64()
                if self.cf.CFNumberGetValue(value, 4, C.byref(number)):
                    return number.value
            return None
        finally:
            self.cf.CFRelease(value)

    def guard(self):
        if not self.app or not self.window:
            raise UIError('Select an open window before any UI action')
        if self.get(self.app, 'AXFrontmost') is not True:
            raise UIError('Target app lost focus; no further UI input sent')
        if self.get(self.window, 'AXMinimized') is not False:
            raise UIError('Target window is minimized or unreadable; no UI input sent')

    @contextmanager
    def snapshot(self, max_nodes=10000):
        if not self.window:
            raise UIError('Select a window before inspection')
        nodes = []
        pending: deque[tuple[int, Node | None]] = deque([(self.cf.CFRetain(self.window), None)])
        try:
            while pending:
                ref, parent = pending.popleft()
                try:
                    node = Node(self, ref, parent)
                except BaseException:
                    self.cf.CFRelease(ref)
                    raise
                nodes.append(node)
                if len(nodes) > max_nodes:
                    raise UIError('AX node limit exceeded; this is not a complete snapshot')
                children = self.raw(ref, 'AXChildren')
                try:
                    if children and self.cf.CFGetTypeID(children) == self.cf.CFArrayGetTypeID():
                        for i in range(self.cf.CFArrayGetCount(children)):
                            child = self.cf.CFArrayGetValueAtIndex(children, i)
                            pending.append((self.cf.CFRetain(child), node))
                finally:
                    if children:
                        self.cf.CFRelease(children)
            yield nodes
        finally:
            for node in nodes:
                node.alive = False
                self.cf.CFRelease(node.ref)
            for ref, _ in pending:
                self.cf.CFRelease(ref)

    @contextmanager
    def stable(self, ready, validate=None, timeout=8):
        """Retry reads of incomplete UI; never replay a mutation or swallow errors."""
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            self.guard()
            with self.snapshot() as nodes:
                if ready(nodes):
                    if validate:
                        validate(nodes)
                    yield nodes
                    return
            time.sleep(0.15)
        raise UIError('Expected UI remained incomplete; inspect state before resuming')

    def wait(self, predicate, description, timeout=8):
        """Returns no native nodes; reacquire handles for subsequent actions."""
        try:
            with self.stable(predicate, timeout=timeout):
                return
        except UIError as error:
            raise UIError(f'{description}: {error}') from error

    def check_node(self, node):
        self.guard()
        if node.ui is not self or not node.alive:
            raise UIError('Control belongs to another UI or an expired snapshot')
        if self.get(node.ref, 'AXEnabled') is not True:
            raise UIError('Control is disabled or its enabled state is unknown')

    def geometry(self, ref):
        position, size = self.raw(ref, 'AXPosition'), self.raw(ref, 'AXSize')
        point, dimensions = Point(), Point()
        try:
            if not position or not size:
                raise UIError('Control bounds are unavailable')
            if not self.ax.AXValueGetValue(position, 1, C.byref(point)) or not self.ax.AXValueGetValue(size, 2, C.byref(dimensions)):
                raise UIError('Cannot decode control bounds')
            if not all(math.isfinite(v) for v in (point.x, point.y, dimensions.x, dimensions.y)) or dimensions.x <= 0 or dimensions.y <= 0:
                raise UIError('Control has no finite clickable area')
            return point.x, point.y, dimensions.x, dimensions.y
        finally:
            if position:
                self.cf.CFRelease(position)
            if size:
                self.cf.CFRelease(size)

    def mouse(self, kind, center):
        event = self.ax.CGEventCreateMouseEvent(None, kind, center, 0)
        if not event:
            raise UIError('Cannot create mouse event')
        try:
            self.ax.CGEventSetIntegerValueField(event, 1, 1)  # actual single click
            self.ax.CGEventPost(0, event)
        finally:
            self.cf.CFRelease(event)

    def click(self, node):
        self.check_node(node)
        x, y, width, height = self.geometry(node.ref)
        wx, wy, ww, wh = self.geometry(self.window)
        center = Point(x + width / 2, y + height / 2)
        if not (wx <= center.x <= wx + ww and wy <= center.y <= wy + wh):
            raise UIError('Control is outside the target window; no click sent')
        self.mouse(5, center)
        self.guard()
        try:
            self.mouse(1, center)
            time.sleep(0.08)
        finally:
            self.mouse(2, center)  # release even on interruption/focus loss
        self.guard()

    def fill(self, node, text):
        self.check_node(node)
        if node.protected or node.role not in ('AXTextField', 'AXTextArea'):
            raise UIError('Only non-protected text controls may be filled')
        if not isinstance(text, str) or '\x00' in text:
            raise UIError('Expected text without NUL characters')
        value = self.cf.CFStringCreateWithCString(None, text.encode('utf-8'), 0x08000100)
        if not value:
            raise UIError('Cannot allocate text value')
        try:
            code = self.ax.AXUIElementSetAttributeValue(node.ref, self.key('AXValue'), value)
            if code != 0:
                raise UIError(f'AXValue setter unsupported or failed ({code}); no fallback input sent')
        finally:
            self.cf.CFRelease(value)

    def close(self):
        for ref in [self.window, self.app, *self.keys.values()]:
            if ref:
                self.cf.CFRelease(ref)
        self.window, self.app, self.keys = None, None, {}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--preflight', action='store_true', help='Report trust and host ancestry; never grant permissions')
    parser.add_argument('--bundle', help='Exact running app bundle ID')
    parser.add_argument('--window', help='Exact window title; omit to list available windows')
    parser.add_argument('--role', action='append', help='Include only this AX role (repeatable)')
    parser.add_argument('--values', action='store_true', help='Opt in to non-protected value output; avoid sensitive views')
    parser.add_argument('--limit', type=int, default=60)
    args = parser.parse_args()
    if args.limit < 1:
        parser.error('--limit must be positive')
    if args.preflight:
        _, ax = libraries()
        trusted = bool(ax.AXIsProcessTrusted())
        print(json.dumps({'accessibility_trusted': trusted, 'host_ancestry': ancestry()}, indent=2))
        return 0 if trusted else 1
    if not args.bundle:
        parser.error('--bundle is required unless using --preflight')
    with UI(args.bundle, args.window) as ui:
        if args.window is None:
            print(json.dumps({'windows': ui.windows}, ensure_ascii=False))
            return 0
        default_roles = {'AXHeading', 'AXButton', 'AXTextField', 'AXTextArea', 'AXCheckBox', 'AXRadioButton'}
        roles = set(args.role) if args.role else default_roles
        with ui.snapshot() as nodes:
            selected = [node for node in nodes if node.role in roles and not node.protected]
            for node in selected[:args.limit]:
                record = {key: getattr(node, key) for key in ('role', 'title', 'description', 'placeholder', 'enabled', 'selected')}
                if args.values:
                    record['value'] = node.value
                print(json.dumps(record, ensure_ascii=False))
            print(json.dumps({'matched': len(selected), 'shown': min(len(selected), args.limit), 'nodes': len(nodes)}))
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (UIError, subprocess.SubprocessError, OSError) as error:
        print(f'STOPPED: {error}', file=sys.stderr)
        sys.exit(1)
