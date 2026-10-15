/// `useMutation`.
library;

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'controller_hook.dart';

/// A mutation owned by this call's position in `build`, as a
/// [MutationController] — `context.mutation` as a hook.
///
/// The widget rebuilds when the mutation's result changes. Unmounting does
/// not cancel a running mutation: it settles, and its cache-level callbacks
/// run.
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
