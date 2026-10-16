/// The Projects tab: a list loaded a page at a time.
library;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:query_kit_hooks/query_kit_hooks.dart';

import 'app.dart';
import 'group.dart';
import 'models.dart';
import 'queries.dart';

class ProjectsTab extends HookWidget {
  const ProjectsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final projects = useInfiniteQuery(projectsQuery(ApiScope.of(context)));
    final pages = projects.value.dataOrNull?.pages ?? const <ProjectSlice>[];
    final items = [for (final page in pages) ...page.items];

    return switch (projects.value) {
      QueryPending() => const Center(child: Text('Loading projects…')),
      QueryError(:final error) => Center(child: Text('$error')),
      QuerySuccess() => Group(
          name: 'projects',
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(child: Text('${items.length} projects loaded')),
                    if (projects.isFetchingNextPage)
                      const Text('Loading more…')
                    else if (projects.hasNextPage)
                      TextButton(
                        onPressed: projects.fetchNextPage,
                        child: const Text('Load more'),
                      )
                    else
                      const Text('All loaded'),
                  ],
                ),
              ),
              Expanded(child: _ProjectList(items: items)),
            ],
          ),
        ),
    };
  }
}

class _ProjectList extends StatelessWidget {
  const _ProjectList({required this.items});

  final List<Project> items;

  @override
  Widget build(BuildContext context) => ListView.builder(
        itemCount: items.length,
        itemBuilder: (context, index) =>
            ListTile(title: Text(items[index].name)),
      );
}
