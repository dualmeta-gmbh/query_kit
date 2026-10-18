---
title: "Guides: TanStack Query concepts in Flutter"
sidebar_label: Guides
description: "Every query_kit guide in one list, grouped by task: reading queries, refetching and the network, paging, mutations, the cache and tools."
---

# Guides

Each guide explains one concept, with the code to use it and the traps around
it. This page lists them all, grouped as the sidebar groups them. If you have
not set up a project yet, start with the [quick start](../quick-start.md).

## Queries

- [Queries](queries.md): what a query is, the three result states, `status`
  versus `fetchStatus`, and the flags that combine them.
- [Four ways to read a query](reading-queries-in-widgets.md): `context.query`,
  `QueryBuilder`, `QueryMixin` and `QueryController`, how to pick between them,
  and when a read is released.
- [Hooks](hooks.md): the optional `query_kit_hooks` add-on, with `useQuery`,
  `useMutation` and the rest of React Query's hooks on `flutter_hooks`.
- [Query keys](query-keys.md): `QueryKey` as a value type, hierarchical keys,
  prefix matching and key factories.
- [Query functions](query-functions.md): a function that returns a `Future` and
  throws on failure, the error types a retry policy can read, and what the
  function's context carries.
- [Describing a query once](query-options.md): options functions, the two
  observer options shapes, `withSelect`, and what `null` means.
- [Parallel queries](parallel-queries.md): several queries at once, and
  `QueriesBuilder` for a list that changes length or order.
- [Combining queries](combining-queries.md): `combine` over a record or a list
  of results, and the rules for pending, error and data.
- [Dependent queries](dependent-queries.md): a query that waits for another
  query's result with `enabled`, and why it is still a waterfall.
- [Disabling queries](disabling-queries.md): `Enabled.no`, a query run only on
  demand, and what a disabled query still does.
- [Side effects](side-effects.md): navigation, snackbars and analytics on a
  change of a result, with the listener widgets and mutation callbacks.

## Refetching and the network

- [Background fetching indicators](background-fetching-indicators.md): showing
  that a query is refreshing without hiding its data, for one result or for the
  whole app.
- [App focus refetching](window-focus-refetching.md): stale queries refetch
  when the user returns to the app, and how to narrow or turn that off.
- [Network mode and offline](network-mode.md): what queries and mutations do
  while the client believes it is offline, and how they resume.
- [Connectivity](connectivity.md): telling the client whether it is online,
  with `OnlineStatus`, a `connectivity_plus` adapter and a reachability probe.
- [Polling](polling.md): `refetchInterval`, polling in the background, and
  stopping when the server confirms.
- [Query retries](query-retries.md): `RetryPolicy` and `RetryDelay`, not
  retrying a 4xx, and showing the attempts in the UI.
- [Query cancellation](query-cancellation.md): the `QueryCancelToken` every
  query function receives, and what `cancelQueries` and a leaving screen do to
  a fetch in flight.

## Paging and early data

- [Paginated queries](paginated-queries.md): one page at a time with the page
  number in the key, and a prefetch that makes *Next* instant.
- [Infinite queries](infinite-queries.md): a list of pages behind one key,
  `maxPages`, and load-on-scroll.
- [Initial query data](initial-query-data.md): seeding the cache with data the
  app already has, and saying how old it is.
- [Placeholder query data](placeholder-query-data.md): data shown while the
  real fetch runs and never written to the cache.
- [Scroll restoration](scroll-restoration.md): a list comes back where it was,
  and what Flutter needs from you to put the position back.

## Mutations

- [Mutations](mutations.md): the four ways to read a mutation, `mutate` and
  `mutateAsync`, per-call callbacks and mutation defaults.
- [Query invalidation](query-invalidation.md): `invalidateQueries`, prefix
  matching, `exact`, predicates and `refetchType`.
- [Invalidations from mutations](invalidations-from-mutations.md): which keys
  to invalidate after a write, from which callback, and what returning the
  future does.
- [Updates from mutation responses](updates-from-mutation-responses.md):
  writing what a mutation returned straight into the cache.
- [Optimistic updates](optimistic-updates.md): showing a write before the
  server confirms it, from the pending variables or by patching the cache.
- [Mutation scopes](mutation-scopes.md): mutations that share a scope run one
  at a time, in the order they were started.
- [Cancelling mutations](cancelling-mutations.md): `mutationFnWithContext`, and
  why cancelling a write fails it rather than reverting it.
- [Mutation state](mutation-state.md): every mutation matching a filter, for a
  "saving…" badge no widget owns.

## The cache and performance

- [Filters](filters.md): `QueryFilters` and `MutationFilters`, the one named
  argument every bulk operation takes.
- [Request waterfalls](request-waterfalls.md): when one request cannot start
  before another has answered, and how hoisting and prefetching avoid it.
- [Prefetching](prefetching.md): fetching with `client.query` before a screen
  asks, or serving the cache and revalidating behind it.
- [Caching](caching.md): how long data is fresh, how long an unobserved entry
  is kept, and a query's life from first read to garbage collection.
- [What rebuilds, and when](render-optimizations.md): `select` narrows what a
  widget reads and `buildWhen` narrows when it rebuilds.
- [Structural sharing](structural-sharing.md): a refetch that brings back equal
  data keeps the cached instances, and how a model takes part.
- [Default query function](default-query-function.md): registering a query
  function per key prefix with `setQueryDefaults`.
- [Global callbacks](global-callbacks.md): `QueryCache` and `MutationCache`
  callbacks that run for every query or mutation of a client.

## Tools and architecture

- [Debugging](debugging.md): there are no devtools, so what the cache can tell
  you by its events and entries instead.
- [Testing](testing.md): the teardown every widget test needs, a harness that
  wraps it, and the pump rules that fake timers impose.
- [Without Flutter](pure-dart.md): using `query_kit` on its own, with observers
  and `subscribe`.
- [Does this replace state management?](does-this-replace-state-management.md):
  what moves into the cache and what stays in your state package.

## Beyond the guides

The guides explain concepts one at a time. The [cookbook](../cookbook/index.md)
starts from tasks such as a token refresh or a search box and puts several
guides to work in one app, and the [examples](../examples/index.md) run every
feature as a live screen. [Important defaults](../important-defaults.md) and
the [API reference](../reference/api.md) sit beside them.
