/// `useIsFetching`, `useIsMutating` and `useMutationState`.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'controller_hook.dart';

/// How many queries matching [filters] are fetching, rebuilding when the
/// count changes. The filters of the latest build are the ones counted.
int useIsFetching({
  QueryFilters filters = const QueryFilters(),
  QueryClient? client,
}) =>
    use(_CountHook(
      client: client,
      subscribe: (c, listener) => c.queryCache.subscribe((_) => listener()),
      count: (c) => c.isFetching(filters: filters),
      label: 'useIsFetching',
    ));

/// How many mutations matching [filters] are pending, rebuilding when the
/// count changes.
int useIsMutating({
  MutationFilters filters = const MutationFilters(),
  QueryClient? client,
}) =>
    use(_CountHook(
      client: client,
      subscribe: (c, listener) => c.mutationCache.subscribe((_) => listener()),
      count: (c) => c.isMutating(filters: filters),
      label: 'useIsMutating',
    ));

final class _CountHook extends Hook<int> {
  const _CountHook({
    required this.client,
    required this.subscribe,
    required this.count,
    required this.label,
  });

  final QueryClient? client;
  final void Function() Function(QueryClient client, void Function() listener)
      subscribe;
  final int Function(QueryClient client) count;
  final String label;

  @override
  _CountHookState createState() => _CountHookState();
}

/// A direct cache subscription, guarded as `ControllerLifetime` guards a
/// controller's: a delivery the notify manager queued before this hook let
/// go — disposed, or moved to another client — finds its generation stale
/// and does nothing (review H-03).
final class _CountHookState extends HookState<int, _CountHook> {
  QueryClient? _client;
  void Function()? _unsubscribe;
  int _generation = 0;
  bool _disposed = false;
  int _built = 0;

  @override
  int build(BuildContext context) {
    final client = hook.client ?? QueryClientProvider.of(context);
    if (!identical(client, _client)) {
      _unsubscribe?.call();
      _client = client;
      final generation = ++_generation;
      _unsubscribe = hook.subscribe(
        client,
        () => client.notifyManager.schedule(() => _deliver(generation)),
      );
    }
    return _built = hook.count(client);
  }

  void _deliver(int generation) {
    if (_disposed || generation != _generation) {
      return;
    }
    if (hook.count(_client!) != _built && context.mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _unsubscribe?.call();
    _unsubscribe = null;
  }

  @override
  Object? get debugValue => _built;

  @override
  String get debugLabel => hook.label;
}

/// What [select] makes of every mutation matching [filters], rebuilding when
/// any of it changes — `MutationStateController` as a hook.
List<TSelected> useMutationState<TSelected>({
  MutationFilters filters = const MutationFilters(),
  required MutationStateSelect<TSelected> select,
  QueryClient? client,
}) =>
    use(_MutationStateHook<TSelected>(filters, select, client: client));

final class _MutationStateHook<TSelected>
    extends ControllerHook<List<TSelected>, List<TSelected>> {
  const _MutationStateHook(this.filters, this.select, {super.client});

  final MutationFilters filters;
  final MutationStateSelect<TSelected> select;

  @override
  _MutationStateHookState<TSelected> createState() =>
      _MutationStateHookState<TSelected>();
}

final class _MutationStateHookState<TSelected> extends ControllerHookState<
    List<TSelected>,
    List<TSelected>,
    MutationStateController<TSelected>,
    _MutationStateHook<TSelected>> {
  @override
  MutationStateController<TSelected> create(QueryClient client) =>
      MutationStateController<TSelected>(client,
          filters: hook.filters, select: hook.select);

  @override
  void apply(MutationStateController<TSelected> controller) =>
      controller.setOptions(filters: hook.filters, select: hook.select);

  @override
  List<TSelected> valueOf(MutationStateController<TSelected> controller) =>
      controller.value;

  @override
  Object? observedStateOf(MutationStateController<TSelected> controller) =>
      _ElementWise(controller.value);

  @override
  List<TSelected> result(
    MutationStateController<TSelected> controller,
    List<TSelected> value,
  ) =>
      value;

  @override
  String get debugLabel => 'useMutationState';
}

final class _ElementWise {
  _ElementWise(this.entries);

  final List<Object?> entries;

  @override
  bool operator ==(Object other) {
    if (other is! _ElementWise || other.entries.length != entries.length) {
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
