# TanStack Query hooks for Flutter | query_kit_hooks

`useQuery`, `useMutation`, `useInfiniteQuery` and the rest of React Query's
hooks, on [`flutter_hooks`](https://pub.dev/packages/flutter_hooks). They read
the same cache, with the same rules, as the four call styles of
[`query_kit_flutter`](https://pub.dev/packages/query_kit_flutter), which this
package builds on and re-exports.

**Documentation: [the hooks guide](https://query-kit.dev/docs/guides/hooks)**
on [query-kit.dev](https://query-kit.dev/) ·
[API reference](https://pub.dev/documentation/query_kit_hooks/latest/)

> **AI-coded.** query_kit is an entirely AI-coded project: all code, tests
> and documentation were written by AI coding agents (Anthropic's Claude). A
> human maintainer set the goals and reviews releases, but did not write the
> code.
>
> **A port, not affiliated.** The behaviour is
> [TanStack Query](https://tanstack.com/query)'s, and upstream's own hook
> tests are ported case by case and run against these hooks, with thanks to
> Tanner Linsley and the TanStack team. This package is not affiliated with,
> endorsed by or connected to them; please take problems to
> [this repository's issues](https://github.com/dualmeta-gmbh/query_kit/issues),
> not to TanStack.

## Why a separate package

`query_kit_flutter` depends on nothing beyond Flutter, so it cannot use
`flutter_hooks`. This package can. If your widgets are already
`HookWidget`s, the hooks read a query the way the rest of your hooks read
state. If they are not, you do not need this package: the binding's four
call styles do the same job, and none of them is behind the hooks.

## Install

```bash
flutter pub add query_kit_hooks flutter_hooks
```

This package brings `query_kit_flutter` with it and re-exports it, so its
import gives you the whole binding. `flutter_hooks` goes in your
`pubspec.yaml` as well, because your files import it for `HookWidget`: this
package does not re-export it, and the `depend_on_referenced_packages` lint
asks for a direct dependency on every package a file imports.

```dart twin="guides/hooks.md#imports"
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:query_kit_hooks/query_kit_hooks.dart';
```

Requires Flutter 3.27 or later.

## Reading a query

Provide a `QueryClient` with a `QueryClientProvider`, exactly as for the
binding. Declare each query once, as a typed definition with its type
arguments written out:

```dart twin="guides/hooks.md#typed-definitions"
final class TaskQueries {
  TaskQueries(this._api);

  final Api _api;

  static final QueryNamespace namespace = QueryNamespace(<Object?>['tasks']);

  late final list = QueryDefinition<List<Task>>(
    namespace: namespace,
    name: 'list',
    queryFn: (context) => _api.listTasks(signal: context.signal),
  );

  late final detail = QueryFamily<String, Task>(
    namespace: namespace,
    name: 'detail',
    queryFn: (id, context) => _api.getTask(id, signal: context.signal),
  );

  late final pages = InfiniteQueryDefinition<List<Task>, int>(
    namespace: namespace,
    name: 'pages',
    pageFn: (context) => _api.taskPage(cursor: context.pageParam),
    initialPageParam: 0,
    getNextPageParam: (page, pages, pageParam, pageParams) =>
        page.isEmpty ? null : pageParam + page.length,
  );
}

final tasks = TaskQueries(api);
```

Then read it from a `HookWidget`. A reference's `options()` are what the
hook takes:

```dart twin="packages/query_kit_hooks/README.md#use-query"
class TaskList extends HookWidget {
  const TaskList({super.key});

  @override
  Widget build(BuildContext context) {
    final result = useQuery(tasks.list.options()); // QueryResult<List<Task>>

    return switch (result) {
      QueryPending() => const Center(child: CircularProgressIndicator()),
      QueryError(:final error) => Center(child: Text('$error')),
      QuerySuccess(:final data) => ListView(
          children: [for (final task in data) Text(task.name)],
        ),
    };
  }
}
```

The hook returns the same sealed `QueryResult` as `context.query`, with the
data type the definition declared. Options of another key on a later
build, `tasks.detail(id)` with a new `id` say, switch the same observer to
the other query. Unmounting the widget lets the query go.

`useInfiniteQuery(tasks.pages.options())` reads a paged definition the same
way, and a mutation's callbacks write through a reference. Two things the
analyzer lets through: a helper typed `QueryObserverOptions<Object>` makes
the hook create an `Object` entry that the reference then refuses, so write
the helper generic; and in `MutationOptions` without type arguments, an
`onMutate` parameter without a type is an `Object?`. The [hooks guide](https://query-kit.dev/docs/guides/hooks#typed-query-definitions)
shows both. Typed query definitions come with query_kit_hooks 0.1.3.

### With raw keys

Options written by hand, with a `QueryKey` and the type argument, work the
same way:

```dart twin="guides/hooks.md#use-query"
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

## The hooks

| Hook | Does what |
|---|---|
| `useQuery`, `useSelectQuery` | one query, with or without `select` |
| `useInfiniteQuery` | a paged query |
| `useMutation` | a mutation, as a `MutationController` |
| `useQueries`, `useCombinedQueries` | a list of queries, raw or combined |
| `useIsFetching`, `useIsMutating` | how many queries are fetching, how many mutations are pending |
| `useMutationState`, `useTypedMutationState` | a selection over the mutation cache, untyped or typed |
| `usePrefetchQuery`, `usePrefetchInfiniteQuery` | start a fetch without reading it |
| `useQueryClient` | the client of the nearest provider |

The hooks that read one result — `useQuery`, `useSelectQuery`,
`useInfiniteQuery`, `useMutation` and `useCombinedQueries` — take a
`buildWhen`, as the binding's call styles do. `useQueries` takes none, as
`QueriesBuilder` takes none. No hook rebuilds for a notification carrying
what the widget is already showing.

What each hook takes and returns, the rules of hooks, what a throw in
`build` costs and how to test a `HookWidget` are in
[the hooks guide](https://query-kit.dev/docs/guides/hooks).

## License and credits

MIT. query_kit is a port of [TanStack Query](https://tanstack.com/query) by
Tanner Linsley and contributors, whose MIT notice is kept in
`LICENSE-TANSTACK`. The hooks run on
[`flutter_hooks`](https://pub.dev/packages/flutter_hooks) by Remi Rousselet.
Bugs and questions go to
[the issue tracker](https://github.com/dualmeta-gmbh/query_kit/issues).
