# Inventory: react-query's hook tests, case by case, for a hooks package

- **Date:** 2026-10-15
- **Upstream revision:** TanStack Query `50680b98c` (`query/packages/react-query/src/__tests__/`)
- **Plan:** [`docs/plans/hooks-package.md`](../plans/hooks-package.md)
- **Method:** four read-only research passes, one per slice, each classifying every `it` of its files against `query_kit` and `query_kit_flutter` as they stand (core 1.0.3, binding 1.0.4 in the working tree). Nothing was ported or run.

Verdicts: **P** portable almost verbatim to a widget test over a hook; **A** portable with an adaptation the row names; **N** not applicable (suspense, SSR/hydration, `throwOnError`/error boundaries, TypeScript types, React-only rendering); **G** needs a `query_kit` feature that does not exist. **dup-core** marks a scenario already covered by a core test.

**These are classifications, not measurements.** A verdict is a hypothesis about a case until the case is ported; the porting tickets record where one turned out wrong. Where a slice below suggests how the hook should be implemented (for example through `markMayNeedRebuild`), the plan's decision D4 supersedes it.

| Upstream file | Cases | P | A | N | G |
|---|---|---|---|---|---|
| `useQuery.test.tsx` (lines 1–3600) | 78 | 58 | 9 | 6 | 5 |
| `useQuery.test.tsx` (lines 3601–end) | 77 | 26 | 34 | 8 | 9 |
| `useInfiniteQuery.test.tsx` | 28 | 6 | 22 | 0 | 0 |
| `useQueries.test.tsx` | 24 | 3 | 12 | 3 | 6 |
| `queryOptions.test.tsx`, `infiniteQueryOptions.test.tsx` | 2 | 0 | 0 | 2 | 0 |
| `useMutation.test.tsx` | 61 | 38 | 17 | 4 | 2 |
| `useMutationState.test.tsx` | 5 | 0 | 5 | 0 | 0 |
| `useIsFetching.test.tsx` | 5 | 1 | 4 | 0 | 0 |
| `QueryClientProvider.test.tsx` | 4 | 3 | 1 | 0 | 0 |
| `mutationOptions.test.tsx` | 14 | 11 | 1 | 2 | 0 |
| **Total** | **298** | **146** | **105** | **25** | **22** |

The remaining files (`suspense`, `useSuspense*`, `HydrationBoundary`, `ssr*`, `QueryResetErrorBoundary`, `fine-grained-persister`, `transition`, every `*.test-d.tsx`) are surveyed at the end of the `useInfiniteQuery`/`useQueries` slice; `usePrefetchQuery` and `usePrefetchInfiniteQuery` are the only ones with portable cases.

---

## `useQuery.test.tsx`, part 1: lines 1–3600 (78 cases)

Source: `query/packages/react-query/src/__tests__/useQuery.test.tsx` at `50680b98c`.
Every case sits in `describe('useQuery')`. Cases 2016–2159 are in `describe('notifyOnChangeProps')`, and 2109 and 2159 are one level deeper, in `describe('function')`. This slice has no `it.each`, `it.skip` or `it.only`.

### What a P verdict assumes

A **P** verdict assumes that a `useQuery` hook over `QueryController` does three things:

1. **The first build reads the optimistic value.** `controller.value` before subscribe is already `fetching`.
2. **It calls `setOptions` at the top of every build.** This matches `QueryBuilder`'s reconcile-in-build.
3. **It skips a notification whose value equals what the last build read.** This is the rule in `ReadEntry._shouldRebuild`. `ReadEntry` is not exported, so the hook needs its own copy through `HookState.markMayNeedRebuild` and `shouldRebuild`.

Without (3), every key or option change made in `build` gets one extra identical build. The cause is `NotifyGate`, which compares against the last value it *delivered*. The provider defers notifications raised during a build to a post-frame callback, and when that callback runs the gate sees a moved value.

Test-driver mapping, applied in every row:

| upstream | Flutter |
|---|---|
| `renderWithClient(c, ui)` | `tester.pumpWidget(app(c, ui))` |
| `fireEvent.click(…)` | `tester.tap(…)` + `tester.pump()` |
| `act(() => window.dispatchEvent(visibilitychange))` | `client.focusManager.onFocus()` + `tester.pump()` |
| `mockVisibilityState('hidden')` / restore | `focusManager.setFocused(false)` / `setFocused(true)` |
| `advanceTimersByTimeAsync(0)` | `tester.pump()` |
| `advanceTimersByTimeAsync(n)` | `tester.pump(ms(n))`, split when upstream rendered more than once in the span (see A rows) |
| `setActTimeout(fn, n)` in `useEffect` | `Timer(ms(n), fn)` in `useEffect`, cancelled in the cleanup |
| `rendered.getByText(s)` | `expect(find.text(s), findsOneWidget)` |
| `notifyOnChangeProps: 'all'` | drop it: notifying on every change is the controller's default |

Verdicts:

- **P**: portable almost verbatim.
- **A**: portable with an adaptation.
- **N**: not applicable.
- **G**: needs a query_kit feature that does not exist.

The dup-core column reads as follows:

- **dup-core** means the exact upstream name is in a core suite.
- **near** means a core test with a different upstream name covers the same mechanism, below the hook.

| line | name | verdict | note | dup-core |
|---|---|---|---|---|
| 48 | should allow to set default data value | P | `result.dataOrNull ?? 'default'`; `pump(ms(11))` | |
| 72 | should return the correct states for a successful query | A | Full-result `toEqual` becomes a field-by-field matcher. There is no `isInitialLoading` (deprecated alias). `isLoadingError` exists only on `QueryError`. Timestamps of `0` become `null`, and `error: null` becomes `errorOrNull`. Dart has extra fields (`consecutiveErrorCount`, `failureStackTrace`). `states.length == 2` holds. | |
| 159 | should return the correct states for an unsuccessful query | A | Same reshape as 72. `advance(2)` spans two renders (failureCount 1 at t0, error at t1), so it becomes `pump()` + `pump(ms(1))`. `Error` equality becomes a message matcher. Options: `RetryPolicy.times(1)`, `RetryDelay.fixed(ms(1))`. | |
| 275 | should set isFetchedAfterMount to true after a query has been fetched | P | `await client.query(QueryOptions(...))` as the prefetch; getByText only | |
| 311 | should not cancel an ongoing fetch when refetch is called with cancelRefetch=false if we have data already | P | `useEffect` + two `Timer(ms(5))`; `refetch(cancelRefetch: false)`; `fetchCount == 1`. Deps `[refetch]` hold because the tear-off is `==`. | near: query_client_test (cancelRefetch cases) |
| 346 | should cancel an ongoing fetch when refetch is called (cancelRefetch=true) if we have data already | P | as 311; `fetchCount == 2` | near: query_client_test |
| 381 | should not cancel an ongoing fetch when refetch is called (cancelRefetch=true) if we do not have data yet | P | as 311; a first load is joined, not cancelled | |
| 415 | should be able to watch a query without providing a query function | P | `setQueryDefaults`; explicit type argument (`useQuery<String>`), required by the top-type debug assert | near: query_observer_test 'should be able to watch a query without defining a query function' |
| 435 | should pick up a query when re-mounting with gcTime 0 | P | Drop `'all'`. React `key` becomes `ValueKey`. **Hooks:** keyed swap unmount/remount with `GcTime.duration(Duration.zero)`; the new hook must pick up the old entry. | near: query_test 'queries with gcTime 0 should be removed immediately after unsubscribing' |
| 507 | should not get into an infinite loop when removing a query with gcTime 0 and rerendering | A | `notifyOnChangeProps: ['isPending','isSuccess','data']` can be dropped (counts are the same here) or replaced by `buildWhen`. **Hooks:** `removeQueries` + `setState` bump; `setOptions` in build re-resolves the removed key. Needs dedupe. | |
| 577 | should fetch when refetchOnMount is false and nothing has been fetched yet | P | `RefetchOn.never` | |
| 599 | should not fetch when refetchOnMount is false and data has been fetched already | P | synchronous test; `states.length == 1` | |
| 621 | should be able to select a part of the data with select | P | `QuerySelectOptions` | near: query_observer_test 'should be able to fetch with a selector' |
| 646 | should be able to select a part of the data with select in object syntax | P | body is identical to 621 (historical name) | near: as 621 |
| 671 | should throw an error when a selector throws | P | a throwing select becomes a `QueryError` carrying the thrown error | near: query_observer_test select-error cases |
| 700 | should not re-run a stable select when it re-renders if selector throws an error | P | Stable select comes from flutter_hooks `useCallback` (or a top-level function), because the memo compares with `==`. Rerender is a `useReducer`/`useState` bump. Counts selector runs 1→1→2. **Hooks:** rebuild with unchanged options. | near (inverse): query_observer_test 'should always run the selector again if selector throws an error and selector is not referentially stable' |
| 738 | should track properties and only re-render when a tracked property changes | G | **trackResult (implicit tracked props).** Only `data` is read, so React skips the `isFetching` flip on refetch and has 3 states; the controller would give 4. A variant with `buildWhen: (p, c) => p.dataOrNull != c.dataOrNull` works. | |
| 779 | should always re-render if we are tracking props but not using any | P | Trivially true: no tracking, so every change rebuilds. `useEffect(…, [result])` keys compare with `==`, and value-equal results do not re-run it. | |
| 809 | should be able to remove a query | P | Drop `'all'`. Remove causes no rebuild (upstream and C9 agree); the `setState` bump re-resolves the key. Needs dedupe. | |
| 857 | should create a new query when refetching a removed query | P | Drop `'all'`. `refetch` re-resolves the key (`executeFetch` → `_updateQuery`). `dataUpdatedAt: 0` becomes `null`. | |
| 904 | should share equal data structures between query results | P | Drop `'all'`; `toBe` becomes `identical`. Maps are deep-equal, so they are shared whole. | near: utils_test (replaceEqualDeep) |
| 971 | should use query function from hook when the existing query does not have a query function | P | `StaleTime.infinite`, `InitialData.value` | near: query_test 'should use queryFn from observer if not provided in options' |
| 1005 | should update query stale state and refetch when invalidated with invalidateQueries | P | getByText of data/isStale/isFetching | |
| 1050 | should not update disabled query when refetching with refetchQueries | P | `Enabled.no`; timer at 20 fires inside `pump(ms(31))` | near: query_client_test 'should not refetch if all observers are disabled' |
| 1090 | should not refetch disabled query when invalidated with invalidateQueries | A | The 10 ms `setActTimeout` never fires upstream (no time is advanced). flutter_test fails on a pending timer, so the effect cleanup must cancel it, or the test must drain it. | |
| 1128 | should not fetch when switching to a disabled query | P | **Hooks:** key change and `enabled` flip in one rebuild (`Enabled.no` for count≠0); exactly 3 states. Needs dedupe. | |
| 1185 | should keep the previous data when placeholderData is set | P | `PlaceholderData.keepPrevious()`. **Hooks:** key change through local state; `states[3]` relies on dedupe. | |
| 1248 | should keep the previous data when placeholderData is set and select fn transform is used | P | as 1185 + `QuerySelectOptions` | |
| 1314 | should keep the previous queryKey (from prevQuery) between multiple pending queries when placeholderData is set and select fn transform is used | P | Three `fireEvent` become three tap+`pump()`; `PlaceholderData.compute((prev, prevQuery) …)` | near: query_observer_test 'should pass the correct previous data to placeholderData function params with select' |
| 1365 | should show placeholderData between multiple pending queries when select fn transform is used | P | Three tap+`pump()` give `states[2..4]` | near: query_observer_test 'should use cached selectResult when switching between queries and placeholderData returns previousData' |
| 1446 | should transition to error state when placeholderData is set | A | `rendered.rerender(<Page count={n}/>)` becomes `pumpWidget(app(client, Page(count: n)))`; `RetryPolicy.never`. **Hooks:** key change driven by widget props; 6 exact states. | |
| 1537 | should not show initial data from next query if placeholderData is set | P | `InitialData.value(99)` + keepPrevious; `states[2]` is 99, not placeholder | |
| 1606 | should keep the previous data on disabled query when placeholderData is set | P | Drop `'all'`; tap refetch + `pump()` then `pump(ms(11))`. **Hooks:** disabled + manual refetch + key change; 6 exact states. | |
| 1697 | should keep the previous data on disabled query when placeholderData is set and switching query key multiple times | A | Drop `'all'`. One `advance(51)` spans timers at 20/30/40 plus the fetch (4 renders), so it becomes stepped pumps. **Hooks:** the first build's `refetch` must hit the current key. | |
| 1778 | should use the correct query function when components use different configurations | P | Drop `'all'`. **Hooks:** two widgets on one key; `refetch` runs the caller's `queryFn`. | |
| 1838 | should be able to set different stale times for a query | A | One `advance(200)` spans 4 and 3 renders across two widgets, so it becomes `pump()`, `pump(10)`, `pump(11)`, `pump(90)`. `states1[1]` exists only because the sibling's fetch start notifies First. **Hooks:** per-observer staleTime. | |
| 1932 | should re-render when a query becomes stale | A | `advance(100)` spans 2 renders, so it becomes `pump()` + `pump(ms(51))` | near: query_cache_test 'should notify query cache when a query becomes stale' |
| 1956 | should re-render disabled observers when other observers trigger a query (#8741) | P | `Enabled` computed from `id != null && enabled`. **Hooks:** a parent (disabled) and a child (enabled) switch key in the same frame. The parent sees `fetching` only through the post-frame notification, so expect two `pump()`. | |
| 2016 | should not re-render when it should only re-render only data change and the selected data did not change | G | **notifyOnChangeProps** `['data']` + select; works with `buildWhen` on `dataOrNull` | |
| 2055 | should not re-render when it should only re-render on data changes and the data did not change | G | **notifyOnChangeProps** `['data']`; works with `buildWhen` | |
| 2109 | should not re-render when it should only re-render on data changes and the data did not change | G | **notifyOnChangeProps** as a function; works with a `buildWhen` predicate | |
| 2159 | should not re-render when change props are not actively being tracked | G | **notifyOnChangeProps** function reading a ref (dynamic `'all'`/`[]`). Works with a `buildWhen` that closes over a `useRef` flag; states 2→2→4. | |
| 2263 | should not override initial data in dependent queries | P | **Hooks:** two hooks in one widget, both `Enabled.no` + `InitialData.value` | |
| 2300 | should update query options | P | `client.queryCache.find(filters: …)!.options.retryDelay == RetryDelay.fixed(ms(20))`. **Hooks:** order-sensitive. Each hook must construct, subscribe and `setOptions` in sequence; "construct both, subscribe later" leaves 10. Drain the pending `sleep` timers. | |
| 2316 | should batch re-renders | P | **Hooks:** two hooks, one key; two notifications give one rebuild (frame coalescing). Render counter of 2. Needs dedupe. | |
| 2344 | should render latest data even if react has discarded certain renders | N | react-specific-rendering: guards React's same-state bail-out under useSyncExternalStore. Mechanically portable as a smoke test, but low value. | |
| 2367 | should start with status pending, fetchStatus idle if enabled is false | P | two hooks; `status.name`, `fetchStatus.name` | |
| 2412 | should be in "pending" state by default | P | synchronous test; drain the `sleep` timer | |
| 2429 | should not refetch query on focus when `enabled` is set to `false` | P | `focusManager.onFocus()`; call counter | |
| 2461 | should not refetch stale query on focus when `refetchOnWindowFocus` is set to `false` | P | `RefetchOn.never` | |
| 2492 | should not refetch stale query on focus when `refetchOnWindowFocus` is set to a function that returns `false` | P | `RefetchOn.when((_) => RefetchOn.never)` | near: query_observer_test 'should return false from shouldFetchOnWindowFocus when …' |
| 2523 | should not refetch fresh query on focus when `refetchOnWindowFocus` is set to `true` | P | `StaleTime.infinite`, `RefetchOn.ifStale` | near: query_observer_test shouldFetchOnWindowFocus cases |
| 2554 | should refetch fresh query on focus when `refetchOnWindowFocus` is set to `always` | P | `RefetchOn.always` | near: as above |
| 2590 | should calculate focus behavior for `refetchOnWindowFocus` depending on function | P | `RefetchOn.when((q) => … ? ifStale : never)`. Upstream renders `states[2]` (fetching) only because the mid-test `toMatchObject` read `isFetching` through the proxy and so tracked it. Flutter's notify-all matches. | near: as above |
| 2640 | should refetch fresh query when refetchOnMount is set to always | P | `RefetchOn.always`, `StaleTime.infinite`, prefetch via `client.query` | |
| 2679 | should refetch stale query when refetchOnMount is set to true | P | `RefetchOn.ifStale`, `StaleTime.zero` | |
| 2720 | should set status to error if queryFn throws | P | `RetryPolicy.never`; getByText | |
| 2751 | should throw error if queryFn throws and throwOnError is in use | N | error-boundary/throwOnError (dropped by #15; no ErrorBoundary) | |
| 2785 | should throw error if queryFn rejects with a falsy error and throwOnError is in use | N | error-boundary/throwOnError; Dart cannot `throw null` either | |
| 2814 | should update with data if we observe no properties and throwOnError | N | error-boundary/throwOnError: guards the interaction of `throwOnError` with an empty tracked-props set | |
| 2841 | should set status to error instead of throwing when error should not be thrown | N | error-boundary/throwOnError; without the option this is 2720 | |
| 2873 | should throw error instead of setting status when error should be thrown | N | error-boundary/throwOnError | |
| 2917 | should continue retries when observers unmount and remount while waiting for a retry (#3031) | P | Already steps time. **Hooks:** unmount and remount through a toggle during the retry backoff; `count == 4`. | |
| 2972 | should restart when observers unmount and remount while waiting for a retry when query was cancelled in between (#3031) | P | as 2917 + `cancelQueries` | |
| 3031 | should always fetch if refetchOnMount is set to always | P | `pump()` then `pump(ms(52))`, one render each | |
| 3083 | should fetch if initial data is set | P | `InitialData.value` | |
| 3115 | should not fetch if initial data is set with a stale time | P | `advance(52)` holds only one render | |
| 3147 | should fetch if initial data updated at is older than stale time | A | `advance(52)` spans 2 renders, so it becomes `pump()` + `pump(ms(52))`. `Date.now() - 1000` becomes `clock.now().subtract(…)`. | |
| 3187 | should fetch if "initial data updated at" is exactly 0 | P | `initialDataUpdatedAt: DateTime.fromMillisecondsSinceEpoch(0)` | near: query_test 'should work with initialDataUpdatedAt set to the epoch' |
| 3220 | should keep initial data when the query key changes | P | **Hooks:** key change from an effect `Timer` → `setState`; `InitialData.compute` closes over build-local `count` | |
| 3254 | should keep initialData visible alongside the error when a refetch fails | P | `QueryError.staleData` through `dataOrNull` | |
| 3279 | should retry specified number of times | P | counter instead of `vi.fn` | |
| 3317 | should not retry if retry function `false` | P | `RetryPolicy.when((n, e, s) => …)` | |
| 3362 | should extract retryDelay from error | P | throw a `DelayError(50)`; `RetryDelay.dynamic((n, e) => ms((e as DelayError).delay))` | |
| 3403 | should continue retry after focus regain | P | `setFocused(false)` before mount, `setFocused(true)` later; a `String` thrown as the error | dup-core: query_test.dart (same name, from `query.test.tsx`) |
| 3473 | should fetch on mount when a query was already created with setQueryData | P | | |
| 3504 | should refetch after focus regain | P | Hidden at mount, then `onFocus` + `pump()`, then `pump(ms(11))` (mapping rule); 4 states | |
| 3566 | should refetch if stale after a prefetch | P | prefetch with `staleTime` via `client.query`; two counters | |

### Tally

| verdict | count | lines |
|---|---|---|
| P | 58 | everything else |
| A | 9 | 72, 159, 507, 1090, 1446, 1697, 1838, 1932, 3147 |
| G | 5 | 738, 2016, 2055, 2109, 2159 (all notifyOnChangeProps/trackResult; all work as A with a `buildWhen` on the hook) |
| N | 6 | 2344, 2751, 2785, 2814, 2841, 2873 |

dup-core by exact name: 1 case (3403). Near overlaps below the hook: 19 cases.

---

## `useQuery.test.tsx`, part 2: a hooks-port classification

- **Source:** `query/packages/react-query/src/__tests__/useQuery.test.tsx` at upstream `50680b98c`, lines 3601–7096 (end of file).
- **Cases:** 77 `it(...)`. No `it.each` in this slice (or anywhere in the file).
- **`describe` nesting:** every case is inside `describe('useQuery')`. Four nested groups:
  - `networkMode online`: 11 cases, 5186–5718
  - `networkMode always`: 2 cases, 5788 and 5824
  - `networkMode offlineFirst`: 1 case, 5868
  - `subscribed`: 4 cases, 5921–6031

  In the table, a nested case's name starts with its group and `›`.
- **Shared setup:** `beforeEach` creates a fresh `QueryCache` and `QueryClient` and calls `vi.useFakeTimers()`. `afterEach` calls `queryClient.clear()` and `vi.useRealTimers()`.

### Legend

| Verdict | Meaning |
|---|---|
| **P** | Ports almost verbatim to a `HookWidget` widget test. The scenario and assertions stay the same, apart from Dart syntax and harness helpers that mirror upstream's one to one: `renderWithClient` → `pumpApp`, `mockOnlineManagerIsOnline` → `client.onlineManager.setOnline`, `Blink` → a timer widget, `useMemo`/`useCallback`/`useRef` → the `flutter_hooks` hook of the same purpose. |
| **A** | Ports with an adaptation, which the note names. Any assertion on the number or sequence of renders is an A: what it counts becomes Flutter builds, and these may need stepped pumps. |
| **N** | Not applicable, with a reason category. |
| **G** | Needs a query_kit feature that does not exist. Each feature was checked with a grep of `packages/query_kit/lib` and `packages/query_kit_flutter/lib`. |

**dup-core:** no upstream name in this slice appears in `packages/query_kit/test` or `packages/query_kit_flutter/test`, which is expected because the core keeps query-core's test names. An entry marked "≈" points to a core test that covers the same scenario at the observer or client level.

**Vocabulary checked in the code:**

- **Present:**
  - `Enabled.{yes,no,when}`; `Enabled.no` is also documented as the spelling of `skipToken`.
  - `StaleTime.{duration,infinite,static,dynamic}`
  - `GcTime.{duration,never}`
  - `RetryPolicy.{never,times,always,when}`
  - `RetryDelay.{fixed,exponential,dynamic}`
  - `RefetchOn.{never,ifStale,always,when}`
  - `RefetchInterval.{off,every,dynamic}`. A zero or negative interval means off (`query_observer.dart:580`).
  - `NetworkMode.{online,always,offlineFirst}`
  - `InitialData.{value,compute}`
  - `PlaceholderData.{keepPrevious,value,compute}`
  - Others: `select` (`QuerySelectOptions`), `structuralSharing`, `meta`, `initialDataUpdatedAt`, `refetchIntervalInBackground`, `retryOnMount` (**bool only**), `errorUpdateCount`, `client.query`, `resetQueries`, `cancelQueries`, `setQueryData(updatedAt: DateTime)`.
  - The managers belong to each client (`client.onlineManager`, `client.focusManager`) and `queryCache.onOnline()` exists.
- **Absent:**
  - `notifyOnChangeProps`
  - `throwOnError`
  - the `subscribed` option
  - `experimental_prefetchInRender` and `promise`
  - `queryKeyHashFn`. Keys compare with `==` by design.
  - `skipToken` as a separate value
  - `isRestoring` and `IsRestoringProvider`; `getOptimisticResult` has no `'isRestoring'` mode
  - `retryOnMount` as a callback over the query
  - `dehydrate` and `hydrate`
  - a debug warning for a missing `queryFn`. The fetch fails with `MissingQueryFunctionError` instead.

### Per-case table

| line | name | verdict | note | dup-core |
|---|---|---|---|---|
| 3601 | should not refetch if not stale after a prefetch | P | `client.query(...).ignore()` with `StaleTime.duration(1s)`. The prefetch is still in flight at mount and the hook dedups onto it. | |
| 3635 | should reset failureCount on successful fetch | P | `RetryDelay.fixed(10ms)` with the default retry. `failureReason?.message` needs a Dart error type that has a message. | |
| 3673 | should use prefetched data for dependent query | A | Prefetch inside `useEffect`. Its async `setPrefetched` is safe because it runs after an `await`. The prefetch writes a `String` and the hook's `queryFn` returns an `int` under one key, so both must be typed `Object`; otherwise query_kit's typed cache throws `QueryDataTypeError`. The click is followed by an immediate assertion, so it becomes tap + `pump()`. Hooks-specific: `enabled` changes between builds. | |
| 3726 | should support dependent queries via the enable config option | P | `enabled: shouldFetch ? Enabled.yes : Enabled.no` from `useState`. Hooks-specific: an option changes in the widget's own rebuild. | |
| 3763 | should mark query as fetching, when using initialData | A | Render count 2 becomes build count 2. The first build must already be the optimistic `isFetching: true`, and subscribing must not cause a second build. | |
| 3788 | should initialize state properly, when initialData is falsy | A | Render count 2. `InitialData.value(0)`. Dart has no truthiness, so "falsy" is moot, but "0 seeds" still holds. The `queryFn` is synchronous (`FutureOr`). | ≈ port_specifics_test: 'InitialData.value(null) seeds a nullable query' |
| 3811 | should show the correct data when switching keys with initialData, placeholderData & staleTime | P | `InitialData.compute(() => filter.isEmpty ? all : null)` closes over build-local state; `PlaceholderData.keepPrevious()`. Hooks-specific: the key changes through `useState`. | |
| 3871 | data should persist when enabled is changed to false | A | Render count 3. `enabled` and the `initialData` value both change between builds; the changed `initialData` is ignored because data exists. `isStale` is false for a disabled observer. Hooks-specific. | ≈ query_observer_test: 'should not be stale for disabled observers' |
| 3921 | should support enabled:false in query object syntax | P | Synchronous, with no pump after `pumpWidget`. `queryCache.find(...)` is not null. | ≈ query_observer_test: 'should not trigger a fetch when subscribed and disabled' |
| 3943 | should init to status:pending, fetchStatus:idle when enabled is false | P | | ≈ query_observer_test: 'should not trigger a fetch when subscribed and disabled' |
| 3968 | should not schedule garbage collection, if gcTimeout is set to `Infinity` | A | Dart has no `setTimeout` spy. Use `GcTime.never` and assert behaviour instead: the entry is still cached after a long pump. Flutter's pending-timer check also proves that no gc timer is armed. Hooks-specific: unmount. | ≈ query_client_test: 'should keep a query in cache if garbage collection time is Infinity' |
| 3991 | should schedule garbage collection, if gcTimeout is not set to infinity | A | `setTimeout` spy → assert that the entry is present at 10 min − 1 ms and gone at 10 min after unmount. | ≈ query_test: 'should be garbage collected when unsubscribed to' |
| 4018 | should not cause memo churn when data does not change | P | `React.useMemo` → `useMemoized(fn, [data])`; `flutter_hooks` compares keys with `==`. The test is weak because the data is the string `'data'`. | |
| 4068 | should update data upon interval changes | A | `useEffect(() => { if (data === 2) setInt(0) })`. `flutter_hooks` runs effects synchronously inside `build`, and a `setState` there is dropped because the element is still dirty, so it must be deferred with a post-frame callback or a microtask and get an extra pump. The test never checks that polling stopped. Hooks-specific: `refetchInterval` changes between builds. | |
| 4100 | should refetch in an interval depending on function result | A | **Hard.** One `advance(51)` must yield 6 recorded states at t≈0/10/20/30/40/50. A single `tester.pump(51ms)` builds one frame, so the harness needs stepped pumps of 1 ms or 10 ms. Uses `RefetchInterval.dynamic((q) => ((q.state.data as int?) ?? 0) < 2 ? 10ms : null)`. | ≈ query_observer_test: 'should refetch at the interval returned when refetchInterval is a function' |
| 4165 | should not interval fetch with a refetchInterval of 0 | P | `RefetchInterval.every(Duration.zero)` is treated as off (`<= Duration.zero`). | |
| 4189 | should accept an empty string as query key | A | `QueryKey([''])`; the `queryFn` returns `ctx.queryKey`, so the data type is `QueryKey`. Upstream's `getByText('')` asserts nothing, so assert `jsonEncode(data.parts) == '[""]'` instead. | |
| 4204 | should accept an object as query key | P | `QueryKey([{'a': 'a'}])` and `jsonEncode(data.parts)` gives `[{"a":"a"}]`. | |
| 4219 | should refetch if any query instance becomes enabled | P | Two hooks on one key: a disabled child and a parent whose `enabled` flips. Hooks-specific: two components share a key and an option changes. | ≈ query_client_test: 'should refetch if at least one observer is enabled' (partial: that one goes through `refetchQueries`) |
| 4251 | should use placeholder data while the query loads | A | Recorded states must be exactly 2: `expect(states).toMatchObject([..])` requires the same array length. `PlaceholderData.value('placeholder')`. | ≈ query_observer_test: 'should use placeholderData as non-cache data when pending a query with no data' |
| 4291 | should use placeholder data even for disabled queries | A | **Hard.** `useEffect(() => setCount(1), [])` must re-render before the synchronous `queryFn`'s result is delivered. In React, that delivery is `setTimeout(0)`. In Flutter, the deferred `setCount` and the microtask-delivered data land in the same next frame, so states[1] and states[2] probably merge unless the `queryFn` gets a delay. Hooks-specific: `enabled` flips while the fetch is in flight. | |
| 4352 | placeholder data should run through select | A | Exactly 2 states. `QuerySelectOptions<int, String>` with `PlaceholderData.value(23)`. | ≈ query_observer_test: 'should use placeholderData as non-cache data…' |
| 4393 | placeholder data function result should run through select | A | `rendered.rerender(<Page/>)` → pump a new non-const widget instance; a const one would not rebuild. Exactly 3 states. The `PlaceholderData.compute` closure is new on every build, so it must still run exactly once. | |
| 4447 | select should only run when dependencies change if memoized | P | `React.useCallback(fn, [count])` → `useCallback(fn, [count])`. The exact `selectRun` counts are a **risk**: query_kit keeps separate memos for the preview selection (`getOptimisticResult`) and the committed selection (`query_observer.dart:436-460`). A first build that reads the optimistic value and then subscribes could run `select` twice where upstream runs it once. Hooks-specific: `select` identity changes between builds. | ≈ query_observer_test: 'should run the selector again if the selector changed' |
| 4491 | select should always return the correct state | P | `useCallback` plus a `forceUpdate` (`useState` counter): a rebuild unrelated to the query keeps the selected data. Hooks-specific. | |
| 4541 | select should structurally share data | A | States are recorded by `useEffect([state.data])`. `flutter_hooks` compares keys with `==`, and Dart `List.==` is identity, so the check stays meaningful. An inline `select` closure is new on every rebuild, so it re-runs and `replaceEqualDeep` must keep the instance. | ≈ query_observer_test: 'should structurally share the selector' |
| 4586 | should cancel the query function when there are no more subscriptions | P | `Blink` (a timer that unmounts the child after 5 ms) becomes a harness widget; `signal.addEventListener('abort')` → `ctx.signal.onCancel(...)`. Hooks-specific: unmount mid-fetch disposes the controller. | ≈ query_test: 'should not continue when last observer unsubscribed if the signal was consumed' |
| 4622 | should cancel the query if the signal was consumed and there are no more subscriptions | P | Four instances under `Blink`; `states[limit]` becomes a list indexed by limit. Only odd limits read `ctx.signal`. The test asserts cache state directly. Hooks-specific: four hooks unmount at once. | ≈ query_test: 'should not continue when last observer unsubscribed if the signal was consumed' + 'should continue if cancellation is not supported and signal is not consumed' |
| 4688 | should refetch when quickly switching to a failed query | A | **Hard.** A chain of `useEffect` calls flips `id` 1→2→1 over successive renders, giving 4 states. In `flutter_hooks` every flip has to be deferred to post-frame and pumped. Hooks-specific: the key switches back and forth while a fetch is in flight. | |
| 4736 | should update query state and refetch when reset with resetQueries | A | Exactly 4 states. `StaleTime.infinite`; `client.resetQueries(filters: QueryFilters(queryKey: key))`. | ≈ query_client_test: 'should reset query' |
| 4807 | should update query state and not refetch when resetting a disabled query with resetQueries | A | Uses `notifyOnChangeProps: 'all'`, which is the binding's only behaviour, so drop it. Exactly 4 states. | ≈ query_client_test: 'should reset query' |
| 4885 | should only call the query hash function once each render | N | other: no `queryKeyHashFn` by design. `QueryKey` is keyed by `==`/`hashCode`, so there is no hash function to count. | |
| 4912 | should hash query keys that contain bigints given a supported query hash function | A | Drop `queryKeyHashFn`. A `BigInt` part hashes natively, so assert `queryCache.find(QueryKey([..., BigInt.one]))` holds `'test'`. | |
| 4935 | should refetch when changed enabled to true in error state | A | `retryOnMount: () => false` → `retryOnMount: false` (a bool); `RefetchOn.never`. `queryFn` must have been called twice right after the toggle, so the hook has to apply options in the build: tap + `pump()`. Hooks-specific: `enabled` comes in through a parent prop. | |
| 4996 | should refetch when query key changed when previous status is error | A | `retryOnMount` callback → bool. The key changes through a parent prop (unmount the errored key, mount a new one). Hooks-specific. | |
| 5056 | should refetch when query key changed when switching between erroneous queries | A | `retryOnMount` callback → bool. Right after the key change, `status: fetching` must be visible in the same frame, so the hook has to report the optimistic result for the new key on that build. Hooks-specific. | |
| 5112 | should have no error in pending state when refetching after error occurred | A | Exactly 4 states, `[pending, error, pending(error: null), success]`. `RetryPolicy.never`. | |
| 5186 | networkMode online › online queries should not start fetching if you are offline | A | States are recorded by `useEffect` with no deps, once per commit. Expects `['paused','fetching','idle']` from one `advance(11)` after going online, which needs `pump()` and then `pump(10ms)`. Online mock → `client.onlineManager.setOnline`. | ≈ retryer_test: 'should pause when offline during a retry and continue when back online' (partial) |
| 5227 | networkMode online › online queries should not refetch if you are offline | P | Online mock helper; invalidate button. `useQuery<string, string>` means `failureReason` is a `String`. | |
| 5290 | networkMode online › online queries should not refetch if you are offline and refocus | A | `window.dispatchEvent('visibilitychange')` → `client.focusManager.onFocus()`, or the app lifecycle through `tester.binding.handleAppLifecycleStateChanged` under `observeAppLifecycle`. | |
| 5338 | networkMode online › online queries should not refetch while already paused | P | Online mock helper. | |
| 5384 | networkMode online › online queries should not refetch while already paused if data is in the cache | P | Online mock helper and `InitialData.value('initial')`. | |
| 5432 | networkMode online › online queries should not get stuck in fetching state when pausing multiple times | A | `visibilitychange` → focus manager, as in 5290; online mock. | |
| 5492 | networkMode online › online queries should pause retries if you are offline | P | `RetryPolicy.times(2)`, `RetryDelay.fixed(10ms)`, and going offline mid-fetch. | ≈ retryer_test: 'should pause when offline during a retry and continue when back online' |
| 5546 | networkMode online › online queries should not fetch if paused initial load and we go online after unmount | A | `async ({ signal: _signal })` reads the signal through destructuring, so the Dart `queryFn` **must read `ctx.signal`** explicitly; that read is why the paused fetch is cancelled. Conditional child: `if (show) Component()`. Hooks-specific: unmount while paused. | ≈ query_test: 'should cancel a paused initial fetch when the last observer unsubscribes' |
| 5603 | networkMode online › online queries should re-fetch if paused and we go online even if already unmounted (because not cancelled) | P | `setQueryData` before mount; no signal read; unmount while paused. | |
| 5663 | networkMode online › online queries should not fetch if paused and we go online when cancelled and no refetchOnReconnect | P | `refetchOnReconnect: RefetchOn.never`; `client.cancelQueries(...)`. | ≈ query_test: 'should throw a CancelledError when a paused query is cancelled' (partial) |
| 5718 | networkMode online › online queries should fetch if paused and we go online even if already unmounted when refetch was not cancelled | P | Invalidate while offline, unmount, then go online. | |
| 5788 | networkMode always › always queries should start fetching even if you are offline | P | `NetworkMode.always`. | ≈ retryer_test: 'should run even when offline with networkMode "always"' |
| 5824 | networkMode always › always queries should not pause retries | P | `RetryPolicy.times(1)`, `RetryDelay.fixed(5ms)`. | ≈ retryer_test: 'should run even when offline with networkMode "always"' |
| 5868 | networkMode offlineFirst › offlineFirst queries should start fetching if you are offline, but pause retries | P | `NetworkMode.offlineFirst`. | ≈ retryer_test: 'should start offline with networkMode "offlineFirst" but pause when the retry stays offline' |
| 5921 | subscribed › should be able to toggle subscribed | G | `subscribed` option (absent). A hook could emulate it by not listening to its controller, plus the asserted observer count. | |
| 5966 | subscribed › should not optimistically show fetching when unsubscribed | G | `subscribed`. Note: `QueryController.value` *is* optimistic while nobody listens and would show `fetching`. An implementation must read the non-optimistic current result, which the core's `getOptimisticResult` cannot produce: it has no mode switch. | |
| 6002 | subscribed › should not be attached to the query when subscribed is false | G | `subscribed`. | |
| 6031 | subscribed › should not re-render when data is added to the cache when subscribed is false | G | `subscribed`, and the render count must be 1. | |
| 6068 | should have status=error on mount when a query has failed | A | Exactly 1 state: the build after subscribing must not happen. `retryOnMount` callback → `false`. `await client.query(...)` before `pumpWidget`. | ≈ query_observer_test: 'should not refetch on mount when retryOnMount is false and query is in error state' |
| 6102 | setQueryData - should respect updatedAt | A | `updatedAt: 100` → `DateTime.fromMillisecondsSinceEpoch(100)`. `dataUpdatedAt` is a `DateTime?`, so print `millisecondsSinceEpoch`. | |
| 6134 | errorUpdateCount should increased on each fetch failure | P | `RetryPolicy.never`; refetch through the result's `refetch`. | |
| 6167 | should use provided custom queryClient | A | `useQuery(options, client: c)` with **no provider**. Without one, the build-aware notify scheduler and the lifecycle wiring are not installed, so the plain microtask scheduler runs. Hooks-specific. | |
| 6191 | should be notified of updates between create and subscribe | P | `React.useRef` → `useRef`; `setQueryData` is called inside the first build, after the hook ran. This tests whether the controller or hook catches an update between reading and subscribing (React: `observer.updateResult()` in the subscribe callback). | ≈ query_observer_test: 'should be able to read latest data after subscribing' |
| 6223 | should reuse same data object reference when queryKey changes back to some cached data | A | Spy-in-`useEffect([data])` call counts. `Map.==` is identity, so the check stays meaningful. A top-level `selector` tear-off is a stable `select`. The data is typed `Map<String, Object?>`. Hooks-specific: the key changes back to a cached key. | ≈ query_observer_test: 'should use cached selectResult when switching between queries and placeholderData returns previousData' (partial) |
| 6289 | should reuse same data object reference when queryKey changes and placeholderData is present | A | Same as 6223. The placeholder `Map` literal is a new instance on every build, as upstream's object literal is, so keep it non-`const` to mirror upstream's identity memo. | |
| 6358 | should not cause an infinite render loop when using unstable callback ref | N | react-specific-rendering: ref callbacks do not exist in Flutter. | |
| 6378 | should keep the previous data when placeholderData is set and cache is used | A | Seven indexed states over key steps `[0,1,0,2]`, using `PlaceholderData.keepPrevious()` and `StaleTime.infinite`. Each tap needs `pump()` and then `pump(11ms)`. The component reads only `data`, so upstream's tracked props would skip notifications that change nothing else; Flutter could record an extra state there (risk). Hooks-specific. | ≈ functional_improvements_test: 'keepPrevious preserves placeholder semantics across keys' |
| 6475 | should throw in case of bad arguments to enhance DevX | N | typescript-types: a JS-only dynamic argument check, which Dart's static types make impossible. | |
| 6495 | should respect skipToken and refetch when skipToken is taken away | A | `skipToken` → `enabled: Enabled.no` (the spelling `option_values.dart` documents); `retryOnMount` callback → bool. Hooks-specific: a parent prop flips it. | |
| 6539 | should allow enabled: true and queryFn: skipToken | G | `skipToken`. With no `queryFn` and `Enabled.yes`, query_kit fetches and fails with `MissingQueryFunctionError` (`query.dart:1013`) instead of staying `pending, idle`. | |
| 6570 | should return correct optimistic result when fetching after error | A | Drop `notifyOnChangeProps: 'all'` (it is the default behaviour). Exactly 4 results across unmount and remount, with two successive clicks and a pump after each. `errorUpdatedAt: 0` → `null` (`DateTime?`), and `> 0` → `isNotNull`. Hooks-specific: the remounted observer's optimistic result on an errored query. | |
| 6669 | should pick up an initialPromise | N | ssr/hydration: needs `dehydrate`/`hydrate`, which are absent. | |
| 6721 | should retry failed initialPromise on the client | N | ssr/hydration. | |
| 6786 | should console.error when there is no queryFn | G | A debug-time warning for a missing `queryFn` at hook mount. The core only fails the fetch with `MissingQueryFunctionError`. Asserting that error instead would be a different test. | |
| 6805 | should retry on mount when throwOnError returns false | N | error-boundary/throwOnError (also absent in code). The leftover, `retryOnMount: true` plus `StaleTime.infinite` refetching an errored query on remount, is portable if wanted. | |
| 6851 | should not retry on mount when throwOnError function returns true | N | error-boundary/throwOnError: an `ErrorBoundary` plus `ensurePreventErrorBoundaryRetry`. | |
| 6923 | should handle throwOnError function based on actual error state | N | error-boundary/throwOnError. The leftover is the same as 6805's. | |
| 6973 | should pass the query to retryOnMount callback | G | `retryOnMount` as `(query) => bool` (upstream `QueryBooleanOption`). query_kit has `bool? retryOnMount` only. | |
| 7004 | should not call retryOnMount callback when the query has data | G | `retryOnMount` callback. The leftover ("3 `queryFn` calls" with `retryOnMount: false`) is portable. | |
| 7054 | should not fetch for the duration of the restoring period when isRestoring is true | G | `IsRestoringProvider` and the `'isRestoring'` optimistic mode, which `getOptimisticResult` lacks (it takes only `optimistic: true`). | |

### Counts

| Verdict | Cases |
|---|---|
| P | 26 |
| A | 34 |
| N | 8 |
| G | 9 |
| Total | 77 |

- **N reasons:**
  - error-boundary/throwOnError: 3
  - ssr/hydration: 2
  - react-specific-rendering: 1
  - typescript-types: 1
  - other, no `queryKeyHashFn` by design: 1
- **G features:**
  - `subscribed`: 4
  - `retryOnMount` callback: 2
  - `skipToken`: 1
  - `isRestoring`/`IsRestoringProvider`: 1
  - missing-`queryFn` debug warning: 1
- **Absent but not G:**
  - `notifyOnChangeProps`: 2 cases use `'all'`, the binding's only behaviour, so the option is dropped (A).
  - `throwOnError`: 3 cases (N).
  - `queryKeyHashFn`: 1 N and 1 A.
  - `dehydrate`/`hydrate`: 2 cases (N).
- **Exact name matches in the repo's tests:** 0 of 77.

### Cross-cutting findings

#### 1. How the tests observe results

- **DOM text:** `getByText`, `getByRole`, `getByLabelText` and `getByTestId` appear in 69 of 77 cases (230 calls). They map to `find.text` and `find.byKey` and are robust.
- **`states`/`results` arrays pushed during render:** 18 cases.
  - 16 of them assert the exact length or the exact sequence: 3763, 3788, 3871, 4100, 4251, 4291, 4352, 4393, 4622 (trivially), 4688, 4736, 4807, 5112, 5186, 6068 and 6570. Watch the array form `expect(states).toMatchObject([...])`: it is length-strict.
  - 6378 indexes `states[0..6]` without a length check.
- **Render counters:**
  - 4885: `renders === hashes` (N).
  - 6031: `renders === 1` (G).
- **Counts through effects or memos:**
  - 4541: one state per `useEffect([data])` run.
  - 5186: one state per commit, via `useEffect` with no deps.
  - 6223 and 6289: spy calls in `useEffect([data])`.
  - 4018: `useMemo` call count.
  - 4447: `select` call count.
- **Other:** `vi.fn` call counts in 19 cases; the cache is inspected directly in 11.
- **Where render batching decides the outcome.** Upstream delivers notifications through `notifyManager` with `setTimeout(0)`. `advanceTimersByTimeAsync(n)` runs each timer as its own task, and `useSyncExternalStore` renders once per delivered batch. As a result, every transition separated by a timer gets its own render, even inside one `advance` call. Flutter's `tester.pump(d)` elapses every timer and then builds one frame. Cases that lose intermediate states:
  - **4100:** one `advance(51)` must yield 6 states.
  - **5186:** one `advance(11)` after going online must yield `fetching` and then `idle` as separate commits.
  - **4688:** the effect cascade plus one `advance(51)` must yield 4 states.
- **React effects.** React's `useEffect` runs after commit, and a `setState` inside it causes another render before the next notification. `flutter_hooks` runs `useEffect` synchronously during `build` (`_EffectHookState.initHook → scheduleEffect`). A `setState` there is silently dropped, because `ComponentElement.performRebuild` clears `dirty` only after `build`. Cases whose effects set state need a post-frame callback or microtask deferral and an extra pump:
  - 4068: `setInt(0)`.
  - 4291: `setCount(1)`. The deferral probably merges states[1] and states[2], because the synchronous `queryFn`'s data arrives on a microtask in the same window.
  - 4688: the `setId` chain.
  - 3673 is fine: its `setState` comes after an `await`.
- **Tracked props.** Upstream's `useBaseQuery` returns `observer.trackResult(result)` when `notifyOnChangeProps` is unset, so React re-renders only for props read during render. The binding notifies on any change in value (`NotifyGate.byValue`). In this slice, every recorded transition also changes a prop the component reads, or the test sets `'all'` (4807, 6570), so no expected count clearly depends on tracked props skipping a render. The latent risk is a notification that changes only unread fields. The likeliest cases are 6378 and 3763, which read only `data`.

#### 2. Timers

- `vi.useFakeTimers()` applies to every case. Four cases never advance time: 3921, 6475, 6539 and 6786.
- `advanceTimersByTimeAsync` appears 134 times in 73 cases. `0` is the most common value; the others are 5/6, 10/11/12, 20/21/22, 26, 31, 51 and 201.
- `sleep(ms)` provides `queryFn` latency in 42 cases. It maps to `Future.delayed`; the core's `test_utils.dart` already has `sleep` and `ms`.
- **Mapping `advance(0)`:** it becomes `tester.pump()`, because query_kit notifies on a microtask where upstream uses `setTimeout(0)`. A notification that arrives *during* a build is deferred by the provider's scheduler to a post-frame callback, which then needs another frame. So the harness wants a `flush()` that pumps without advancing time until no frame is scheduled.
- **Mapping `advance(n)`:**
  - Use `pump(Duration(milliseconds: n))` when only the end state is asserted.
  - Use a stepped `advance(tester, n, step: 1ms)` when states are recorded across the window.
- **Never use `pumpAndSettle` mid-test:** it moves the fake clock in 100 ms steps while frames are scheduled, which fires sleep, retry and interval timers.
- **`setTimeout` spies** (3968, 3991) have no Dart equivalent; query_kit arms `Timer`s directly. Assert the gc behaviour instead.
- **Teardown:** upstream's `afterEach(clear)` becomes the ADR-0002 snippet (`queryWidgetTest` in `packages/query_kit_flutter/test/harness.dart`), because Flutter asserts that no timer is pending before `tearDown` runs.

#### 3. Helpers a Dart harness should mirror

**From `react-query/src/__tests__/utils.tsx`:**

| Helper | What it does | Dart equivalent |
|---|---|---|
| `renderWithClient(client, ui)` | Wraps `ui` in `QueryClientProvider`; `rerender` keeps the provider. | The binding harness's `app()`/`pumpApp`. `rerender` must pump a non-const new instance. |
| `Blink({duration, children})` | Shows the children, then after `duration` (via `setActTimeout`) shows `off`, which unmounts them. Resets when `duration` or `children` change. | A small widget with a `Timer`. Used in 4586 and 4622. |
| `mockOnlineManagerIsOnline(v)` | A spy on `onlineManager.isOnline()` that emits no event; tests then call `queryCache.onOnline()` by hand. | `client.onlineManager.setOnline(v)`: hermetic because each client has its own manager. `setOnline(true)` resumes paused mutations and then calls `onOnline` one microtask later, which is equivalent after a pump. Restore in teardown. Used in 14 cases. |
| `setActTimeout(fn, ms)` | `setTimeout` wrapped in `act`. | A plain `Timer`. |
| `setIsServer` | Switches server mode. | Not used in this slice. |

**From `@tanstack/query-test-utils`:**

| Helper | What it does | Dart equivalent |
|---|---|---|
| `queryKey()` | A unique key `['query_N']`. | Core `test_utils.dart` has `queryKey()`. |
| `sleep(ms)` | Timer-based delay. | Core `test_utils.dart` has `sleep`. |
| `mockVisibilityState` | Spies on `document.visibilityState`. | Imported but unused in this slice. 5290 and 5432 dispatch `visibilitychange` instead, which becomes `client.focusManager.onFocus()` or the lifecycle path. |

**From React Testing Library:**

| API | Dart equivalent |
|---|---|
| `fireEvent.click` (52 calls in 36 cases) | `tester.tap` + `pump`. React's `act` flushes renders and effects synchronously after a click, and several cases assert right after the click (3673, 4935, 5056, 6289). |
| `rendered.unmount()` | `pumpWidget(SizedBox())`. |
| `render(<X/>)` with no provider (6167) | `pumpWidget` without a provider. |

**React hooks inside components:**

| React | `flutter_hooks` | Note |
|---|---|---|
| `useState`/`useReducer` (25 cases) | `useState` | |
| `useEffect` (9 cases) | `useEffect` | Runs synchronously in build; see section 1. |
| `useCallback`/`useMemo`/`useRef` (4 cases) | `useCallback`/`useMemoized`/`useRef` | Keys compare with `==`, not `Object.is`. Equivalent for strings, lists and maps, which have identity `==`, but not for value classes. |

**Library helpers:**

| Upstream | query_kit |
|---|---|
| `keepPreviousData` | `PlaceholderData.keepPrevious()` |
| `skipToken` | `Enabled.no` |
| `noop` | `.ignore()` |

#### 4. Hooks-specific scenarios (most valuable for the binding)

- **The key changes on rerender:**
  - 3811: key from `useState`, with `InitialData.compute` and `keepPrevious`.
  - 4688: rapid 1→2→1 switching while a fetch is in flight.
  - 4996, 5056: a parent prop changes the key between errored queries; 5056 needs `fetching` in the same frame.
  - 6223, 6289: switching back to a cached key, with the `select` reference reused.
  - 6378: `keepPrevious` across cached and uncached keys, 7 states.
  - 4622: four instances with different keys.
- **Options change between builds:**
  - `enabled` false→true: 3673, 3726, 4219, 4935, 6495.
  - `enabled` true→false while `initialData` changes: 3871.
  - `refetchInterval` changes: 4068.
  - `enabled` flips while a fetch is in flight: 4291.
  - `select` identity, through `useCallback` and a `forceUpdate`: 4447, 4491, 4541.
  - `subscribed` toggled: 5921, 5966 (G).
- **What these imply for the hook's design:**
  - React calls `getOptimisticResult(options)` during render and `setOptions` in an effect after commit. The binding's builder widgets apply options only on a *parent* update (`build_reconcile_test.dart`: 'same options re-evaluate Enabled.when only on a parent update').
  - A hook's options come from its own build, often after the widget's own `setState`. The hook therefore has to apply options on **every** build: 3726, 3871, 4447 and 6378 all change options through the widget's own state.
- **Unmount and remount:**
  - 3968, 3991: gc after unmount.
  - 4586, 4622: unmount mid-fetch through `Blink`, then cancellation.
  - 5546, 5603, 5718: unmount while paused offline.
  - 6570: unmount and remount in two successive clicks.
  - 6805–7004: remount after an error, with `retryOnMount`.
- **Two hooks on one key:** 4219, a disabled sibling and an enabling parent.
- **A rebuild that changes no option:** 4393 (`rerender`); 4491 and 4541 (`forceUpdate`). An inline `select` or `placeholderData` closure is a new instance on every build.
- **Side effects during render:**
  - 6191: `setQueryData` inside the first build, after the hook ran. React relies on `observer.updateResult()` in the subscribe callback.
  - `flutter_hooks`' `useListenable` subscribes in `initHook`, during build. `QueryController` subscribes on its first listener.
- **No provider, explicit client:** 6167.
- **isRestoring:** 7054 (G).
- **Conditional hooks:** none in this slice. Both React and `flutter_hooks` forbid them.

### First 10 to port in a proof-of-concept spike

1. **6068 should have status=error on mount when a query has failed.** Exactly one build: subscribing over an errored query with `retryOnMount: false` must not notify. This tests the controller's "no notification for nothing" against React's one render.
2. **3763 should mark query as fetching, when using initialData.** The first build must already be the optimistic `isFetching: true`, followed by exactly one more build: the optimistic-first-build contract.
3. **6191 should be notified of updates between create and subscribe.** A cache write between the hook's read and its subscription must still arrive; this probes `ControllerLifetime`'s subscribe gap.
4. **5056 should refetch when query key changed when switching between erroneous queries.** A parent prop changes the key and `fetching` must show in that same frame. This decides whether the hook applies options and reads the optimistic result in build.
5. **3871 data should persist when enabled is changed to false.** The hook's own `setState` changes options, giving 3 exact builds. `isStale` flips for a disabled observer and the changed `initialData` is ignored. This tests applying options on every build, unlike the builder widgets.
6. **4447 select should only run when dependencies change if memoized.** Exact `select` run counts through the first build, the subscribe and a `useCallback` change. This exposes the core's split between the preview and committed selection memos, and whether the hook calls `getOptimisticResult` and `setOptions` per build.
7. **6378 should keep the previous data when placeholderData is set and cache is used.** The richest key-change trace (7 states, `keepPrevious`, a cached key) and a check for tracked-props drift.
8. **6570 should return correct optimistic result when fetching after error.** Unmount and remount in two clicks; the new observer's optimistic result on an errored query (pending, error cleared, `errorUpdateCount` kept). This exercises hook disposal and recreation.
9. **4622 should cancel the query if the signal was consumed and there are no more subscriptions.** Four hooks unmount mid-fetch, and only the ones that read the signal cancel. This proves that the hook's dispose path destroys the observer exactly as React's unsubscribe does.
10. **4100 should refetch in an interval depending on function result.** Six states inside one 51 ms advance force the harness decision on stepped pumping versus `advanceTimersByTimeAsync`. Every other per-render test depends on that decision.

Runners-up:

- **4291** and **4688:** force the decision on how `useEffect` and `setState` are written in ports.
- **4935:** the `queryFn` must be called synchronously on an `enabled` toggle.
- **4219:** two hooks on one key.

---

## react-query adapter tests → `query_kit_flutter_hooks`: infinite queries, `useQueries`, options helpers

Upstream: `query/packages/react-query/src/__tests__/` at `50680b98c`. Read-only research; no repo file changed.

### Assumptions behind the verdicts

- **Hook shapes assumed** (thin layer over the binding's public API):
  - `useInfiniteQuery(options, {client})` returns the `InfiniteQueryController` it owns, as `context.infiniteQuery` does. Paging state (`hasNextPage`, `isFetchingNextPage`, `isFetchNextPageError`, `isRefetching`, `isRefetchError`, `fetchNextPage`, …) lives on the controller, not on the sealed `QueryResult` (PORTING_NOTES divergence, #16).
  - `useQueries(queries, {client})` returns `List<QueryResult<TData>>` from a hook-owned `QueriesController`, with `setQueries` applied in build before the read (the `QueriesBuilder._reconcile` pattern).
- **Verdicts:** **P** means a mechanical translation: Dart syntax, `tester.pump(d)` for `vi.advanceTimersByTimeAsync(d)`, an explicit `pump()` after a tap, option spellings (`pageFn`, the four-argument `PageParamFn`, `RetryPolicy.times`, `RetryDelay.fixed`), dropping `notifyOnChangeProps: 'all'` (the default here, since tracked props were dropped in #15). **A** means a semantic adaptation is needed, and the note says which.
- **"snapshot"**: the test pushes `state` per render and later reads paging flags from it. A controller is live, so the port has to record `(controller.value, controller.hasNextPage, …)` at build time. If `useInfiniteQuery` returned an immutable per-build snapshot instead, these 10 cases become **P**.
- **dup-core**: I grepped all 54 upstream names (28 + 24 + 2) against `packages/query_kit/test/**` and `packages/query_kit_flutter/test/**`. **None matched**, so no case is a name-level duplicate and the column is `—` throughout. Where a core test pins the same *mechanism* under a query-core name, I give it as `rel: file:line`. That is a pointer, not a duplicate of the hook-level scenario.
- Features checked against the code: `maxPages`, `initialPageParam` (required), `getPreviousPageParam`, infinite `select` (`InfiniteQuerySelectOptions`, `SelectFn<InfiniteData,…>`), infinite `placeholderData` (incl. `PlaceholderData.keepPrevious()`), `cancelRefetch` on `fetchNextPage`/`fetchPreviousPage`, and `QueryCancelToken` (`onCancel`, `isCancelled`) all **exist**. `refetchPage` is not used by any case (removed upstream in v5). Absent: `throwOnError` (dropped, #15), `notifyOnChangeProps`/tracked props (dropped, #15), `skipToken` (spelled `Enabled.no`, #17), a `subscribed` option, `IsRestoringProvider`/persistence restore, `isInitialLoading` (a deprecated alias of `isLoading`), and any `combine`, gate or `buildWhen` on `QueriesController`/`QueriesBuilder`.

### useInfiniteQuery.test.tsx (28 cases)

| file:line | name | verdict | note | dup-core |
|---|---|---|---|---|
| useInfiniteQuery:48 | should return the correct states for a successful query | A | Replace the whole-object `toEqual` with a field-by-field matcher over the `QueryResult` plus the controller flags. Mappings: `dataUpdatedAt: 0` becomes `null`, `error` becomes `errorOrNull`, `isLoadingError`/`isRefetchError` come from the `QueryError` getters or the controller. No `isInitialLoading` (deprecated alias). 2 builds with a single `pump(11ms)`. | — (rel: infinite_query_observer_test.dart:245) |
| useInfiniteQuery:140 | should not throw when fetchNextPage returns an error | P | Use `useEffect` keyed on the `controller.fetchNextPage` tear-off, which is `==` across builds, with a `Timer(20ms)`. `fetchNextPage` already completes with a `QueryError` and never throws (documented). `retry: RetryPolicy.times(1)`, `retryDelay: RetryDelay.fixed(10ms)`. | — |
| useInfiniteQuery:180 | should keep the previous data when placeholderData is set | A | Use `PlaceholderData.keepPrevious()` and a key `[key, order]` changed through `useState`. The hook applies the new options in build and must skip the notification that carries what that build already showed (`ReadEntry`-style "last built" gate), or the count is 7, not 6. Needs a pump after each tap, plus a snapshot for `isFetchingNextPage`. | — (rel: functional_improvements_test.dart:185) |
| useInfiniteQuery:269 | should be able to select a part of the data | P | `InfiniteQuerySelectOptions`, with `select` returning `InfiniteData<String,int>`. 2 builds. | — (rel: infinite_query_observer_test.dart:20) |
| useInfiniteQuery:305 | should be able to select a new result and not cause infinite renders | A | Replace `React.useCallback` with a stable `select` (static function, or `useCallback`/`useMemoized`). An inline closure re-runs the select every build, which is the documented trap. `Math.random` becomes `Random`, and `{...x, id}` becomes a record. `selectCalled == 1` pins that re-applying equal options in build does not re-run `select`. | — |
| useInfiniteQuery:354 | should be able to reverse the data | P | Infinite `select` reversing both lists. 4 builds, with a `pump()` after the tap. | — |
| useInfiniteQuery:410 | should be able to fetch a previous page | A | snapshot (`hasNextPage`/`hasPreviousPage`/`isFetchingPreviousPage`). 4 builds, pump after the tap. | — |
| useInfiniteQuery:487 | should be able to refetch when providing page params automatically | A | snapshot. `isRefetching` must be read from the controller, because `result.isRefetching` is true for page fetches too. 8 builds, with a `pump()` after each of the 3 taps. The `isFetching: false` assertion straight after the click is checked before the pump. | — |
| useInfiniteQuery:598 | should return the correct states when refetch fails | A | snapshot. `isRefetchError` comes from the controller. `{pages:[10]}` survives as `QueryError.staleData` (`dataOrNull`). 4 builds. | — |
| useInfiniteQuery:692 | should return the correct states when fetchNextPage fails | A | snapshot (`isFetchNextPageError`). 4 builds. | — |
| useInfiniteQuery:778 | should return the correct states when fetchPreviousPage fails | A | snapshot (`isFetchPreviousPageError`). 4 builds. | — |
| useInfiniteQuery:868 | should silently cancel any ongoing fetch when fetching more | P | The texts are `status.name`/`fetchStatus.name`, plus a Dart rendering of `pages`/`pageParams` in place of `JSON.stringify`. `advance(0)` becomes `pump()`. | — |
| useInfiniteQuery:913 | should silently cancel an ongoing fetchNextPage request when another fetchNextPage is invoked | A | `AbortSignal` becomes `QueryCancelToken`: `onabort` and `addEventListener` are two `onCancel` callbacks, and `aborted` is `isCancelled`. Two Timers sit in an effect keyed on `fetchNextPage`, and **exactly 3** page-fn calls pin a stable `fetchNextPage` identity across builds. | — |
| useInfiniteQuery:988 | should not cancel an ongoing fetchNextPage request when another fetchNextPage is invoked if `cancelRefetch: false` is used | A | As :913, with `fetchNextPage(cancelRefetch: false)`. Exactly 2 calls. | — |
| useInfiniteQuery:1054 | should keep fetching first page when not loaded yet and triggering fetch more | A | snapshot (`hasNextPage`). A Timer effect keyed on `fetchNextPage`. 2 builds, because a fetchNextPage during the first load joins (documented). | — |
| useInfiniteQuery:1102 | should stop fetching additional pages when the component is unmounted and AbortSignal is consumed | A | Unmount through a Timer-driven `setState` in the parent. Seed with `InitialData.value(InfiniteData(...))`, and check `getQueryState`. Note that upstream's page fn never reads `signal` despite the name, so `fetches == 2` at 125 ms holds with or without cancellation. Port it verbatim and record that the test is weak. | — (rel: port_specifics_test.dart:71, infinite_query_behavior_test.dart:101) |
| useInfiniteQuery:1150 | should be able to set new pages with the query client | A | `setQueryData<InfiniteData<int,int>>`. `initialPageParam` comes from `useState`, so the options change without a key change (`setInfiniteOptions` in build). The JSON text needs a Dart rendering. | — |
| useInfiniteQuery:1207 | should only refetch the first page when initialData is provided | A | Replace `createRenderStream` (real timers) with a per-build snapshot list under fake time. 4 builds, with a pump after the tap. | — |
| useInfiniteQuery:1284 | should keep initialData visible alongside the error when a refetch fails | P | `QueryError` with `staleData` gives `isError` together with `dataOrNull`. 2 builds. | — |
| useInfiniteQuery:1319 | should set hasNextPage to false if getNextPageParam returns undefined | A | snapshot (`hasNextPage`). `undefined` becomes `null`. 2 builds. | — |
| useInfiniteQuery:1357 | should compute hasNextPage correctly using initialData | A | snapshot, plus `InitialData.value`. 2 builds. | — |
| useInfiniteQuery:1396 | should compute hasNextPage correctly for falsy getFetchMore return value using initialData | A | snapshot. 2 builds. | — |
| useInfiniteQuery:1435 | should not use selected data when computing hasNextPage | A | snapshot, plus `InfiniteQuerySelectOptions`. `getNextPageParam` sees raw pages. 2 builds. | — (rel: port_specifics_test.dart:2815) |
| useInfiniteQuery:1477 | should build fresh cursors on refetch | A | Replace `useRef` with the hooks `useRef` or a captured counter, and use `invalidateQueries(filters: QueryFilters(queryKey: key))`. A long text-finder UI. `items.splice` is a list mutation the page fn closes over. | — (rel: infinite_query_observer_test.dart:96) |
| useInfiniteQuery:1612 | should compute hasNextPage correctly for falsy getFetchMore return value on refetching | A | Two clicks in one tick: `setState` (Remove Last Page) and then `refetch`. React flushes the render and effects inside each `act`; Flutter does not. **A `pump()` is required between the taps**, or `refetch` runs the previous build's page-fn closure. Uses `useRef`. | — (rel: infinite_query_observer_test.dart:205) |
| useInfiniteQuery:1733 | should cancel the query function when there are no more subscriptions | A | The page fn consumes `context.signal.onCancel`. The `Promise` becomes a `Completer`. Hide through `setState`, then pump; hook dispose → controller dispose → observer destroy must cancel within that frame. The `sleep(1000)` timer needs the teardown pump. | — (rel: query_test.dart:341) |
| useInfiniteQuery:1783 | should use provided custom queryClient | P | `useInfiniteQuery(options, client: client)` with no provider in the tree. | — |
| useInfiniteQuery:1807 | should not fetch when queryFn is skipToken, and fetch once it is replaced | A | `skipToken` becomes `enabled: postId == null ? Enabled.no : Enabled.yes` (#17). `pageFn` is always set. Re-enabling on the same key fetches once. | — |

**Totals (useInfiniteQuery): P 6, A 22, N 0, G 0.** Ten of the A cases are snapshot-only and would be P with a snapshot-returning hook.

### useQueries.test.tsx (24 cases)

| file:line | name | verdict | note | dup-core |
|---|---|---|---|---|
| useQueries:25 | should return the correct states | A | `results.length == 3` needs the pump split as `pump(10ms)` + `pump(190ms)`. A single `pump(201ms)` coalesces into 2 builds. | — (rel: queries_observer_test.dart:60) |
| useQueries:66 | should not optimistically show fetching when unsubscribed | G | **`subscribed` option**. `QueriesController.value` is the *optimistic* list (fetching) while unlistened, which is exactly what this case forbids. | — |
| useQueries:94 | should track results | A | "No render for isFetching transition" (L136–137) is tracked props, dropped in #15. Here a refetch rebuilds for `fetching` and again for the data, giving 4 builds, not 3. Port with the count changed and a divergence row, or with a `buildWhen` on data if the hook takes one. | — |
| useQueries:142 | should throw error if in one of queries' queryFn throws and throwOnError is in use | N | error-boundary/throwOnError | — |
| useQueries:208 | …throwOnError function resolves to true | N | error-boundary/throwOnError | — |
| useQueries:276 | …rejects with a falsy error and throwOnError is in use | N | error-boundary/throwOnError (and Dart has no "falsy error") | — |
| useQueries:309 | should use provided custom queryClient | P | `useQueries(queries, client: client)` with no provider. | — |
| useQueries:337 | should combine queries | A | `results.combine((values) => (combined: true, res: values.join(',')))` gives `CombinedData`. Final text only. | — (rel: combined_result_test.dart:257) |
| useQueries:381 | should not return new instances when called without queries | A | Empty list with a combine returning a constant. Key `useEffect` on the `CombinedResult` (value `==`), **not** on the `List` (identity). Rebuild through `setState`. The effect count stays 1 because of value equality and `CombineMemo`'s `replaceEqualDeep`. | — |
| useQueries:434 | should not have infinite render loops with empty queries (#6645) | P | `useEffect` with no keys counts builds, which must be 1. Flutter has no `useSyncExternalStore` snapshot loop. | — |
| useQueries:454 | should only call combine with query results | A | Replace `[query1, query2]` destructuring with `values[0]`/`values[1]`, or use two `useQuery` calls and `(a, b).combine`. Final text only. | — |
| useQueries:490 | should track property access through combine function | G | **Combine-gated rebuild.** "No further re-render because data didn't change" (L585–586) needs the hook to rebuild only when the combined output moves, and to ignore fetch flags. `CombinedResult ==` includes `isFetching`, so it also needs a `buildWhen`. The combined `refetch` closure maps to `CombinedResult.refetch`. `[4,5,6]` is a tolerance. | — |
| useQueries:589 | should synchronously track properties of all observer even if a property (isLoading) is only accessed on one observer (#7000) | A | Compute `results.any((r) => r.isLoading)` over the raw list in build. `combine` would yield `CombinedError` because id 2 fails. With no tracking here, the upstream bug cannot occur. Worth keeping as a regression. | — |
| useQueries:630 | should not have stale closures with combine (#6648) | A | `CombineMemo` + **`keys: [count]`**. Without keys the memo returns the stale output: this case pins why `keys:` exists. | — (rel: integration_feedback_test.dart:13) |
| useQueries:674 | should optimize combine if it is a stable reference | A | Call counts diverge by design. Upstream gets 3/3/4/7 (combine sees pending results and re-runs when the result array or the fn identity changes). `CombineMemo` gives 1/1/1/2: the combiner runs only once every source has data **and** a data identity changed, and not on a rerender. Keep the invariant ("no call for an unchanged refetch"), change the numbers, record the divergence. | — |
| useQueries:753 | should re-run combine if the functional reference changes | A | A Dart closure has no identity that is stable across builds, so `useCallback([state])` becomes `keys: [state]`. The combiner then runs 1 → 2 times, where upstream runs 3 → 4. | — |
| useQueries:817 | should not re-render if combine returns a stable reference | G | **Combine-gated rebuild**, plus a **raw-results combiner**. Upstream `combine: () => 'foo'` is `'foo'` from the first render. Dart's `combine` is `CombinedPending` and then `CombinedData('foo')`, so even when gated that is 2 builds, not 1. | — |
| useQueries:871 | should re-render once combine returns a different reference | G | **Combine-gated rebuild.** A gate on `CombinedResult ==` reproduces 2 builds: `CombinedPending(isFetching)` stays equal through the first two resolutions, then `CombinedData('foo')`. Without a gate it is 4. | — |
| useQueries:926 | should track properties correctly with combine | A | `results.combine` gives `CombinedPending` ("pending") and then `CombinedData` (the join). `setQueryData` on key1 recomputes. Final texts only. | — |
| useQueries:993 | should not re-run stable combine on unrelated re-render | A | A hook-owned `CombineMemo` (`useMemoized`) is not re-run on an unrelated `setState`. Counts are 1/1/1, where upstream has 3/3/3. The invariant (no extra calls) holds. | — |
| useQueries:1070 | should not cause infinite re-renders when removing last query | A | The queries list sits in `useState` and shrinks 2→1, then swaps to key2. A build counter must stay < 10. Sync `queryFn: (_) => 'data1'`. | — (rel: queries_observer_test.dart:93) |
| useQueries:1142 | should return correct results when queries count changes with stable combine reference | P | Identity combine means none is needed. The `results.length == n` assertion must hold on **every** build, which pins `setQueries` before the read in the same build. | — (rel: queries_observer_test.dart:241) |
| useQueries:1195 | should not fetch for the duration of the restoring period when isRestoring is true | G | **`IsRestoringProvider`** (persistence-restore gate; `persister` not ported, #15). | — |
| useQueries:1251 | should not fetch queries with different durations for the duration of the restoring period when isRestoring is true | G | **`IsRestoringProvider`**. | — |

**Totals (useQueries): P 3, A 12, N 3, G 6.**

### queryOptions.test.tsx / infiniteQueryOptions.test.tsx (1 case each)

| file:line | name | verdict | note | dup-core |
|---|---|---|---|---|
| queryOptions:7 | should return the object received as a parameter without any modification. | N | typescript-types: an identity helper that exists for type inference. In Dart the options classes *are* the helper ("made the only way", website `guides/query-options.md`). | — |
| infiniteQueryOptions:8 | should return the object received as a parameter without any modification. | N | typescript-types, as above. | — |

**Totals: N 2.**

### G-features (counted over the four files)

| Missing feature | Cases | Where it would live |
|---|---|---|
| Combine-gated rebuild for a collection: rebuild only when the combined output changes, optionally with `buildWhen`. `QueriesController` notifies on any element change, and `QueriesBuilder` deliberately has no `buildWhen`. | 3 (useQueries:490, :817, :871) | Hooks package (implementable on public API: a hook-owned `CombineMemo`, with the combination computed in the listener) |
| Raw-results combiner (`R Function(List<QueryResult<T>>)` that sees pending and error results). Dart's `combine` only ever hands the combiner data. | 1 (:817; also explains the count deltas in :674, :753, :993) | New API, not recommended (see finding 1) |
| `subscribed` option, with a non-optimistic read while unsubscribed | 1 (useQueries:66) | Binding/core |
| `IsRestoringProvider` / persistence restore gate | 2 (useQueries:1195, :1251) | Out of scope until a persister exists (#15) |

None of `maxPages`, `initialPageParam`, `getPreviousPageParam`, infinite `select`, infinite `placeholderData` or `cancelRefetch` is missing. `refetchPage` is unused.

### Cross-cutting findings

#### 1. Typing `useQueries` over the existing API

query_kit's `QueriesObserver<TQueryData, TData>` is **homogeneous**, and heterogeneous sets combine as a **record of results** (`(a, b).combine(…)`, arities 2–6). A list of one type has `.combine` and `.combineWith(other, …)`, a source can be `optional()`, and `CombineMemo` + `keys:` memoises. Hooks make the heterogeneous case easy: a fixed, mixed set is not a loop, so it is N × `useQuery` plus a record `combine`. `useQueries` is needed only for a **dynamic-length, homogeneous** list.

Signature 1, plain (recommended base):

```dart
List<QueryResult<TData>> useQueries<TQueryData, TData>(
  List<QueryObserverOptionsBase<TQueryData, TData>> queries, {
  QueryClient? client,
});
// combine is the existing extension:
final combined = useQueries(opts).combine(
  (values) => …,
  memo: useMemoized(CombineMemo<R>.new),
  keys: [search],
);
// heterogeneous: (useQuery(a), useQuery(b)).combine((a, b) => …)
```

It owns a `QueriesController` (`useMemoized`, keyed on the client), calls `setQueries(queries)` in every build before reading `value` (as `QueriesBuilder._reconcile` does), and rebuilds when the `(result, refetch)` pairs differ element-wise from what the last build showed (as `QueriesBuilder._shown` does).

Signature 2, combine-gated (covers useQueries:490/:871 and keeps the existing semantics):

```dart
CombinedResult<R> useQueriesCombined<TQueryData, TData, R>(
  List<QueryObserverOptionsBase<TQueryData, TData>> queries,
  R Function(List<TData> values) combine, {
  List<Object?>? keys,
  BuildWhen<CombinedResult<R>>? buildWhen,
  QueryClient? client,
});
```

The hook owns a `CombineMemo`. In the controller listener it computes `value.combine(combine, memo:, keys:)` with the **last build's** closure and keys, and marks the element dirty only if the `CombinedResult` differs (`==`) from the one last built and `buildWhen` allows. A raw-results `combine` (upstream's exact shape) would be new API. I'd defer it and record :817 plus the call counts as divergences.

What the upstream tests pin down:

- The combine output is structurally shared, so a deep-equal output is the same instance and no effect re-runs (:381). `CombineMemo` does this through `replaceEqualDeep`, and `CombinedResult` has value `==`.
- The component re-renders only when the combined output changes (:817 renders 1, :871 renders 2, :490 L586). This needs the gate.
- The combine re-runs only when the result array or the combine-fn identity changes (:674 3/3/4/7, :753 3→4, :993 3/3/3). Dart's memo re-runs on a data-identity change or a `keys` change instead, so the counts differ and the invariants hold.
- No stale closure: the latest render's combine is used (:630). Here that is `keys:`, the documented `CombineMemo` trap.
- The result length equals the queries of the **same** render, with no lag frame (:1142). The hook must call `setQueries` before it reads.
- No loops when the list is empty or shrinks (:434, :1070). The risk in Dart is a `List` compared by identity: `QueriesController.value` before the first listener is a **fresh optimistic list on every read**. Key effects on `CombinedResult` or compare element-wise, never on the list itself.

#### 2. Render-count and batching-dependent assertions

A Flutter widget test builds at most once per frame, and `tester.pump(d)` elapses `d` and then renders one frame. Upstream gets one render per settled timer inside a single `advanceTimersByTimeAsync`, and one render after a click before the next timer (the notify flushes on `setTimeout(0)`).

- **Split the pumps at each transition:** useQueries L57→L60 (3 renders inside one 201 ms advance).
- **`pump()` after every tap, or the intermediate `fetching` state is lost:** useInfiniteQuery L214/L223 (6), L387/L391 (4), L442/L448 (4), L520–531/L535 (8), L641/L645 (4), L727/L731 (4), L815/L821 (4), L1260 (render stream), L1612's two taps (L1721–1722, which also need a pump *between* them).
- **Assertions straight after a click, before the flush:** L532, L642, L728, L818 (`isFetching: false`). In Flutter these are trivially true before the pump. Keep them.
- **Exact build counts:** useInfiniteQuery L67, L223, L294, L342, L391, L448, L535, L645, L731, L821, L1085, L1308, L1340, L1379, L1418, L1460, and L1239–1281 (4 `takeRender`). useQueries L60, L127, L137, L543, L574, L586, L868, L923, L451 (`renderCount` 1), L424/L431 (effect count), L1130/L1138 (< 10), and L1190 (every build).
- **Counts that depend on tracked props** (dropped in #15; they need a gate or `buildWhen`, or a changed number): useQueries L137, L586, L733, L868, L923.
- **Counts of combine or select calls** (`CombineMemo` semantics give other numbers): useQueries L727, L733, L738, L750, L809, L814, L1049, L1058, L1067. useInfiniteQuery L343 (`selectCalled` 1; needs a stable `select`).
- **The +1 build trap:** options are re-applied in build (a key change at useInfiniteQuery L218–223, `initialPageParam` at L1174), and the observer's notification then arrives *after* that build carrying what it already showed. The binding absorbs this with `ReadEntry` ("value its last build read"), but **`ReadEntry`, `ObservedState` and `observedStateOf` are not exported** (`read_entry.dart` exports only `BuildWhen`, and the barrel hides the other two). The hooks package must either re-implement the comparison, rebuilding the infinite "observed state" record from the public getters, or the binding must export them.

#### 3. Hooks-specific behaviour exercised

- **The queries list changes length between renders:** useQueries:1070 (2→1, then swapping to a different key), :1142 (0→1→2, checked on every build), :381 (stays empty across a rerender), :434 (empty).
- **Key change, and options change without a key change:** useInfiniteQuery:180 (key `[key, order]` with `keepPrevious`: the placeholder must show in the same build that changed the key); :1150 (`initialPageParam` from `useState`, then `setQueryData`, then refetch from the held params); :1807 (enabled toggled by state on the same key).
- **`fetchNextPage` identity:** :140, :913, :988 and :1054 run `useEffect(…, [fetchNextPage])`. If the identity changed per build, the effect would re-fire and :913/:988's exact call counts (3, 2) would break. A `controller.fetchNextPage` tear-off is `==` across builds (same instance) and changes only when the controller is replaced (a client change). flutter_hooks compares `keys` with `==`; confirm this in the spike, since `flutter_hooks` is not in the local pub cache.
- **Callback and closure identity:** a `select` via `useCallback` (:305, `selectCalled` 1); `combine` via `useCallback([])`, `useCallback([state])` or a module-level function (:674, :753, :993, :1142); an inline combine capturing state (:630).
- **The latest build's closures are the ones that run:** :1612 (`setState` + `refetch` in one tick); :1477 (the page fn reads a mutable list plus a `useRef` counter).
- **Lifecycle:** unmount mid-refetch (:1102), hook disposal cancelling a signal-consuming fetch (:1733), and a custom client without a provider (useInfiniteQuery:1783, useQueries:309).

### Survey of the remaining files (counts by regex over `it(`/`test(`)

| File | Cases | Verdict for a Dart hooks package |
|---|---|---|
| suspense.test.tsx | 7 | N, suspense. These are the staleTime ≥ 1000 ms clamp under Suspense. Flutter has no Suspense. |
| useSuspenseQuery.test.tsx | 24 | N, suspense. |
| useSuspenseQueries.test.tsx | 27 | N, suspense. |
| useSuspenseInfiniteQuery.test.tsx | 5 | N, suspense (and dev-mode `skipToken` logging). |
| usePrefetchQuery.test.tsx | 6 | The **concept is meaningful**: `usePrefetchQuery(options)` fires `client.query(options).ignore()` during build when `client.getQueryState(key) == null`, and skips existing, pending or failed state. Implementable today. The cases all observe through `useSuspenseQuery` and fallbacks, so at most 2–3 (prefetch when absent, skip when present, don't refetch a failed one) port as **A** with a plain `useQuery` consumer and call counts. The endless-loop and waterfall cases are suspense-only. |
| usePrefetchInfiniteQuery.test.tsx | 3 | Same concept for `client.infiniteQuery`. 1 case is portable as **A** (prefetch when absent); the other 2 are suspense. |
| HydrationBoundary.test.tsx | 12 | N, ssr/hydration. There is no dehydrate/hydrate in query_kit. |
| ssr.test.tsx | 9 | N, ssr/hydration. Flutter has no server render. |
| ssr-hydration.test.tsx | 3 | N, ssr/hydration. |
| QueryResetErrorBoundary.test.tsx | 14 | N, error-boundary/throwOnError (dropped, #15). The "reset and retry" concept is already `refetch`, or `CombinedResult.retry()` for several sources. No hook is needed. |
| fine-grained-persister.test.tsx | 3 | N, `persister` not ported (#15). It becomes relevant only if a persistence package appears, alongside `IsRestoring`. |
| transition.test.tsx | 2 | N, react-specific-rendering (`useDeferredValue`/`startTransition`). The user-level need is `PlaceholderData.keepPrevious()`, which is covered by useInfiniteQuery:180. |
| `*.test-d.tsx` (13 files) | ~170 | N, typescript-types. A **small subset is meaningful as Dart static-inference checks** (an analyzer-only "compiles" test, like `examples/doc_snippets`): from `useInfiniteQuery.test-d` (10), that `initialPageParam` types `pageParam`, TData defaults to `InfiniteData<TPageData, TPageParam>`, and `select` goes to an arbitrary type; from `useQueries.test-d` (22), that the element type is inferred from the options with no type arguments (the tuple and heterogeneous cases do not apply); from `useMutationState.test-d` (3), `select` inference. The `queryOptions`/`infiniteQueryOptions`/`usePrefetch*` type tests are N. |

### Five cases to port first (proof-of-concept spike)

1. **useInfiniteQuery:48 — should return the correct states for a successful query.** The baseline: optimistic first build, every field of the result mapped, and the controller-vs-snapshot return shape decided.
2. **useInfiniteQuery:180 — should keep the previous data when placeholderData is set.** A key change inside the hook, `keepPrevious`, and exactly 6 builds. It proves the "last built" gate that `ReadEntry` provides and that is not exported.
3. **useInfiniteQuery:913 — should silently cancel an ongoing fetchNextPage request when another fetchNextPage is invoked.** `fetchNextPage` identity under effect keys (exactly 3 calls), and `QueryCancelToken` callbacks.
4. **useQueries:1142 — should return correct results when queries count changes with stable combine reference.** `setQueries` before the read in the same build, with the length correct on every build.
5. **useQueries:871 — should re-render once combine returns a different reference.** It forces the `useQueries` combine decision (a gate on `CombinedResult`, signature 2). The runner-up is :630 (`keys:` against stale closures).

---

## Hooks port research — mutation slice

Upstream: `query/packages/react-query/src/__tests__/` at `50680b98c`.
Files: `useMutation.test.tsx` (61), `useMutationState.test.tsx` (5: 4 `useIsMutating` + 1 `useMutationState`),
`useIsFetching.test.tsx` (5), `QueryClientProvider.test.tsx` (4), `mutationOptions.test.tsx` (14). **89 cases.**
No `it.each`, `it.skip` or `it.todo` in any of the five files. The `*.test-d.tsx` type tests are out of scope (all would be N, `typescript-types`).

Describe nesting:
- `useMutation.test.tsx`: one `describe('useMutation')`; `beforeEach` builds a fresh `QueryCache`, `MutationCache` and `QueryClient`, with fake timers.
- `useMutationState.test.tsx`: `describe('useIsMutating')` (4) and `describe('useMutationState')` (1); a client per case.
- `useIsFetching.test.tsx`: `describe('useIsFetching')` (5).
- `QueryClientProvider.test.tsx`: `describe('QueryClientProvider')` (3) > `describe('useQueryClient')` (1).
- `mutationOptions.test.tsx`: `describe('mutationOptions')` (14).

### Legend

- **P**: the same widget shape and assertions. Only these mechanical mappings: `fireEvent.click` → `tester.tap` and `pump()`; `advanceTimersByTimeAsync(n)` → `tester.pump(Duration(milliseconds: n))`; `setActTimeout(fn, n)` inside `useEffect` → `Timer` inside flutter_hooks `useEffect`; `vi.fn` → recorder lists; option syntax (`retry: 1` → `RetryPolicy.times(1)`, `retryDelay: 5` → `RetryDelay.fixed(5 ms)`, `gcTime: 0` → `GcTime.duration(Duration.zero)`, `Infinity` → `GcTime.never`); callback arity (Dart `onError`/`onSettled` take a `StackTrace`); `mutate()` with no variables → `mutate(null)`.
- **A**: needs a semantic adaptation, described in the note.
- **N**: not applicable to Flutter/Dart.
- **G**: depends on a query_kit feature that does not exist.
- **dup-core**: the scenario is already covered by a core test. No upstream adapter-test *name* occurs anywhere in `packages/query_kit/test` or `packages/query_kit_flutter/test`; the entries below are matched by scenario and marked *partial* where they cover only part of the case.

### useMutation.test.tsx — `describe('useMutation')`

| file:line | name | verdict | note | dup-core |
|---|---|---|---|---|
| useMutation.test.tsx:34 | should be able to reset `data` | P | text heading; tap mutate → pump → tap reset → pump; `data = 'empty'` default → `dataOrNull ?? 'empty'` | |
| useMutation.test.tsx:66 | should be able to reset `error` | P | `errorOrNull`; `mutate` ignores the rejection, so no uncaught error | |
| useMutation.test.tsx:102 | should call mutate callbacks when useMutation has no callbacks | P | per-call `MutateCallbacks` on `MutationController.mutate` | partial: mutation_observer_test 'mutation callbacks should be called in correct order with correct arguments for success case' |
| useMutation.test.tsx:136 | should call mutateAsync callbacks when useMutation has no callbacks | P | `useEffect` + `Timer(0)` with keys `[mutateAsync]`. A probe of `mutateAsync` identity: an unstable identity re-runs the effect after each result change | partial: same (success case) |
| useMutation.test.tsx:170 | should call mutate error callbacks when useMutation has no callbacks | P | | partial: mutation_observer_test '…arguments for error case' |
| useMutation.test.tsx:207 | should call mutateAsync error callbacks when useMutation has no callbacks | P | try/catch around `mutateAsync`; identity probe | partial: same (error case) |
| useMutation.test.tsx:243 | should call only mutate onSuccess when useMutation has no callbacks | P | | partial: '…success case' |
| useMutation.test.tsx:274 | should call only mutate onError when useMutation has no callbacks | P | | partial: '…error case' |
| useMutation.test.tsx:308 | should call only mutate onSettled when useMutation has no callbacks | P | | partial: '…success case' |
| useMutation.test.tsx:339 | should call only mutateAsync onSuccess when useMutation has no callbacks | P | identity probe | partial: '…success case' |
| useMutation.test.tsx:367 | should call only mutateAsync onError when useMutation has no callbacks | P | identity probe | partial: '…error case' |
| useMutation.test.tsx:400 | should call only mutateAsync onSettled when useMutation has no callbacks | P | identity probe | partial: '…success case' |
| useMutation.test.tsx:428 | should be able to call `onSuccess` and `onSettled` after each successful mutate | P | three taps, one `pump()`; the heading shows a closure variable, so it needs any rebuild after the clicks (the result change gives one) | |
| useMutation.test.tsx:476 | should set correct values for `failureReason` and `failureCount` on multiple mutate calls | P | first call rejects synchronously; `failureReason` → `toString()` | |
| useMutation.test.tsx:529 | should be able to call `onError` and `onSettled` after each failed mutate | P | | |
| useMutation.test.tsx:598 | should be able to call `onSuccess` callback after successful mutate | P | order: the options callback, then the per-call one (documented on `MutateCallbacks`) | |
| useMutation.test.tsx:632 | should be able to call `onError` callback after failed mutate | P | | |
| useMutation.test.tsx:669 | should be able to call `onSettled` callback after mutate | P | | |
| useMutation.test.tsx:703 | should be able to call `onSuccess` callback after successful mutateAsync | P | identity probe | |
| useMutation.test.tsx:737 | should be able to call `onError` callback after failed mutateAsync | P | identity probe | |
| useMutation.test.tsx:773 | should be able to call `onSettled` callback after mutateAsync | P | identity probe | |
| useMutation.test.tsx:807 | should be able to override the useMutation success callbacks | P | options success+settled, then per-call, then the awaited result: `MutationController.mutateAsync` runs the per-call callbacks before the future completes | |
| useMutation.test.tsx:857 | should be able to override the error callbacks when using mutateAsync | P | | |
| useMutation.test.tsx:908 | should be able to override the error callbacks when using mutate | P | | |
| useMutation.test.tsx:954 | should be able to override the settled callbacks when using mutate | P | | |
| useMutation.test.tsx:999 | should be able to use mutation defaults | A | **render-count**: `states.length == 3` within a single `advance(21)` (timer at 10, function at 20). `pump(21ms)` builds one frame, so the pending state is lost; split into `pump(10ms)` + `pump(11ms)`. Also an identity probe (effect keyed `[mutate]`) | partial: mutation_test 'setMutationDefaults should be able to set defaults', 'mutation should set correct success states' |
| useMutation.test.tsx:1034 | should be able to retry a failed mutation | P | `RetryPolicy.times(1)`, `RetryDelay.fixed(5ms)`; `pump(15ms)` | |
| useMutation.test.tsx:1063 | should not retry mutations while offline | A | `mockOnlineManagerIsOnline` spy → `client.onlineManager.setOnline(false/true)`. That is a real event, and a mounted client resumes paused mutations by itself (query_client.dart:515-533), so the explicit `resumePausedMutations()` that follows is a second resume. Verify it is harmless | |
| useMutation.test.tsx:1117 | should call onMutate even if paused | A | online mock as above. `onMutate` is called with `('todo', {client, meta, mutationKey})`, but `OnMutate` takes the variables only (mutation_options.dart:148), so the context half of the assertion is dropped, as the core did for `setMutationDefaults` | |
| useMutation.test.tsx:1176 | should optimistically go to paused state if offline | A | online mock. `states[1] == 'pending, true'` with "no intermediate 'pending, false'". Frame coalescing makes that absence vacuous; to keep the strength, record from a controller listener, not from `build` | |
| useMutation.test.tsx:1231 | should be able to retry a mutation when online | A | online mock; `networkMode: NetworkMode.offlineFirst`; the `failureReason: new Error('oops')` match → compare the message | |
| useMutation.test.tsx:1301 | should not change state if unmounted | A | no assertion upstream. Flutter: tap mutate, tap unmount, **`pump()` so the unmount lands**, then `pump(10ms)` to drain the `sleep(10)` timer. Otherwise testWidgets fails on a pending timer. Assert `takeException()` is null (no `setState` after dispose) | |
| useMutation.test.tsx:1321 | should be able to throw an error when throwOnError is set to true | N | error-boundary/throwOnError (`throwOnError` deliberately dropped, PORTING_NOTES divergence table, #15) | |
| useMutation.test.tsx:1366 | should be able to throw an error when throwOnError is a function that returns true | N | error-boundary/throwOnError | |
| useMutation.test.tsx:1417 | should not throw an error when throwOnError is set to false | N | error-boundary/throwOnError: no option to set; without it the case is 1469 | |
| useMutation.test.tsx:1443 | should not throw an error when throwOnError is a function that returns false | N | error-boundary/throwOnError: same as 1417 | |
| useMutation.test.tsx:1469 | should not throw an error when throwOnError is not set | P | error lands in the result | |
| useMutation.test.tsx:1494 | should pass meta to mutation on success | P | its own client with `MutationCache(onSuccess: (…, mutation) => …mutation.meta)`; the harness has to `adopt` it | partial: mutation_observer_test 'mutation cache should have different meta when updated between mutations' |
| useMutation.test.tsx:1535 | should pass meta to mutation on error | P | as above | partial: same |
| useMutation.test.tsx:1578 | should call cache callbacks when unmounted | A | **ordering**: React unmounts inside `fireEvent.click(hide)`. Flutter's `pump(10ms)` elapses *before* it builds the frame (flutter_test binding.dart:1952-1960), so the component would still be mounted when the mutation settles and the per-call callbacks would run (1 ≠ 0). Insert `pump()` after tapping hide. The hook must `dispose` its controller on unmount, not `cancel` it | partial: mutation_cache_test 'should call callbacks even with gcTime 0 and mutation still pending'; mutation_test 'mutate update the mutation state even without an active subscription 1/2' |
| useMutation.test.tsx:1650 | should call mutate callbacks only for the last observer | A | two `mutate` calls on one hook; per-call callbacks only for the last. The callback assertions carry upstream's 4th `context` argument, which is dropped (no callback context) | |
| useMutation.test.tsx:1761 | should go to error state if onSuccess callback errors | A | drop the `context` argument; Dart `onError` gets `(error, stackTrace, vars, onMutateResult)` | partial: mutation_test 'error by mutations onSuccess triggers onError callback' |
| useMutation.test.tsx:1796 | should go to error state if onError callback errors | A | a throwing `onError` is reported to the zone, and testWidgets fails a test on any uncaught zone error (binding.dart:1544-1580). Wrap the tap in `runZonedGuarded` and collect what it catches. Upstream installs an `unhandledRejection` listener but asserts nothing about it | partial: mutation_observer_test 'onError and onSettled is reported to the zone'; mutation_test 'errors by onError and consecutive onSettled callbacks are reported to the zone' |
| useMutation.test.tsx:1841 | should go to error state if onSettled callback errors | A | zone capture as in 1796; drop the `context` argument | partial: same |
| useMutation.test.tsx:1893 | should use provided custom queryClient | A | rendered **without a provider**: the hook needs an explicit `client:`. With no provider the notify scheduler is the core's `scheduleMicrotask` (notify_manager.dart:76) and the client is not mounted. The harness `app()` always installs a provider, so this case needs a bare `MaterialApp` | |
| useMutation.test.tsx:1928 | should be able to chain mutateAsync calls sequentially | P | two `useMutation` in one widget (positional hook identity); flutter_hooks `useState`; `pump(10)` + `pump(11)` | |
| useMutation.test.tsx:1968 | should handle error in chained mutateAsync calls | P | | |
| useMutation.test.tsx:2014 | should set success message from mutate callbacks when mutation succeeds | P | `useState` set from per-call `onSuccess`; `retry: false` → `RetryPolicy.never` | |
| useMutation.test.tsx:2056 | should set error message from mutate callbacks when mutation fails | P | | |
| useMutation.test.tsx:2098 | should handle conditional error with retry using mutate | P | | |
| useMutation.test.tsx:2148 | should support optimistic update on success | P | `onMutate` writes hook-local `useState` synchronously (core: `onMutate` runs synchronously without a cache `onMutate`). Asserted after tap + `pump()`. The hook must re-apply options every build, because `onMutate` closes over this build's `items` | |
| useMutation.test.tsx:2205 | should support optimistic update and rollback on error | P | as above; rollback through `onMutateResult` | |
| useMutation.test.tsx:2267 | should update the cache in onMutate and roll back via onMutateResult in onError | P | updater `setQueryData` → `updateQueryData`; `cancelQueries(filters: …)` | |
| useMutation.test.tsx:2308 | should keep the optimistic update in place when the mutation succeeds | P | | |
| useMutation.test.tsx:2339 | should be able to run multiple mutateAsync calls in parallel with Promise.all | A | `Promise.all` → `Future.wait`; rename the case as the core did ('should handle Future.wait() patterns') | |
| useMutation.test.tsx:2378 | should handle Promise.all rejection when one parallel mutateAsync call fails | A | `Future.wait` (it waits for all, then throws the first error; the visible result is the same); rename | |
| useMutation.test.tsx:2426 | should handle partial failure in parallel mutateAsync calls with Promise.allSettled | A | Dart has no `allSettled`: map each future with `.then(ok, onError:)`; rename | |
| useMutation.test.tsx:2479 | should pass a non-undefined onMutateResult alongside context to onSuccess | A | the `data`/`variables`/`onMutateResult` half ports; the `context.client/meta/mutationKey` half is G (no callback context) | partial: mutation_observer_test callback-argument cases (onMutateResult) |
| useMutation.test.tsx:2507 | should give mutationFn the same QueryClient instance via context | A | `mutationFnWithContext: (v, ctx) => … ctx.client.getQueryData(key)` | partial: mutation_context_test 'the function is told the client, meta, key and what onMutate returned' |
| useMutation.test.tsx:2533 | should include mutationKey in the context passed to hook-level callbacks | G | **callback context**: `onSuccess`/`onError`/`onSettled` get no `MutationFunctionContext` (mutation_options.dart:156-200); deliberate divergence #14/#83 | |
| useMutation.test.tsx:2555 | should let onSuccess invalidate queries via context.client without a useQueryClient() closure | G | callback context, as above. The test exists to avoid the closure, so rewriting it over `useQueryClient()` defeats it | |

### useMutationState.test.tsx

#### `describe('useIsMutating')`

| file:line | name | verdict | note | dup-core |
|---|---|---|---|---|
| useMutationState.test.tsx:17 | should return the number of fetching mutations | A | **hardest render-count case**: `[0,1,2,1,0]` (the comment at 64-68 says the count may vary, then 71-77 assert it exactly). The last `advance(41)` covers two transitions (t=20: 2→1, t=50: 1→0), so split it into `pump(10ms)` + `pump(31ms)`, with tap + `pump()` before each. `useIsMutating` does not exist in the binding: build it over `MutationStateController` filtered on pending (see finding 5). Sibling observers | partial: query_client_test 'isMutating > should return length of mutating' |
| useMutationState.test.tsx:80 | should filter correctly by mutationKey | A | `mutate1(); mutate2()` run in `useEffect`. **flutter_hooks runs effects synchronously during build**, before the child `IsMutating` builds, so its first value is 1, not 0. Mirror React by posting the mutate from the effect to a post-frame callback. Expect `[0,1,0]` with `pump()` then `pump(100ms)` | partial: mutation_cache_test 'findAll > should filter correctly' |
| useMutationState.test.tsx:116 | should filter correctly by predicate | A | as in 80; predicate → `m.options.mutationKey?.parts.first == key1.parts.first` | partial: same |
| useMutationState.test.tsx:154 | should use provided custom queryClient | A | no provider: an explicit client on both hooks, microtask scheduler; mutate in `useEffect` (build-time effect, as in 80) | |

#### `describe('useMutationState')`

| file:line | name | verdict | note | dup-core |
|---|---|---|---|---|
| useMutationState.test.tsx:195 | should return variables after calling mutate | A | `variables == [[], [1], []]` is a render count. React renders `[1]` inside `advance(151)`; Flutter needs tap + `pump()`, then `pump(151ms)`. `select: (m) => m.state.variables` | |

### useIsFetching.test.tsx — `describe('useIsFetching')`

| file:line | name | verdict | note | dup-core |
|---|---|---|---|---|
| useIsFetching.test.tsx:18 | should update as queries start and stop fetching | A | `setReady` (`useState`) → the rebuild re-applies `enabled`, and the fetch starts **during build**. The provider delivers that notification post-frame (query_client_provider.dart:598-602), so 'isFetching: 1' needs a **second** `pump()` | partial: query_client_test 'isFetching > should return length of fetching queries'; binding functional_improvements_test 'is-fetching controller counts live…' |
| useIsFetching.test.tsx:60 | should not update state while rendering | A | render count `[0,1,1,2,1,0]`. Index 2 is a parent-driven re-render, so the `IsFetching` child must be **non-const** to rebuild with its parent. Index 1 comes through the provider's first-build microtask path (`debugBuilding`) and may already land in `pumpWidget`'s frame; verify empirically. Index 3 needs `pump(1ms)` after `pump(50ms)` (post-frame). Good evidence that a fetch started in build does not `setState` during build | partial: as above |
| useIsFetching.test.tsx:129 | should be able to filter | A | the children mount on `setStarted` and fetch in build, so the 'isFetching: 1' text needs an extra `pump()`. "Never 2" is weaker under frame coalescing; record from a listener to keep its strength | partial: as above |
| useIsFetching.test.tsx:188 | should show the correct fetching state when mounted after a query | P | provided the `useQuery` hook subscribes during build (so the fetch has started when `useIsFetching` reads), the first frame shows 1. If it subscribes post-frame, add one `pump()` | partial: as above |
| useIsFetching.test.tsx:214 | should use provided custom queryClient | A | no provider: an explicit client on `useQuery` and `useIsFetching`; `QueryCache(onSuccess:)` exists | |

### QueryClientProvider.test.tsx — `describe('QueryClientProvider')`

| file:line | name | verdict | note | dup-core |
|---|---|---|---|---|
| QueryClientProvider.test.tsx:21 | sets a specific cache for all queries to use | P | `queryCache.find(filters: QueryFilters(queryKey: key))?.state.data` | |
| QueryClientProvider.test.tsx:52 | allows multiple caches to be partitioned | P | two sibling `QueryClientProvider`s with distinct clients (each installs the scheduler on its own client's `NotifyManager`); a custom tree, since the harness `app()` wraps one provider; `adopt` the second client | |
| QueryClientProvider.test.tsx:108 | uses defaultOptions for queries when they don't provide their own config | P | `QueryDefaults(gcTime: GcTime.never)`; read `options.gcTime` | |
| QueryClientProvider.test.tsx:147 | (`describe('useQueryClient')`) should throw an error if no query client has been set | A | `useQueryClient()` → `QueryClientProvider.of`, which throws a `FlutterError` with a different message ('No QueryClientProvider found above this widget…'); catch it with `tester.takeException()` | |

### mutationOptions.test.tsx — `describe('mutationOptions')`

| file:line | name | verdict | note | dup-core |
|---|---|---|---|---|
| mutationOptions.test.tsx:20 | should return the object received as a parameter without any modification (with mutationKey in mutationOptions) | N | typescript-types: `mutationOptions()` is an identity helper for inference; Dart's `MutationOptions` value is the thing itself | |
| mutationOptions.test.tsx:29 | should return the object received as a parameter without any modification (without mutationKey in mutationOptions) | N | typescript-types | |
| mutationOptions.test.tsx:37 | should return the number of fetching mutations when used with useIsMutating (with mutationKey in mutationOptions) | P | `mutationOptions(x)` → `x`; `[0,1,0]` maps 1:1 (tap + `pump()`, `pump(51ms)`); needs the `useIsMutating` hook | |
| mutationOptions.test.tsx:83 | should return the number of fetching mutations when used with useIsMutating (without mutationKey in mutationOptions) | P | | |
| mutationOptions.test.tsx:128 | should return the number of fetching mutations when used with useIsMutating | P | two taps, one `pump()` → 2 | |
| mutationOptions.test.tsx:180 | should return the number of fetching mutations when used with useIsMutating (filter mutationOpts1.mutationKey) | P | | |
| mutationOptions.test.tsx:234 | should return the number of fetching mutations when used with queryClient.isMutating (with mutationKey in mutationOptions) | A | `queryClient.isMutating(mutationOpts)` passes the options object as filters (duck typing) → `isMutating(filters: MutationFilters(mutationKey: opts.mutationKey))`. Read in `build`; the rebuild comes from the `useMutation` result | partial: query_client_test 'isMutating > should return length of mutating' |
| mutationOptions.test.tsx:266 | should return the number of fetching mutations when used with queryClient.isMutating (without mutationKey in mutationOptions) | P | | partial: same |
| mutationOptions.test.tsx:297 | should return the number of fetching mutations when used with queryClient.isMutating | P | | partial: same |
| mutationOptions.test.tsx:335 | should return the number of fetching mutations when used with queryClient.isMutating (filter mutationOpt1.mutationKey) | P | `MutationFilters(mutationKey: …)` | partial: same |
| mutationOptions.test.tsx:375 | should return the number of fetching mutations when used with useMutationState (with mutationKey in mutationOptions) | P | `useMutationState` without `select` → the hook defaults to `m.state` (the controller requires `select`). `length == 1` depends on both hooks' success landing in **one** build; Flutter's coalescing gives the same | |
| mutationOptions.test.tsx:410 | should return the number of fetching mutations when used with useMutationState (without mutationKey in mutationOptions) | P | | |
| mutationOptions.test.tsx:444 | should return the number of fetching mutations when used with useMutationState | P | two mutations settle at the same fake time, one frame → 2 entries in insertion order | |
| mutationOptions.test.tsx:486 | should return the number of fetching mutations when used with useMutationState (filter mutationOpt1.mutationKey) | P | | |

### Counts

| file | P | A | N | G | total |
|---|---|---|---|---|---|
| useMutation.test.tsx | 38 | 17 | 4 | 2 | 61 |
| useMutationState.test.tsx | 0 | 5 | 0 | 0 | 5 |
| useIsFetching.test.tsx | 1 | 4 | 0 | 0 | 5 |
| QueryClientProvider.test.tsx | 3 | 1 | 0 | 0 | 4 |
| mutationOptions.test.tsx | 11 | 1 | 2 | 0 | 14 |
| **total** | **53** | **28** | **6** | **2** | **89** |

G-features: callback context (`MutationFunctionContext` as the 4th argument of `onSuccess`/`onError`/`onSettled` and the 2nd of `onMutate`): 2 cases as G (2533, 2555), plus 5 A cases that drop a context assertion (1117, 1650, 1761, 1841, 2479). This is a recorded divergence (#14/#83), not an oversight.
Not G but a decision: `useIsMutating` (no `IsMutatingController`), 8 cases (useMutationState 17/80/116/154, mutationOptions 37/83/128/180).

### Cross-cutting findings

1. **Observation and render counts.** Most `useMutation` cases assert on text (`getByText`, `getByRole('heading').textContent`), which does not depend on how many renders happened. The fragile ones record per render: useMutation 1028-1031 and 1216-1218; useMutationState 71-77, 113, 151, 242; useIsFetching 114-126 and 185; mutationOptions 75-80 (and the same block in each sibling case) and 402-407. Flutter builds one frame per `pump` and elapses time *before* that frame (flutter_test binding.dart:1952-1960). So each expected entry needs its own pump, and a state change that must land before time advances (unmount at 1578 and 1301, `setReady` at useIsFetching 53, `setStarted` at 178) needs a `pump()` first. A fetch started in build reaches its readers post-frame, which costs one more pump (useIsFetching 18, 60, 129). "No intermediate state" assertions (1216; useIsFetching 185) go vacuous under coalescing unless they are recorded in a listener.
2. **Timers.** `vi.useFakeTimers` + `advanceTimersByTimeAsync(n)` → `tester.pump(n ms)`, and `advance(0)` → `pump()`. Upstream needs `advance(0)` mostly to flush its `setTimeout(0)` notify scheduler; under the provider, query_kit delivers synchronously outside a build, post-frame inside one, and through a microtask during the first attach build (query_client_provider.dart:579-611). Without a provider it uses a microtask (notify_manager.dart:76). `sleep()` in a function is a FakeAsync timer; one left pending fails testWidgets' end-of-test timer check (1301). `retryDelay`/`gcTime: 0` timers created during an elapse still run within it.
3. **Helpers.** `renderWithClient` → the binding's `queryWidgetTest` + `pumpApp`; `setActTimeout` → `Timer` in `useEffect` (12 uses in useMutation, 1 in useIsFetching); `mockOnlineManagerIsOnline` (1063/1117/1176/1231) → `client.onlineManager.setOnline` (a real event that auto-resumes, unlike the spy); `queryKey`/`sleep` from query-test-utils → copies of core `test_utils.dart` (not exported); `vi.fn` → recorder lists; `process.on('unhandledRejection')` (1796/1841) → `runZonedGuarded`; `vi.spyOn(console.error)` appears only in N cases and in 147. `Blink`, `setIsServer` and `rerender` are not used in this slice.
4. **Hooks behaviour exercised.** Unmount mid-mutation (1301, 1578: options and cache callbacks run, per-call ones dropped, `gcTime: 0` collects; this matches `MutationController.dispose`, query_controller.dart:543-582). Last-mutate-wins for per-call callbacks (1650). `mutate`/`mutateAsync` identity as `useEffect` keys (136, 207, 339, 367, 400, 703, 737, 773, 807, 857, 999, 1034; useMutationState 80, 116, 154): Dart tear-offs from one controller are `==`, and flutter_hooks compares keys with `==`. `reset` (34, 66). Options re-applied every build, with `onMutate` closing over local state (2148, 2205). Two `useMutation` calls in one widget (1928 and the mutationOptions cases): hooks have positional identity, which avoids `context.mutation`'s key-based identity and its ambiguity assertion (read_set.dart:372-470). An explicit client with no provider (1893, 154, 214). **flutter_hooks `useEffect` runs synchronously in build, React's after commit**, which affects every case that mutates directly in an effect (useMutationState 102-105, 140-143, 168-170).
5. **`useIsMutating`.** Upstream exports it as a separate hook, but it is only `useMutationState({filters: {...filters, status: 'pending'}}, client).length` (useMutationState.ts:35-44). query_kit_flutter has **no `IsMutatingController`**. The documented answer is a `MutationStateController` filtered on pending, read for its length (coming-from-react-query.md:50; is_fetching_controller.dart doc); the snapshot is `client.isMutating()` (query_client.dart:603-611, which overrides `status` as upstream does). The hook can be built over `MutationStateController` with no binding change, or a `ValueListenable<int>` `IsMutatingController` can be added beside `IsFetchingController`. Related: `IsFetchingController.filters` is final (is_fetching_controller.dart:49-57), so a `useIsFetching(filters)` hook has to recreate it when the filters change, and `MutationStateController.select` is required where `useMutationState`'s is optional.

---

