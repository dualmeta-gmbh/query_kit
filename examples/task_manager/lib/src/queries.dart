/// The whole cache policy of this demo lives in this file — every key,
/// staleness, seeding, polling and rollback rule the app has, in under 300
/// lines including comments. Note how small it is compared to the manual
/// reload wiring it replaces.
///
/// Shape: the list query owns *which* tasks exist, and a per-task query
/// owns *what each one is*. Both the overview rows and the detail screen read
/// the same per-task query, so invalidating one task updates both screens —
/// there is no cross-cache patching to keep in sync.
///
/// Both queries are declared once, in [TaskQueries], with their keys, their
/// data types and their fetch functions. Nothing outside this file spells a
/// key: a screen observes a reference's options, and a mutation reads, writes
/// and invalidates through a reference, so the type of what it touches is the
/// one the query was declared with.
library;

import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'api.dart';
import 'models.dart';

/// The client-wide defaults.
///
/// This app deliberately turns the aggressive ones off: no refetch when it
/// comes back to the foreground or the network returns, and one retry instead
/// of three — a demo backend that answers in ~900 ms should not be asked twice
/// for the same thing every time the window regains focus. Both the app and
/// the acceptance suite build their client from this, so the tests run the
/// policy the app ships with.
const DefaultOptions appDefaultOptions = DefaultOptions(
  queries: QueryDefaults(
    refetchOnWindowFocus: RefetchOn.never,
    refetchOnReconnect: RefetchOn.never,
    retry: RetryPolicy.times(1),
  ),
);

/// The app's two queries: their keys, their data types and how each is
/// fetched.
///
/// | | key | data |
/// |---|---|---|
/// | [list] | `['tasks', 'list', {search, project}]` | [TaskListResponse] |
/// | [byId] | `['tasks', 'byId', id]` | [Task] |
///
/// `queries.byId('1')` is the reference to one task's entry. It reads, writes
/// and invalidates that entry, and its `options()` are what a screen
/// observes. [list] and [byId] themselves select every list or every task,
/// and [namespace] everything the app caches.
///
/// The class holds the [TaskApi] the queries fetch through and no client,
/// so one instance serves any client, and making it fetches nothing. Every
/// list is one shared definition rather than options re-declared per screen:
/// two observers on one key with two different query functions would be a
/// coin flip over which one actually runs, and the seeding below would
/// silently stop happening depending on which widget built first.
final class TaskQueries {
  TaskQueries(this.api);

  /// The transport. The mutations below send their writes through it too.
  final TaskApi api;

  /// The prefix of everything this app caches.
  static final QueryNamespace namespace = QueryNamespace(const ['tasks']);

  /// One list per filter.
  ///
  /// The key holds the filters as their JSON map, the shape the backend
  /// receives them in, rather than the [TaskFilters] object.
  ///
  /// The query function also pushes each task into its per-task entry.
  /// `initialData` cannot do this job: it is only consulted when an entry is
  /// empty, so once a row has been built, later list responses would have no
  /// path into that entry and the row would render its own stale copy
  /// forever. Seeding also stamps those entries fresh, so building the rows
  /// never triggers a burst of per-task fetches.
  late final QueryFamily<TaskFilters, TaskListResponse> list =
      QueryFamily<TaskFilters, TaskListResponse>(
    namespace: namespace,
    name: 'list',
    keyOf: (filters) => [filters.toJson()],
    queryFn: (filters, context) async {
      final result = await api.listTasks(filters, signal: context.signal);
      for (final task in result.tasks) {
        byId(task.id).write(context.client, task);
      }
      return result;
    },
    configure: (base, _) => base.copyWith(
      staleTime: const StaleTime.duration(Duration(seconds: 45)),
    ),
  );

  /// One task, read by both the overview rows and the detail screen.
  late final QueryFamily<String, Task> byId = QueryFamily<String, Task>(
    namespace: namespace,
    name: 'byId',
    queryFn: (id, context) => api.getTask(id, signal: context.signal),
    configure: (base, _) => base.copyWith(
      staleTime: const StaleTime.duration(Duration(seconds: 45)),
      // While the scheduler has an unconfirmed write outstanding, poll until
      // it settles. The poll must survive the app losing focus, otherwise a
      // confirmation that lands while the user glances away is never picked
      // up.
      refetchInterval: RefetchInterval.dynamic((query) {
        final task = query.state.data;
        return task is Task && task.reminderPending
            ? const Duration(milliseconds: 500)
            : null;
      }),
      refetchIntervalInBackground: true,
    ),
  );
}

/// Used by the header: the overview's unfiltered list with a `select`, so
/// this costs no extra request — it derives from the cache entry that is
/// already there. Two widgets, two shapes of the same data, one fetch.
QuerySelectOptions<TaskListResponse, ({int synced, int total})> syncedTasks(
  TaskQueries queries,
) =>
    queries.list(TaskFilters.all).options().withSelect(
          (data) => (
            synced: data.tasks.where((task) => task.synced).length,
            total: data.tasks.length,
          ),
        );

/// One task as the overview rows and the detail screen observe it:
/// [TaskQueries.byId], plus a fallback seed from the lists.
///
/// The seed is for a task opened before any list response has seeded its
/// entry. Finding it means reading the lists, which takes a client, and a
/// definition holds none — so it is added here, per use, with a `copyWith`.
/// Inheriting the list's timestamp matters: dated data must not look freshly
/// fetched, or it would never revalidate.
QueryObserverOptions<Task> taskQuery(
  QueryClient client,
  TaskQueries queries,
  String id,
) {
  final options = queries.byId(id).options();
  for (final (list, data) in queries.list.readAll(client)) {
    for (final task in data?.tasks ?? const <Task>[]) {
      if (task.id == id) {
        return options.copyWith(
          initialData: InitialData.compute(() => task),
          initialDataUpdatedAt: list.state(client)?.dataUpdatedAt,
        );
      }
    }
  }
  return options;
}

/// What an optimistic write stashes so it can be rolled back.
///
/// The task as it was, or `null` when nothing was cached. Nothing finer is
/// needed: the optimistic patch writes nothing when there is no task to
/// patch, so "no entry" and "no data" both have nothing to restore.
typedef TaskSnapshot = Task?;

typedef RenameInput = ({String id, String name});

MutationOptions<Task, RenameInput, TaskSnapshot> renameTaskMutation(
  QueryClient client,
  TaskQueries queries,
) =>
    MutationOptions<Task, RenameInput, TaskSnapshot>(
      mutationKey: QueryKey(const <Object?>['renameTask']),
      mutationFn: (input) => queries.api.renameTask(input.id, input.name),
      onMutate: (input) async {
        final task = queries.byId(input.id);
        // Stop in-flight fetches so a stale response cannot overwrite the
        // patch.
        await task.cancel(client);
        final previous = task.read(client);
        task.update(client, (old) => old?.copyWith(name: input.name));
        return previous;
      },
      onError: (_, __, input, previous) {
        if (previous != null) {
          queries.byId(input.id).write(client, previous);
        }
      },
      // One invalidation, one entry. The detail screen and the overview row
      // both read this query, so both reconcile from the single refetch.
      onSettled: (_, __, ___, input, ____) =>
          queries.byId(input.id).invalidate(client),
    );

typedef ReminderInput = ({String id, bool value});

MutationOptions<Task, ReminderInput, TaskSnapshot> setReminderMutation(
  QueryClient client,
  TaskQueries queries,
) =>
    MutationOptions<Task, ReminderInput, TaskSnapshot>(
      mutationKey: QueryKey(const <Object?>['setReminder']),
      mutationFn: (input) =>
          queries.api.setReminder(input.id, value: input.value),
      onMutate: (input) async {
        final task = queries.byId(input.id);
        await task.cancel(client);
        final previous = task.read(client);
        // Write the requested value to `reminderTarget`, not to the
        // confirmed field, and deliberately leave `pending` alone: setting it
        // here would start the confirmation poll before the write had even
        // reached the backend, and the first poll would read pre-write state.
        // The UI renders `target ?? reminder`, so the switch still
        // flips instantly, and every later response agrees with it.
        task.update(
            client, (old) => old?.copyWith(reminderTarget: input.value));
        return previous;
      },
      onError: (_, __, input, previous) {
        if (previous != null) {
          queries.byId(input.id).write(client, previous);
        }
      },
      // The accepted response carries `pending: true`, which starts the poll
      // above. No invalidation here — the poll is already the reconciliation
      // loop.
      onSuccess: (accepted, input, ___) =>
          queries.byId(input.id).write(client, accepted),
    );

typedef CreateInput = ({String name, String? project, Priority? priority});

/// No optimistic step, so no `onMutate` and nothing to roll back:
/// `MutationOptions.simple` is the form for that.
MutationOptions<Task, CreateInput, void> createTaskMutation(
  QueryClient client,
  TaskQueries queries,
) =>
    MutationOptions.simple(
      mutationKey: QueryKey(const <Object?>['createTask']),
      mutationFn: (input) => queries.api.createTask(
          name: input.name, project: input.project, priority: input.priority),
      // Membership is a list concern, so this one invalidates every list.
      onSuccess: (_, __, ___) => queries.list.invalidate(client),
    );

/// Every list entry as it was before an optimistic delete.
typedef ListSnapshot
    = List<(TypedQueryKey<TaskListResponse>, TaskListResponse?)>;

MutationOptions<String, String, ListSnapshot> deleteTaskMutation(
  QueryClient client,
  TaskQueries queries,
) =>
    MutationOptions<String, String, ListSnapshot>(
      mutationKey: QueryKey(const <Object?>['deleteTask']),
      mutationFn: queries.api.deleteTask,
      onMutate: (id) async {
        await queries.list.cancel(client);
        final snapshot = queries.list.readAll(client);
        queries.list.updateAll(
          client,
          (old) => old?.withTasks(
            old.tasks.where((task) => task.id != id).toList(),
          ),
        );
        return snapshot;
      },
      onError: (_, __, ___, snapshot) {
        // Each list goes back to exactly what it held, whatever has happened
        // to it since: `readAll` returned every entry's typed key with its
        // data, and the key writes it back.
        for (final (key, data) in snapshot ?? const <Never>[]) {
          if (data != null) {
            key.write(client, data);
          }
        }
      },
      // The per-task entry goes only once the server has agreed: a refused
      // delete springs the row back, and the detail screen behind it must
      // still render from the seeded entry rather than fetch it again.
      onSuccess: (_, id, __) => queries.byId(id).remove(client),
      onSettled: (_, __, ___, ____, _____) => queries.list.invalidate(client),
    );
