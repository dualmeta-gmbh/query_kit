# Deepening

How to deepen a cluster of shallow modules safely, given its dependencies. Uses the vocabulary of [SKILL.md](SKILL.md): module, interface, seam, adapter.

## Dependency categories

Classify each dependency of the candidate. The category decides how the deepened module is tested across its seam.

### 1. In-process

Pure computation and in-memory state. Nearly all of `packages/query_kit` is here: the caches, observers, retryer, structural sharing, keys. Merge and test through the new interface; no adapter. Time counts as in-process because it is already behind a zone seam (`clock.now()`, `Timer`), with `fake_async` as the test adapter (`packages/query_kit/test/test_utils.dart`).

### 2. Local-substitutable

A dependency with a local stand-in that runs in the suite. The examples' backends are this: the showcase has a dio fake and an express server, and `backend_contract_test.dart` runs the same cases against both; the task manager the same with fourteen shared cases plus one fake-only `close()` case, the server group skipped unless `TASK_MANAGER_SERVER` is set (`examples/task_manager/test/backend_contract_test.dart`). The stand-in is kept honest by the contract test: map #49 found drifts between fakes and the servers they stood in for, ten as `CLAUDE.md` counts them (PORTING_NOTES, "C57", "C58", where each is enumerated). A deepening that touches a fake must keep its contract case.

### 3. Remote but owned

Your own service across a network. Only the two example servers (`examples/*/server/`) qualify, and they are already behind a port with two adapters (fake and HTTP). The port lives in the example, not in the packages: a transport adapter belongs with the example that uses it, and the packages' dependency contracts stay as declared ([REPOSITORY.md](REPOSITORY.md), "Decisions already made").

### 4. True external

Flutter itself: the scheduler, element lifecycle, `AppLifecycleListener`, the test binding. The binding does not mock these; it tests against the real `flutter_test` binding with the harness in `packages/query_kit_flutter/test/harness.dart`. Connectivity is the one place a user supplies an adapter (`OnlineStatus`, a stream the provider listens to), because `connectivity_plus` is ruled out as a dependency.

## Seam discipline

- **One adapter means a hypothetical seam, two a real one.** A new abstract interface needs a second adapter or a contract it carries (ownership, substitution in a test, a cache event that names it); adapter count alone neither justifies nor removes a seam. `QueryObserverRef` and `MutationObserverRef` exist for the cache events that name their observer, not as extension points; their docs say implementing them is unsupported.
- **Internal seams stay internal.** A deep module may have private members its own callers use (`ReadSet.sweep` is called from `query_context.dart` and `query_mixin.dart`; widget tests reach it through those readers, not directly). Do not export one because a test wants it; the barrel files are the public interface (REPOSITORY.md, "The public surface since 1.0.0").
- **A seam that already exists is completed, not replaced.** `QueryCacheRef` was an incomplete interface, not a bad seam (PORTING_NOTES, "C54").

## Testing strategy: replace, do not layer, except the ported suites

- The ported suites (the seventeen files in PORTING_NOTES' Status table) test through their modules' interfaces, four of them via `src/` imports, and are not touched by a deepening beyond an import adaptation; [REPOSITORY.md](REPOSITORY.md), "Ported tests stay as ported". If one goes red, the deepening changed behaviour.
- Port-only tests that assert past the interface (a private field through `@visibleForTesting`, an internal event order) are a shape complaint, not waste. A historical regression stays; one is removed only after a test at the new interface asserts the same sequence or contract under the same finding ID, and the PORTING_NOTES row says what the old assertion pinned and why nothing unique is lost. Line coverage (CI holds 99.8 % core, 99.7 % binding) does not show that; reading the two assertions does.
- New tests go at the deepened interface and assert observable outcomes. A test that must change when the implementation changes is testing past the interface.
- A rule with several shapes gets a table, not a case: `packages/query_kit_flutter/test/reader_shapes_test.dart` asks the same three questions of ten reader shapes after four kinds of frame because each earlier fix was proven on one shape and broke the next.
