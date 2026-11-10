/// The Dart samples of the hooks guide (`website/docs/guides/hooks.md`) and
/// of this package's README, as code the analyzer sees.
///
/// A marked region is what a page's fence shows, and the fence names it
/// with `twin="<id>"`; `../docs_fences_test.dart` holds the two equal. The
/// samples live here, in the hooks package, and not in `examples/doc_snippets`
/// with the rest of the site's, because they need `flutter_hooks`, which no
/// example may depend on.
///
/// The samples that have to run — the widget test, the `unawaited` trap —
/// are in `guide_test.dart` beside this file.
library;

import 'package:flutter/material.dart';
// >>> guides/hooks.md#imports
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:query_kit_hooks/query_kit_hooks.dart';
// <<<

import 'fixtures.dart';

// >>> guides/hooks.md#use-query
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
// <<<

class OpenTaskCount extends HookWidget {
  const OpenTaskCount({super.key});

  @override
  Widget build(BuildContext context) {
    // >>> guides/hooks.md#use-select-query
    final open = useSelectQuery(
      tasksQuery().withSelect((tasks) => tasks.where((t) => !t.done).length),
    );
    // <<<
    return Text('${open.dataOrNull ?? '…'} open');
  }
}

class FeedList extends HookWidget {
  const FeedList({super.key});

  @override
  Widget build(BuildContext context) {
    // >>> guides/hooks.md#use-infinite-query
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
    // <<<
  }
}

// >>> guides/hooks.md#use-mutation
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
// <<<

class TaskNames extends HookWidget {
  const TaskNames(this.ids, {super.key});

  final List<String> ids;

  @override
  Widget build(BuildContext context) {
    // >>> guides/hooks.md#use-queries
    final results = useQueries([for (final id in ids) taskQuery(id)]);

    return Column(
      children: [
        for (final result in results) Text(result.dataOrNull?.name ?? '…'),
      ],
    );
    // <<<
  }
}

class MatchingTasks extends HookWidget {
  const MatchingTasks(this.ids, this.needle, {super.key});

  final List<String> ids;
  final String needle;

  @override
  Widget build(BuildContext context) {
    // >>> guides/hooks.md#use-combined-queries
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
    // <<<
  }
}

class ActivityBar extends HookWidget {
  const ActivityBar({super.key});

  @override
  Widget build(BuildContext context) {
    // >>> guides/hooks.md#counts
    final fetching = useIsFetching();
    final saving = useIsMutating(
      filters: MutationFilters(mutationKey: QueryKey(<Object?>['tasks'])),
    );

    if (fetching == 0 && saving == 0) return const SizedBox.shrink();
    return Text(saving > 0 ? 'Saving…' : 'Loading…');
    // <<<
  }
}

class PendingWrites extends HookWidget {
  const PendingWrites({super.key});

  @override
  Widget build(BuildContext context) {
    // >>> guides/hooks.md#mutation-state
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
    // <<<
    return Text('${adding.length} adding, ${names.join(', ')}');
  }
}

// >>> guides/hooks.md#prefetch
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
// <<<

class TaskTitle extends HookWidget {
  const TaskTitle(this.id, {super.key});

  final String id;

  @override
  Widget build(BuildContext context) {
    // >>> guides/hooks.md#build-when
    final task = useQuery(
      taskQuery(id),
      // A background refetch flips `isFetching` twice. This widget shows no
      // spinner for it, so only a new status or new data rebuilds it.
      buildWhen: (previous, current) =>
          previous.status != current.status ||
          previous.dataOrNull != current.dataOrNull,
    );
    // <<<
    return Text(task.dataOrNull?.name ?? '…');
  }
}

// >>> guides/hooks.md#selected-options
QueryObserverOptions<Task> selectedTaskQuery(String? id) =>
    QueryObserverOptions(
      queryKey: QueryKey(<Object?>['tasks', id]),
      queryFn: (context) => api.getTask(id!, signal: context.signal),
      // No selection: nothing to fetch.
      enabled: id == null ? Enabled.no : Enabled.yes,
    );
// <<<

class SelectedTask extends HookWidget {
  const SelectedTask(this.selectedId, {super.key});

  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    // >>> guides/hooks.md#selected-read
    // Called on every build, selection or not.
    final task = useQuery(selectedTaskQuery(selectedId));
    // <<<
    return Text(task.dataOrNull?.name ?? 'Nothing selected');
  }
}

// >>> packages/query_kit_hooks/README.md#use-query
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
// <<<

class TaskDetail extends HookWidget {
  const TaskDetail(this.id, {super.key});

  final String id;

  @override
  Widget build(BuildContext context) {
    // >>> guides/hooks.md#typed-read
    final task = useQuery(tasks.detail(id).options()); // QueryResult<Task>
    final pages = useInfiniteQuery(tasks.pages.options());
    // <<<
    final more = pages.value.dataOrNull?.flatten<Task>() ?? const <Task>[];
    return Text('${task.dataOrNull?.name ?? '…'} and ${more.length} more');
  }
}

class TaskPager extends HookWidget {
  const TaskPager(this.id, this.nextId, {super.key});

  final String id;
  final String nextId;

  @override
  Widget build(BuildContext context) {
    // >>> guides/hooks.md#typed-key
    final client = useQueryClient();
    final next = tasks.detail(nextId);
    // A new reference on every build, equal to the last one for an equal
    // id: the prefetch runs again only when the next id changes.
    useEffect(() {
      next.fetch(client).ignore();
      return null;
    }, [next]);
    // <<<
    final task = useQuery(tasks.detail(id).options());
    return Text(task.dataOrNull?.name ?? '…');
  }
}

// >>> guides/hooks.md#typed-mutation
class RenameTask extends HookWidget {
  const RenameTask(this.id, {super.key});

  final String id;

  @override
  Widget build(BuildContext context) {
    final client = useQueryClient();
    final task = tasks.detail(id); // QueryRef<Task>
    final rename = useMutation(
      MutationOptions<Task, String, Task?>(
        mutationFn: (name) => api.rename(id, name),
        onMutate: (name) async {
          await task.cancel(client);
          final previous = task.read(client);
          task.update(client, (current) => current?.copyWith(name: name));
          return previous;
        },
        onError: (_, __, ___, previous) {
          if (previous != null) task.write(client, previous);
        },
        onSettled: (_, __, ___, ____, _____) => task.invalidate(client),
      ),
    );

    return FilledButton(
      onPressed: rename.value.isPending ? null : () => rename.mutate('Renamed'),
      child: const Text('Rename'),
    );
  }
}
// <<<

// >>> guides/hooks.md#typed-helper
/// Shows what [builder] makes of the data, once [options] have some.
class Loaded<T> extends HookWidget {
  const Loaded(this.options, {required this.builder, super.key});

  // `QueryObserverOptions<T>`, not `QueryObserverOptions<Object>`: the
  // hook creates the entry for the type it is handed.
  final QueryObserverOptions<T> options;
  final Widget Function(T data) builder;

  @override
  Widget build(BuildContext context) {
    return switch (useQuery(options)) {
      QueryPending() => const CircularProgressIndicator(),
      QueryError(:final error) => Text('$error'),
      QuerySuccess(:final data) => builder(data),
    };
  }
}

// A Loaded<Task>: the type comes from the reference.
final title = Loaded(
  tasks.detail('1').options(),
  builder: (task) => Text(task.name),
);
// <<<
