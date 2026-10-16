/// The app, its shell, and the activity line every tab shares.
library;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:query_kit_hooks/query_kit_hooks.dart';

import 'api.dart';
import 'group.dart';
import 'posts.dart';
import 'projects.dart';
import 'queries.dart';
import 'todos.dart';

class HooksExampleApp extends HookWidget {
  const HooksExampleApp({super.key, required this.api, this.client});

  final ExampleApi api;

  /// Injected by the tests, which bring their own client.
  final QueryClient? client;

  @override
  Widget build(BuildContext context) {
    final client = useMemoized(
      () => this.client ?? QueryClient(defaultOptions: exampleDefaults),
    );
    return QueryClientProvider(
      client: client,
      child: ApiScope(
        api: api,
        child: MaterialApp(
          title: 'query_kit_hooks',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorSchemeSeed: const Color(0xFF0B5FFF),
            useMaterial3: true,
          ),
          home: const HomeShell(),
        ),
      ),
    );
  }
}

/// The [ExampleApi] every screen talks to.
class ApiScope extends InheritedWidget {
  const ApiScope({super.key, required this.api, required super.child});

  final ExampleApi api;

  static ExampleApi of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ApiScope>()!.api;

  @override
  bool updateShouldNotify(ApiScope oldWidget) => api != oldWidget.api;
}

/// Opens post [id]: on top of the current screen, or in its place.
typedef OpenPost = void Function(int id, {bool replace});

class HomeShell extends HookWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    final api = ApiScope.of(context);
    // The Projects tab is built only when it is chosen. Its first page is
    // fetched now, so the tab opens on data and not on a spinner.
    usePrefetchInfiniteQuery(projectsQuery(api));

    final tab = useState(0);
    final viewed = useState(const <int>[]);

    void open(int id, {bool replace = false}) {
      viewed.value = [
        id,
        for (final seen in viewed.value)
          if (seen != id) seen,
      ].take(3).toList();
      final route = MaterialPageRoute<void>(
        builder: (_) => PostDetail(id: id, onOpen: open),
      );
      final navigator = Navigator.of(context);
      if (replace) {
        navigator.pushReplacement(route).ignore();
      } else {
        navigator.push(route).ignore();
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('query_kit_hooks'),
        bottom: const ActivityBar(),
      ),
      body: switch (tab.value) {
        0 => PostsTab(viewed: viewed.value, onOpen: open),
        1 => const TodosTab(),
        _ => const ProjectsTab(),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab.value,
        onDestinationSelected: (index) => tab.value = index,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.article_outlined),
            label: 'Posts',
          ),
          NavigationDestination(
            icon: Icon(Icons.check_box_outlined),
            label: 'Todos',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            label: 'Projects',
          ),
        ],
      ),
    );
  }
}

/// What the cache is doing, app-wide: how many queries are fetching, how
/// many todo writes are pending, and which of them failed.
class ActivityBar extends HookWidget implements PreferredSizeWidget {
  const ActivityBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(36);

  @override
  Widget build(BuildContext context) {
    final fetching = useIsFetching();
    final saving = useIsMutating(
      filters: MutationFilters(mutationKey: Keys.todoWrites),
    );
    final failures = useMutationState(
      filters: MutationFilters(
        mutationKey: Keys.todoWrites,
        status: MutationStatus.error,
      ),
      select: (mutation) => mutation.state.error,
    );
    final scenario = ApiScope.of(context).scenario;

    return Group(
      name: 'activity',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(
              spacing: 16,
              children: [
                Text('fetching $fetching'),
                Text('saving $saving'),
                Text('failed ${failures.length}'),
                if (failures.isNotEmpty) Text('last failure: ${failures.last}'),
                if (scenario != null) Text('scenario $scenario'),
              ],
            ),
          ),
          SizedBox(
            height: 2,
            child: fetching > 0 ? const LinearProgressIndicator() : null,
          ),
        ],
      ),
    );
  }
}
