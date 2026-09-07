# Logic Prototype

Build a single self-contained HTML file that lets anyone drive a state model by clicking buttons. Use this when the question is about business logic, state transitions, or data shape. The demo should be shareable with a designer, PM, or domain expert without installing anything.

## Good Fit

- "Does this state machine handle X then Y?"
- "Can this data model represent this edge case?"
- "What should the interface feel like before writing it?"
- Any case where someone should press buttons and watch state change.

If the question is visual, use [ui.md](ui.md).

## Process

### 1. State The Question

Before writing code, write a visible intro at the top of the demo:

- What state model is being prototyped
- What question the prototype answers

Use domain language, not implementation terms. Someone returning to the demo later should understand what they are evaluating.

### 2. Isolate Portable Logic

Put the logic in an inline script as a small pure module that could be lifted or translated into the real codebase later. The page is throwaway; the validated logic is the part worth retaining.

Good shapes:

- Pure reducer: `(state, action) => state`
- Explicit state machine
- Small pure function set over a plain data type
- Class/module with clear method surface when ongoing internal state is load-bearing

Keep logic independent of the page: no DOM, I/O, or logging for control flow. Button handlers call its interface, never reach into its internals. If the production runtime differs, treat the demo as a model of behavior, not proof that production code works.

### 3. Build The Shareable File

Use plain HTML/CSS/JavaScript, all inline. No framework, bundler, external assets, CDN, or server. It must work when opened directly as a local file.

Lay it out in this order:

1. **Title and explanation** of the question.
2. **Current state**, shown as readable labelled fields, not a raw JSON dump. Re-render after each action and call out important changes.
3. **Free-play buttons**, one per action, so the recipient can explore in any order.
4. **Guided walkthroughs**, one scenario per tab. Explain the setup and what to watch for, then provide ordered buttons that perform real actions and advance the walkthrough. Starting a walkthrough resets to a known state.

Both free play and walkthroughs use the same logic interface. Show why an illegal action is rejected without corrupting state. If free play invalidates a walkthrough's setup, restart it rather than pretending its steps still apply.

Include a happy path, a tricky edge case, and an attempted illegal action. Keep the presentation restrained: clear typography, spacing, and one accent color. State and actions matter more than polish.

### 4. Hand It Over

Give the user the absolute file path and open it if appropriate. They should be able to double-click it and explore without a run command. Use synthetic data; a shareable file must not embed credentials or private production data.

Adjust actions or scenarios as feedback exposes mistaken assumptions in the model.

### 5. Capture The Answer

Follow the cleanup rules in [Prototype Build](../SKILL.md): record the question and answer durably, then delete or absorb the prototype. Lift or translate the validated logic into real code; do not preserve a prototype-only branch or ship the HTML shell.

## Anti-Patterns

- Adding a test suite to a throwaway demo
- Wiring to a real database unless persistence is the question
- Generalizing beyond one question
- Mixing domain logic and DOM manipulation
- Requiring a framework, build step, server, or network access to open the file
- Shipping the HTML shell as production code
