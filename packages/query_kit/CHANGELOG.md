# Changelog

## 1.1.0

Typed query definitions. A definition declares a query once, with its key,
its input, its data type and its options. Calling it gives a reference to one
cache entry, and the reference reads, writes, fetches and invalidates that
entry with the declared type, so a call site names no key and no type
argument.

**The new types**

- `QueryDefinition` and `QueryFamily` declare a query without and with an
  input. `InfiniteQueryDefinition` and `InfiniteQueryFamily` do the same for
  a paged query.
- `QueryRef` and `InfiniteQueryRef` are references to one entry. A family
  gives one when it is called with an input, and a definition without an
  input is its own reference. `QueryEntryRef` is what the two have in
  common, for a function that needs only the cache.
- `TypedQueryKey` is a reference's key together with its data type.
- `QueryNamespace` is a key prefix with no data type, and `QueryTarget` is
  anything that can be invalidated, refetched, cancelled, reset or removed:
  a namespace, a family or a reference.

A reference's `options()` are ordinary observer options, so they go
wherever options went before. References and typed keys are values: two
are equal when they address the same entry with the same data type.

**What is checked, and when**

- The analyzer refuses a misspelled definition, an input of the wrong type,
  a written value or an updater result of the wrong type, and a read
  assigned to the wrong type. A namespace and a target have no write.
- Some mistakes are found only when the code runs. Write every
  definition's type arguments out: left to inference, a family's input or
  an infinite definition's page type can become `Object?`, or a key-only
  definition's data type `dynamic`, and the analyzer does not always say
  so. A debug build refuses such a definition with an `AssertionError`; a
  release build does not check. A reference assigned to a wider type, a
  cast, or a list literal of references of different data types compiles
  a write of the wrong type, and the write throws when it runs, before
  anything is stored. A typed write into an entry of another
  type throws `QueryDataTypeError`.
- Nothing checks a raw call on a definition's key, or two definitions of
  one key and one data type with different fetch functions, which are one
  entry. A record input that holds a list, a map or a set needs a `keyOf`,
  or every call is a new entry.

The [typed queries guide](https://query-kit.dev/docs/guides/typed-queries)
lists every limit, with what each one costs and how to avoid it.

**Writes**

A typed write stores into the entry the cache holds when the value is
stored, or throws. It throws `QueryDataTypeError` when an entry of another
type has taken that entry's place, and `StateError` when a cache listener or
the entry's own `structuralSharing` removed the entry during the write. It
never reports a value it did not store. A bulk `updateAll` checks every
updater's result and every entry's type before the first write, but it is
not a transaction: a write that fails after others leaves those in place.

**Equal options**

The options of a definition without an input, held in a field, are equal
from one `options()` call to the next once the client has applied its
defaults, so an observer handed them again does not report a change. That
holds as long as `configure` builds nothing new per call. For an infinite
definition it holds when `configure` returns the same `structuralSharing`
function or the same `InitialData.compute` function each time; a closure
written inside `configure` is a new function on every call. A family
declared with a fetch function wraps it anew for every reference's
`options()`, so those options are never equal.

**Unchanged**

The raw `QueryKey` API is unchanged and not deprecated. A reference and a
raw key with the same parts are the same cache entry, so an app can move
one query at a time, and both forms can read the same entry. The README's
quick start now leads with a typed definition, and shows the raw form after
it.

## 1.0.4

- Move the documentation to https://query-kit.dev/. Update homepage,
  documentation and README links. No API or behavior changes.

## 1.0.3

- A fetch or a mutation met from another error zone than the one it began
  in now reaches that zone. Dart delivers a future's error only within the
  error zone the future was made in, so an `await cancelQueries` from another
  zone waited for good, `clear`, `removeQueries` and `resetQueries` reported
  the cancelled fetch's `CancelledError` as uncaught, a caller who joined a
  fetch or read `Query.future` never heard that it failed, and
  `resumePausedMutations` waited for good on a mutation that failed. A
  Flutter app has two error zones as soon as a `runZonedGuarded` wraps
  `runApp`, or a widget test's zone meets the binding's: a refetch on focus
  is started by a platform callback. Within one zone nothing changes.
- `QueryState`, `MutationState` and `DefaultedMutationOptions` compare equal
  only to a value of the same type arguments. A `QueryState<int>` and an
  equal `QueryState<num>` used to be equal one way and not the other, so a
  `Set` held one or both depending on the order they went in. A comparison
  between the same type arguments is unchanged.
- The errors reference gave a remedy that does not compile for the
  `UnsupportedError` an `InfiniteQueryObserver` throws for plain options. It
  now names both that do: the infinite options to `setInfiniteOptions`, or
  what `client.infiniteObserverOptions` makes of them to `setOptions`.

## 1.0.2

No change to the code. The documentation site moved to its own address,
<https://query-kit.dev/>; the package page's homepage and
documentation links, the README and the library's dartdoc name it, and the
former address redirects there. The README opens with a title a reader
searches for, "TanStack Query for Dart | query_kit", instead of the package name,
which pub.dev's own heading above it already shows.

## 1.0.1

No change to the code. The package page now names the documentation site,
<https://query-kit.dev/>, as its homepage and
documentation, the README opens with a link to it, the quick start, the
examples and the API reference, and the description says what the package is:
TanStack Query for Dart.

## 1.0.0

First release. `query_kit` is a Dart port of TanStack Query's `query-core`:
a cache for server state with no Flutter dependency. The Flutter binding is
[`query_kit_flutter`](https://pub.dev/packages/query_kit_flutter). From here
on, a breaking change is a major version.

query_kit is an entirely AI-coded project: all code, tests and documentation
were written by AI coding agents (Anthropic's Claude). A human maintainer set
the goals and reviews releases, but did not write the code. It is a community
port, not affiliated with or endorsed by TanStack.

**Queries**

- `QueryClient` with a `QueryCache`: caching by `QueryKey`, `staleTime` and
  `gcTime`, request deduplication, retries with backoff (`RetryPolicy`,
  `RetryDelay`) and cancellation through `QueryCancelToken`.
- `QueryObserver` for reactive reads, with sealed `QueryResult`s
  (`QueryPending`, `QuerySuccess`, `QueryError` carrying the last good data).
- Refetching on focus, on reconnect, on an interval (`RefetchInterval`) and
  after `invalidateQueries`; `Enabled` for dependent and lazy queries.
- `select`, `InitialData`, `PlaceholderData` (including
  `PlaceholderData.keepPrevious()`) and structural sharing, extendable to
  your own classes with `StructurallyShareable`.
- `QueryClient.query` for imperative reads — fetch, prefetch, "ensure" and
  stale-while-revalidate in one method.
- `getQueryData`, `setQueryData`, `updateQueryData`, `cancelQueries`,
  `refetchQueries`, `resetQueries`, `removeQueries`, `QueryFilters`, and
  per-key defaults through `setQueryDefaults`.
- `consecutiveErrorCount` on every result, so polling can give up after N
  failures.

**Mutations**

- `MutationObserver` and `MutationCache`, with `onMutate`, `onSuccess`,
  `onError` and `onSettled`, optimistic updates and rollback.
- `MutationOptions.simple` for mutations without an optimistic step;
  `mutationFnWithContext` and `cancel()` for cancellable mutations.
- `MutationScope` to run writes one after another; paused mutations resume
  when the client is back online (`resumePausedMutations`).
- `MutationStateObserver` for cache-wide mutation state, `isMutating`.

**Infinite queries**

- `InfiniteQueryObserver` with `fetchNextPage`, `fetchPreviousPage`,
  `hasNextPage` and `maxPages`, over a typed `InfinitePageContext`.

**Collections**

- `QueriesObserver` for a dynamic list of queries, and `combine` over a
  record or a list of results (`CombinedResult`, `CombineMemo`, `optional()`,
  `combineWith`).

**Dart-first design**

- Sealed option values (`StaleTime`, `GcTime`, `Enabled`, `RetryPolicy`,
  `RefetchOn`, `RefetchInterval`, …) instead of magic numbers.
- `QueryKey` is a value type; a key is bound to one data type and a
  mismatched read throws `QueryDataTypeError`.
- `AppFocusManager`, `OnlineManager` and `NotifyManager` owned per client;
  time goes through `package:clock`, so `fake_async` controls every timer.

Not in this release: persistence and hydration, `streamedQuery`,
server-side rendering, devtools.
