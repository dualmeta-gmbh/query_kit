/// `useMutation`.
library;

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'controller_hook.dart';

/// A mutation owned by this call's position in `build`, as a
/// [MutationController] — `context.mutation` as a hook.
///
/// The widget rebuilds when the mutation's result changes, and only when
/// [buildWhen], if given, agrees. [client] is used instead of the nearest
/// `QueryClientProvider`'s.
///
/// Every build hands [options] to the controller, so a run still in flight
/// calls the callbacks of the latest build — they may close over that
/// build's state — and a different `mutationKey` starts over at idle.
/// Options that are new on every build add no build.
///
/// Unmounting does not cancel a running mutation: it settles, the callbacks
/// in [options] and the cache's run, and a `mutateAsync` future completes.
/// The callbacks handed to a single `mutate` or `mutateAsync` call are
/// dropped, because the widget they were meant for is gone. The same holds
/// when a build throws before this call: `flutter_hooks` then disposes this
/// hook, and the one that takes its place on the next build starts idle,
/// even while the earlier run is still going.
MutationController<TData, TVariables, TOnMutateResult>
    useMutation<TData, TVariables, TOnMutateResult>(
  MutationOptions<TData, TVariables, TOnMutateResult> options, {
  BuildWhen<MutationResult<TData, TVariables>>? buildWhen,
  QueryClient? client,
}) =>
        use(_MutationHook<TData, TVariables, TOnMutateResult>(options,
            buildWhen: buildWhen, client: client));

final class _MutationHook<TData, TVariables, TOnMutateResult>
    extends ControllerHook<
        MutationController<TData, TVariables, TOnMutateResult>,
        MutationResult<TData, TVariables>> {
  const _MutationHook(this.options, {super.buildWhen, super.client});

  final MutationOptions<TData, TVariables, TOnMutateResult> options;

  @override
  _MutationHookState<TData, TVariables, TOnMutateResult> createState() =>
      _MutationHookState<TData, TVariables, TOnMutateResult>();
}

final class _MutationHookState<TData, TVariables, TOnMutateResult>
    extends ControllerHookState<
        MutationController<TData, TVariables, TOnMutateResult>,
        MutationResult<TData, TVariables>,
        MutationController<TData, TVariables, TOnMutateResult>,
        _MutationHook<TData, TVariables, TOnMutateResult>> {
  @override
  MutationController<TData, TVariables, TOnMutateResult> create(
          QueryClient client) =>
      MutationController<TData, TVariables, TOnMutateResult>(
          client, hook.options);

  @override
  void apply(
          MutationController<TData, TVariables, TOnMutateResult> controller) =>
      controller.setOptions(hook.options);

  @override
  MutationResult<TData, TVariables> valueOf(
          MutationController<TData, TVariables, TOnMutateResult> controller) =>
      controller.value;

  @override
  MutationController<TData, TVariables, TOnMutateResult> result(
    MutationController<TData, TVariables, TOnMutateResult> controller,
    MutationResult<TData, TVariables> value,
  ) =>
      controller;

  @override
  String get debugLabel => 'useMutation';
}
