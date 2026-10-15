/// `useIsFetching`, `useIsMutating`, `useMutationState` and
/// `useTypedMutationState`.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'controller_hook.dart';

/// How many queries matching [filters] are fetching, rebuilding the widget
/// when the count changes — `IsFetchingController` as a hook.
///
/// The filters of the latest build are the ones counted, so they may be
/// built anew in every `build`: that costs neither a new subscription nor a
/// build.
///
/// ```dart
/// final fetching = useIsFetching();
/// return fetching > 0 ? const LinearProgressIndicator() : const SizedBox();
/// ```
int useIsFetching({
  QueryFilters filters = const QueryFilters(),
  QueryClient? client,
}) =>
    use(_IsFetchingHook(filters, client: client));

/// How many mutations matching [filters] are pending, rebuilding the widget
/// when the count changes.
///
/// Only pending mutations count, whatever status [filters] names. The
/// filters of the latest build are the ones counted, as for
/// [useIsFetching].
int useIsMutating({
  MutationFilters filters = const MutationFilters(),
  QueryClient? client,
}) =>
    use(_IsMutatingHook(filters, client: client));

// Two hook types rather than one with the cache as a field: flutter_hooks
// keeps a hook's state when the hook at its position has the same runtime
// type, so a shared type would let `useIsMutating` inherit a query-cache
// subscription from a `useIsFetching` it replaced on a hot reload, and count
// mutations without ever hearing of one.
abstract base class _CountHook extends Hook<int> {
  const _CountHook({required this.client});

  final QueryClient? client;

  // Subscribes `listener` to the cache this hook counts in.
  void Function() subscribe(QueryClient client, void Function() listener);

  // The count, with this hook's filters.
  int count(QueryClient client);

  String get label;

  @override
  _CountHookState createState() => _CountHookState();
}

final class _IsFetchingHook extends _CountHook {
  const _IsFetchingHook(this.filters, {required super.client});

  final QueryFilters filters;

  @override
  void Function() subscribe(QueryClient client, void Function() listener) =>
      client.queryCache.subscribe((_) => listener());

  @override
  int count(QueryClient client) => client.isFetching(filters: filters);

  @override
  String get label => 'useIsFetching';
}

final class _IsMutatingHook extends _CountHook {
  const _IsMutatingHook(this.filters, {required super.client});

  final MutationFilters filters;

  @override
  void Function() subscribe(QueryClient client, void Function() listener) =>
      client.mutationCache.subscribe((_) => listener());

  @override
  int count(QueryClient client) => client.isMutating(filters: filters);

  @override
  String get label => 'useIsMutating';
}

// A direct cache subscription (plan, D12), guarded as `ControllerLifetime`
// guards a controller's: a delivery the notify manager queued before this
// state let go of its subscription — disposed, or moved to another client —
// finds its generation stale and does nothing, not even read the filters
// (review H-03; plan, D5 rule 5).
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
    // `hook` is this build's: its filters count from here on.
    return _built = hook.count(client);
  }

  void _deliver(int generation) {
    if (_disposed || generation != _generation || !context.mounted) {
      return;
    }
    if (hook.count(_client!) != _built) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    // `context` is not touched: this runs after the element unmounted.
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

/// What [select] makes of every mutation matching [filters], one entry per
/// mutation in the order they were added, rebuilding the widget when any
/// entry changes — `MutationStateController` as a hook.
///
/// [filters] and [select] may be built anew in every `build`: the latest
/// ones apply, and an unchanged selection costs no build. [select] runs over
/// every matching mutation on every change to the mutation cache, so keep it
/// cheap.
///
/// ```dart
/// final pendingTitles = useMutationState(
///   filters: MutationFilters(
///     mutationKey: QueryKey(['todos', 'add']),
///     status: MutationStatus.pending,
///   ),
///   select: (mutation) => mutation.state.variables,
/// );
/// ```
///
/// [useTypedMutationState] selects from mutations of one type, typed.
List<TSelected> useMutationState<TSelected>({
  MutationFilters filters = const MutationFilters(),
  required MutationStateSelect<TSelected> select,
  QueryClient? client,
}) =>
    use(_MutationStateHook<TSelected>(filters, select, client: client));

/// [useMutationState] over the mutations of one type, [select] receiving
/// them typed — `MutationStateController.typed` as a hook.
///
/// The types usually come from [select]'s parameter, and a type left as
/// `Object?` matches anything:
///
/// ```dart
/// final pendingRenames = useTypedMutationState(
///   filters: const MutationFilters(status: MutationStatus.pending),
///   // Every mutation whose variables are a String, and `variables` needs
///   // no cast.
///   select: (Mutation<Object?, String, Object?> mutation) =>
///       mutation.state.variables!,
/// );
/// ```
///
/// The type test is a mutation's declared type arguments, and it holds
/// whatever filters a later build passes; a predicate in [filters] only
/// ever sees mutations of those types.
List<TSelected>
    useTypedMutationState<TData, TVariables, TOnMutateResult, TSelected>({
  MutationFilters filters = const MutationFilters(),
  required TypedMutationStateSelect<TData, TVariables, TOnMutateResult,
          TSelected>
      select,
  QueryClient? client,
}) =>
        use(_TypedMutationStateHook<TData, TVariables, TOnMutateResult,
            TSelected>(filters, select, client: client));

// The untyped and the typed selection are two hook types for the reason
// `_CountHook` has two: a typed selection's type test lives in its
// controller, so swapping one call for the other must not keep the state.
abstract base class _SelectionHook<TSelected>
    extends ControllerHook<List<TSelected>, List<TSelected>> {
  const _SelectionHook(this.filters, {super.client});

  final MutationFilters filters;
}

final class _MutationStateHook<TSelected> extends _SelectionHook<TSelected> {
  const _MutationStateHook(super.filters, this.select, {super.client});

  final MutationStateSelect<TSelected> select;

  @override
  _MutationStateHookState<TSelected> createState() =>
      _MutationStateHookState<TSelected>();
}

final class _TypedMutationStateHook<TData, TVariables, TOnMutateResult,
    TSelected> extends _SelectionHook<TSelected> {
  const _TypedMutationStateHook(super.filters, this.select, {super.client});

  final TypedMutationStateSelect<TData, TVariables, TOnMutateResult, TSelected>
      select;

  @override
  _TypedMutationStateHookState<TData, TVariables, TOnMutateResult, TSelected>
      createState() => _TypedMutationStateHookState<TData, TVariables,
          TOnMutateResult, TSelected>();
}

// A selection's state: `setOptions` with the latest filters and select on
// every build after the first (plan, D9), and a rebuild only when the
// selection moved element by element.
abstract base class _SelectionHookState<TSelected,
        H extends _SelectionHook<TSelected>>
    extends ControllerHookState<List<TSelected>, List<TSelected>,
        MutationStateController<TSelected>, H> {
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
}

final class _MutationStateHookState<TSelected>
    extends _SelectionHookState<TSelected, _MutationStateHook<TSelected>> {
  @override
  MutationStateController<TSelected> create(QueryClient client) =>
      MutationStateController<TSelected>(client,
          filters: hook.filters, select: hook.select);

  @override
  void apply(MutationStateController<TSelected> controller) =>
      controller.setOptions(filters: hook.filters, select: hook.select);

  @override
  String get debugLabel => 'useMutationState';
}

final class _TypedMutationStateHookState<TData, TVariables, TOnMutateResult,
        TSelected>
    extends _SelectionHookState<
        TSelected,
        _TypedMutationStateHook<TData, TVariables, TOnMutateResult,
            TSelected>> {
  @override
  MutationStateController<TSelected> create(QueryClient client) =>
      MutationStateController.typed<TData, TVariables, TOnMutateResult,
          TSelected>(client, filters: hook.filters, select: hook.select);

  @override
  void apply(MutationStateController<TSelected> controller) {
    final select = hook.select;
    // `setOptions` takes the erased signature. The controller's type test
    // runs before any select, so every mutation this one receives is of the
    // declared types, and the cast cannot fail.
    controller.setOptions(
      filters: hook.filters,
      select: (mutation) =>
          select(mutation as Mutation<TData, TVariables, TOnMutateResult>),
    );
  }

  @override
  String get debugLabel => 'useTypedMutationState';
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
