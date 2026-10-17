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

The last column of each table gives the reason in a clause. [Where these were
decided](#where-these-were-decided) says where the full reasoning is. For how
query_kit sits among the other Dart packages, see [other Dart
libraries](other-dart-libraries.md).

## Types

| TanStack Query | query_kit | Why |
|---|---|---|
| `getQueryData` casts whatever is cached to the type you asked for | a key is bound to the exact type it was first used with; reading it as another type — a supertype or a nullable one included — throws `QueryDataTypeError`. A write may store any value the entry's type can hold. See [type safety in Dart](../dart-type-safety.md#one-key-one-exact-type) | A blind cast hides a wrong type until it fails far from the cause. One key with one exact type turns the mismatch into an error at the read. |
| union-typed options: `staleTime: number \| 'static' \| fn`, `retry: boolean \| number \| fn`, … | sealed value types: `StaleTime`, `RetryPolicy`, `Enabled`, `RefetchOn`, `RefetchInterval`, … `null` always means "not configured" | Dart has no union types, so each choice is a sealed value type the compiler can check. |
| `staleTime: Infinity` | `StaleTime.infinite`, distinct from `StaleTime.static` | Never stale but still refetchable is not the same as static, so the two have different names. |
| `initialData: null` and `placeholderData: null` mean "none" | `InitialData.value(null)` is a value of `null`; a `.compute` returning `null` means "none" | `null` can be real data in Dart, so a named constructor says whether you mean a value or none. |
| one observer options object with an optional `select` | two shapes: `QueryObserverOptions<TData>` without `select`, `QuerySelectOptions<TQueryData, TData>` with `select` required. `withSelect` turns the first into the second | With one options type, leaving out `select` let the data type infer as `dynamic`. Two shapes close that hole. |
| `queryKeyHashFn`, keys hashed to strings | `QueryKey` is a value type compared part by part; `debugString` is for logs | A key compares as a value, so no hash string is needed. The string is only for logs. |
| `TError` type parameter | errors are `Object` plus a `StackTrace` | Dart can throw any object, so a type for the error would promise more than the language can keep. |
| a `queryFn` that resolves to `undefined` fails the query at run time | cannot happen: the query function returns a `Future<T>`, and the type says whether `null` is a value | There is no `undefined`, and the `Future<T>` type already says whether `null` is a value. |
| a `refetchInterval` or `enabled` callback gets a typed `Query` | the callbacks of `StaleTime.dynamic`, `Enabled.when`, `RefetchInterval.dynamic` and `RefetchOn`'s computed form get a `Query<Object?>`, because the same values sit in `QueryDefaults`, which match every key and type. Cast `query.state.data` to your type inside the callback | The same option values sit in client defaults that match every key and type, so they cannot depend on the data type. A typed form could be added later. |
| `setQueryData(key, undefined)` writes nothing | there is no `undefined`, and `null` is a value: `setQueryData<Product?>(key, null)` creates the entry and writes `null` into it. A bare `setQueryData(key, null)`, with no type, is treated as "write nothing". To leave the data alone from an updater, return `null` from `updateQueryData` | Dart has no `undefined` and `null` is a value, so writing `null` creates the entry. Only an untyped `null` is read as "write nothing". |
| an observer without `select` whose data type differs from the query's is not checked | refused with `ArgumentError` when it is built or handed new options; the binding's controllers also refuse a top-typed result type (`Object?`, `dynamic`) in debug builds | A data type that differs from the query's would fail later at a read, so it is refused when the observer is built. |

## API shape

| TanStack Query | query_kit | Why |
|---|---|---|
| `fetchQuery`, `prefetchQuery`, `ensureQueryData` | one `client.query`: `await` it, `.ignore()` it, `staleTime: StaleTime.static`, or `revalidateIfStale: true`. See [prefetching](../guides/prefetching.md) | Upstream deprecates all three. One method with options covers prefetching, ensuring and stale-while-revalidate. |
| a positional filters object | a named `filters:` argument everywhere | One spelling everywhere, so `find(filters)` next to `findAll(filters:)` is not a trap. |
| `skipToken` | `Enabled.no` — which, unlike `skipToken`, lets `refetchQueries` refetch a query that nobody observes and that has been fetched before (see *Behaviour* below) | `Enabled.no` covers both `skipToken` and `enabled: false`, so a query is switched off one way. |
| `hasNextPage`, `fetchNextPage`, and `isRefetching` / `isRefetchError` corrected for page fetches, on the result | on the infinite query's controller or observer; the sealed result keeps one shape | The paging flags live where the infinite query is observed, so the sealed result keeps one shape. |
| an infinite query's `queryFn` | `pageFn`, with a typed page context | A page function gets a typed page context instead of a loose argument. |
| `useQueries` with a tuple of different types and `combine` | `QueriesBuilder` for a list of one type; different types combine as a record of results, `(a, b).combine(…)`. See [combining queries](../guides/combining-queries.md) | A list of queries has one data type. Different types combine as a record of results, which the type checker can follow. |
| `keepPreviousData` | `const PlaceholderData.keepPrevious()` | A constant survives the observer's placeholder caching, which a fresh closure each build would not. |
| `initialDataUpdatedAt` as a function | `initialDataUpdatedAtCompute` | Dart has no value-or-function union, so the function form is its own option, evaluated only when data is seeded. |
| a mutation function's second argument | `mutationFnWithContext: (variables, context)`; plain `mutationFn` takes the variables only | Most mutations need only their variables, so the plain form stays simple and the context form is separate and typed. |
| `mutate(variables, { onSuccess, … })` | `mutate(variables, callbacks: MutateCallbacks(…))` | The result's `mutate` takes the variables only. Per-call callbacks go through a named `MutateCallbacks` object. |
| the rollback handle on the mutation result (`context`) | passed to `onSuccess`, `onError` and `onSettled`, not on `MutationResult` | A third type parameter on the sealed result would tax every `switch` on it for a value only the callbacks need. |
| module-level `focusManager`, `onlineManager`, `notifyManager` | instances owned by each `QueryClient`; `NotifyManager.shared` opts back into one shared manager | Managers owned by each client keep two clients, or two tests, from sharing state. |
| `QueryClientProvider` always takes a client you made | `QueryClientProvider(client: …)` borrows one; `QueryClientProvider.create` builds its own and clears it when it goes. See [the reference](widgets-and-controllers.md#queryclientprovider) | A provider that built its client can clear it when it leaves, which a borrowed client must never be. |
| cache callbacks on a reassignable `config` | final constructor arguments of `QueryCache` and `MutationCache` | Nothing upstream reassigns them, and a handler that has to change can close over a variable its owner swaps. |
| `subscribe` keeps its listeners in a `Set`, so subscribing one function twice registers it once, and either unsubscribe removes it | every `subscribe` is its own registration, and the function it returns removes that one only, once — because two tear-offs of one method are `==` in Dart, and a `Set` would let one subscriber's unsubscribe silence another | Two tear-offs of one method are `==` in Dart, so a `Set` let one subscriber's unsubscribe silence another's. |
| `persister`, `hydrate`, `dehydrate`, `isRestoring` | not in 1.0: the cache lives in memory. `Query.setState`, `setQueryData(…, updatedAt:)` and the cache's events are the points a persister connects to; see [offline first and persistence](../cookbook/offline-first-and-persistence.md) and the [feature matrix](feature-matrix.md) | A persister needs a storage format and a way to hydrate, which 1.0 leaves to the app. The cache's write and event hooks are the way in. |

## Rebuilds

| TanStack Query | query_kit | Why |
|---|---|---|
| `notifyOnChangeProps` and tracked result properties | whole results are compared; `buildWhen` narrows rebuilds explicitly. See [what rebuilds](../guides/render-optimizations.md) | `select` narrows what a reader sees and `buildWhen` narrows what rebuilds it, instead of tracking which properties were read. |
| `throwOnError` | errors live in the sealed result | Errors are data in the sealed result, so there is nothing to throw into a boundary. |
| a `select` memo kept while the selector and its input are `===` the last ones | kept while both are `==` — two tear-offs of one method count as one selector, and data with value equality (a record, a value class, `InfiniteData`) that comes back equal is not selected again | Two tear-offs of one method are `==` in Dart, so equality, not identity, tells whether the selector changed. |
| `replaceEqualDeep` walks arrays and plain objects; a `Map`, a `Set` or a class instance is replaced | lists are shared element by element, maps and sets whole when deep-equal, `InfiniteData`'s pages and params each on its own; typed data (`Uint8List`) and any other class are leaves compared with `==`, unless the class implements `StructurallyShareable`. A custom `structuralSharing` hook is typed to the query's data, so it covers the cache write but not a `select`'s output; `noStructuralSharing()` is the one spelling that switches both off. See [structural sharing](../guides/structural-sharing.md) | Dart has no plain objects to walk. Lists and maps are shared by value, and other classes opt in with `StructurallyShareable`. |
| an observer's listeners are told about every state change | a listener is told only when the new result is not `==` to the last one it was told. On a mutation that means fewer intermediate states: one `pending` across `onMutate`, not two | A listener told only about a result that differs from the last one it heard saves rebuilds that show nothing new. |
| notifications are batched to the next macrotask (`setTimeout(0)`) | batched to a microtask, so a batch lands before the next frame rather than after it. `NotifyManager.setScheduler` puts the old timing back | A microtask lands before the next frame, which is what a Flutter screen wants. The old timing is one setting away. |
| a listener that subscribes during a notification hears that same notification | it hears the next one; a listener removed during a notification is skipped, as in TanStack Query | Delivering to a snapshot keeps a listener added mid-notification out of a round it did not ask for. |
| a side effect on a query result needs a component that also renders | `QueryListener`, `InfiniteQueryListener` and `MutationListener` run a callback per accepted change and never rebuild their child. See [the reference](widgets-and-controllers.md#listeners) | A callback that never rebuilds its child lets a side effect run without costing a build. |

## Behaviour

| TanStack Query | query_kit | Why |
|---|---|---|
| a fetch with no query function is retried like any failure | `MissingQueryFunctionError` is never retried, and neither is `MissingMutationFunctionError` | It is a configuration error, so retrying only delays the message. |
| an imperative fetch with no retry policy writes `retry: 0` into the shared query | the one-attempt rule applies to that fetch alone | One attempt for one call should not change the query's options for everyone else. |
| a state-dependent filter on `invalidateQueries` refetches none of what it invalidated | the matched set is fixed before invalidating, so it refetches what it marked | A filter over the state it changes must be read once, before the change, or it matches nothing afterwards. |
| a filter predicate that throws, throws synchronously out of the bulk operations | `invalidateQueries`, `refetchQueries`, `resetQueries` and `cancelQueries` fail their returned future instead; `removeQueries`, which returns nothing, still throws where it is called | These operations return futures, so a throw becomes a failed future like any other error. |
| a throwing listener, `retry` or `retryDelay` callback can leave a fetch pending forever | the throw is reported to the zone, or becomes the fetch's error; the fetch settles | One bad callback must not leave a fetch pending forever, so the throw becomes the fetch's error or is reported. |
| a silent cancel with no successor leaves `fetchStatus: 'fetching'` | it is put back to `idle` | Otherwise the status claims a fetch that is not running. |
| a cancelled fetch's late response can still write over the fetch that replaced it | only the fetch that currently owns the query writes; a cancelled one settles into nothing, and a third caller joins the running fetch instead of starting another | A cancelled fetch must not overwrite the one that replaced it. |
| a cancelled fetch's retry delay still runs to its end | the delay is dropped with the fetch | A cancelled fetch has nothing left to retry, so the wait only holds a timer. |
| a `retryDelay` callback runs once more than there are retries, after the final failure too | it runs only when a retry follows | The callback can have side effects such as a counter or a log, so it runs only when a retry follows. |
| two callers of one fetch can see its result before the cache has it | every caller's future completes after the cache is written and its callbacks ran, so callers and cache agree | Every caller should see the same state as the cache when its future completes. |
| an `enabled` callback over state outside the cache is never seen to change | it is re-read on the next `setOptions` — in Flutter, the reader's next rebuild — and a query that became enabled then fetches if stale. See [dependent queries](../guides/dependent-queries.md) | State outside the cache cannot notify the observer, so the next hand-over of options reads it again. |
| `refetchQueries`, and `invalidateQueries` with `refetchType: 'all'`, skip an unobserved query whose `queryFn` is `skipToken` even when it holds data | `Enabled.no` spells both `skipToken` and `enabled: false`, and the second meaning is kept: an explicit refetch includes an unobserved query that has been fetched before, whatever its last reader's `enabled` was. `enabled` governs automatic fetching only | `Enabled.no` also means `enabled: false`, which switches off automatic fetching and not an explicit refetch. |
| a listener that reacts to a query's `fetch` event finds nothing to cancel or join yet | the fetch is in place before the event goes out: `cancelQueries` from that listener stops the request, and `client.query` of the same key joins it | Cancelling or joining from a fetch listener needs the fetch to exist already. |
| an observer subscribed again after its query was garbage-collected rejoins the dead query | it looks the key up again and joins the entry that is in the cache now | Rejoining a removed query would revive a dead entry, so the key is looked up again. |
| a `select` that threw keeps reporting its error after `select` is removed, and a kept placeholder keeps its old selection after `select` changes | the error goes with the selector and the raw data is reported; a new `select` runs over the placeholder | A selection error belongs to the selector that threw it, so removing or changing `select` clears it. |
| `resetQueries` on a query nobody observes leaves it in the cache for good | it is garbage-collected after its `gcTime`, like any unobserved query | An unobserved entry should leave the cache after its `gcTime` like any other. |
| a `select` that throws on a new key's first data shows the previous key's (or the placeholder's) selection as stale data | it is a loading error with no stale data: a selection belongs to the key it came from | A selection belongs to the key it came from, so another key's selection is not stale data. |
| every foreground event refetches stale queries | the same by default; `refetchMinBackgroundDuration` can skip a refetch after a short absence. See [app focus refetching](../guides/window-focus-refetching.md) | Leaving the app for a moment to read a notification should not refetch every stale query on return. |
| `resumePausedMutations` waits for the whole client to be online | decided per mutation by its own network mode | A mutation's own network mode, not the state of the whole client, decides whether it can go. |
| `await resumePausedMutations()` can complete before the resumed mutations' `onSuccess` ran, so a refetch can overtake their cache writes | it completes after every resumed run has settled and its callbacks have run | Awaiting should mean the work is done, so a refetch cannot overtake the resumed writes. |
| a mutation's `setOptions` while it runs can move it to another scope | the scope is fixed for the run | A running mutation holds its place in its scope's queue, and moving it mid-run would break the order. |
| a scope's turn goes to the earliest-*built* pending mutation | it goes to the one that started first, and it holds the scope until its callbacks have run | The mutation that started first keeps the scope until its callbacks have run, so writes do not overlap. |
| removing a scope's queued mutation that never started leaves the rest of the queue paused until the next resume | the next one in the scope starts; `clear()` empties the cache first, so nothing it drops starts | A queue should not stall because the mutation at its head was removed. |
| two same-scope mutations with a synchronous `onMutate` run `optimistic 1, optimistic 2, request 1` | `optimistic 1, request 1, optimistic 2`: a synchronous `onMutate` goes straight to the request, so an optimistic update reaches the frame that asked for it | A synchronous `onMutate` needs no artificial wait, so an optimistic update reaches the frame that asked for it. |
| a mutation removed from the cache keeps retrying, or stays paused for good | it stops, and fails with its last error or a `CancelledError`; its `onError` runs a moment later, which is why a widget test's teardown clears the client twice. See [testing](../guides/testing.md) | A removed mutation should stop and settle, not retry or wait for ever. |
| `mutate` on a forgotten observer re-attaches it | `mutate` on a disposed `MutationController` still runs the mutation and its options' callbacks, attaches nothing, and drops the per-call callbacks | A disposed controller can still run its mutation, but nothing should attach to a screen that is gone. |
| a mutation observer's `setOptions` before its first `mutate` emits `observerOptionsUpdated` with no mutation | nothing is emitted until the observer has a mutation | Nothing has changed in the cache yet, so there is nothing for a listener to hear. |
| mutation defaults may carry callbacks | `setMutationDefaults` carries no callbacks | Defaults have no place to receive the typed context, so they carry options only. |
| mutations cannot be cancelled | `cancel()` fails a run with `CancelledError`; see [cancelling mutations](../guides/cancelling-mutations.md) | A long-running write may need to be stopped. The run fails with `CancelledError` and nothing is rolled back for you. |

## Hooks

The optional add-on [`query_kit_hooks`](../guides/hooks.md) has React Query's
hook names, and React Query's own hook tests are ported and run against it.
Where it differs:

| React Query | `query_kit_hooks` | Why |
|---|---|---|
| `notifyOnChangeProps` and tracked result properties | `buildWhen` on the hooks that read one result: `useQuery`, `useSelectQuery`, `useInfiniteQuery`, `useMutation`, `useCombinedQueries`. `useQueries` takes none, as `QueriesBuilder` takes none, so a refetch's fetching state costs it a build of its own | One rule for every call style: `buildWhen` narrows rebuilds. |
| a component renders each change it is notified of on its own, a batch of notifications through `notifyManager` as one | a widget builds once per frame, for every notification before it, so two changes React renders apart can be one build | Flutter builds once per frame, however many notifications came before it. |
| `useQueries({ queries, combine })` | `useCombinedQueries(queries, combiner, keys: …)`, which returns a `CombinedResult`: pending until every query has data, with the combiner run over the values rather than the results. It runs again when a value or a key changes, not on every build, so what it captures goes in `keys:` where React wraps it in `useCallback`. There is no raw `combine` | The combiner reruns when a value or a key changes, not on every build, so what it captures goes in `keys:`. |
| `useInfiniteQuery` returns a result with `hasNextPage`, `fetchNextPage`, … | it returns the `InfiniteQueryController`: the result in `value`, the paging flags and `fetchNextPage` beside it | A hook returns what the matching builder style returns, so the paging flags sit with the controller. |
| `useMutation` returns a result with `mutate`, `mutateAsync`, `reset` | it returns the `MutationController`: the result in `value`, `mutate`, `mutateAsync` and `reset` its members | A hook returns what the matching builder style returns, so the controller keeps `mutate` and `reset`. |
| `useMutationState` with an optional `select` | `select` is required, and `useTypedMutationState` selects from mutations of one type, typed | A default selection would need a fixed state type in Dart, so `select` is required. |
| `useQueryClient(queryClient?)` | `useQueryClient()` takes no client; the other hooks take `client:`. A missing provider throws the binding's `FlutterError`, not "No QueryClient set" | The builders already take a `client:` argument, and the hooks do the same. |
| `usePrefetchQuery` and `usePrefetchInfiniteQuery` beside the Suspense hooks | no Suspense: the reader shows its own pending state | Flutter has no Suspense. The reader shows its own pending state, and an earlier build starts the prefetch. |
| the mutation callbacks' last argument, the mutation function context | not passed: `onMutate` gets the variables alone, and the other callbacks end at `onMutateResult` | The function context has its own option, `mutationFnWithContext`, so the callbacks keep a shorter list. |
| the Suspense hooks, `throwOnError`, `HydrationBoundary`, `useIsRestoring`, `subscribed`, `skipToken`, `retryOnMount` as a function | not in the package; see [not in this package](../guides/hooks.md#not-in-this-package) | They depend on React, error boundaries or hydration, which have no counterpart here. |

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

## Where these were decided

The audit trail of the whole port is the table of deliberate divergences in
the [porting
notes](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md), which lists the
upstream behaviour, what is done here, and where each was settled. It is one
long file that GitHub shows as plain text, so search it for "Deliberate
divergences". The add-on's differences are settled in the [hooks
plan](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/plans/hooks-package.md) (in German) and its own [porting
notes](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit_hooks/test/PORTING_NOTES.md).

Three decision records cover the larger choices:

- [One type slot for a plain query](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/adr/0001-one-type-slot-for-plain-queries.md)
  explains the two options shapes.
- [Core operations own their state](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/adr/0003-core-operation-lifetimes.md)
  explains the cancelled-fetch, mutation-scope and removal rules.
- [Hooks are an add-on](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/adr/0004-hooks-are-an-add-on-over-an-adapter-library.md)
  explains why the hooks are a separate package.

[Design notes](../project/design-notes.md) lists the rest.
