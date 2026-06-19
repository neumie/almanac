# Deepening

How to deepen a cluster of shallow modules safely, given its dependencies. Assumes the vocabulary in `codebase-design`: **module**, **interface**, **seam**, **adapter**.

## Dependency Categories

### In-Process

Pure computation, in-memory state, no I/O. Always deepenable: merge modules and test through the new interface directly. No adapter needed.

### Local-Substitutable

Dependencies with local test stand-ins: PGLite for Postgres, in-memory filesystem, local fake clock. Deepenable if the stand-in exists. Test the deepened module with the stand-in running in the test suite. The seam can remain internal.

### Remote But Owned

Your own services across a network boundary. Define a port at the seam. The deep module owns logic; transport is injected as an adapter. Tests use an in-memory adapter. Production uses HTTP, gRPC, queue, or similar adapter.

Recommendation shape:

> Define a port at the seam, implement a production adapter and an in-memory test adapter, so logic sits in one deep module even though deployment crosses a network.

### True External

Third-party services you do not control. The deepened module takes the external dependency as an injected port. Tests provide a mock adapter.

## Seam Discipline

- One adapter means a hypothetical seam. Two adapters means a real seam.
- Internal seams may exist inside a deep module; do not expose them through the external interface because tests use them.
- If a proposed seam has only one concrete adapter and no expected variation, it is likely indirection.

## Testing Strategy

Replace; do not layer.

- Old unit tests on shallow modules become waste once tests exist at the deepened interface.
- Write new tests at the deepened module's interface.
- Assert observable outcomes through the interface, not internal state.
- Tests should survive internal refactors. If a test changes when implementation changes, it tests past the interface.
