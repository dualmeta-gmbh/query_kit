/// The domain the hooks guide's samples talk about, and the options
/// functions they share with the rest of the site.
///
/// The names and shapes are `examples/doc_snippets`' own — `Task`, `api`,
/// `tasksQuery()`, `taskQuery(id)`, `feedQuery()` — so a reader who comes
/// from another page meets the same vocabulary. They are repeated here
/// rather than imported, because `doc_snippets` may not depend on this
/// package and this package may not depend on `doc_snippets`.
library;

import 'package:flutter/foundation.dart';
import 'package:query_kit_hooks/query_kit_hooks.dart';

/// A model with value equality.
@immutable
class Task {
  const Task({required this.id, required this.name, required this.done});

  final String id;
  final String name;
  final bool done;

  @override
  bool operator ==(Object other) =>
      other is Task &&
      other.id == id &&
      other.name == name &&
      other.done == done;

  @override
  int get hashCode => Object.hash(id, name, done);
}

@immutable
class Post {
  const Post(this.title);

  final String title;
}

/// Stands in for an HTTP client.
class Api {
  Future<List<Task>> listTasks({QueryCancelToken? signal}) async =>
      const <Task>[];

  Future<Task> getTask(String id, {QueryCancelToken? signal}) async =>
      Task(id: id, name: 'Draft the changelog', done: true);

  Future<Task> rename(String id, String name) async =>
      Task(id: id, name: name, done: false);

  Future<void> addTask(String name) async {}

  Future<List<Post>> feed({required int cursor}) async => const <Post>[];
}

final Api api = Api();

final QueryKey tasksKey = QueryKey(<Object?>['tasks']);

QueryKey taskKey(String id) => QueryKey(<Object?>['tasks', id]);

/// As on the quick start.
QueryObserverOptions<List<Task>> tasksQuery() => QueryObserverOptions(
      queryKey: tasksKey,
      queryFn: (context) => api.listTasks(signal: context.signal),
      staleTime: const StaleTime.duration(Duration(seconds: 30)),
    );

/// As on the query options guide.
QueryObserverOptions<Task> taskQuery(String id) => QueryObserverOptions(
      queryKey: taskKey(id),
      queryFn: (context) => api.getTask(id, signal: context.signal),
    );

/// As on the infinite queries guide.
InfiniteQueryObserverOptions<List<Post>, int> feedQuery() =>
    InfiniteQueryObserverOptions<List<Post>, int>(
      queryKey: QueryKey(<Object?>['feed']),
      pageFn: (context) => api.feed(cursor: context.pageParam),
      initialPageParam: 0,
      getNextPageParam: (page, pages, pageParam, pageParams) =>
          page.isEmpty ? null : pageParam + page.length,
    );
