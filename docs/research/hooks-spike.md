# Spike: `query_kit_hooks` (AP0 of the hooks plan)

**Date:** 2026-10-15. **Plan:** [`docs/plans/hooks-package.md`](../plans/hooks-package.md), AP0.
**Code:** `packages/query_kit_hooks/`, outside the workspace, uncommitted until AP2.
**Upstream:** `query/` at `50680b98c`. **Toolchain:** Flutter 3.41.4 stable,
`flutter_hooks` 0.21.3+1.

The spike was extended after the two plan reviews (Astra H-02, Fable P2-3).
The first cut built only `useQuery`, `useSelectQuery` and `useMutation`. That
was the one set of hooks for which the rebuild rule is trivial, because
`observedState` is `value` there. It now also covers paging flags, a
collection, a combination, direct cache subscriptions and prefetch.

## What was built

The hooks use public API only (plan D4, path A).

| File | Lines | What |
|---|---|---|
| `lib/src/rebuild_rule.dart` | 52 (32 code) | `RebuildRule<T>`: `ReadEntry`'s decision without its ownership. It takes two closures, value and observed state, and has `read()` and `shouldRebuild(buildWhen)` |
| `lib/src/controller_hook.dart` | 100 | One `HookState` shape for every controller-owning hook (D5) |
| `lib/src/use_query.dart` | 74 | `useQuery`, `useSelectQuery` |
| `lib/src/use_infinite_query.dart` | 72 | `useInfiniteQuery`; its observed state is the controller's public `observedState` record (result plus paging flags) |
| `lib/src/use_mutation.dart` | 68 | `useMutation` |
| `lib/src/use_queries.dart` | 166 | `useQueries` and `useCombinedQueries` (D10). The gate is element-wise over `(result, refetch)`, and for the combination over `(CombinedResult, [(isError, refetch)…])` |
| `lib/src/use_counts.dart` | 178 | `useIsFetching` and `useIsMutating`, which are direct cache subscriptions with a generation and disposed guard (D12). Also `useMutationState` over `MutationStateController.setOptions` |
| `lib/src/use_prefetch.dart` | 27 | `usePrefetchQuery`, with an untyped existence check (D11) |

## What was ported

| Suite | Cases | Green | Assertion changed |
|---|---|---|---|
| `useQuery.test.tsx` | 21 (72, 435, 700, 738, 1128, 1185, 1606, 1932, 1956, 2300, 2316, 3763, 3871, 4100, 4447, 4622, 5056, 6068, 6191, 6378, 6570) | 21 | 738 (`buildWhen` for tracked props), 6068 (`retryOnMount: false` for the callback) |
| `useInfiniteQuery.test.tsx` | 2 (48, 180) | 2 | — (the paging flags are read from the controller per build) |
| `useQueries.test.tsx` | 3 (490, 871, 1142) | 3 | 490 partially: upstream's partial-combination output has no counterpart, because `CombinedResult` is pending until every source has data. Two initial builds instead of three; the no-rebuild invariant at the end is kept |
| `useMutation.test.tsx` | 3 (34, 999, 1578) | 3 | — |
| `useIsFetching.test.tsx` | 1 (60) | 1 | — |
| `useMutationState.test.tsx` | 1 (17, `useIsMutating`) | 1 | — |
| own: `hook_specifics_test.dart` | 8 | 8 | — |
| own: `review_reproductions_test.dart` | 6 | 6 | — |

**Total: 45 tests, 45 green (31 ported, 14 of the package's own).** All 45
are green against the committed core and binding (`859fbdc`, binding
1.0.3). The first 44 were also green against the 1.0.4 working tree of the
main checkout; the last specifics case was written after the move to the
worktree.

Several translations are not assertion changes:

- `notifyOnChangeProps: 'all'` is dropped (it is the default here).
- `Error` becomes `StateError`, and `JSON.stringify` becomes a record's
  `toString`.
- Sparse `states[limit]` becomes a map, and `React.useCallback` becomes
  `useCallback`.
- 871's `'pending'` is `CombinedPending`.
- 1142's identity combiner over raw results is plain `useQueries` (review
  H-05).
- 60's children are created in the parent's build. React re-renders a child
  element created anew, and Flutter rebuilds a new widget, but not the same
  instance.

## Measurements

1. **Frame coalescing (D8).** With `advance(ms)` as one `tester.pump(ms)`,
   2 of 21 useQuery cases fail (1932 and 4100), because several timers fall
   inside one step and get one frame between them. With `advance` stepped
   one millisecond per frame, none fail. The only changed build count is
   490's, and D10 changes it by design. React does not render once per
   notification either: it batches (2316 expects two renders for two
   observers). What the stepping mirrors is a render after each timer
   macrotask.
2. **The rule and `adapter.dart`'s surface (D4).** One ownership-free rule,
   32 lines of code, covers every hook. Each hook supplies its value and its
   observed state as closures:
   - for `useQuery` and `useMutation`, the value;
   - for `useInfiniteQuery`, the public `observedState` record;
   - for `useQueries`, `useMutationState` and the combination, an
     element-wise wrapper the hook package defines.

   Nothing hidden is needed: `BuildWhen` is exported, and `observedState`
   is a public getter. `ObservedState` and `observedStateOf` are not needed
   at all, and neither is `ReadEntry`, which owns and disposes its
   controller (H-06). If `adapter.dart` is built, its whole surface is
   `RebuildRule`.
3. **`select` double run (4447).** Not observed through the hook: 1, 2 and
   3 runs, as upstream. No core ticket.
4. **Update between create and subscribe (6191).** Not missed: the hook
   subscribes in the same build that creates the observer.
5. **+1 build.** None. Case 72 records 2 builds, as upstream does. Equal
   options rebuilt three times by a parent add exactly three builds and no
   fetch. New filter objects and a new `select` on every build add no build
   either (`hook_specifics_test.dart`, last case).
6. **Teardown.** No pending timer and no "setState during build" in 45
   tests.
7. **Combined gate (Astra H-01).** Reproduced as a test. Two sources fail,
   then the second is repaired by `setQueryData`. The `CombinedResult` stays
   equal (`CombinedError` with the first error), but `retry` would act on
   fewer sources. With the action key the hook rebuilds, and `retry` leaves
   the repaired source alone. **Negative control:** with the gate on the
   value alone, the test fails (2 builds where 3 are expected).
8. **Queued count delivery after disposal (Astra H-03).** Reproduced as a
   test. A sibling's build starts a fetch, so the provider defers the
   delivery past the frame. In that frame the probe throws before
   `useIsFetching`, and `flutter_hooks` disposes it while the element stays
   mounted. **Negative control:** without the generation and disposed guard,
   the late delivery's `setState` rebuilds the element (3 builds where 2 are
   expected).
9. **A throw before a hook (Astra H-04).** Measured for a pending mutation
   and for a fetch that consumed its signal:
   - The mutation runs on and its options' `onSuccess` runs. The per-call
     `onSuccess` is dropped, and the replacement hook starts idle while the
     cache holds the mutation as a success.
   - The fetch is cancelled and reverted (pending, idle), and the next build
     fetches again.
   - A throw after the last hook keeps every hook
     (`hook_specifics_test.dart`).
10. **Untyped prefetch check (Fable P2-1).** Reproduced:
    `client.getQueryState<dynamic>(key)` throws `QueryDataTypeError` once
    the entry exists. That is what the plan's first spelling would have
    called on the second build. `queryCache.find(…exact)` does not throw,
    and the prefetch fetches once.
11. **`MutationStateController` with changing filters (Fable P2-2).** Not
    reproduced. The controller has `setOptions({filters, select})`, and the
    hook calls it on every build without a new subscription or an extra
    build.
12. **Lifecycle.**
    - A `GlobalKey` move keeps the observer.
    - Hot reload (`reassembleApplication`) keeps the observer and fetches
      nothing.
    - A client switch through the provider re-creates the observer.
    - `client:` works without a provider.
    - Unmount releases the observer.

**Not measured:** the Flutter 3.27.4 floor, which resolves `flutter_hooks`
0.21.2 because 0.21.3+1 requires Flutter 3.32 (review P3-3), and
compiled-to-JavaScript runs. Both are AP2's CI work.

## Verdict

**Go**, by the revised gate (plan, AP0):

- Every behavioural invariant passes, 45 of 45.
- No hidden API is needed.
- No timer or build assertion is left.
- The adaptation share is 3 of 31 ported cases with a changed assertion
  (738, 6068, 490), and one changed build count (490, by D10).
