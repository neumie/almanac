# Native UI helper and task adapters

## Permissions and inspection

Resolve the actual installed directory symlink:

- `~/.agents/skills/almanac/macos-automate` (Codex/Pi)
- `~/.claude/skills/almanac/macos-automate` (Claude Code)

The CLI never activates an app or sends input:

```sh
python3 <skill-dir>/scripts/macos_ui.py --preflight
python3 <skill-dir>/scripts/macos_ui.py --bundle com.example.app
python3 <skill-dir>/scripts/macos_ui.py --bundle com.example.app --window "Main" --role AXTextField --role AXButton --limit 30
```

`--preflight` checks `AXIsProcessTrusted` and prints executable ancestry, not environment or command-line arguments. An ancestor GUI app is a host candidate, not proof of which TCC entry the OS will require. Have the user grant access in Settings and test the actual caller again. A direct link can help when Settings layouts differ:

```sh
open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'
```

Do not claim the link opened a particular screen without observing it. Do not grant permissions, edit TCC, enable remote debugging, or restart a live agent automatically. Screen capture has a separate permission and may fail even when AX works.

Without `--window`, the helper lists available titles. Selecting a window requires exactly one match; for repeated titles, stop and design a stronger selector instead of silently selecting the first. Inspection can read a background window; mutations require the target app in front and the target window non-minimized. Inspect only the relevant app/window. `--values` is opt-in; protected text controls are omitted, but an app may mislabel sensitive content, so do not inspect a credential screen.

## API

Import from the resolved directory, not a copied app-specific macro:

```python
from pathlib import Path
import sys

skill_dir = Path.home() / ".agents/skills/almanac/macos-automate"
# For Claude Code, use ~/.claude/skills/almanac/macos-automate instead.
sys.path.insert(0, str(skill_dir / "scripts"))
from macos_ui import UI, UIError, unique
```

- `with UI(bundle_id, window_title) as ui`: resolves the running process and exact window; closes native references on exit. No activation, launching, or preferences changes.
- `with ui.snapshot() as nodes`: owned AX nodes for that window, including `role`, `title`, `description`, `placeholder`, `subrole`, `value`, `enabled`, `selected`, `protected`, `parent`, and `children`. Nodes may include hidden content. `node.descendants()` helps scope a dialog.
- `unique(nodes, role="AXButton", title="Save")`: rejects missing/ambiguous selectors. Use the form subtree, not the entire app, when labels repeat.
- `with ui.stable(ready, validate=None, timeout=8) as nodes`: rechecks complete read snapshots with a deadline. `ready` is a pure completeness test; `validate` raises for unsafe semantic state. It never retries actions or swallows validation failures.
- `ui.guard()`: requires the target app frontmost and target window known non-minimized. It does not move focus for you.
- `ui.click(node)`: checks a live owned node and current enabled state, computes live bounds inside the selected window, emits mouse move/down/up with click count 1, and always attempts release after a mouse-down attempt. Stops on focus loss. The helper cannot determine whether another modal overlays a control: the adapter must verify page/dialog scope first.
- `ui.fill(node, text)`: sets UTF-8 text through `AXValue` on an enabled, non-protected text control. No clipboard or keyboard fallback. Success means the setter returned, not that React/app state has caught up.
- `ui.wait(predicate, description, timeout=8)`: bounded read-only wait, returns no handles. Reacquire nodes inside a new snapshot for the next action.

Do not retain a `Node` outside its context. Actions on released nodes fail. Do not call `ui.close()` while a snapshot context is still active. The helper does not interpret app accounts, roles, sharing, checked-state encodings, selectors, duplicate rules, success responses, or undo semantics; those belong to the task adapter.

## Adapter pattern

Write only the app-specific transitions. This is a **shape**, not a runnable macro: implement the named predicates and authoritative lookups from inspected UI before execution.

```python
with UI(bundle_id, window_title) as ui:
    for item in validated_source:
        existing = lookup_exact_item_across_library(ui, item.key)
        if existing:
            append_audit(item.key, "already-present")
            continue

        with ui.stable(page_ready, validate_destination) as nodes:
            ui.click(unique(nodes, role="AXButton", title=observed_add_label))

        with ui.stable(form_ready, validate_options_and_destination) as nodes:
            form = observed_dialog_subtree(nodes)
            field = unique(form, role="AXTextField", placeholder=observed_placeholder)
            require_empty_or_approved_value(field)
            ui.fill(field, item.text)

        ui.wait(lambda nodes: exact_value_and_submit_enabled(nodes, item.text),
                "confirm exact input")

        with ui.stable(form_ready, validate_options_and_destination) as nodes:
            form = observed_dialog_subtree(nodes)
            require_exact_input(form, item.text)
            ui.click(unique(form, role="AXButton", title=observed_save_label))

        # Do NOT click Save again on timeout. The write may already have happened.
        verify_exact_saved_item_across_library(ui, item.key)
        append_audit(item.key, "verified")
```

Source validation and dry-run are pure code. Task adapters must bind loop values in deferred callbacks, require opt-in mutation, and support a bounded pilot. Do not infer unchecked from missing AX state. When a control uses a nonstandard encoding, inspect a safe state transition before relying on it. Do not toggle a sensitive option just to experiment.

## Duplicate lookup and reconciliation

A snapshot shows rendered UI, not necessarily all records. Determine the app's behavior **before bulk writes**:

1. Does UI search include older entries? Test an exact known older item.
2. Is matching case-insensitive, accent-sensitive, or substring-based? Inspect exact saved keys, not just nonempty results.
3. Does the UI debounce/filter asynchronously? Wait for the exact query and the corresponding result/loading state; stale results are not proof of absence.
4. If search is unavailable, follow pagination or permitted scrolling to completion. Record coverage; stopping at the first screen is not authoritative.
5. If a complete lookup cannot be established, do not promise resumability or re-add ambiguous items. Return the uncertainty to the user.

Maintain per-item statuses independently of a final visible-row assertion:

- `already-present`: authoritative exact lookup found the record.
- `verified`: the committed record was semantically read back in the intended destination.
- `unknown-after-submit`: Save was sent but persistence could not be established. Reconcile through read-only lookup before any retry.
- `failed`: a precondition/action failed; distinguish whether a submit may have occurred.

A save can succeed before a dialog disappears or an AX tree stabilizes. A successful click/setter is not evidence of persistence. A final list with only 100 rows is not evidence that 59 previously verified items vanished. Preserve logs, check search/pagination, and report evidence boundaries. Do not convert a list-limit failure into a duplicate bulk run or claim fresh final verification from earlier logs alone.

## Focused validation

Run helper tests without GUI writes:

```sh
python3 -m unittest discover -s tests/macos-automate -p 'test_*.py'
```

From the Almanac checkout, also run `bash tests/test-skills.sh` and `bash tests/test-structure.sh`. Test commands follow the host's CPU admission policy; UI inspection/automation is event-driven, not a compiler workload.

Use a read-only native smoke inspection for the target app, followed by the explicitly approved task pilot. Pure fixture tests verify helper mechanics, not arbitrary app behavior. No universal keyboard sequence, checkbox encoding, import limit, or success selector is claimed.
