# Logic Prototype

Build a tiny interactive terminal app that lets the user drive a state model by hand. Use this when the question is about business logic, state transitions, or data shape.

## Good Fit

- "Does this state machine handle X then Y?"
- "Can this data model represent this edge case?"
- "What should the API feel like before writing it?"
- Any case where user should press buttons and watch state change.

If the question is visual, use `references/ui.md`.

## Process

### 1. State The Question

Before writing code, write one paragraph in the prototype README or top-of-file comment:

- What state model is being prototyped
- What question the prototype answers

### 2. Pick The Language

Use the host project's runtime and conventions. If the project has no obvious runtime, ask.

### 3. Isolate Portable Logic

Put the actual logic behind a small pure interface that could be lifted into real code later. The terminal shell is throwaway; logic should not be.

Good shapes:

- Pure reducer: `(state, action) => state`
- Explicit state machine
- Small pure function set over a plain data type
- Class/module with clear method surface when ongoing internal state is load-bearing

Keep logic pure: no I/O, no terminal code, no logging for control flow.

### 4. Build Small TUI

Build the lightest terminal UI that exposes state:

1. Initialize one in-memory state object.
2. Render current state and keyboard shortcuts.
3. Read one key or line.
4. Dispatch to a handler.
5. Re-render full frame.
6. Loop until quit.

Use native ANSI escape codes if useful. Avoid adding dependencies unless project already uses one.

### 5. Make It Runnable

Add one command to existing task runner (`package.json`, `Makefile`, `justfile`, `pyproject.toml`). If no runner exists, put the command at top of the prototype README.

### 6. Capture The Answer

When prototype answers its question, record the answer and delete or absorb the prototype.

## Anti-Patterns

- Adding tests
- Wiring to real DB unless persistence is the question
- Generalizing beyond one question
- Mixing logic and TUI
- Shipping the TUI shell
