/// `useInfiniteQuery`.
library;

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'controller_hook.dart';

/// Observes the infinite query [options] describe and returns its
/// [InfiniteQueryController] — `context.infiniteQuery` as a hook.
///
/// The widget rebuilds when the result changes, as [buildWhen] allows, and
/// always when only the paging flags moved.
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

  @override
  Object? observedStateOf(
          InfiniteQueryController<TPageData, TPageParam, TData> controller) =>
      controller.observedState;

  @override
  InfiniteQueryController<TPageData, TPageParam, TData> result(
    InfiniteQueryController<TPageData, TPageParam, TData> controller,
    QueryResult<TData> value,
  ) =>
      controller;

  @override
  String get debugLabel => 'useInfiniteQuery';
}
