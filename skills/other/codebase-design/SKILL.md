---
name: codebase-design
description: Use when designing module interfaces, seams, deep modules, testability, AI-navigable architecture, or when another skill needs design vocabulary.
metadata:
  upstream: mattpocock/skills/skills/engineering/codebase-design
  upstream-sha: 16620c24528b737408e78d95dd6a0e01a98d3d63
  adapted-date: "2026-06-19"
---

# Codebase Design

Design **deep modules**: lots of behavior behind a small interface, placed at a clean seam, testable through that interface. Use this language wherever code is designed or restructured. Aim for leverage for callers, locality for maintainers, and testability for everyone.

## Glossary

Use these terms exactly. Do not drift into "component", "service", "API", or "boundary" when these terms fit.

**Module**: anything with an interface and an implementation. Scale-free: function, class, package, or tier-spanning slice.

**Interface**: everything a caller must know to use a module correctly: type signature, invariants, ordering constraints, error modes, required config, and performance characteristics.

**Implementation**: code inside a module. Distinct from **adapter**: an adapter is about the role it fills at a seam.

**Depth**: leverage at the interface. A module is **deep** when lots of behavior sits behind a small interface; **shallow** when the interface is nearly as complex as the implementation.

**Seam**: place where behavior can be altered without editing in that place; the location where a module interface lives. Use "seam" instead of "boundary" unless discussing DDD bounded contexts.

**Adapter**: concrete thing satisfying an interface at a seam.

**Leverage**: what callers get from depth: more capability per interface fact they learn.

**Locality**: what maintainers get from depth: change, bugs, knowledge, and verification concentrate in one place.

## Principles

- **Depth is a property of the interface, not the implementation.** A deep module can have internal seams and internal composition; callers still see one small external interface.
- **Deletion test.** Imagine deleting the module. If complexity vanishes, it was pass-through. If complexity reappears across callers, it was earning its keep.
- **The interface is the test surface.** Callers and tests should cross the same seam.
- **One adapter means a hypothetical seam. Two adapters means a real seam.** Do not introduce a seam unless something actually varies across it.

## Designing For Testability

Good interfaces make testing natural:

1. Accept dependencies; do not create them internally.
2. Return results where possible; avoid hidden side effects.
3. Keep surface area small. Fewer methods and params mean simpler callers and tests.

## Going Deeper

- For dependency categories and safe deepening, read `~/.claude/skills/almanac/codebase-design/references/deepening.md`.
- For alternative interface exploration, read `~/.claude/skills/almanac/codebase-design/references/design-it-twice.md`.
