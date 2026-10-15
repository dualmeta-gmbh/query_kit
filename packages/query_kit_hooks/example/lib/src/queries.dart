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
/// to the app refetches them.
QueryObserverOptions<List<Todo>> todosQuery(ExampleApi api) =>
    QueryObserverOptions<List<Todo>>(
      queryKey: Keys.todos,
      queryFn: (context) => api.todos(signal: context.signal),
    );

/// The same entry as [todosQuery], narrowed to how many are open: a
/// refetch that changes the list but not that number answers the same.
QuerySelectOptions<List<Todo>, int> openTodosQuery(ExampleApi api) {
  final todos = todosQuery(api);
  return QuerySelectOptions<List<Todo>, int>(
    queryKey: todos.queryKey,
    queryFn: todos.queryFn,
    select: (todos) => todos.where((todo) => !todo.done).length,
  );
}

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
/// Todo writes overlap: another todo ticked, one added. So a write touches
/// only its own todo, and it puts back only that todo. The list is refetched
/// by the last write to settle, because a refetch while another write is in
/// flight shows the list without that write. Two writes to one todo never
/// overlap: the screen takes no tick on a todo whose write is in flight.
MutationOptions<Todo, Toggle, bool> toggleTodoMutation(
  QueryClient client,
  ExampleApi api,
) =>
    MutationOptions<Todo, Toggle, bool>(
      mutationKey: Keys.toggleTodo,
      mutationFn: (toggle) => api.setDone(toggle.id, done: toggle.done),
      onMutate: (toggle) async {
        // A refetch that answers after the write would overwrite it.
        await client.cancelQueries(
          filters: QueryFilters(queryKey: Keys.todos, exact: true),
        );
        _setDone(client, toggle.id, done: toggle.done);
        // What the todo was: the box offers the other value.
        return !toggle.done;
      },
      onError: (_, __, toggle, before) {
        if (before != null) {
          _setDone(client, toggle.id, done: before);
        }
      },
      onSettled: (_, __, ___, ____, _____) async {
        if (_isLastTodoWrite(client)) {
          await _refetchTodos(client);
        }
      },
    );

/// Adds a todo. The list shows it while it is pending from the mutation's
/// own variables (`useTypedMutationState`), not from the cache: an
/// optimistic update through the UI. The todo the backend answers with goes
/// into the list at once, so the pending row hands over to it without a gap,
/// and the last todo write to settle refetches the list, as a tick's does.
MutationOptions<Todo, String, void> addTodoMutation(
  QueryClient client,
  ExampleApi api,
) =>
    MutationOptions.simple(
      mutationKey: Keys.addTodo,
      mutationFn: api.addTodo,
      onSuccess: (added, _, __) {
        client.updateQueryData<List<Todo>>(
          Keys.todos,
          (todos) => todos == null || todos.any((todo) => todo.id == added.id)
              ? todos
              : [...todos, added],
        );
      },
      onSettled: (_, __, ___, ____, _____) {
        if (_isLastTodoWrite(client)) {
          _refetchTodos(client).ignore();
        }
      },
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

/// Whether the write asking, from its `onSettled`, is the only todo write
/// in flight. It still counts itself there, so the last is a count of one.
bool _isLastTodoWrite(QueryClient client) =>
    client.isMutating(
      filters: MutationFilters(mutationKey: Keys.todoWrites),
    ) ==
    1;

Future<void> _refetchTodos(QueryClient client) => client.invalidateQueries(
      filters: QueryFilters(queryKey: Keys.todos, exact: true),
    );
