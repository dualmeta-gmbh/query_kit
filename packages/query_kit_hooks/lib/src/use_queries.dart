/// `useQueries` and `useCombinedQueries`.
library;

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'controller_hook.dart';

/// Observes every query in [queries] and returns their results, in order —
/// `QueriesBuilder` as a hook. No `buildWhen`, as there: a predicate over
/// the whole list cannot say which query moved.
List<QueryResult<TData>> useQueries<TQueryData, TData>(
  List<QueryObserverOptionsBase<TQueryData, TData>> queries, {
  QueryClient? client,
}) =>
    use(_QueriesHook<TQueryData, TData>(queries, client: client));

/// Observes every query in [queries] and returns what they amount to
/// together, by `combine`'s rules (`CombinedResult`) — and rebuilds only
/// when that changes, or when what its `retry`/`refetch` would act on does.
///
/// [combiner] must be a function of the values and of [keys] alone, as with
/// a `CombineMemo`: it runs again only when a value or a key changed, not on
/// every build as an inline `combine` does in React. So [keys] is required —
/// `const []` for a combiner that captures nothing from the build, the
/// captured values otherwise (review P3-9), as `useMemoized` spells it.
CombinedResult<R> useCombinedQueries<TQueryData, TData, R>(
  List<QueryObserverOptionsBase<TQueryData, TData>> queries,
  R Function(List<TData> values) combiner, {
  required List<Object?> keys,
  BuildWhen<CombinedResult<R>>? buildWhen,
  QueryClient? client,
}) =>
    use(_CombinedQueriesHook<TQueryData, TData, R>(queries, combiner,
        combineKeys: keys, buildWhen: buildWhen, client: client));

// ADR-0003: value equality does not imply callback ownership equality.

/// Element-wise equality over what a collection's actions act on: each
/// source's result and its `refetch` target, because equal results do not
/// mean equal callbacks.
final class _Sources {
  _Sources(this.entries);

  final List<Object?> entries;

  @override
  bool operator ==(Object other) {
    if (other is! _Sources || other.entries.length != entries.length) {
      return false;
    }
    for (var i = 0; i < entries.length; i++) {
      if (other.entries[i] != entries[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(entries);
}

final class _QueriesHook<TQueryData, TData>
    extends ControllerHook<List<QueryResult<TData>>, List<QueryResult<TData>>> {
  const _QueriesHook(this.queries, {super.client});

  final List<QueryObserverOptionsBase<TQueryData, TData>> queries;

  @override
  _QueriesHookState<TQueryData, TData> createState() =>
      _QueriesHookState<TQueryData, TData>();
}

final class _QueriesHookState<TQueryData, TData> extends ControllerHookState<
    List<QueryResult<TData>>,
    List<QueryResult<TData>>,
    QueriesController<TQueryData, TData>,
    _QueriesHook<TQueryData, TData>> {
  @override
  QueriesController<TQueryData, TData> create(QueryClient client) =>
      QueriesController<TQueryData, TData>(client, hook.queries);

  @override
  void apply(QueriesController<TQueryData, TData> controller) =>
      controller.setQueries(hook.queries);

  @override
  List<QueryResult<TData>> valueOf(
          QueriesController<TQueryData, TData> controller) =>
      controller.value;

  @override
  Object? observedStateOf(QueriesController<TQueryData, TData> controller) =>
      _Sources([
        for (final result in controller.value) (result, result.refetch),
      ]);

  @override
  List<QueryResult<TData>> result(
    QueriesController<TQueryData, TData> controller,
    List<QueryResult<TData>> value,
  ) =>
      value;

  @override
  String get debugLabel => 'useQueries';
}

final class _CombinedQueriesHook<TQueryData, TData, R>
    extends ControllerHook<CombinedResult<R>, CombinedResult<R>> {
  const _CombinedQueriesHook(this.queries, this.combiner,
      {required this.combineKeys, super.buildWhen, super.client});

  final List<QueryObserverOptionsBase<TQueryData, TData>> queries;
  final R Function(List<TData> values) combiner;

  /// The combiner's own keys — not `Hook.keys`, which would make
  /// flutter_hooks re-create the state, and the observers with it.
  final List<Object?> combineKeys;

  @override
  _CombinedQueriesHookState<TQueryData, TData, R> createState() =>
      _CombinedQueriesHookState<TQueryData, TData, R>();
}

final class _CombinedQueriesHookState<TQueryData, TData, R>
    extends ControllerHookState<
        CombinedResult<R>,
        CombinedResult<R>,
        QueriesController<TQueryData, TData>,
        _CombinedQueriesHook<TQueryData, TData, R>> {
  final CombineMemo<R> _memo = CombineMemo<R>();

  @override
  QueriesController<TQueryData, TData> create(QueryClient client) =>
      QueriesController<TQueryData, TData>(client, hook.queries);

  @override
  void apply(QueriesController<TQueryData, TData> controller) =>
      controller.setQueries(hook.queries);

  @override
  CombinedResult<R> valueOf(QueriesController<TQueryData, TData> controller) =>
      controller.value
          .combine(hook.combiner, memo: _memo, keys: hook.combineKeys);

  /// The combination, and beside it what `retry` and `refetch` act on: which
  /// sources are in error, and each source's refetch target.
  @override
  Object? observedStateOf(QueriesController<TQueryData, TData> controller) => (
        valueOf(controller),
        _Sources([
          for (final source in controller.value)
            (source.isError, source.refetch),
        ]),
      );

  @override
  CombinedResult<R> result(
    QueriesController<TQueryData, TData> controller,
    CombinedResult<R> value,
  ) =>
      value;

  @override
  String get debugLabel => 'useCombinedQueries';
}
