/// Every query key, query and mutation the app uses, in one place: a widget
/// says which hook reads what, and this file says what it is.
///
/// Options are built by functions, which is what React Query's
/// `queryOptions` does: two widgets reading one key read it with the same
/// options.
library;

import 'package:query_kit_hooks/query_kit_hooks.dart';

import 'api.dart';
import 'models.dart';

abstract final class Keys {
  static QueryKey get posts => QueryKey(const <Object?>['posts']);
  static QueryKey post(int id) => posts.append(<Object?>[id]);
  static QueryKey comments(int postId) =>
      post(postId).append(const <Object?>['comments']);
  static QueryKey get todos => QueryKey(const <Object?>['todos']);
  static QueryKey get projects => QueryKey(const <Object?>['projects']);

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

/// Todos change under the user's hands, so they are never fresh: a return
/// to the app, or to the tab, refetches them. Not while a todo write is in
/// flight, though: that read could answer with the list from before the
/// write and take its tick off the screen. The last write to settle
/// refetches instead.
QueryObserverOptions<List<Todo>> todosQuery(
  ExampleApi api,
  QueryClient client,
) =>
    QueryObserverOptions<List<Todo>>(
      queryKey: Keys.todos,
      queryFn: (context) => api.todos(signal: context.signal),
      refetchOnMount: _unlessWriting(client),
      refetchOnWindowFocus: _unlessWriting(client),
      refetchOnReconnect: _unlessWriting(client),
    );

/// The same entry as [todosQuery], narrowed to how many are open: a
/// refetch that changes the list but not that number answers the same.
QuerySelectOptions<List<Todo>, int> openTodosQuery(
  ExampleApi api,
  QueryClient client,
) {
  final todos = todosQuery(api, client);
  return QuerySelectOptions<List<Todo>, int>(
    queryKey: todos.queryKey,
    queryFn: todos.queryFn,
    refetchOnMount: todos.refetchOnMount,
    refetchOnWindowFocus: todos.refetchOnWindowFocus,
    refetchOnReconnect: todos.refetchOnReconnect,
    select: (todos) => todos.where((todo) => !todo.done).length,
  );
}

/// [RefetchOn.ifStale] while no todo write is in flight, [RefetchOn.never]
/// while one is. The core asks it when the moment comes: on mount, on
/// focus, on reconnect.
///
/// A list with no data yet loads on mount whatever this says. A write can
/// meet that first load, and its answer cancels it ([toggleTodoMutation]).
RefetchOn _unlessWriting(QueryClient client) => RefetchOn.when(
      (_) =>
          _writes(client).inFlight == 0 ? RefetchOn.ifStale : RefetchOn.never,
    );

InfiniteQueryObserverOptions<ProjectSlice, int> projectsQuery(
  ExampleApi api,
) =>
    InfiniteQueryObserverOptions<ProjectSlice, int>(
      queryKey: Keys.projects,
      pageFn: (context) =>
          api.projects(context.pageParam, signal: context.signal),
      initialPageParam: 0,
      getNextPageParam: (page, _, __, ___) => page.nextId,
      staleTime: _aMinute,
    );

typedef Toggle = ({int id, bool done});

/// Ticks a todo in the cache before the backend answers, and puts it back if
/// the backend refuses: an optimistic update through the cache.
///
/// Todo writes overlap: another todo ticked, one added. So the rules are
/// TkDodo's for concurrent optimistic updates, which upstream's guide links
/// to, with the last write told apart by a count of the writes' own
/// ([_TodoWrites]):
///
/// - a tick cancels the reads of the list in flight before it ticks, and no
///   refetch starts while a write is in flight ([todosQuery]), so no answer
///   from before a tick lands over it;
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
MutationOptions<Todo, Toggle, bool> toggleTodoMutation(
  QueryClient client,
  ExampleApi api,
) =>
    MutationOptions<Todo, Toggle, bool>(
      mutationKey: Keys.toggleTodo,
      mutationFn: (toggle) => api.setDone(toggle.id, done: toggle.done),
      onMutate: (toggle) async {
        _started(client);
        await _cancelTodoReads(client);
        _setDone(client, toggle.id, done: toggle.done);
        // What the todo was: the box offers the other value.
        return !toggle.done;
      },
      onSuccess: (todo, _, __) async {
        await _cancelTodoReads(client);
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
/// optimistic update through the UI. The todo the backend answers with goes
/// into the list before the mutation leaves pending, so a list on the
/// screen hands the pending row over to it without a gap.
///
/// It writes nothing to the cache before the backend answers, so unlike a
/// tick it cancels no read as it starts. It follows the rules of
/// [toggleTodoMutation] for the rest.
MutationOptions<Todo, String, void> addTodoMutation(
  QueryClient client,
  ExampleApi api,
) =>
    MutationOptions<Todo, String, void>(
      mutationKey: Keys.addTodo,
      mutationFn: api.addTodo,
      onMutate: (_) => _started(client),
      onSuccess: (todo, _, __) async {
        await _cancelTodoReads(client);
        _appendTodo(client, todo);
      },
      onSettled: (_, __, ___, ____, _____) => _settled(client),
    );

QueryFilters get _todoList => QueryFilters(queryKey: Keys.todos, exact: true);

/// Cancels a read of the list in flight: its answer may be from before the
/// write that asks.
Future<void> _cancelTodoReads(QueryClient client) =>
    client.cancelQueries(filters: _todoList);

void _setDone(QueryClient client, int id, {required bool done}) {
  client.updateQueryData<List<Todo>>(
    Keys.todos,
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
  client.updateQueryData<List<Todo>>(
    Keys.todos,
    (todos) => todos == null
        ? null
        : [for (final each in todos) each.id == todo.id ? todo : each],
  );
}

/// The backend's answer for an add, at the end of the list. Not if the list
/// has that todo already: a read brought it after it was stored, and it may
/// have been ticked since.
void _appendTodo(QueryClient client, Todo todo) {
  client.updateQueryData<List<Todo>>(
    Keys.todos,
    (todos) => todos == null || todos.any((each) => each.id == todo.id)
        ? todos
        : [...todos, todo],
  );
}

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

/// From a write's `onSettled`: one fewer in flight, and the last refetches
/// the list, for every write in it and what changed elsewhere.
///
/// Not awaited: the write is over, and the read is not part of it. A read
/// of the list still in flight here was sent after every answer that went
/// in, which each cancelled the reads before it, so the refetch may join it.
void _settled(QueryClient client) {
  if (--_writes(client).inFlight == 0) {
    client.invalidateQueries(filters: _todoList).ignore();
  }
}
