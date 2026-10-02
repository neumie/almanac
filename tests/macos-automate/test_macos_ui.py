import importlib.util
import io
import sys
import unittest
from contextlib import contextmanager, redirect_stdout
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

HELPER = Path(__file__).resolve().parents[2] / 'skills/productivity/macos-automate/scripts/macos_ui.py'
SPEC = importlib.util.spec_from_file_location('macos_ui', HELPER)
assert SPEC is not None and SPEC.loader is not None
M = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(M)


def node(**kwargs):
    values = dict(role='AXButton', title='Save', description='', protected=False, value=None,
                  placeholder=None, enabled=True, selected=False, children=[], alive=True, ref=4)
    values.update(kwargs)
    return SimpleNamespace(**values)


def bare_ui():
    ui = M.UI.__new__(M.UI)
    ui.app, ui.window, ui.keys = 1, 2, {}
    ui.cf, ui.ax = Mock(), Mock()
    ui.get = Mock(side_effect=lambda ref, key: {'AXFrontmost': True, 'AXMinimized': False, 'AXEnabled': True}.get(key))
    return ui


class Selectors(unittest.TestCase):
    def test_exact_selector(self):
        target = node()
        self.assertIs(M.unique([target, node(title='Cancel')], role='AXButton', title='Save'), target)

    def test_missing_and_ambiguous_fail(self):
        for nodes in ([], [node(), node()]):
            with self.assertRaises(M.UIError):
                M.unique(nodes, title='Save')

    def test_bundle_rejects_script_injection_without_launch(self):
        with patch.object(M.subprocess, 'check_output') as launch:
            for bundle in ('app', 'com.x" & do shell script "x', 'com.x\n'):
                with self.assertRaises(M.UIError):
                    M.process_id(bundle)
            launch.assert_not_called()

    def test_invalid_pid_is_a_controlled_error(self):
        with patch.object(M.subprocess, 'check_output', return_value='not a pid'):
            with self.assertRaises(M.UIError):
                M.process_id('com.example.app')

    def test_secure_values_are_never_requested(self):
        for state in ({'AXSubrole': 'AXSecureTextField'}, {'AXProtectedContent': True}):
            ui = Mock()
            ui.get.side_effect = lambda ref, name: state.get(name, 'AXTextField' if name == 'AXRole' else None)
            result = M.Node(ui, 4, None)
            self.assertTrue(result.protected)
            self.assertIsNone(result.value)
            self.assertNotIn((4, 'AXValue'), [call.args for call in ui.get.call_args_list])


class Safety(unittest.TestCase):
    def test_focus_and_window_state_fail_closed(self):
        for bad_key, bad_value in (('AXFrontmost', False), ('AXFrontmost', None), ('AXMinimized', True), ('AXMinimized', None)):
            ui = bare_ui()
            ui.get.side_effect = lambda ref, key: bad_value if key == bad_key else {'AXFrontmost': True, 'AXMinimized': False}.get(key)
            with self.assertRaises(M.UIError):
                ui.guard()

    def test_expired_foreign_and_unknown_enabled_controls_fail(self):
        ui = bare_ui()
        for candidate in (node(ui=ui, alive=False), node(ui=object())):
            with self.assertRaises(M.UIError):
                ui.check_node(candidate)
        ui.get.side_effect = lambda ref, key: {'AXFrontmost': True, 'AXMinimized': False, 'AXEnabled': None}.get(key)
        with self.assertRaises(M.UIError):
            ui.check_node(node(ui=ui))

    def test_click_uses_live_center_and_releases_on_interrupt(self):
        ui = bare_ui()
        ui.geometry = Mock(side_effect=[(20, 30, 80, 40), (0, 0, 400, 300)])
        seen = []

        def mouse(kind, center):
            seen.append((kind, center.x, center.y))
            if kind == 1:
                raise KeyboardInterrupt()

        ui.mouse = mouse
        with self.assertRaises(KeyboardInterrupt):
            ui.click(node(ui=ui))
        self.assertEqual(seen, [(5, 60, 50), (1, 60, 50), (2, 60, 50)])

    def test_off_window_control_sends_no_input(self):
        ui = bare_ui()
        ui.geometry = Mock(side_effect=[(500, 500, 80, 40), (0, 0, 400, 300)])
        ui.mouse = Mock()
        with self.assertRaises(M.UIError):
            ui.click(node(ui=ui))
        ui.mouse.assert_not_called()

    def test_native_mouse_event_is_a_single_click_and_released(self):
        ui = bare_ui()
        ui.ax.CGEventCreateMouseEvent.return_value = 42
        ui.mouse(1, M.Point(30, 40))
        ui.ax.CGEventSetIntegerValueField.assert_called_once_with(42, 1, 1)
        ui.ax.CGEventPost.assert_called_once_with(0, 42)
        ui.cf.CFRelease.assert_called_once_with(42)

    def test_fill_is_unicode_and_releases_on_unsupported_setter(self):
        ui = bare_ui()
        ui.cf.CFStringCreateWithCString.return_value = 42
        ui.ax.AXUIElementSetAttributeValue.return_value = -25205
        with self.assertRaises(M.UIError):
            ui.fill(node(ui=ui, role='AXTextField'), 'Žluťoučký tým')
        self.assertEqual(ui.cf.CFStringCreateWithCString.call_args_list[0].args[1], 'Žluťoučký tým'.encode('utf-8'))
        ui.cf.CFRelease.assert_called_once_with(42)
        ui.ax.CGEventPost.assert_not_called()

    def test_fill_rejects_protected_fields_and_nul(self):
        ui = bare_ui()
        for candidate, text in ((node(ui=ui, role='AXTextField', protected=True), 'text'), (node(ui=ui, role='AXButton'), 'text'), (node(ui=ui, role='AXTextField'), 'x\x00y')):
            with self.assertRaises(M.UIError):
                ui.fill(candidate, text)
        ui.cf.CFStringCreateWithCString.assert_not_called()

    def test_close_is_idempotent(self):
        ui = bare_ui()
        ui.keys = {'role': 3}
        ui.close()
        ui.close()
        self.assertEqual([call.args[0] for call in ui.cf.CFRelease.call_args_list], [2, 1, 3])


class ReadWaits(unittest.TestCase):
    def test_incomplete_reads_retry_and_validate_once(self):
        ui = bare_ui()
        ui.guard = Mock()
        reads = iter([[], [node()]])

        @contextmanager
        def snapshot():
            yield next(reads)

        ui.snapshot = snapshot
        validate = Mock()
        with patch.object(M.time, 'sleep'):
            with ui.stable(bool, validate) as nodes:
                self.assertEqual(len(nodes), 1)
        validate.assert_called_once()
        self.assertEqual(ui.guard.call_count, 2)
        ui.ax.CGEventPost.assert_not_called()

    def test_unsafe_semantic_state_is_not_retried(self):
        ui = bare_ui()
        ui.guard = Mock()

        @contextmanager
        def snapshot():
            yield [node()]

        ui.snapshot = snapshot
        validate = Mock(side_effect=M.UIError('Wrong destination'))
        with self.assertRaisesRegex(M.UIError, 'Wrong destination'):
            with ui.stable(bool, validate):
                self.fail('Must not yield unsafe state')
        validate.assert_called_once()

    def test_wait_returns_no_handles(self):
        ui = bare_ui()
        ui.guard = Mock()

        @contextmanager
        def snapshot():
            yield [node()]

        ui.snapshot = snapshot
        self.assertIsNone(ui.wait(lambda nodes: nodes[0], 'ready'))

    def test_wait_error_names_the_postcondition(self):
        ui = bare_ui()
        with self.assertRaisesRegex(M.UIError, 'saved record'):
            ui.wait(bool, 'saved record', timeout=0)
        ui.ax.CGEventPost.assert_not_called()

    def test_snapshot_handles_expire_and_references_are_released(self):
        ui = bare_ui()
        ui.cf.CFRetain.side_effect = lambda ref: ref
        ui.cf.CFGetTypeID.return_value = 'array'
        ui.cf.CFArrayGetTypeID.return_value = 'array'
        ui.cf.CFArrayGetCount.return_value = 1
        ui.cf.CFArrayGetValueAtIndex.return_value = 4
        ui.raw = Mock(side_effect=lambda ref, key: 11 if ref == 2 and key == 'AXChildren' else None)
        with ui.snapshot() as nodes:
            self.assertEqual([n.ref for n in nodes], [2, 4])
            self.assertTrue(all(n.alive for n in nodes))
            self.assertIs(nodes[1].parent, nodes[0])
        self.assertTrue(all(not n.alive for n in nodes))
        self.assertEqual([call.args[0] for call in ui.cf.CFRelease.call_args_list], [11, 2, 4])

    def test_read_timeout_does_not_send_input(self):
        ui = bare_ui()
        with self.assertRaises(M.UIError):
            with ui.stable(bool, timeout=0):
                self.fail('Must not yield')
        ui.ax.CGEventPost.assert_not_called()


class Inspector(unittest.TestCase):
    def test_cli_is_read_only_and_values_are_opt_in(self):
        for show_values in (False, True):
            target = node(role='AXTextField', value='sample text')
            secret = node(role='AXTextField', protected=True, value='must not print')

            class FakeUI:
                def __init__(self, *args):
                    self.windows = ['Main']

                def __enter__(self):
                    return self

                def __exit__(self, *args):
                    pass

                @contextmanager
                def snapshot(self):
                    yield [target, secret]
                # No action methods: any mutation attempted by the CLI fails.

            output = io.StringIO()
            args = ['macos_ui.py', '--bundle', 'com.example.app', '--window', 'Main']
            if show_values:
                args.append('--values')
            with patch.object(M, 'UI', FakeUI), patch.object(sys, 'argv', args), redirect_stdout(output):
                self.assertEqual(M.main(), 0)
            self.assertNotIn('must not print', output.getvalue())
            self.assertEqual('sample text' in output.getvalue(), show_values)


if __name__ == '__main__':
    unittest.main()
