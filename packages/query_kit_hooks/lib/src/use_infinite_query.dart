/// `useInfiniteQuery`.
library;

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:query_kit_flutter/adapter.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'controller_hook.dart';

/// Observes the infinite query [options] describe and returns its
/// [InfiniteQueryController] — `context.infiniteQuery` as a hook.
///
/// The controller rather than a result, because paging lives on it: the
/// pages are in its `value`, the flags such as `hasNextPage` and
/// `isFetchingNextPage` beside it, and `fetchNextPage` loads more.
///
/// ```dart
/// final feed = useInfiniteQuery(feedQuery());
/// final posts = feed.value.dataOrNull?.flatten<Post>() ?? const <Post>[];
/// return ListView(
///   children: [
///     for (final post in posts) ListTile(title: Text(post.title)),
///     if (feed.hasNextPage)
///       TextButton(
///         onPressed: feed.isFetchingNextPage ? null : feed.fetchNextPage,
///         child: const Text('Load more'),
///       ),
///   ],
/// );
/// ```
///
/// The controller belongs to this call's position in `build`, and the hook
/// disposes it; do not dispose it yourself. A different `queryKey` on the
/// next build switches the same controller to the other query, which is
/// what lets `placeholderData` keep showing the previous one's pages.
///
/// So a `fetchNextPage` held in a callback acts on the query the controller
/// observes when it is called: after a key change, the new one. Called after
/// the widget is gone, it still fetches into the cache, as React Query's
/// does, and nothing rebuilds for it. A callback that can outlive the widget
/// checks `context.mounted` first.
///
/// [buildWhen] compares results, as it does for `context.infiniteQuery` and
/// `InfiniteQueryBuilder`. A fetch that moves the paging flags rebuilds
/// without asking it, whether the result moved too or not: it never sees
/// the flags, and a "no" would leave the widget showing the old ones —
/// "Load more" with no next page.
///
/// [client] is used instead of the nearest `QueryClientProvider`'s.
InfiniteQueryController<TPageData, TPageParam, TData>
    useInfiniteQuery<TPageData, TPageParam, TData>(
  InfiniteQueryObserverOptionsBase<TPageData, TPageParam, TData> options, {
  BuildWhen<QueryResult<TData>>? buildWhen,
  QueryClient? client,
}) =>
        use(_InfiniteQueryHook<TPageData, TPageParam, TData>(options,
            buildWhen: buildWhen, client: client));

final class _InfiniteQueryHook<TPageData, TPageParam, TData>
    extends ControllerHook<
        InfiniteQueryController<TPageData, TPageParam, TData>,
        QueryResult<TData>> {
  const _InfiniteQueryHook(this.options, {super.buildWhen, super.client});

  final InfiniteQueryObserverOptionsBase<TPageData, TPageParam, TData> options;

  @override
  _InfiniteQueryHookState<TPageData, TPageParam, TData> createState() =>
      _InfiniteQueryHookState<TPageData, TPageParam, TData>();
}

final class _InfiniteQueryHookState<TPageData, TPageParam, TData>
    extends ControllerHookState<
        InfiniteQueryController<TPageData, TPageParam, TData>,
        QueryResult<TData>,
        InfiniteQueryController<TPageData, TPageParam, TData>,
        _InfiniteQueryHook<TPageData, TPageParam, TData>> {
  @override
  InfiniteQueryController<TPageData, TPageParam, TData> create(
          QueryClient client) =>
      InfiniteQueryController<TPageData, TPageParam, TData>(
          client, hook.options);

  @override
  void apply(
          InfiniteQueryController<TPageData, TPageParam, TData> controller) =>
      controller.setInfiniteOptions(hook.options);

  @override
  QueryResult<TData> valueOf(
          InfiniteQueryController<TPageData, TPageParam, TData> controller) =>
      controller.value;

  /// The binding's rule, whose `beside` is the paging flags: a move of one
  /// rebuilds whatever `buildWhen` says of the result.
  @override
  RebuildRule<QueryResult<TData>> ruleOf(
          InfiniteQueryController<TPageData, TPageParam, TData> controller) =>
      RebuildRule.of(controller);

  @override
  InfiniteQueryController<TPageData, TPageParam, TData> result(
    InfiniteQueryController<TPageData, TPageParam, TData> controller,
    QueryResult<TData> value,
  ) =>
      controller;

  @override
  String get debugLabel => 'useInfiniteQuery';
}
