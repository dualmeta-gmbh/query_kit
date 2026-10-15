/// The Posts tab: a list, the posts recently viewed, and a post's detail.
library;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:query_kit_hooks/query_kit_hooks.dart';

import 'app.dart';
import 'group.dart';
import 'queries.dart';

class PostsTab extends HookWidget {
  const PostsTab({super.key, required this.viewed, required this.onOpen});

  /// The ids of the posts opened last, newest first.
  final List<int> viewed;
  final OpenPost onOpen;

  @override
  Widget build(BuildContext context) {
    final posts = useQuery(postsQuery(ApiScope.of(context)));

    return Column(
      children: [
        if (viewed.isNotEmpty) RecentlyViewed(ids: viewed, onOpen: onOpen),
        Expanded(
          child: switch (posts) {
            QueryPending() => const Center(child: Text('Loading posts…')),
            QueryError(:final error) => Center(child: Text('$error')),
            QuerySuccess(:final data) => Group(
                name: 'posts',
                child: ListView.builder(
                  itemCount: data.length,
                  itemBuilder: (context, index) => ListTile(
                    title: Text(data[index].title),
                    onTap: () => onOpen(data[index].id),
                  ),
                ),
              ),
          },
        ),
      ],
    );
  }
}

/// The posts opened last: a list of ids that changes as the user reads,
/// each read as its own query. They were fetched when they were opened, so
/// the cache answers.
class RecentlyViewed extends HookWidget {
  const RecentlyViewed({super.key, required this.ids, required this.onOpen});

  final List<int> ids;
  final OpenPost onOpen;

  @override
  Widget build(BuildContext context) {
    final api = ApiScope.of(context);
    final posts = useQueries([for (final id in ids) postQuery(api, id)]);

    return Group(
      name: 'recently viewed',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Recently viewed'),
            // Buttons, not chips: a chip carries a selected state, and the
            // web reads a selectable thing as a checkbox.
            for (final (index, post) in posts.indexed)
              OutlinedButton(
                onPressed: () => onOpen(ids[index]),
                child: Text(post.dataOrNull?.title ?? 'Loading…'),
              ),
          ],
        ),
      ),
    );
  }
}

class PostDetail extends HookWidget {
  const PostDetail({super.key, required this.id, required this.onOpen});

  final int id;
  final OpenPost onOpen;

  @override
  Widget build(BuildContext context) {
    final api = ApiScope.of(context);
    // The comments are read below, by a widget that exists only once the
    // post has arrived. Prefetched here, their request runs beside the
    // post's instead of after it.
    usePrefetchQuery(commentsQuery(api, id));
    final post = useQuery(postQuery(api, id));

    return Scaffold(
      appBar: AppBar(title: Text('Post $id')),
      body: switch (post) {
        QueryPending() => const Center(child: Text('Loading post…')),
        QueryError(:final error) => Center(child: Text('$error')),
        QuerySuccess(:final data) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              UpNext(id: id, onOpen: onOpen),
              Group(
                name: 'post',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(data.body),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Comments(postId: id),
            ],
          ),
      },
    );
  }
}

class Comments extends HookWidget {
  const Comments({super.key, required this.postId});

  final int postId;

  @override
  Widget build(BuildContext context) {
    final comments = useQuery(commentsQuery(ApiScope.of(context), postId));

    return Group(
      name: 'comments',
      child: switch (comments) {
        QueryPending() => const Text('Loading comments…'),
        QueryError(:final error) => Text('$error'),
        QuerySuccess(:final data) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${data.length} comments'),
              for (final comment in data)
                ListTile(
                  title: Text(comment.text),
                  subtitle: Text(comment.author),
                ),
            ],
          ),
      },
    );
  }
}

/// The two posts after this one in the list, as one answer: nothing until
/// both are here, one error if either fails. Fetched now, the next post
/// opens from the cache.
class UpNext extends HookWidget {
  const UpNext({super.key, required this.id, required this.onOpen});

  final int id;
  final OpenPost onOpen;

  @override
  Widget build(BuildContext context) {
    final api = ApiScope.of(context);
    final ids = useSelectQuery(postIdsQuery(api)).dataOrNull ?? const <int>[];
    final at = ids.indexOf(id);
    final next = at < 0 ? const <int>[] : ids.skip(at + 1).take(2).toList();
    final upNext = useCombinedQueries(
      [for (final id in next) postQuery(api, id)],
      (posts) => [for (final post in posts) post.title],
      keys: const [],
    );

    if (next.isEmpty) {
      return const SizedBox.shrink();
    }
    return Group(
      name: 'up next',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: switch (upNext) {
          CombinedPending() => const Text('Up next: loading…'),
          CombinedError(:final error) => TextButton(
              onPressed: upNext.retry,
              child: Text('Up next failed: $error. Try again'),
            ),
          CombinedData(:final data) => Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Up next: ${data.join(', then ')}'),
                FilledButton(
                  onPressed: () => onOpen(next.first, replace: true),
                  child: const Text('Next post'),
                ),
              ],
            ),
        },
      ),
    );
  }
}
