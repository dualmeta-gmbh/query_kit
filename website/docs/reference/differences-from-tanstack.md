---
title: Differences from TanStack Query
description: Where query_kit behaves differently from TanStack Query on purpose — the shape of the API, the rules Dart's type system adds, and the failure cases it settles differently.
---

# Differences from TanStack Query

query_kit follows TanStack Query's behaviour: the same cache, the same
staleness and refetch rules, the same order of callbacks. Where it differs,
the difference is deliberate — usually because Dart or Flutter offers
something better, or because the JavaScript behaviour depends on something
Dart does not have. This page lists what you can notice. For a name-by-name
map, see [coming from React Query](../coming-from-react-query.md); for what
is not here at all, the [feature matrix](feature-matrix.md).

The last column of each table says where the difference was decided: a
ticket, a decision record, or a section of the porting notes, the audit trail
of the whole port. The notes are one long file that GitHub shows as plain
text, so the link opens the file and the link text names the section to
search for. For how query_kit sits among the other Dart packages, see [other
Dart libraries](other-dart-libraries.md).

## Types

| TanStack Query | query_kit | Decided in |
|---|---|---|
| `getQueryData` casts whatever is cached to the type you asked for | a key is bound to the exact type it was first used with; reading it as another type — a supertype or a nullable one included — throws `QueryDataTypeError`. A write may store any value the entry's type can hold. See [type safety in Dart](../dart-type-safety.md#one-key-one-exact-type) | [#7](https://github.com/dualmeta-gmbh/query_kit/issues/7); [porting notes, fourth review](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md); [porting notes, final functional review](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md) {/* jargon-ok */} |
| union-typed options: `staleTime: number \| 'static' \| fn`, `retry: boolean \| number \| fn`, … | sealed value types: `StaleTime`, `RetryPolicy`, `Enabled`, `RefetchOn`, `RefetchInterval`, … `null` always means "not configured" | [#10](https://github.com/dualmeta-gmbh/query_kit/issues/10) {/* jargon-ok */} |
| `staleTime: Infinity` | `StaleTime.infinite`, distinct from `StaleTime.static` | [#10](https://github.com/dualmeta-gmbh/query_kit/issues/10) {/* jargon-ok */} |
| `initialData: null` and `placeholderData: null` mean "none" | `InitialData.value(null)` is a value of `null`; a `.compute` returning `null` means "none" | [#10](https://github.com/dualmeta-gmbh/query_kit/issues/10); [porting notes, deliberate divergences](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md) {/* jargon-ok */} |
| one observer options object with an optional `select` | two shapes: `QueryObserverOptions<TData>` without `select`, `QuerySelectOptions<TQueryData, TData>` with `select` required. `withSelect` turns the first into the second | [the options-shape decision](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/adr/0001-one-type-slot-for-plain-queries.md); [#35](https://github.com/dualmeta-gmbh/query_kit/issues/35) {/* jargon-ok */} |
| `queryKeyHashFn`, keys hashed to strings | `QueryKey` is a value type compared part by part; `debugString` is for logs | [#8](https://github.com/dualmeta-gmbh/query_kit/issues/8) {/* jargon-ok */} |
| `TError` type parameter | errors are `Object` plus a `StackTrace` | [#7](https://github.com/dualmeta-gmbh/query_kit/issues/7) {/* jargon-ok */} |
| a `queryFn` that resolves to `undefined` fails the query at run time | cannot happen: the query function returns a `Future<T>`, and the type says whether `null` is a value | [#7](https://github.com/dualmeta-gmbh/query_kit/issues/7) {/* jargon-ok */} |
| a `refetchInterval` or `enabled` callback gets a typed `Query` | the callbacks of `StaleTime.dynamic`, `Enabled.when`, `RefetchInterval.dynamic` and `RefetchOn`'s computed form get a `Query<Object?>`, because the same values sit in `QueryDefaults`, which match every key and type. Cast `query.state.data` to your type inside the callback | [porting notes, release review of client, keys and mutations, LIB-4](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md) {/* jargon-ok */} |
| `setQueryData(key, undefined)` writes nothing | there is no `undefined`, and `null` is a value: `setQueryData<Product?>(key, null)` creates the entry and writes `null` into it. A bare `setQueryData(key, null)`, with no type, is treated as "write nothing". To leave the data alone from an updater, return `null` from `updateQueryData` | [#7](https://github.com/dualmeta-gmbh/query_kit/issues/7); [porting notes, pre-release deep-dive review, FI-18](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md); [porting notes, release review, L5-2](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md) {/* jargon-ok */} |
| an observer without `select` whose data type differs from the query's is not checked | refused with `ArgumentError` when it is built or handed new options; the binding's controllers also refuse a top-typed result type (`Object?`, `dynamic`) in debug builds | [porting notes, fifth review](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md); [the options-shape decision](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/adr/0001-one-type-slot-for-plain-queries.md) {/* jargon-ok */} |

## API shape

| TanStack Query | query_kit | Decided in |
|---|---|---|
| `fetchQuery`, `prefetchQuery`, `ensureQueryData` | one `client.query`: `await` it, `.ignore()` it, `staleTime: StaleTime.static`, or `revalidateIfStale: true`. See [prefetching](../guides/prefetching.md) | [#17](https://github.com/dualmeta-gmbh/query_kit/issues/17); [functional improvements plan](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/plans/functional-improvements.md) {/* jargon-ok */} |
| a positional filters object | a named `filters:` argument everywhere | [#17](https://github.com/dualmeta-gmbh/query_kit/issues/17); [porting notes, fifth review, N1](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md) {/* jargon-ok */} |
| `skipToken` | `Enabled.no` — which, unlike `skipToken`, lets `refetchQueries` refetch a query that nobody observes and that has been fetched before (see *Behaviour* below) | [#17](https://github.com/dualmeta-gmbh/query_kit/issues/17) {/* jargon-ok */} |
| `hasNextPage`, `fetchNextPage`, and `isRefetching` / `isRefetchError` corrected for page fetches, on the result | on the infinite query's controller or observer; the sealed result keeps one shape | [#16](https://github.com/dualmeta-gmbh/query_kit/issues/16); [porting notes, third review](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md) {/* jargon-ok */} |
| an infinite query's `queryFn` | `pageFn`, with a typed page context | [#16](https://github.com/dualmeta-gmbh/query_kit/issues/16) {/* jargon-ok */} |
| `useQueries` with a tuple of different types and `combine` | `QueriesBuilder` for a list of one type; different types combine as a record of results, `(a, b).combine(…)`. See [combining queries](../guides/combining-queries.md) | [#82](https://github.com/dualmeta-gmbh/query_kit/issues/82); [competitor study, section 6 item 13](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/research/competitor-deep-dive.md) {/* jargon-ok */} |
| `keepPreviousData` | `const PlaceholderData.keepPrevious()` | [functional improvements plan](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/plans/functional-improvements.md); [competitor study, section 6 item 4](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/research/competitor-deep-dive.md) {/* jargon-ok */} |
| `initialDataUpdatedAt` as a function | `initialDataUpdatedAtCompute` | [functional improvements plan](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/plans/functional-improvements.md) {/* jargon-ok */} |
| a mutation function's second argument | `mutationFnWithContext: (variables, context)`; plain `mutationFn` takes the variables only | [#83](https://github.com/dualmeta-gmbh/query_kit/issues/83) {/* jargon-ok */} |
| `mutate(variables, { onSuccess, … })` | `mutate(variables, callbacks: MutateCallbacks(…))` | [porting notes, ninth review, C23.8](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md) {/* jargon-ok */} |
| the rollback handle on the mutation result (`context`) | passed to `onSuccess`, `onError` and `onSettled`, not on `MutationResult` | [#14](https://github.com/dualmeta-gmbh/query_kit/issues/14); [porting notes, fourth review, A2](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md) {/* jargon-ok */} |
| module-level `focusManager`, `onlineManager`, `notifyManager` | instances owned by each `QueryClient`; `NotifyManager.shared` opts back into one shared manager | [#19](https://github.com/dualmeta-gmbh/query_kit/issues/19); [porting notes, third review](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md) {/* jargon-ok */} |
| `QueryClientProvider` always takes a client you made | `QueryClientProvider(client: …)` borrows one; `QueryClientProvider.create` builds its own and clears it when it goes. See [the reference](widgets-and-controllers.md#queryclientprovider) | [functional improvements plan](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/plans/functional-improvements.md); [competitor study, section 6 item 7](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/research/competitor-deep-dive.md) {/* jargon-ok */} |
| cache callbacks on a reassignable `config` | final constructor arguments of `QueryCache` and `MutationCache` | [#66](https://github.com/dualmeta-gmbh/query_kit/issues/66) {/* jargon-ok */} |
| `subscribe` keeps its listeners in a `Set`, so subscribing one function twice registers it once, and either unsubscribe removes it | every `subscribe` is its own registration, and the function it returns removes that one only, once — because two tear-offs of one method are `==` in Dart, and a `Set` would let one subscriber's unsubscribe silence another | [porting notes, a Set of listeners does not port](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md); [#59](https://github.com/dualmeta-gmbh/query_kit/issues/59) {/* jargon-ok */} |
| `persister`, `hydrate`, `dehydrate`, `isRestoring` | not in 1.0: the cache lives in memory. `Query.setState`, `setQueryData(…, updatedAt:)` and the cache's events are the points a persister connects to; see [offline first and persistence](../cookbook/offline-first-and-persistence.md) and the [feature matrix](feature-matrix.md) | [#15](https://github.com/dualmeta-gmbh/query_kit/issues/15); [#17](https://github.com/dualmeta-gmbh/query_kit/issues/17) {/* jargon-ok */} |

## Rebuilds

| TanStack Query | query_kit | Decided in |
|---|---|---|
| `notifyOnChangeProps` and tracked result properties | whole results are compared; `buildWhen` narrows rebuilds explicitly. See [what rebuilds](../guides/render-optimizations.md) | [#15](https://github.com/dualmeta-gmbh/query_kit/issues/15) {/* jargon-ok */} |
| `throwOnError` | errors live in the sealed result | [#15](https://github.com/dualmeta-gmbh/query_kit/issues/15) {/* jargon-ok */} |
| a `select` memo kept while the selector and its input are `===` the last ones | kept while both are `==` — two tear-offs of one method count as one selector, and data with value equality (a record, a value class, `InfiniteData`) that comes back equal is not selected again | [porting notes, ninth review, C14](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md) {/* jargon-ok */} |
| `replaceEqualDeep` walks arrays and plain objects; a `Map`, a `Set` or a class instance is replaced | lists are shared element by element, maps and sets whole when deep-equal, `InfiniteData`'s pages and params each on its own; typed data (`Uint8List`) and any other class are leaves compared with `==`, unless the class implements `StructurallyShareable`. A custom `structuralSharing` hook is typed to the query's data, so it covers the cache write but not a `select`'s output; `noStructuralSharing()` is the one spelling that switches both off. See [structural sharing](../guides/structural-sharing.md) | [#12](https://github.com/dualmeta-gmbh/query_kit/issues/12); [porting notes, sharing a map whole: what it costs](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md); [porting notes, fifth review](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md) {/* jargon-ok */} |
| an observer's listeners are told about every state change | a listener is told only when the new result is not `==` to the last one it was told. On a mutation that means fewer intermediate states: one `pending` across `onMutate`, not two | [porting notes, fourth review, A19](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md); [porting notes, pre-release deep-dive review, FI-02](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md) {/* jargon-ok */} |
| notifications are batched to the next macrotask (`setTimeout(0)`) | batched to a microtask, so a batch lands before the next frame rather than after it. `NotifyManager.setScheduler` puts the old timing back | [#19](https://github.com/dualmeta-gmbh/query_kit/issues/19) {/* jargon-ok */} |
| a listener that subscribes during a notification hears that same notification | it hears the next one; a listener removed during a notification is skipped, as in TanStack Query | [#59](https://github.com/dualmeta-gmbh/query_kit/issues/59); [porting notes, deliberate divergences](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md) {/* jargon-ok */} |
| a side effect on a query result needs a component that also renders | `QueryListener`, `InfiniteQueryListener` and `MutationListener` run a callback per accepted change and never rebuild their child. See [the reference](widgets-and-controllers.md#listeners) | [functional improvements plan](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/plans/functional-improvements.md); [competitor study, section 6 item 8](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/research/competitor-deep-dive.md) {/* jargon-ok */} |

## Behaviour

| TanStack Query | query_kit | Decided in |
|---|---|---|
| a fetch with no query function is retried like any failure | `MissingQueryFunctionError` is never retried, and neither is `MissingMutationFunctionError` | [porting notes, fourth review, A20](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md) {/* jargon-ok */} |
| an imperative fetch with no retry policy writes `retry: 0` into the shared query | the one-attempt rule applies to that fetch alone | [porting notes, fifth review, item 48](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md) {/* jargon-ok */} |
| a state-dependent filter on `invalidateQueries` refetches none of what it invalidated | the matched set is fixed before invalidating, so it refetches what it marked | [porting notes, fifth review, item 49](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md) {/* jargon-ok */} |
| a filter predicate that throws, throws synchronously out of the bulk operations | `invalidateQueries`, `refetchQueries`, `resetQueries` and `cancelQueries` fail their returned future instead; `removeQueries`, which returns nothing, still throws where it is called | [porting notes, pre-release deep-dive review, AR-12](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md) {/* jargon-ok */} |
| a throwing listener, `retry` or `retryDelay` callback can leave a fetch pending forever | the throw is reported to the zone, or becomes the fetch's error; the fetch settles | [porting notes, third review](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md); [porting notes, fourth review](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md) {/* jargon-ok */} |
| a silent cancel with no successor leaves `fetchStatus: 'fetching'` | it is put back to `idle` | [porting notes, eighth review](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md); [porting notes, ninth review, C9](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md) {/* jargon-ok */} |
| a cancelled fetch's late response can still write over the fetch that replaced it | only the fetch that currently owns the query writes; a cancelled one settles into nothing, and a third caller joins the running fetch instead of starting another | [the operation-lifetimes decision](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/adr/0003-core-operation-lifetimes.md); [porting notes, deliberate divergences](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md) {/* jargon-ok */} |
| a cancelled fetch's retry delay still runs to its end | the delay is dropped with the fetch | [porting notes, third review](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md) {/* jargon-ok */} |
| a `retryDelay` callback runs once more than there are retries, after the final failure too | it runs only when a retry follows | [porting notes, pre-release deep-dive review, DC-16](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md) {/* jargon-ok */} |
| two callers of one fetch can see its result before the cache has it | every caller's future completes after the cache is written and its callbacks ran, so callers and cache agree | [porting notes, fifth review, item 45](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md) {/* jargon-ok */} |
| an `enabled` callback over state outside the cache is never seen to change | it is re-read on the next `setOptions` — in Flutter, the reader's next rebuild — and a query that became enabled then fetches if stale. See [dependent queries](../guides/dependent-queries.md) | [#84](https://github.com/dualmeta-gmbh/query_kit/issues/84) {/* jargon-ok */} |
| `refetchQueries`, and `invalidateQueries` with `refetchType: 'all'`, skip an unobserved query whose `queryFn` is `skipToken` even when it holds data | `Enabled.no` spells both `skipToken` and `enabled: false`, and the second meaning is kept: an explicit refetch includes an unobserved query that has been fetched before, whatever its last reader's `enabled` was. `enabled` governs automatic fetching only | [porting notes, final review of the pre-release branch, F2 and F3](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md) {/* jargon-ok */} |
| a listener that reacts to a query's `fetch` event finds nothing to cancel or join yet | the fetch is in place before the event goes out: `cancelQueries` from that listener stops the request, and `client.query` of the same key joins it | [porting notes, fifth review, item 44](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md) {/* jargon-ok */} |
| an observer subscribed again after its query was garbage-collected rejoins the dead query | it looks the key up again and joins the entry that is in the cache now | [porting notes, deliberate divergences](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md) {/* jargon-ok */} |
| a `select` that threw keeps reporting its error after `select` is removed, and a kept placeholder keeps its old selection after `select` changes | the error goes with the selector and the raw data is reported; a new `select` runs over the placeholder | [porting notes, deliberate divergences](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md) {/* jargon-ok */} |
| `resetQueries` on a query nobody observes leaves it in the cache for good | it is garbage-collected after its `gcTime`, like any unobserved query | [porting notes, third review](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md) {/* jargon-ok */} |
| a `select` that throws on a new key's first data shows the previous key's (or the placeholder's) selection as stale data | it is a loading error with no stale data: a selection belongs to the key it came from | [porting notes, pre-release deep-dive review, OB-01](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md) {/* jargon-ok */} |
| every foreground event refetches stale queries | the same by default; `refetchMinBackgroundDuration` can skip a refetch after a short absence. See [app focus refetching](../guides/window-focus-refetching.md) | [functional improvements plan](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/plans/functional-improvements.md); [competitor study, section 6 item 3](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/research/competitor-deep-dive.md) {/* jargon-ok */} |
| `resumePausedMutations` waits for the whole client to be online | decided per mutation by its own network mode | [porting notes, fifth review, item 47](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md); [porting notes, ninth review, C4](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md) {/* jargon-ok */} |
| `await resumePausedMutations()` can complete before the resumed mutations' `onSuccess` ran, so a refetch can overtake their cache writes | it completes after every resumed run has settled and its callbacks have run | [porting notes, ninth review, C10](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md) {/* jargon-ok */} |
| a mutation's `setOptions` while it runs can move it to another scope | the scope is fixed for the run | [porting notes, fifth review, item 46](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md) {/* jargon-ok */} |
| a scope's turn goes to the earliest-*built* pending mutation | it goes to the one that started first, and it holds the scope until its callbacks have run | [the operation-lifetimes decision](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/adr/0003-core-operation-lifetimes.md) {/* jargon-ok */} |
| removing a scope's queued mutation that never started leaves the rest of the queue paused until the next resume | the next one in the scope starts; `clear()` empties the cache first, so nothing it drops starts | [the operation-lifetimes decision](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/adr/0003-core-operation-lifetimes.md); [porting notes, pre-release deep-dive review, MU-01](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md) {/* jargon-ok */} |
| two same-scope mutations with a synchronous `onMutate` run `optimistic 1, optimistic 2, request 1` | `optimistic 1, request 1, optimistic 2`: a synchronous `onMutate` goes straight to the request, so an optimistic update reaches the frame that asked for it | [the operation-lifetimes decision](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/adr/0003-core-operation-lifetimes.md) {/* jargon-ok */} |
| a mutation removed from the cache keeps retrying, or stays paused for good | it stops, and fails with its last error or a `CancelledError`; its `onError` runs a moment later, which is why a widget test's teardown clears the client twice. See [testing](../guides/testing.md) | [porting notes, third and fourth review](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md); [porting notes, ninth review, C5 and C11](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md) {/* jargon-ok */} |
| `mutate` on a forgotten observer re-attaches it | `mutate` on a disposed `MutationController` still runs the mutation and its options' callbacks, attaches nothing, and drops the per-call callbacks | [porting notes, ninth review, C18](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md) {/* jargon-ok */} |
| a mutation observer's `setOptions` before its first `mutate` emits `observerOptionsUpdated` with no mutation | nothing is emitted until the observer has a mutation | [porting notes, pre-release deep-dive review, FI-09](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md) {/* jargon-ok */} |
| mutation defaults may carry callbacks | `setMutationDefaults` carries no callbacks | [#14](https://github.com/dualmeta-gmbh/query_kit/issues/14); [#83](https://github.com/dualmeta-gmbh/query_kit/issues/83) {/* jargon-ok */} |
| mutations cannot be cancelled | `cancel()` fails a run with `CancelledError`; see [cancelling mutations](../guides/cancelling-mutations.md) | [#83](https://github.com/dualmeta-gmbh/query_kit/issues/83) {/* jargon-ok */} |

## Hooks

The optional add-on [`query_kit_hooks`](../guides/hooks.md) has React Query's
hook names, and React Query's own hook tests are ported and run against it.
Where it differs:

| React Query | `query_kit_hooks` | Decided in |
|---|---|---|
| `notifyOnChangeProps` and tracked result properties | `buildWhen` on the hooks that read one result: `useQuery`, `useSelectQuery`, `useInfiniteQuery`, `useMutation`, `useCombinedQueries`. `useQueries` takes none, as `QueriesBuilder` takes none, so a refetch's fetching state costs it a build of its own | [hooks plan, D8](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/plans/hooks-package.md); [#15](https://github.com/dualmeta-gmbh/query_kit/issues/15) {/* jargon-ok */} |
| a component renders each change it is notified of on its own, a batch of notifications through `notifyManager` as one | a widget builds once per frame, for every notification before it, so two changes React renders apart can be one build | [hooks plan, D8](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/plans/hooks-package.md) {/* jargon-ok */} |
| `useQueries({ queries, combine })` | `useCombinedQueries(queries, combiner, keys: …)`, which returns a `CombinedResult`: pending until every query has data, with the combiner run over the values rather than the results. It runs again when a value or a key changes, not on every build, so what it captures goes in `keys:` where React wraps it in `useCallback`. There is no raw `combine` | [hooks plan, D10](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/plans/hooks-package.md); [#82](https://github.com/dualmeta-gmbh/query_kit/issues/82) {/* jargon-ok */} |
| `useInfiniteQuery` returns a result with `hasNextPage`, `fetchNextPage`, … | it returns the `InfiniteQueryController`: the result in `value`, the paging flags and `fetchNextPage` beside it | [hooks plan, D9](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/plans/hooks-package.md) {/* jargon-ok */} |
| `useMutation` returns a result with `mutate`, `mutateAsync`, `reset` | it returns the `MutationController`: the result in `value`, `mutate`, `mutateAsync` and `reset` its members | [hooks plan, D9](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/plans/hooks-package.md) {/* jargon-ok */} |
| `useMutationState` with an optional `select` | `select` is required, and `useTypedMutationState` selects from mutations of one type, typed | [hooks plan, D9](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/plans/hooks-package.md) {/* jargon-ok */} |
| `useQueryClient(queryClient?)` | `useQueryClient()` takes no client; the other hooks take `client:`. A missing provider throws the binding's `FlutterError`, not "No QueryClient set" | [hooks plan, D7](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/plans/hooks-package.md) {/* jargon-ok */} |
| `usePrefetchQuery` and `usePrefetchInfiniteQuery` beside the Suspense hooks | no Suspense: the reader shows its own pending state | [hooks plan, D11](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/plans/hooks-package.md); [hooks plan, D14](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/plans/hooks-package.md) {/* jargon-ok */} |
| the mutation callbacks' last argument, the mutation function context | not passed: `onMutate` gets the variables alone, and the other callbacks end at `onMutateResult` | [hooks plan, D14](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/plans/hooks-package.md); [#83](https://github.com/dualmeta-gmbh/query_kit/issues/83) {/* jargon-ok */} |
| the Suspense hooks, `throwOnError`, `HydrationBoundary`, `useIsRestoring`, `subscribed`, `skipToken`, `retryOnMount` as a function | not in the package; see [not in this package](../guides/hooks.md#not-in-this-package) | [hooks plan, D14](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/plans/hooks-package.md); [#92](https://github.com/dualmeta-gmbh/query_kit/issues/92) {/* jargon-ok */} |

One difference comes from `flutter_hooks` rather than from React Query: a
build that throws disposes the hooks from the throw on, and the next build
creates them anew. [When a build throws](../guides/hooks.md#when-a-build-throws)
says what that costs a fetch or a mutation in flight.

## Dart and Flutter only

- **Structural sharing into your own classes.** A class implementing
  `StructurallyShareable` is walked into; any other class is a leaf. See
  [structural sharing](../guides/structural-sharing.md).
- **`consecutiveErrorCount`** on the query's state and result, for giving up
  after failures in a row. See [polling](../guides/polling.md).
- **App lifecycle as focus.** `inactive` counts as focused on phones and as
  unfocused on desktops.
- **`refetchMinBackgroundDuration`** on the focus manager, so a glance at a
  notification does not refetch every stale query on return.
- **`combine` over a record of results**, of different types, with a
  `CombinedResult` that is pending, an error or data. See [combining
  queries](../guides/combining-queries.md).
- **Cancellation is `QueryCancelToken`**, with `onCancel` as the interop point,
  because Dart has no ecosystem-wide abort signal.

## Robustness

Some JavaScript behaviours leave a fetch hanging when user code throws in an
unexpected place. Here every such throw either becomes the fetch's error or is
reported to the zone (`FlutterError.onError` in an app), and the fetch
settles either way:

- a throwing `retry` or `retryDelay` callback is the fetch's error;
- a throwing cache listener, observer listener, focus or online listener, or
  a callback queued in a notification batch, is reported to the zone, and the
  listeners after it still run;
- a throwing cancel callback is reported, and the other cancel callbacks
  still run;
- a query or mutation removed from its cache cannot be added back, so one key
  never has two live entries;
- a dynamic option that throws while an observer subscribes, or while it is
  handed new options, leaves the observer as it was — nothing half-registered,
  nothing half-switched — and the throw reaches the caller;
- an observer destroyed from inside its own notification stays destroyed: no
  timer it scheduled re-arms polling.

Every one of these is covered by a test in the core package's suite. The
[errors reference](errors.md#errors-from-callbacks-and-listeners) says what
each throw becomes.
