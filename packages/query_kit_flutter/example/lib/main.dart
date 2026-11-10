// query_kit is an entirely AI-coded project: all code, tests and
// documentation were written by AI coding agents (Anthropic's Claude). A
// human maintainer set the goals and reviews releases, but did not write the
// code.
//
// A one-file tour: a query declared once as a typed definition, a provider,
// the query read two ways, and a mutation that invalidates it. No server:
// the "API" is a delay and a list.
//
//   flutter run
import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

/// Stands in for an HTTP client.
class Api {
  final List<String> _tasks = ['Kitchen', 'Hallway', 'Garage'];

  Future<List<String>> list() async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return List.unmodifiable(_tasks);
  }

  Future<void> add(String name) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    _tasks.add(name);
  }
}

final api = Api();

/// Every query of the app, declared once: its key, its fetch function and
/// its data type, with the type arguments written out.
final class TaskQueries {
  TaskQueries(this._api);

  final Api _api;

  /// Every key below starts with 'tasks'.
  static final QueryNamespace namespace = QueryNamespace(<Object?>['tasks']);

  /// The task names, under the key ['tasks', 'list'].
  late final list = QueryDefinition<List<String>>(
    namespace: namespace,
    name: 'list',
    queryFn: (context) => _api.list(),
    configure: (base) => base.copyWith(
      staleTime: const StaleTime.duration(Duration(seconds: 30)),
    ),
  );
}

final tasks = TaskQueries(api);

/// The same entry, reduced to one flag. A `select` shares the cache entry;
/// its reader still rebuilds whenever the *result* changes — `fetchStatus`
/// and `dataUpdatedAt` are part of it, so every refetch is a rebuild, which
/// is exactly what a spinner needs. `select` keeps `data` stable, and
/// `buildWhen` on a builder is what would skip the rebuild.
QuerySelectOptions<List<String>, bool> fetchingQuery() =>
    tasks.list.options().withSelect((_) => true);

void main() {
  runApp(
    QueryClientProvider(
      client: QueryClient(),
      child: const MaterialApp(home: TasksScreen()),
    ),
  );
}

class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // One of the four equal call styles: read in build. The widget rebuilds
    // when the result changes. A reference's `options()` are the options
    // every call style takes, and the result's data type, `List<String>`,
    // comes from the definition.
    final list = context.query(tasks.list.options());
    // The client, taken here in `build` rather than inside the callback
    // below. A mutation outlives the widget that started it — disposing its
    // controller does not cancel it — so `onSuccess` can run after this
    // element is gone, and looking an ancestor up from a deactivated element
    // throws. The cache work has to happen either way; the client is the
    // right thing to close over, the `BuildContext` is not.
    final client = QueryClientProvider.of(context);
    // A mutation, the same way. `MutationOptions.simple` is the form without
    // an `onMutate` step: its types come from `api.add`.
    final add = context.mutation(
      MutationOptions.simple(
        mutationFn: api.add,
        onSuccess: (_, __, ___) => tasks.list.invalidate(client),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks'),
        actions: <Widget>[
          // Another, equally valid: a builder, for a leaf that only wants one
          // flag.
          QuerySelectBuilder<List<String>, bool>(
            options: fetchingQuery(),
            builder: (context, result) => result.isFetching
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () => result.refetch(),
                  ),
          ),
        ],
      ),
      body: switch (list) {
        QueryPending() => const Center(child: CircularProgressIndicator()),
        QueryError(:final error, staleData: null) =>
          Center(child: Text('$error')),
        QuerySuccess(:final data) ||
        QueryError(staleData: final data!) =>
          ListView(
            children: <Widget>[
              for (final name in data) ListTile(title: Text(name)),
            ],
          ),
      },
      floatingActionButton: FloatingActionButton(
        onPressed: add.value.isPending
            ? null
            : () => add.mutate('Task ${DateTime.now().second}'),
        child: const Icon(Icons.add),
      ),
    );
  }
}
