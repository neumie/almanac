# Design It Twice

Use this parallel sub-agent pattern when the user wants alternative interfaces for a chosen deepening candidate. The first idea is rarely best.

## Process

### 1. Frame The Problem Space

Before spawning sub-agents, write a user-facing explanation of the chosen candidate:

- Constraints the new interface must satisfy
- Dependencies it relies on and their category from `references/deepening.md`
- A rough illustrative code sketch to ground constraints, not a proposal

Show this to the user, then proceed. The user can read while sub-agents work.

### 2. Spawn Sub-Agents

Spawn at least three sub-agents in parallel. Each must produce a radically different interface for the deepened module.

Prompt each sub-agent with a separate technical brief: file paths, coupling details, dependency category, what sits behind the seam, project domain vocabulary, and `codebase-design` vocabulary.

Give each agent a distinct design constraint:

- Minimize interface: aim for 1-3 entry points, maximize leverage per entry point.
- Maximize flexibility: support many use cases and extension.
- Optimize for common caller: make the default case trivial.
- Design around ports and adapters when cross-seam dependencies matter.

Each sub-agent outputs:

1. Interface: types, methods, params, invariants, ordering, error modes
2. Usage example
3. What implementation hides behind the seam
4. Dependency strategy and adapters
5. Trade-offs: where leverage is high, where thin

### 3. Present And Compare

Present designs sequentially, then compare by **depth**, **locality**, and **seam placement**.

Give a recommendation. If elements combine well, propose a hybrid. Be opinionated; the user wants a strong read, not a menu.
