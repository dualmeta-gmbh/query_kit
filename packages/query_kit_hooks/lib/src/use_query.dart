/// `useQuery` and `useSelectQuery`.
library;

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'controller_hook.dart';

/// Observes the query [options] describe and returns its current result,
/// rebuilding the widget when the result changes — `context.query` as a hook.
///
/// The observer belongs to this call's position in `build`: a different
/// `queryKey` on the next build switches the same observer to the other
/// query, which is what lets `placeholderData` show the previous one's data.
QueryResult<TData> useQuery<TData>(
  QueryObserverOptions<TData> options, {
  BuildWhen<QueryResult<TData>>? buildWhen,
  QueryClient? client,
}) =>
    use(_QueryHook<TData, TData>(options,
        buildWhen: buildWhen, client: client));

/// [useQuery] for a query with a `select`: the cache holds [TQueryData], the
/// widget reads [TData].
QueryResult<TData> useSelectQuery<TQueryData, TData>(
  QuerySelectOptions<TQueryData, TData> options, {
  BuildWhen<QueryResult<TData>>? buildWhen,
  QueryClient? client,
}) =>
    use(_QueryHook<TQueryData, TData>(options,
        buildWhen: buildWhen, client: client));

final class _QueryHook<TQueryData, TData>
    extends ControllerHook<QueryResult<TData>, QueryResult<TData>> {
  const _QueryHook(this.options, {super.buildWhen, super.client});

  final QueryObserverOptionsBase<TQueryData, TData> options;

  @override
  _QueryHookState<TQueryData, TData> createState() =>
      _QueryHookState<TQueryData, TData>();
}

final class _QueryHookState<TQueryData, TData> extends ControllerHookState<
    QueryResult<TData>,
    QueryResult<TData>,
    QueryController<TQueryData, TData>,
    _QueryHook<TQueryData, TData>> {
  @override
  QueryController<TQueryData, TData> create(QueryClient client) =>
      QueryController<TQueryData, TData>(client, hook.options);

  @override
  void apply(QueryController<TQueryData, TData> controller) =>
      controller.setOptions(hook.options);

  @override
  QueryResult<TData> valueOf(QueryController<TQueryData, TData> controller) =>
      controller.value;

  @override
  Object? observedStateOf(QueryController<TQueryData, TData> controller) =>
      controller.observedState;

  @override
  QueryResult<TData> result(
    QueryController<TQueryData, TData> controller,
    QueryResult<TData> value,
  ) =>
      value;

  @override
  String get debugLabel => 'useQuery';
}
