/// Every query and mutation the app uses, in one place: a widget says which
/// hook reads what, and this file says what it is.
///
/// Todos and projects are typed query definitions: each resource is a class
/// that holds a namespace, its queries and its writes, and a widget reads a
/// query through its reference (`todos.list.options()`), with no key and no
/// type argument at the call site. Posts are written in the raw form, a key
/// and an options function per query, which is what React Query's
/// `queryOptions` does. Both read the same cache, and the app uses both on
/// purpose.
library;

import 'package:query_kit_hooks/query_kit_hooks.dart';

import 'api.dart';
import 'models.dart';

/// The keys of the posts, which are read through raw options, and of the
/// todo writes, which mutations filter by.
abstract final class Keys {
  // Posts show the raw form on purpose: a `QueryKey` and an options
  // function per query, beside the typed definitions of todos and projects.
  static QueryKey get posts => QueryKey(const <Object?>['posts']);
  static QueryKey post(int id) => posts.append(<Object?>[id]);
  static QueryKey comments(int postId) =>
      post(postId).append(const <Object?>['comments']);

  /// The mutation key of every todo write: `useIsMutating` and the
  /// mutation-state hooks filter by it.
  static QueryKey get todoWrites => QueryKey(const <Object?>['todo-writes']);
  static QueryKey get addTodo => todoWrites.append(const <Object?>['add']);
  static QueryKey get toggleTodo =>
      todoWrites.append(const <Object?>['toggle']);
}

/// The client-wide defaults: one retry, not three, so a refused request
/// shows its error within a second or two.
const DefaultOptions exampleDefaults = DefaultOptions(
  queries: QueryDefaults(retry: RetryPolicy.times(1)),
);

/// Posts and projects change rarely, so they stay fresh for a minute: going
/// back to a list, or opening a post twice, costs no request.
const StaleTime _aMinute = StaleTime.duration(Duration(minutes: 1));

// The raw form, kept on purpose: posts are read through options functions.
QueryObserverOptions<List<Post>> postsQuery(ExampleApi api) =>
    QueryObserverOptions<List<Post>>(
      queryKey: Keys.posts,
      queryFn: (context) => api.posts(signal: context.signal),
      staleTime: _aMinute,
    );

/// The same entry as [postsQuery], narrowed to the ids in order: what the
/// detail screen needs to know which post comes next.
QuerySelectOptions<List<Post>, List<int>> postIdsQuery(ExampleApi api) {
  final posts = postsQuery(api);
  return QuerySelectOptions<List<Post>, List<int>>(
    queryKey: posts.queryKey,
    queryFn: posts.queryFn,
    staleTime: posts.staleTime,
    select: (posts) => [for (final post in posts) post.id],
  );
}

QueryObserverOptions<Post> postQuery(ExampleApi api, int id) =>
    QueryObserverOptions<Post>(
      queryKey: Keys.post(id),
      queryFn: (context) => api.post(id, signal: context.signal),
      staleTime: _aMinute,
    );

QueryObserverOptions<List<Comment>> commentsQuery(ExampleApi api, int id) =>
    QueryObserverOptions<List<Comment>>(
      queryKey: Keys.comments(id),
      queryFn: (context) => api.comments(id, signal: context.signal),
      staleTime: _aMinute,
    );

/// Projects, a page at a time: one infinite query with no input.
final class ProjectQueries {
  ProjectQueries(this._api);

  final ExampleApi _api;

  /// Everything about projects: `['projects', ...]`.
  static final QueryNamespace namespace = QueryNamespace(const ['projects']);

  /// Every project, in pages. The type arguments are written out because
  /// `getNextPageParam` reads its page: Dart infers the page type from
  /// `pageFn` only when no other paging function needs it.
  late final list = InfiniteQueryDefinition<ProjectSlice, int>(
    namespace: namespace,
    name: 'list',
    pageFn: (context) =>
        _api.projects(context.pageParam, signal: context.signal),
    initialPageParam: 0,
    getNextPageParam: (page, _, __, ___) => page.nextId,
    configure: (base) => base.copyWith(staleTime: _aMinute),
  );
}

typedef Toggle = ({int id, bool done});

/// Todos: the list, how many are open, and the two writes, ticking one and
/// adding one.
///
/// Todo writes overlap: another todo ticked, one added. So the rules are
/// TkDodo's for concurrent optimistic updates, which upstream's guide links
/// to, with the last write told apart by a count of the writes' own
/// ([_TodoWrites]):
///
/// - a tick cancels the reads of the list in flight before it ticks, and no
///   refetch starts while a write is in flight ([list]), so no answer from
///   before a tick lands over it;
/// - every write cancels them when its answer arrives, before that goes
///   in: a read sent before the write was stored may still be out, a
///   first load above all, which no gate holds back ([_unlessWriting]);
/// - a write touches only its own todo: it ticks it, puts the backend's
///   answer in its place, or puts it back;
/// - the last write to settle refetches the list, for what changed
///   elsewhere, and does not wait for that read.
///
/// Two writes to one todo never overlap: the screen takes no tick on a todo
/// whose write is in flight.
final class TodoQueries {
  TodoQueries(this._api);

  final ExampleApi _api;

  /// Everything about todos: `['todos', ...]`.
  static final QueryNamespace namespace = QueryNamespace(const ['todos']);

  /// Every todo. Todos change under the user's hands, so they are never
  /// fresh: a return to the app, or to the tab, refetches them. Not while a
  /// todo write is in flight, though: that read could answer with the list
  /// from before the write and take its tick off the screen. The last write
  /// to settle refetches instead.
  late final list = QueryDefinition(
    namespace: namespace,
    name: 'list',
    queryFn: (context) => _api.todos(signal: context.signal),
    configure: (base) => base.copyWith(
      refetchOnMount: _unlessWriting,
      refetchOnWindowFocus: _unlessWriting,
      refetchOnReconnect: _unlessWriting,
    ),
  );

  /// The same entry as [list], narrowed to how many are open: a refetch
  /// that changes the list but not that number answers the same.
  QuerySelectOptions<List<Todo>, int> openCount() => list
      .options()
      .withSelect((todos) => todos.where((todo) => !todo.done).length);

  /// Ticks a todo in the cache before the backend answers, and puts it back
  /// if the backend refuses: an optimistic update through the cache.
  MutationOptions<Todo, Toggle, bool> toggle(QueryClient client) =>
      MutationOptions<Todo, Toggle, bool>(
        mutationKey: Keys.toggleTodo,
        mutationFn: (toggle) => _api.setDone(toggle.id, done: toggle.done),
        onMutate: (toggle) async {
          _started(client);
          await list.cancel(client);
          _setDone(client, toggle.id, done: toggle.done);
          // What the todo was: the box offers the other value.
          return !toggle.done;
        },
        onSuccess: (todo, _, __) async {
          await list.cancel(client);
          _putTodo(client, todo);
        },
        onError: (_, __, toggle, before) {
          if (before != null) {
            _setDone(client, toggle.id, done: before);
          }
        },
        onSettled: (_, __, ___, ____, _____) => _settled(client),
      );

  /// Adds a todo. The list shows it while it is pending from the mutation's
  /// own variables (`useTypedMutationState`), not from the cache: an
  /// optimistic update through the UI. The todo the backend answers with
  /// goes into the list before the mutation leaves pending, so a list on
  /// the screen hands the pending row over to it without a gap.
  ///
  /// It writes nothing to the cache before the backend answers, so unlike a
  /// tick it cancels no read as it starts. It follows the rules of [toggle]
  /// for the rest.
  MutationOptions<Todo, String, void> add(QueryClient client) =>
      MutationOptions<Todo, String, void>(
        mutationKey: Keys.addTodo,
        mutationFn: _api.addTodo,
        onMutate: (_) => _started(client),
        onSuccess: (todo, _, __) async {
          await list.cancel(client);
          _appendTodo(client, todo);
        },
        onSettled: (_, __, ___, ____, _____) => _settled(client),
      );

  void _setDone(QueryClient client, int id, {required bool done}) {
    list.update(
      client,
      (todos) => todos == null
          ? null
          : [
              for (final todo in todos)
                todo.id == id ? todo.copyWith(done: done) : todo,
            ],
    );
  }

  /// The backend's answer for a tick, in place of the todo with its id.
  void _putTodo(QueryClient client, Todo todo) {
    list.update(
      client,
      (todos) => todos == null
          ? null
          : [for (final each in todos) each.id == todo.id ? todo : each],
    );
  }

  /// The backend's answer for an add, at the end of the list. Not if the
  /// list has that todo already: a read brought it after it was stored, and
  /// it may have been ticked since.
  void _appendTodo(QueryClient client, Todo todo) {
    list.update(
      client,
      (todos) => todos == null || todos.any((each) => each.id == todo.id)
          ? todos
          : [...todos, todo],
    );
  }

  /// From a write's `onSettled`: one fewer in flight, and the last
  /// refetches the list, for every write in it and what changed elsewhere.
  ///
  /// Not awaited: the write is over, and the read is not part of it. A read
  /// of the list still in flight here was sent after every answer that went
  /// in, which each cancelled the reads before it, so the refetch may join
  /// it.
  void _settled(QueryClient client) {
    if (--_writes(client).inFlight == 0) {
      list.invalidate(client).ignore();
    }
  }
}

/// [RefetchOn.ifStale] while no todo write is in flight, [RefetchOn.never]
/// while one is. The core asks it when the moment comes: on mount, on
/// focus, on reconnect, handing it the query, whose client counts the
/// writes.
///
/// A list with no data yet loads on mount whatever this says. A write can
/// meet that first load, and its answer cancels it ([TodoQueries.toggle]).
final RefetchOn _unlessWriting = RefetchOn.when(
  (query) =>
      _writes(query.client).inFlight == 0 ? RefetchOn.ifStale : RefetchOn.never,
);

/// The todo writes between their `onMutate` and their `onSettled`, counted
/// per client by the writes themselves.
///
/// TkDodo's article asks `isMutating` instead, from `onSettled`, where a
/// write still counts itself: 1 means it is the last. But two writes that
/// settle in one turn each count the other there, and neither refetches.
/// Here a write takes itself out before it looks, so exactly one finds
/// none left.
final class _TodoWrites {
  int inFlight = 0;
}

final Expando<_TodoWrites> _todoWrites = Expando<_TodoWrites>();

_TodoWrites _writes(QueryClient client) =>
    _todoWrites[client] ??= _TodoWrites();

/// From a write's `onMutate`, first thing: one more in flight.
void _started(QueryClient client) => _writes(client).inFlight += 1;
