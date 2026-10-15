# TanStack Query hooks for Flutter | query_kit_hooks

`useQuery`, `useMutation`, `useInfiniteQuery` and the rest of React Query's
hooks, on [`flutter_hooks`](https://pub.dev/packages/flutter_hooks). They read
the same cache, with the same rules, as the four call styles of
[`query_kit_flutter`](https://pub.dev/packages/query_kit_flutter), which this
package builds on and re-exports.

> **In development.** This package has not been released yet. The first
> release is 0.1.0; until then its API can change without notice.

**Documentation: [the hooks guide](https://query-kit.dualmeta.io/docs/guides/hooks)**
on [query-kit.dualmeta.io](https://query-kit.dualmeta.io/) ·
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
binding. Then read a query from a `HookWidget`:

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

The hook takes the same options and returns the same sealed `QueryResult` as
`context.query`. A different `queryKey` on a later build switches the same
observer to the other query. Unmounting the widget lets the query go.

## The hooks in 0.1.0

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
[the hooks guide](https://query-kit.dualmeta.io/docs/guides/hooks).

## License and credits

MIT. query_kit is a port of [TanStack Query](https://tanstack.com/query) by
Tanner Linsley and contributors, whose MIT notice is kept in
`LICENSE-TANSTACK`. The hooks run on
[`flutter_hooks`](https://pub.dev/packages/flutter_hooks) by Remi Rousselet.
Bugs and questions go to
[the issue tracker](https://github.com/dualmeta-gmbh/query_kit/issues).
