/// `packages/query_kit/README.md`'s samples — the pub.dev landing page of the
/// core, which is frozen into every published archive and so has to compile
/// on the day it ships.
///
/// Its own file, and like `pure_dart.dart` without Flutter, because the page
/// is the core's. The samples print, which is what a console program does.
// ignore_for_file: avoid_print
library;

import 'package:query_kit/query_kit.dart';

import 'doc_snippets.dart' show Api, Task, api;

// >>> packages/query_kit/README.md#definitions
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
// <<<

/// The README's quick start, top to bottom: setup, a first query read two
/// ways, the cache read and written, the same with raw keys, a first
/// mutation, and the cleanup that lets the process exit.
Future<void> readmeQuickStart(String id) async {
  // >>> packages/query_kit/README.md#setup
  final client = QueryClient();
  client.mount(); // react to focus and connectivity changes
  // <<<

  // >>> packages/query_kit/README.md#first-query
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
  // <<<
  print(all.length);
  await task.fetch(client); // joins the observer's fetch: there is data now

  // >>> packages/query_kit/README.md#cache
  final Task? cached = task.read(client); // no fetch, no subscription
  task.update(client, (previous) => previous?.copyWith(name: 'Renamed'));

  await task.invalidate(client); // this one entry
  await tasks.detail.invalidate(client); // every detail
  await TaskQueries.namespace.invalidate(client); // everything under 'tasks'
  // <<<
  print(cached?.name);

  // >>> packages/query_kit/README.md#raw-keys
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
  // <<<
  print('${listed.length} ${rawCached?.name}');
  rawObserver.destroy();

  // >>> packages/query_kit/README.md#first-mutation
  final addTask = MutationObserver(
    client,
    MutationOptions.simple(
      mutationFn: api.addTask,
      // Mark the list stale and refetch it for whoever is watching.
      onSuccess: (_, __, ___) => tasks.list.invalidate(client),
    ),
  );

  await addTask.mutateAsync('Write the release notes');
  // <<<

  // >>> packages/query_kit/README.md#cleanup
  unsubscribe();
  client.unmount();
  client.clear(); // empties the cache and cancels its timers
  // <<<
}
