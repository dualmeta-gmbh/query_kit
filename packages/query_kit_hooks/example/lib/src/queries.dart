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
/// write and take its tick off the screen. The write that settles with no
/// other in flight refetches instead.
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
/// while one is. One rule per client, so the options above compare equal
/// from one build to the next.
RefetchOn _unlessWriting(QueryClient client) =>
    _unlessWritingRules[client] ??= RefetchOn.when(
      (_) => _todoWritesInFlight(client) == 0
          ? RefetchOn.ifStale
          : RefetchOn.never,
    );

final Expando<RefetchOn> _unlessWritingRules = Expando<RefetchOn>();

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
/// to:
///
/// - every write cancels the reads of the list in flight, and no read starts
///   while one is in flight ([todosQuery]), so no answer from before a write
///   lands after it;
/// - a write touches only its own todo: it ticks it, puts the backend's
///   answer in its place, or puts it back;
/// - the write that settles while no other is in flight refetches the list,
///   for what changed elsewhere. It does not wait for that refetch, so the
///   next write to settle counts it out.
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
        await _cancelTodoReads(client);
        _setDone(client, toggle.id, done: toggle.done);
        // What the todo was: the box offers the other value.
        return !toggle.done;
      },
      onSuccess: (todo, _, __) => _putTodo(client, todo),
      onError: (_, __, toggle, before) {
        if (before != null) {
          _setDone(client, toggle.id, done: before);
        }
      },
      onSettled: (_, __, ___, ____, _____) => _refetchIfLast(client),
    );

/// Adds a todo. The list shows it while it is pending from the mutation's
/// own variables (`useTypedMutationState`), not from the cache: an
/// optimistic update through the UI. The todo the backend answers with goes
/// into the list at once, so the pending row hands over to it without a gap.
/// It follows the rules of [toggleTodoMutation] for the rest.
MutationOptions<Todo, String, void> addTodoMutation(
  QueryClient client,
  ExampleApi api,
) =>
    MutationOptions<Todo, String, void>(
      mutationKey: Keys.addTodo,
      mutationFn: api.addTodo,
      onMutate: (_) => _cancelTodoReads(client),
      onSuccess: (todo, _, __) => _putTodo(client, todo),
      onSettled: (_, __, ___, ____, _____) => _refetchIfLast(client),
    );

/// Cancels a read of the list in flight: its answer may be from before the
/// write that asks.
Future<void> _cancelTodoReads(QueryClient client) => client.cancelQueries(
      filters: QueryFilters(queryKey: Keys.todos, exact: true),
    );

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

/// The backend's answer for [todo] in the list: in place of the todo with
/// its id, or at the end for a todo the list does not have yet.
void _putTodo(QueryClient client, Todo todo) {
  client.updateQueryData<List<Todo>>(
    Keys.todos,
    (todos) => todos == null
        ? null
        : todos.any((each) => each.id == todo.id)
            ? [for (final each in todos) each.id == todo.id ? todo : each]
            : [...todos, todo],
  );
}

int _todoWritesInFlight(QueryClient client) => client.isMutating(
      filters: MutationFilters(mutationKey: Keys.todoWrites),
    );

/// From a write's `onSettled`, where it still counts itself: refetches the
/// list if no other todo write is in flight.
void _refetchIfLast(QueryClient client) {
  if (_todoWritesInFlight(client) == 1) {
    client
        .invalidateQueries(
          filters: QueryFilters(queryKey: Keys.todos, exact: true),
        )
        .ignore();
  }
}
