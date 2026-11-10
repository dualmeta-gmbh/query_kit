---
title: "Quick start: TanStack Query in a Flutter app"
sidebar_label: Quick start
description: TanStack Query in a Flutter app in four steps — a provider at the root, a typed query definition, a widget that reads it, and the mutation that invalidates it.
---

# Quick start

Four pieces: a client at the root of the app, a definition that describes the
query, a widget that reads it, and a write that tells the cache what it made
stale. Ten minutes, and every later page builds on them. If you have not seen
what the library is for yet, the [overview](overview.md) comes first.

## 0. Install

```bash
flutter pub add query_kit_flutter
```

One import, `package:query_kit_flutter/query_kit_flutter.dart`, brings in the
binding and the whole core with it. Pure Dart, versions and SDK floors are on
[installation](installation.md).

The samples below talk to an `api` object — whatever your app already uses to
reach its backend. All it has to offer is methods that return a `Future` and
throw when the request fails; [query functions](guides/query-functions.md)
shows one built on dio and one on `package:http`.

## 1. A client at the root

```dart snippet="quick-start.md#main"
void main() {
  runApp(
    QueryClientProvider(
      client: QueryClient(),
      child: const MaterialApp(home: TasksScreen()),
    ),
  );
}
```

The provider **mounts** the client it is given, which is what wires up
refetch-on-focus, refetch-on-reconnect and the resuming of paused mutations.
It does *not* dispose it: a `QueryClient` outlives the tree by design, so
`client.clear()` is yours to call — at sign-out, or at the end of a widget test.

If you want the provider to own the client as well, use
`QueryClientProvider.create`, which builds it and `clear()`s it when the tree
comes down:

```dart snippet="quick-start.md#main-owning-its-client"
void main() {
  runApp(
    QueryClientProvider.create(
      create: QueryClient.new,
      child: const MaterialApp(home: TasksScreen()),
    ),
  );
}
```

Create the client once — never in a `build` method, where every rebuild would
start an empty cache.

## 2. Describe the query once

Declare the query once, as a [typed query definition](guides/typed-queries.md).
It is what makes the same query readable from several widgets without drift:

```dart snippet="quick-start.md#definition"
final allTasks = QueryDefinition<List<Task>>(
  namespace: QueryNamespace(['tasks']),
  name: 'all',
  queryFn: (context) => api.listTasks(signal: context.signal),
  configure: (options) => options.copyWith(
    staleTime: const StaleTime.duration(Duration(seconds: 30)),
  ),
);
```

- The **namespace and the name** make the key, `['tasks', 'all']`, which
  identifies the data in the cache. See [query keys](guides/query-keys.md).
- The **function** fetches it, and must throw when it fails. `context.signal`
  lets it cancel its request. See [query functions](guides/query-functions.md).
- The **type argument** is the data type. Write it on every definition: a
  definition that takes an input, a family, has nothing else to tell Dart its
  input type. See [why the type arguments are
  written](guides/typed-queries.md#why-the-type-arguments-are-written).
- **`configure`** sets the options every use shares.
  `StaleTime.duration(…)` rather than a number: every option with a real
  "off" value is a sealed value type. See [important
  defaults](important-defaults.md).

The same query can be written as plain options behind a function, with a key
written by hand; every page's samples take either. See [describing a query
once](guides/query-options.md).

## 3. Read it

```dart snippet="quick-start.md#typed-screen"
class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tasks = context.query(allTasks.options());

    return Scaffold(
      appBar: AppBar(title: const Text('Tasks')),
      body: switch (tasks) {
        QueryPending() => const Center(child: CircularProgressIndicator()),
        QueryError(:final error) => Center(child: Text('$error')),
        QuerySuccess(:final data) => ListView(
            children: <Widget>[
              for (final task in data) TaskTile(task),
            ],
          ),
      },
    );
  }
}
```

`allTasks.options()` hands the definition's options to the widget; the
result is typed from them, with no type argument at the call site.

`QueryResult` is sealed, so the `switch` is exhaustive and there is no `data!`
anywhere. `QueryError` also carries `staleData` — the last good value — which
is what lets an error banner sit *above* the data that is still on screen
rather than replacing it. [Queries](guides/queries.md) explains every state a
result can be in.

This is one of [four equal ways to read a
query](guides/reading-queries-in-widgets.md). The other three are a builder
widget, a `State` mixin and a plain `ValueListenable`; none of them is the
default. If your widgets are already `HookWidget`s, the optional add-on
`query_kit_hooks` reads the same query with `useQuery`; see
[hooks](guides/hooks.md).

## 4. Write something, and invalidate

```dart snippet="quick-start.md#typed-mutation"
@override
Widget build(BuildContext context) {
  // Take the client here, in build, not inside the callback. A mutation
  // outlives the widget that started it, so `onSuccess` can run after this
  // element is gone, and looking an ancestor up from a deactivated element
  // throws.
  final client = QueryClientProvider.of(context);

  final add = context.mutation(
    MutationOptions.simple(
      mutationFn: api.addTask,
      onSuccess: (_, __, ___) => allTasks.invalidate(client),
    ),
  );

  return FilledButton(
    onPressed: add.value.isPending ? null : () => add.mutate('New task'),
    child: Text(add.value.isPending ? 'Adding…' : 'Add'),
  );
}
```

A mutation hands back a `MutationController` rather than a result, because you
need `mutate` as well as the state: `add.value` is the `MutationResult`,
`add.mutate(vars)` starts it. `allTasks.invalidate(client)` marks the list
stale and refetches it while it is on screen. See [mutations](guides/mutations.md) and
[invalidation from mutations](guides/invalidations-from-mutations.md).

:::note[In React Query]
The same four steps as TanStack Query's quick start: `QueryClientProvider`
at the root, `useQuery` (here `context.query`, or one of the other three
call styles), `useMutation` (here `context.mutation`, which returns a
controller) and an invalidation in `onSuccess`. The query is declared once,
as `queryOptions()` would declare it, and every use goes through it rather
than an object literal at the call site. See
[differences from TanStack Query](reference/differences-from-tanstack.md).
:::

## What you just got

Without writing any of it:

- **One request for many readers.** Mount the same query in five widgets and
  the cache deduplicates it.
- **Stale-while-revalidate.** A second visit renders from cache immediately and
  refetches behind it if the data is older than `staleTime`.
- **Refetch when the app returns to the foreground** — and on reconnect, once
  you [plug in connectivity](guides/connectivity.md) — retries with
  exponential backoff, and garbage collection of entries nobody is watching.
- **Cancellation** the moment nothing is observing the query any more, when
  the query function hands `context.signal` to its HTTP client.

Which of those fire, and when, is [important defaults](important-defaults.md).

## A runnable version

The showcase's `simple` screen is this page's query, running in your browser:
one read, its loading and success states, and a refetch that keeps the data on
screen while it runs. The backend is in memory, with the same 300 ms latency
as the real one.

<LiveDemo feature="simple" height={560} />

`packages/query_kit_flutter/example/` is a [one-file tour](examples/one-file-tour.mdx) of the same ground —
a provider, a query read two ways and a mutation that invalidates it, with
no server. `flutter run` in that directory.

For every feature as its own screen, see [the examples](examples/index.md); for
whole tasks, the [cookbook](cookbook/index.md); for one concept at a time, the
[guides](guides/index.md).

## Next steps

- [Important defaults](important-defaults.md) — why the list refetched when
  you came back to the app, and how to change it.
- [Queries](guides/queries.md) — every state a result can be in, and the
  flags for a spinner, a refresh bar and an error banner.
- [Query keys](guides/query-keys.md) — how to name data so one invalidation
  reaches exactly what a write changed.
- [Four ways to read a query](guides/reading-queries-in-widgets.md) — the
  builder, the mixin and the controller, if `context.query` is not the shape
  your widget wants.
- [Mutations](guides/mutations.md) — callbacks, errors and
  [optimistic updates](guides/optimistic-updates.md).
- [Testing](guides/testing.md) — the teardown every widget test with a
  client needs at its end.
- [Where the client lives](cookbook/dependency-injection.md) — one client, provided at the root and
  reached from anywhere, once the app has more than one screen.
