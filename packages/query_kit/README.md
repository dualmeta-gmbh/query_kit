# TanStack Query for Dart | query_kit

A cache for server state that knows when data is stale, refetches it in the
background, retries, cancels, deduplicates requests, and runs mutations and
infinite queries — with **no Flutter dependency**. In a Flutter app, use
[`query_kit_flutter`](https://pub.dev/packages/query_kit_flutter), which
re-exports all of this.

**Documentation: [query-kit.dev](https://query-kit.dev/)**, with
guides, a cookbook and live examples.
[Quick start](https://query-kit.dev/docs/quick-start) ·
[Pure Dart](https://query-kit.dev/docs/guides/pure-dart) ·
[Examples](https://query-kit.dev/docs/examples) ·
[API reference](https://pub.dev/documentation/query_kit/latest/)

> **AI-coded.** query_kit is an entirely AI-coded project: all code, tests
> and documentation were written by AI coding agents (Anthropic's Claude). A
> human maintainer set the goals and reviews releases, but did not write the
> code.
>
> **A port, not affiliated.** The behaviour is
> [TanStack Query](https://tanstack.com/query)'s, and upstream's own test
> suite is ported case by case — every case left out is listed with its
> reason — and run against this code, with thanks to Tanner Linsley and the
> TanStack team. This package is not affiliated with,
> endorsed by or connected to them; please take problems to
> [this repository's issues](https://github.com/dualmeta-gmbh/query_kit/issues),
> not to TanStack.

## Install

```bash
dart pub add query_kit
```

Dart SDK 3.6 or later. In a Flutter app, add `query_kit_flutter` instead
(`flutter pub add query_kit_flutter`); it brings this package with it.

## Quick start

### Create a client

One `QueryClient` holds the cache. Mounting it lets it react to the focus
and connectivity changes its `focusManager` and `onlineManager` report —
refetch on focus and on reconnect, resume paused mutations. The Flutter
binding mounts the client and feeds both managers for you; in pure Dart
nothing reports a change until you do (`client.onlineManager.setOnline`).

```dart snippet="packages/query_kit/README.md#setup"
final client = QueryClient();
client.mount(); // react to focus and connectivity changes
```

### A first query

A query is a key plus a function that fetches. Declare both once, in a
class per resource, and write the type arguments out:

```dart snippet="packages/query_kit/README.md#definitions"
final class TaskQueries {
  TaskQueries(this._api);

  final Api _api;

  /// Every key below starts with 'tasks'.
  static final QueryNamespace namespace = QueryNamespace(<Object?>['tasks']);

  /// One list: the key ['tasks', 'list'].
  late final list = QueryDefinition<List<Task>>(
    namespace: namespace,
    name: 'list',
    queryFn: (context) => _api.listTasks(signal: context.signal),
    configure: (base) => base.copyWith(
      staleTime: const StaleTime.duration(Duration(seconds: 45)),
    ),
  );

  /// One entry per id: the key ['tasks', 'detail', id].
  late final detail = QueryFamily<String, Task>(
    namespace: namespace,
    name: 'detail',
    queryFn: (id, context) => _api.getTask(id, signal: context.signal),
  );
}

final tasks = TaskQueries(api);
```

`tasks.list` is a definition, and `tasks.detail(id)` gives a reference to
one entry. A reference carries the data type, so nothing after this needs a
key or a type argument. Read it once, or observe it and hear about every
change:

```dart snippet="packages/query_kit/README.md#first-query"
// Imperative: fetch and cache, completing with a List<Task>.
final all = await tasks.list.fetch(client);

// Reactive: an observer that keeps a widget (or anything) up to date.
final task = tasks.detail(id); // QueryRef<Task>
final observer = client.observe(task.options());

final unsubscribe = observer.subscribe((result) {
  switch (result) {
    case QueryPending():
      print('loading');
    case QuerySuccess(:final data):
      print(data.name);
    case QueryError(:final error, :final staleData):
      print('$error (still showing ${staleData?.name})');
  }
});
```

The result is a **sealed** type, so the `switch` is exhaustive and the data
needs no `!`. A `QueryError` still carries the last good data, which is what
makes stale-while-revalidate readable.

The same reference reads and writes the cache, and every definition and
namespace invalidates what it covers:

```dart snippet="packages/query_kit/README.md#cache"
final Task? cached = task.read(client); // no fetch, no subscription
task.update(client, (previous) => previous?.copyWith(name: 'Renamed'));

await task.invalidate(client); // this one entry
await tasks.detail.invalidate(client); // every detail
await TaskQueries.namespace.invalidate(client); // everything under 'tasks'
```

The analyzer refuses a misspelled definition, an input of the wrong type
(`tasks.detail(42)`), a write of the wrong type (`task.write(client,
'done')`) and a read into the wrong type (`String? name =
task.read(client)`).

Some mistakes are only caught when the code runs, or not at all. Without
its type arguments a family's input becomes `Object?`; a debug build refuses
that declaration, a release build does not. A reference assigned to a wider
type, or a list literal of references of different data types, is checked
when a write runs, not by the analyzer. A write through a raw key is not
checked against the definition, and two definitions of one key and one type
are one entry whatever their fetch functions. The
[typed queries guide](https://query-kit.dev/docs/guides/typed-queries) has
the whole list. Typed query definitions are new in query_kit 1.1.0.

#### With raw keys

A definition builds a plain `QueryKey`, `[...namespace, name, input]`, and
the client takes plain keys as before. This is the same cache work written
by hand, and it reaches the same entries:

```dart snippet="packages/query_kit/README.md#raw-keys"
final listKey = QueryKey(<Object?>['tasks', 'list']);
final detailKey = QueryKey(<Object?>['tasks', 'detail', id]);

final listed = await client.query<List<Task>>(
  QueryOptions<List<Task>>(
    queryKey: listKey,
    queryFn: (context) => api.listTasks(signal: context.signal),
    staleTime: const StaleTime.duration(Duration(seconds: 45)),
  ),
);
final rawObserver = client.observe<Task, Task>(
  QueryObserverOptions<Task>(
    queryKey: detailKey,
    queryFn: (context) => api.getTask(id, signal: context.signal),
  ),
);

final Task? rawCached = client.getQueryData<Task>(detailKey);
client.updateQueryData<Task>(
  detailKey,
  (previous) => previous?.copyWith(name: 'Renamed'),
);
await client.invalidateQueries(
  filters: QueryFilters(queryKey: QueryKey(<Object?>['tasks'])),
);
```

Here the type argument is repeated at every call, and a key is bound to one
data type: a read of the wrong type throws a `QueryDataTypeError` naming
both.

### A first mutation

A mutation changes something on the server. Invalidating the list afterwards
marks it stale and refetches it for everyone observing it:

```dart snippet="packages/query_kit/README.md#first-mutation"
final addTask = MutationObserver(
  client,
  MutationOptions.simple(
    mutationFn: api.addTask,
    // Mark the list stale and refetch it for whoever is watching.
    onSuccess: (_, __, ___) => tasks.list.invalidate(client),
  ),
);

await addTask.mutateAsync('Write the release notes');
```

### Cleaning up

A client owns timers (unused entries are garbage-collected after `gcTime`),
so a command-line program ends by letting its observers go and clearing the
cache:

```dart snippet="packages/query_kit/README.md#cleanup"
unsubscribe();
client.unmount();
client.clear(); // empties the cache and cancels its timers
```

Unsubscribe (or `destroy()`) observers first: an observer with a
`refetchInterval` keeps polling into a cleared cache.

## Features

- **Caching with staleness.** `staleTime` decides when data is old, `gcTime`
  when an unused entry goes; stale data is shown while it is refreshed.
- **Request deduplication.** Every caller of the same key shares one fetch.
- **Background refetching** on focus, on reconnect, on an interval, and after
  invalidation.
- **Retries** with exponential backoff, and **cancellation** through
  `QueryCancelToken`, whose `onCancel` hook wires into `dio`'s `CancelToken`
  or any other client that can abort a request.
- **Mutations** with `onMutate` / `onSuccess` / `onError` / `onSettled`,
  optimistic updates and rollback, serialised writes through
  `MutationScope`, and paused mutations that resume when you are back online.
- **Infinite queries** with `fetchNextPage` / `fetchPreviousPage` and
  `maxPages`.
- **Initial and placeholder data**, `select` to derive what a reader sees,
  and **structural sharing**, so an unchanged refetch keeps your lists and
  maps — and, through `StructurallyShareable`, your own classes.
- **Lists and combinations of queries**: `QueriesObserver` for a dynamic
  list, and `(a, b).combine(…)` for results of different types.
- **Cache-wide state**: `isFetching`, `isMutating`, `MutationStateObserver`,
  and direct reads and writes with `getQueryData` / `setQueryData`.
- **Typed query definitions**: a query's key, input and data type declared
  once; references fetch, read, write and invalidate with no key and no type
  argument at the call site.
- **Dart-first types**: sealed results, sealed option values (`StaleTime`,
  `RetryPolicy`, `Enabled`, …) instead of magic numbers, and `QueryKey` as a
  value type. A key is bound to one data type, and a mismatched read throws
  a `QueryDataTypeError` naming both types.
- **Testable**: time goes through `package:clock`, so `fake_async` controls
  every timer.

Not in 1.0: persistence and hydration, `streamedQuery`, server-side
rendering and devtools.

## Learn more

- [Overview](https://query-kit.dev/docs/overview) and
  [important defaults](https://query-kit.dev/docs/important-defaults)
- [Using the core without Flutter](https://query-kit.dev/docs/guides/pure-dart)
- [Queries](https://query-kit.dev/docs/guides/queries),
  [query keys](https://query-kit.dev/docs/guides/query-keys),
  [typed queries](https://query-kit.dev/docs/guides/typed-queries),
  [mutations](https://query-kit.dev/docs/guides/mutations)
  and [infinite queries](https://query-kit.dev/docs/guides/infinite-queries)
- [Coming from React Query](https://query-kit.dev/docs/coming-from-react-query):
  the JavaScript names and their Dart counterparts
- [Differences from TanStack Query](https://query-kit.dev/docs/reference/differences-from-tanstack)
- [Troubleshooting](https://query-kit.dev/docs/reference/troubleshooting)
- [API reference](https://pub.dev/documentation/query_kit/latest/)
- A runnable tour: [`example/example.dart`](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/example/example.dart)

## License and credits

MIT. query_kit is a port of [TanStack Query](https://tanstack.com/query) by
Tanner Linsley and contributors, whose MIT notice is kept in
`LICENSE-TANSTACK`. Bugs and questions go to
[the issue tracker](https://github.com/dualmeta-gmbh/query_kit/issues).
