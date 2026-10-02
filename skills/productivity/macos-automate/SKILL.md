---
name: macos-automate
description: Use when automating a macOS app, writing a desktop macro, or bulk-entering data through its UI when no suitable supported API or import is available.
compatibility: macOS and Python 3.10+; UI automation requires user-granted Accessibility access for the hosting application.
---

# macOS Automate

Build a small, app-specific state machine on the bundled native UI helper. Do not reinvent the ctypes bindings, start with blind key sequences, or build a universal macro runner.

## Fast path

1. **Bound the task.** Identify the app, target window/account/library, source data, allowed writes, duplicate key, stop behavior, and observable success. Prefer a supported import/API/CLI if it actually supports the task. Ask only for unresolved consequential choices; writing a macro does not authorize executing unrelated or destructive actions.
2. **Preflight permissions once.** Resolve this skill's directory, then run `python3 <skill-dir>/scripts/macos_ui.py --preflight`. It reports AX trust and the executable ancestry without command-line arguments. The host may be a GUI agent/Electron app behind a detached shell, not the terminal you expected. If denied, ask the user to grant Accessibility access, retry once, then diagnose the actual host instead of repeating permission guesses. Never alter TCC databases, bypass OS permissions, or restart the host/app automatically.
3. **Inspect narrowly.** Run the inspector for the exact bundle ID/window. It performs no clicks, typing, activation, or dictionary writes. Filter roles and limit output. Value output is opt-in; avoid credentials, messages, and unrelated windows. Confirm live names, roles, subroles, placeholders, enabled state, and the actual dialog. Hidden/background controls can still appear in AX; scope actions to the expected page/dialog, not the first matching label anywhere.
4. **Reuse the helper.** Read [the helper API and adapter pattern](references/native-ui.md), then import `UI` and `unique` from `scripts/macos_ui.py`. Keep app-specific selectors and behavior in the task script. Use Python files, not increasingly elaborate shell heredocs, for repeated work.
5. **Pilot before batching.** Validate the source without UI writes. Test one real entry and read it back in the intended library. For bulk entry, also test an existing item and non-ASCII text before the full run. Tell the user when the macro will control the UI; one writer, no competing mouse/keyboard automation.
6. **Execute with checks.** For each item: authoritative duplicate lookup → expected page → expected dialog/options → exact input → one save → semantic read-back → durable per-item log. Use bounded waits for complete read snapshots; never blindly retry a save after a timeout. Stop on lost focus, ambiguous controls, changed destination, unexpected state, or unreadable safety switches. Preserve saved work; do not auto-delete or roll back user data.
7. **Reconcile honestly.** A visible list is not a complete database. Check search/pagination/virtualization before declaring an item missing or safe to re-add. Record `verified`, `already-present`, `unknown-after-submit`, or `failed` separately. Resume only after inspecting the last ambiguous write and checking duplicates across the real library. Report actual counts, validation, and limitations—not just an exit code.

## Native UI rules

- Prefer named AX selectors; `unique` must reject zero or multiple matches. Match the dialog subtree and destination, including personal vs team sharing.
- `AXPress`/`click` can return success without the app changing. Inspect the expected postcondition. If AX activation is ineffective, use `UI.click`, which reads live AX bounds and emits a genuine single click. Never substitute stored screen coordinates.
- `UI.fill` uses `AXValue`, preserving Unicode without changing the clipboard. A successful setter is asynchronous: wait until the field's exact value and the app's submit state agree. If the setter is unsupported, stop and design a scoped keyboard/paste fallback; do not assume modifiers or synthetic typing work.
- AX trees can be incomplete during re-rendering. Retry **reads** with a deadline. Checked options, wrong accounts, disabled controls, or uncertain writes are not transient-read failures.
- Boolean AX attributes can be missing or represented differently across apps. Establish how a switch reports its state; require a known safe state rather than treating `None` as unchecked.
- Keep the target app in front. The helper never activates it or dismisses a modal automatically. Do not suppress the focus guard for convenience.
- Reuse references only inside `with ui.snapshot()` / `with ui.stable(...)`; they are released afterward. Reacquire nodes for later actions. A snapshot/predicate must not leak native handles as a wait result.
- Normal UI automation is not a route to undocumented APIs, app databases, account data, or platform-policy bypasses.

## Installed resource paths

Use the directory symlink, not Claude's single-file command symlink:

- Codex / Pi: `~/.agents/skills/almanac/macos-automate/`
- Claude Code: `~/.claude/skills/almanac/macos-automate/`

Example read-only inspection:

```sh
python3 <skill-dir>/scripts/macos_ui.py --preflight
python3 <skill-dir>/scripts/macos_ui.py --bundle com.example.app
python3 <skill-dir>/scripts/macos_ui.py --bundle com.example.app --window "Main" --role AXHeading --role AXButton --limit 50
```

With `--bundle` alone, the inspector lists available windows. Capture a screenshot only when useful and permitted; Screen Recording is separate from Accessibility. If an element is unavailable, ask for a bounded manual step rather than spending many rounds guessing clicks.

## Delivery

- Keep the task macro and input in the task's own project, not in the generic skill.
- Make mutation opt-in (`--run` or equivalent), with dry-run validation, a small pilot limit, bounded waits, and an append-only per-item audit log that excludes secrets. Long noninteractive runs use the host's labeled background-job facility; UI/event-driven work is not a CPU-build workload.
- State which checks passed, failed, or were not run. Distinguish inspected UI, tested helper mechanics, actual app saves, and untested dictation/business behavior.
- Do not commit, publish, send, share with a team, grant permissions, or launch subagents just because this skill was loaded.

## Proven lesson

A Wispr Flow personal-dictionary import processed 159 terms through the normal UI, preserving Czech accents. Permission belonged to the GUI hosting the detached agent, not the assumed terminal. AX activation returned without opening controls; native mouse events needed click count **1**. Incomplete AX snapshots needed bounded read-only waiting. The final page exposed only the latest **100** rows: the older entries were present via search, so a naive final-list check falsely failed. Do not transplant the app's selectors, limits, or checkbox encoding into other apps as universal facts.
