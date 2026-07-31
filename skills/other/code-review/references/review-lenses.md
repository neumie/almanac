# Review Lens Contracts

Apply these contracts only to the reviewed patch and behavior it changes. Inspect enough surrounding code to establish impact, but do not turn the review into a whole-codebase audit.

## Shared Finding Bar

Report a finding only when all are true:

1. The patch introduces the problem or materially worsens it.
2. The reviewer can point to an exact changed location, or to a cited requirement that the patch fails to implement.
3. There is a concrete demonstration: a breaking input or repro, a traceable data/control-flow path, a failing check, or a cited repository/design criterion violation.
4. The consequence is material and the recommendation is actionable.

Do not report generic hardening advice, personal style preferences, speculative future requirements, or issues already emitted by a formatter/linter/type checker. A missing test is a finding only when it leaves materially risky changed behavior unverified.

## Severity

- **P0 — Critical:** exploitable critical vulnerability, irreversible data loss, broad outage, or another issue that makes the change unsafe to merge or deploy immediately.
- **P1 — High:** likely user-facing incorrectness, authorization/security failure, reliability failure, breaking contract, or missing core requirement. Blocks merge.
- **P2 — Medium:** concrete but non-immediate architecture, test, performance, compatibility, or operability risk that should be corrected.
- **P3 — Low:** small, concrete, worthwhile issue. Never use P3 for a pure preference or optional cleanup.

Set confidence to **High**, **Medium**, or **Low**. Low-confidence findings still need evidence and must say what information is missing.

## Finding Format

```md
### [P1] Imperative, specific title
- **Location:** `path/to/file.ext:line` (or cited missing requirement)
- **Confidence:** High | Medium | Low
- **Evidence:** changed code plus repro, input, trace, failed check, or violated criterion
- **Impact:** concrete user, system, security, or maintenance consequence
- **Recommendation:** smallest directionally correct fix; do not implement it
```

Return `No findings` when nothing clears the bar. Do not invent a finding to fill a lens.

## Behavior Contract

Check:

- **Spec conformance:** missing, partial, or incorrectly implemented requirements; behavior the spec did not request; acceptance criteria contradicted by the patch.
- **Functional correctness:** wrong conditions, state transitions, calculations, ordering, defaults, serialization, time/date handling, and stale or inconsistent state.
- **Inputs and invariants:** empty, null, malformed, duplicate, boundary, maximum-size, and out-of-order inputs; invariants before and after mutations.
- **Failure behavior:** error propagation, cleanup, partial failure, atomicity, transactions, idempotency, retries, timeouts, cancellation, and resource lifetime.
- **Concurrency:** races, lost updates, double execution, unsafe shared state, deadlocks, and retry amplification where concurrent execution is plausible.

When no spec exists, do not infer product requirements. Review observable correctness and reliability, then record spec conformance as unverified.

## Architecture Contract

Follow the `codebase-design` skill rather than redefining its module/interface/seam principles here. Apply them to the changed design and check:

- whether changed interfaces hide or leak invariants, error modes, configuration, ordering, or performance constraints;
- whether seams represent real variation and adapters preserve dependency direction, rather than adding pass-through indirection;
- coupling, cohesion, locality, layering, cycles, fan-out, and the blast radius future changes would inherit;
- alignment with `CONTEXT.md`, ADRs, documented dependency rules, and established domain language;
- testability through the same interface callers use, without exposing internals solely for tests;
- repository standards and changed-code maintainability.

Use Fowler smells only as judgement-call labels: **Mysterious Name, Duplicated Code, Feature Envy, Data Clumps, Primitive Obsession, Repeated Switches, Shotgun Surgery, Divergent Change, Speculative Generality, Message Chains, Middle Man,** and **Refused Bequest**. A documented repository decision overrides the smell baseline. Report a smell only when its concrete maintenance cost is visible in the patch.

## Security Contract

Trace assets, actors, entry points, trust boundaries, and changed data/control flow. Check applicable areas:

- **Authentication and session handling:** identity binding, token/session lifetime, rotation, revocation, cookie attributes, and fail-closed behavior.
- **Authorization and isolation:** operation-level and object-level checks, tenant boundaries, role/ownership changes, confused-deputy paths, and privilege escalation.
- **Input and execution sinks:** SQL/command/template injection, XSS, path traversal, SSRF, unsafe redirects, unsafe deserialization, file uploads, and output encoding.
- **Browser and API controls:** CSRF, CORS, origin assumptions, replay, rate limits, pagination/resource bounds, and mass assignment.
- **Secrets and cryptography:** committed or logged secrets, insecure randomness, home-grown crypto, key handling, and unsafe algorithm/mode changes.
- **Privacy:** collection, storage, transport, caching, telemetry, logs, retention, and deletion of personal or sensitive data.
- **Supply chain and configuration:** new dependencies, risky install/build hooks, integrity/version changes, excessive infrastructure permissions, exposed services, and insecure defaults.
- **Abuse and availability:** attacker-controlled fan-out, unbounded work or allocation, amplification, lockout bypass, and denial-of-service paths.

A security finding needs a traceable attack or data-exposure path and must name the violated trust assumption. Missing generic hardening without such a path belongs in residual risk, not findings.

## Verification & Operations Contract

Check applicable areas:

- **Tests:** changed behavior, acceptance criteria, regressions, boundaries, negative/error paths, concurrency where relevant, meaningful assertions, and tests through public interfaces rather than implementation details. Flag excessive mocking only when it allows a concrete defect to pass.
- **Compatibility:** public APIs, schemas, events, stored data, migrations, configuration, command-line behavior, version skew, deprecation, and downstream callers.
- **Delivery safety:** migration ordering, mixed-version operation, feature flags, rollout sequencing, rollback, backfills, and failure recovery.
- **Performance and scale:** algorithmic growth, N+1 I/O, missing pagination/indexes, blocking work, repeated parsing/allocation, oversized payloads, cache correctness, and bounded resource use.
- **Operability:** actionable errors, logs without sensitive data, metrics, traces, audit events, health signals, alertability, timeout/retry configuration, and diagnosability of partial failure.
- **User interfaces, when changed:** keyboard and assistive-technology semantics, focus management, labels, loading/empty/error states, responsive behavior, and localization assumptions.

Prefer measured or code-path evidence. A theoretical micro-optimization, generic request for more logs, or blanket demand for higher coverage is not a finding.
