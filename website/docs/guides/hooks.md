---
title: "useQuery and useMutation in Flutter"
sidebar_label: Hooks
description: "Use React Query-style hooks in Flutter with query_kit_hooks: fetch and cache data, run mutations, load more pages, and test your HookWidgets."
---

# useQuery and useMutation in Flutter \{#hooks\}

`query_kit_hooks` is an optional add-on: `useQuery`, `useMutation`,
`useInfiniteQuery` and the rest of React Query's hooks, on
[`flutter_hooks`](https://pub.dev/packages/flutter_hooks). The hooks read the
same cache, by the same rules, as the binding's [four ways to read a
query](reading-queries-in-widgets.md): they are built on the binding's
controllers, and the package re-exports the binding.

It is a package of its own because the binding depends on nothing beyond
Flutter, and `flutter_hooks` is a third-party package. It is for an app whose
widgets are already `HookWidget`s. It is not a fifth call style and not a
default: nothing on this site prefers the hooks to the four call styles, or
the four to the hooks. An app that does not use `flutter_hooks` needs nothing
on this page.

## Installation

```bash
flutter pub add query_kit_hooks flutter_hooks
```

`query_kit_hooks` brings `query_kit_flutter` with it and re-exports it, so
its import gives you the whole binding. `flutter_hooks` goes in your
`pubspec.yaml` as well, because your files import it for `HookWidget`: this
package does not re-export it, and the `depend_on_referenced_packages` lint
asks for a direct dependency on every package a file imports.

```dart snippet="prose-only: its twin is in query_kit_hooks, which no example may depend on" twin="guides/hooks.md#imports"
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:query_kit_hooks/query_kit_hooks.dart';
```

It needs Flutter 3.27 or later, as the binding does. The client comes from a
`QueryClientProvider` at the root, exactly as for the call styles; see the
[quick start](../quick-start.md).

## Reading a query

```dart snippet="prose-only: its twin is in query_kit_hooks, which no example may depend on" twin="guides/hooks.md#use-query"
class TasksScreen extends HookWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tasks = useQuery(
      QueryObserverOptions<List<Task>>(
        queryKey: QueryKey(<Object?>['tasks']),
        queryFn: (context) => api.listTasks(signal: context.signal),
      ),
    );

    return switch (tasks) {
      QueryPending() => const Center(child: CircularProgressIndicator()),
      QueryError(:final error) => Center(child: Text('$error')),
      QuerySuccess(:final data) => ListView(
          children: [for (final task in data) Text(task.name)],
        ),
    };
  }
}
```

`useQuery` takes the same `QueryObserverOptions` and returns the same sealed
`QueryResult` as `context.query`. The observer belongs to the call's position
in `build`: a different `queryKey` on a later build switches the same
observer to the other query, which is what lets `const
PlaceholderData.keepPrevious()` go on showing the previous key's data while
the new one loads. When the widget unmounts, the hook lets go of its
observer, and the query is garbage-collected after its `gcTime` like any
query nobody observes.

The samples below take their options from functions, as the rest of the
site does: `tasksQuery()` from the [quick start](../quick-start.md),
`taskQuery(id)` from [query options](query-options.md), `feedQuery()` from
[infinite queries](infinite-queries.md).

## The hooks

| Hook | Returns | In the binding |
|---|---|---|
| `useQuery(options)` | `QueryResult<TData>` | `context.query`, `QueryBuilder` |
| `useSelectQuery(options)` | `QueryResult<TData>` | `context.selectQuery`, `QuerySelectBuilder` |
| `useInfiniteQuery(options)` | `InfiniteQueryController` | `context.infiniteQuery`, `InfiniteQueryBuilder` |
| `useMutation(options)` | `MutationController` | `context.mutation`, `MutationBuilder` |
| `useQueries(queries)` | `List<QueryResult<TData>>` | `QueriesBuilder` |
| `useCombinedQueries(queries, combiner, keys: …)` | `CombinedResult<R>` | `combine` over a list of results |
| `useIsFetching()` | `int` | `IsFetchingController` |
| `useIsMutating()` | `int` | `client.isMutating()`, kept current |
| `useMutationState(select: …)` | `List<TSelected>` | `MutationStateController` |
| `useTypedMutationState(select: …)` | `List<TSelected>` | `MutationStateController.typed` |
| `usePrefetchQuery(options)` | nothing | `client.query(options).ignore()` when nothing is cached |
| `usePrefetchInfiniteQuery(options)` | nothing | `client.infiniteQuery(options).ignore()` when nothing is cached |
| `useQueryClient()` | `QueryClient` | `QueryClientProvider.of(context)` |

Every hook but `useQueryClient` also takes `client:`; see [the
rules](#the-rules-of-hooks).

### `useSelectQuery`

```dart snippet="prose-only: its twin is in query_kit_hooks, which no example may depend on" twin="guides/hooks.md#use-select-query"
final open = useSelectQuery(
  tasksQuery().withSelect((tasks) => tasks.where((t) => !t.done).length),
);
```

`useQuery` for options with a `select`: the cache holds the query's data, the
widget reads what `select` makes of it, as with `context.selectQuery`.
`withSelect` turns a `QueryObserverOptions` into the `QuerySelectOptions` it
takes.

### `useInfiniteQuery`

```dart snippet="prose-only: its twin is in query_kit_hooks, which no example may depend on" twin="guides/hooks.md#use-infinite-query"
final feed = useInfiniteQuery(feedQuery());
final posts = feed.value.dataOrNull?.flatten<Post>() ?? const <Post>[];

return ListView(
  children: [
    for (final post in posts) ListTile(title: Text(post.title)),
    if (feed.hasNextPage)
      TextButton(
        onPressed: feed.isFetchingNextPage ? null : feed.fetchNextPage,
        child: const Text('Load more'),
      ),
  ],
);
```

It returns the `InfiniteQueryController` rather than a result, as
`context.infiniteQuery` does, because paging lives on it: the pages are in
its `value`, the flags such as `hasNextPage` and `isFetchingNextPage` beside
it, and `fetchNextPage` loads more. The hook owns the controller; do not
dispose it. A `fetchNextPage` held in a callback acts on the query the
controller observes when it is called. Called after the widget is gone, it
still fetches into the cache, and nothing rebuilds for it.

### `useMutation` and `useQueryClient`

```dart snippet="prose-only: its twin is in query_kit_hooks, which no example may depend on" twin="guides/hooks.md#use-mutation"
class RenameButton extends HookWidget {
  const RenameButton(this.id, {super.key});

  final String id;

  @override
  Widget build(BuildContext context) {
    final client = useQueryClient();
    final rename = useMutation(
      MutationOptions.simple(
        mutationFn: (String name) => api.rename(id, name),
        onSuccess: (_, __, ___) =>
            client.invalidateQueries(filters: QueryFilters(queryKey: tasksKey)),
      ),
    );

    return FilledButton(
      onPressed: rename.value.isPending ? null : () => rename.mutate('Renamed'),
      child: const Text('Rename'),
    );
  }
}
```

`useMutation` returns the `MutationController`: `value` is the
`MutationResult`, and `mutate`, `mutateAsync`, `reset` and `cancel` are on
it. Every build hands the options to the controller, so a run in flight calls
the callbacks of the latest build, and a different `mutationKey` starts over
at idle. Unmounting does not cancel a running mutation: it settles, the
callbacks in its options run, and a `mutateAsync` future completes. The
callbacks handed to one `mutate` call are dropped with the widget.

`useQueryClient` is `QueryClientProvider.of` as a hook: the client of the
nearest provider, and the widget rebuilds when the provider is given another
one. It takes no `client:`.

### `useQueries` and `useCombinedQueries`

```dart snippet="prose-only: its twin is in query_kit_hooks, which no example may depend on" twin="guides/hooks.md#use-queries"
final results = useQueries([for (final id in ids) taskQuery(id)]);

return Column(
  children: [
    for (final result in results) Text(result.dataOrNull?.name ?? '…'),
  ],
);
```

`useQueries` observes a list of queries of one data type and returns their
results in order, as `QueriesBuilder` does. It rebuilds when a result
changes, or when a result's `refetch` now acts on another query. A different
list on a later build updates the same hook: a key that stays keeps its
observer, so reordering starts no request.

One data type is a rule, not a default. A list of a `String` query and an
`int` query still compiles, as `Object`, and creates both cache entries as
`Object`, so a reader of either key as its own type, `String` or `int`, then
throws `QueryDataTypeError`. Where React Query types each query of the list on its
own, read queries of different types with a `useQuery` each, and combine the
results with `(a, b).combine(…)`.

```dart snippet="prose-only: its twin is in query_kit_hooks, which no example may depend on" twin="guides/hooks.md#use-combined-queries"
final matching = useCombinedQueries(
  [for (final id in ids) taskQuery(id)],
  (tasks) => tasks.where((task) => task.name.contains(needle)).toList(),
  // The combiner reads `needle`, so a new needle runs it again.
  keys: [needle],
);

return switch (matching) {
  CombinedPending() => const CircularProgressIndicator(),
  CombinedError(:final error) => TextButton(
      onPressed: matching.retry,
      child: Text('$error. Try again'),
    ),
  CombinedData(:final data) => Text('${data.length} match'),
};
```

`useCombinedQueries` is React Query's `useQueries({ combine })`. It returns a
[`CombinedResult`](combining-queries.md): pending until every query has data,
an error when one failed with nothing to show, otherwise the combiner's
result over the values, in order. `retry` refetches the queries in error,
`refetch` all of them. The combiner runs again only when a value or one of
`keys` changed, not on every build as an inline `combine` does in React. So
`keys` is required: `const []` for a combiner that captures nothing from the
build, the captured values otherwise.

Queries of different data types are read one `useQuery` each, and their
results combined as a record, `(a, b).combine(…)`; see [combining
queries](combining-queries.md).

### `useIsFetching` and `useIsMutating`

```dart snippet="prose-only: its twin is in query_kit_hooks, which no example may depend on" twin="guides/hooks.md#counts"
final fetching = useIsFetching();
final saving = useIsMutating(
  filters: MutationFilters(mutationKey: QueryKey(<Object?>['tasks'])),
);

if (fetching == 0 && saving == 0) return const SizedBox.shrink();
return Text(saving > 0 ? 'Saving…' : 'Loading…');
```

How many queries matching the filters are fetching, and how many mutations
matching them are pending. The widget rebuilds when the number changes.
`useIsMutating` counts only pending mutations, whatever status its filters
name. The filters of the latest build are the ones counted, so they may be
built anew in every build.

### `useMutationState` and `useTypedMutationState`

```dart snippet="prose-only: its twin is in query_kit_hooks, which no example may depend on" twin="guides/hooks.md#mutation-state"
// What every pending add was called with, untyped.
final adding = useMutationState(
  filters: MutationFilters(
    mutationKey: QueryKey(<Object?>['tasks', 'add']),
    status: MutationStatus.pending,
  ),
  select: (mutation) => mutation.state.variables,
);

// Every pending mutation whose variables are a String, typed.
final names = useTypedMutationState(
  filters: const MutationFilters(status: MutationStatus.pending),
  select: (Mutation<Object?, String, Object?> mutation) =>
      mutation.state.variables!,
);
```

What `select` makes of every mutation matching the filters, one entry per
mutation in the order they were added; the widget rebuilds when an entry
changes. `select` is required: React Query's default, `(mutation) =>
mutation.state`, is written out where that is what you want.
`useTypedMutationState` keeps the mutations of the types its `select` names —
a type left as `Object?` matches anything — and hands them over typed.
`select` runs over every matching mutation on every change to the mutation
cache, so keep it cheap. See [mutation state](mutation-state.md).

### `usePrefetchQuery` and `usePrefetchInfiniteQuery`

```dart snippet="prose-only: its twin is in query_kit_hooks, which no example may depend on" twin="guides/hooks.md#prefetch"
class TasksPage extends HookWidget {
  const TasksPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Both fetches are running by the time the widgets below read them.
    usePrefetchQuery(tasksQuery());
    usePrefetchInfiniteQuery(feedQuery());

    return const Column(
      children: [Expanded(child: TasksScreen()), Expanded(child: FeedList())],
    );
  }
}
```

Each starts a fetch if the cache holds no entry for the key, and returns
nothing. Called in a widget above the ones that read the data, the fetch is
running by the time a reader subscribes, and the reader joins it instead of
starting its own. Any entry counts: one that is fetching, one that failed and
one left pending are all left alone, and a reader that mounts may refetch it
as its own options allow. The hooks hold no observer and never rebuild the
widget. There is no Suspense: each reader shows its own pending state. See
[prefetching](prefetching.md).

## What rebuilds

The hooks that read one result take a `buildWhen` of the binding's type:
`useQuery`, `useSelectQuery` and `useInfiniteQuery` over the
`QueryResult`, `useMutation` over the `MutationResult`, and
`useCombinedQueries` over the `CombinedResult`. None of them rebuilds for a
notification carrying what the widget already shows, and the notifications
of one frame are one build.

```dart snippet="prose-only: its twin is in query_kit_hooks, which no example may depend on" twin="guides/hooks.md#build-when"
final task = useQuery(
  taskQuery(id),
  // A background refetch flips `isFetching` twice. This widget shows no
  // spinner for it, so only a new status or new data rebuilds it.
  buildWhen: (previous, current) =>
      previous.status != current.status ||
      previous.dataOrNull != current.dataOrNull,
);
```

`previous` is the result the widget last built, not the last one it was told
about, as on every call style; see [`buildWhen`](render-optimizations.md#buildwhen).

`useQueries` takes none, for the reason `QueriesBuilder` takes none: a
predicate over the whole list cannot say which query moved. A query that
needs filtering is read with its own `useQuery`. The counts and the
mutation-state selections take none either: they rebuild only when the
number, or an entry, changes.

### What `buildWhen` does not decide

Two things sit beside the result a predicate compares. A change there
rebuilds the widget without asking `buildWhen`, whether the result changed
too or not, because a "no" would leave the widget acting on what is no
longer true:

- **An infinite query's paging flags.** `hasNextPage`, `hasPreviousPage`,
  `isFetchingNextPage`, `isFetchingPreviousPage`, `isFetchNextPageError` and
  `isFetchPreviousPageError` live on the controller, not in the result. A
  refetch that keeps the data but drops the next page would otherwise leave
  "Load more" on screen with no next page to load.
- **What `useCombinedQueries`' `retry` and `refetch` act on.** Which queries
  are in error, and the query each source's `refetch` reaches, are not part
  of the `CombinedResult`. When they change — a query repaired behind an
  unchanged error, say — the widget rebuilds, so the `retry` it holds acts on
  the queries in error now.

## The rules of hooks

`flutter_hooks` tells hooks apart by their position among the calls of one
`build`, as React does. Three rules follow.

**Every hook is called on every build, in the same order** — not inside an
`if`, a loop whose length changes, or a callback. A hook of another kind at a
position throws a `StateError` ("Type mismatch between hooks") and disposes
the hooks from there on. A query that is only sometimes needed keeps its
call, and `enabled` holds it back, as for a [dependent
query](dependent-queries.md):

```dart snippet="prose-only: its twin is in query_kit_hooks, which no example may depend on" twin="guides/hooks.md#selected-options guides/hooks.md#selected-read"
QueryObserverOptions<Task> selectedTaskQuery(String? id) =>
    QueryObserverOptions(
      queryKey: QueryKey(<Object?>['tasks', id]),
      queryFn: (context) => api.getTask(id!, signal: context.signal),
      // No selection: nothing to fetch.
      enabled: id == null ? Enabled.no : Enabled.yes,
    );

// Called on every build, selection or not.
final task = useQuery(selectedTaskQuery(selectedId));
```

**A key is not an identity.** A different `queryKey` at the same position is
the same hook reading another query; nothing is created anew. The `keys`
`useCombinedQueries` takes are its combiner's, not the hook's. This is the
other way round from `watchQuery` and `context.query`, which tell their reads
apart by key and type, so an `if` around one of those is fine.

**`client:` replaces the provider.** Every hook but `useQueryClient` takes
one, and uses it instead of the nearest `QueryClientProvider`'s client. With
it, a hook needs no provider above it; with neither, it throws a
`FlutterError` that names the missing provider. Another client on a later
build re-creates the hook's observer on that client.

## When a build throws

When `build` throws, `flutter_hooks` disposes the hooks from the one the
build was in when it threw, that one included, to the last. The hooks before
it stay, and a throw after the last hook disposes nothing. A disposed hook
lets go of its observer as on unmount, and the next build that gets that far
creates a new hook in its place. For a query or a mutation whose hook was
disposed:

| What | After the throw |
|---|---|
| The query's cache entry | Stays for its `gcTime`, like any query nobody observes. Only an idle query is collected: a fetch that runs on, as in the next row, keeps it past its `gcTime`, zero included, and its end starts the `gcTime` again |
| A fetch in flight | Once the query has no observer left: cancelled, and the query back where it was before the fetch, if the query function used `context.signal` or the fetch was paused before the query had data. Otherwise the request runs on and its result is cached, with no retry unless an observer comes back. The new hook joins a fetch still running, or fetches again if the data is stale |
| What the observer remembered | Gone: `keepPrevious` placeholder data has no previous data to show, and `select` runs afresh |
| A mutation in flight | Runs on, and the callbacks in its options run |
| The callbacks handed to `mutate` | Dropped, with the disposed controller |
| What the new hook shows | A fresh start: a new `useMutation` is idle even while the old run is still pending, and does not find it by its key |

So code that can throw — parsing, a lookup that may miss — goes after the
last hook, or into a widget of its own, where a throw takes none of these
hooks with it.

## Testing

The [teardown every widget test
needs](testing.md#the-teardown-every-widget-test-needs) applies unchanged. A
hook lets go of its observer when its widget unmounts, so the same steps —
the tree down, the frame after it, the client cleared twice — leave no timer
pending. `TasksScreen` here is the `HookWidget` from the top of this page,
and the test is the testing guide's, line for line:

```dart snippet="prose-only: its twin is in query_kit_hooks, which no example may depend on" twin="guides/hooks.md#testing"
testWidgets('the list loads', (tester) async {
  final client = QueryClient();
  await tester.pumpWidget(QueryClientProvider(
    client: client,
    child: const MaterialApp(home: TasksScreen()),
  ));
  await tester.pumpAndSettle();
  expect(find.byType(ListView), findsOneWidget);

  // Let the widgets go, and the frame after them run.
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
  // Then the cache and its timers.
  client.clear();
  // A mutation the clear dropped fails a moment later and its callbacks
  // run then; let them, then clear what they wrote.
  await tester.pump();
  client.clear();
});
```

The guide's harness and its pump rules hold for hooks as they are.

## A trap: `unawaited(client.query(…))`

In an `async` function the `unawaited_futures` lint asks for a future nobody
awaits to be marked, and `unawaited` from `dart:async` is the usual mark.
Around `client.query`, it changes the type:

```dart snippet="prose-only: its twin is in query_kit_hooks, which no example may depend on" twin="guides/hooks.md#trap"
// Creates the entry for `void`: the first typed reader throws.
unawaited(client.query(tasksQuery()));
```

`unawaited` takes a `Future<void>`, and Dart infers `client.query`'s type
argument from it, so the entry is created for `void`. The first reader that
asks for `List<Task>` — `useQuery(tasksQuery())`, or any call style — then
throws a `QueryDataTypeError`, because [one key holds one exact
type](../dart-type-safety.md#one-key-one-exact-type). Let the type come from
the options, or write it out:

```dart snippet="prose-only: its twin is in query_kit_hooks, which no example may depend on" twin="guides/hooks.md#trap-typed"
// The type comes from the options:
client.query(tasksQuery()).ignore();
// or is written out:
unawaited(client.query<List<Task>>(tasksQuery()));
```

## Not in this package

React Query hooks and options with no counterpart here:

- **The Suspense hooks** — `useSuspenseQuery`, `useSuspenseQueries`,
  `useSuspenseInfiniteQuery` — and Suspense in the prefetch hooks. Flutter
  has no Suspense; the sealed result puts the pending state in the reader's
  own `switch`.
- **`throwOnError` and `QueryErrorResetBoundary`.** An error is the
  `QueryError` case of the result, not a throw.
- **`HydrationBoundary` and `IsRestoringProvider`.** The core has no
  hydration and no persister.
- **`subscribed`.** No call style has it.
- **`skipToken`.** `enabled: Enabled.no` does its job, as in [the
  rules](#the-rules-of-hooks) above.
- **`retryOnMount` as a function.** The option is a `bool`.
- **A raw `combine` on `useQueries`.** `useCombinedQueries` takes a combiner
  over the values and returns a `CombinedResult`.
- **The context argument of the mutation callbacks.** `onMutate`,
  `onSuccess`, `onError` and `onSettled` get no client, `meta` or key; they
  close over what they need.
- **`queryOptions` and `mutationOptions`.** In Dart a function that returns
  options does the same, and the samples here use one.

:::note[In React Query]
The names are React Query's, and so is the behaviour: React Query's own hook
tests are ported and run against these hooks. Where they differ —
`buildWhen` for `notifyOnChangeProps`, `useCombinedQueries` for `combine`, a
frame for a render — is listed under
[hooks](../reference/differences-from-tanstack.md#hooks) in the differences
from TanStack Query.
:::
