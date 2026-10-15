/// The one shape every controller-owning hook has (plan, D5): everything in
/// `build`, nothing in `initHook`, the rebuild decided in the listener.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:query_kit_flutter/adapter.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

/// A hook that owns a [ChangeNotifier] controller [C] whose value is [T],
/// and returns [R] from it.
abstract base class ControllerHook<R, T> extends Hook<R> {
  /// No `keys`: a changed key is `setOptions` on the same controller (D6).
  const ControllerHook({this.client, this.buildWhen});

  /// The client to use instead of the nearest provider's.
  final QueryClient? client;

  /// Whether a change from the built value to the current one rebuilds.
  final BuildWhen<T>? buildWhen;
}

/// The state behind a [ControllerHook].
abstract base class ControllerHookState<R, T, C extends ChangeNotifier,
    H extends ControllerHook<R, T>> extends HookState<R, H> {
  QueryClient? _client;
  C? _controller;
  RebuildRule<T>? _rule;

  /// A new controller for [client] from the current hook's options.
  @protected
  C create(QueryClient client);

  /// Hands the current hook's options to [controller].
  @protected
  void apply(C controller);

  /// The controller's value.
  @protected
  T valueOf(C controller);

  /// What the controller observes beside its value; the value by default.
  @protected
  Object? observedStateOf(C controller) => valueOf(controller);

  /// What the hook returns, given the controller and the value just read.
  @protected
  R result(C controller, T value);

  @override
  R build(BuildContext context) {
    final client = hook.client ?? QueryClientProvider.of(context);
    var controller = _controller;
    if (controller == null || !identical(client, _client)) {
      _release();
      _client = client;
      final created = controller = _controller = create(client);
      _rule = RebuildRule<T>(
        value: () => valueOf(created),
        observedState: () => observedStateOf(created),
      );
      created.addListener(_onChanged);
    } else {
      apply(controller);
    }
    return result(controller, _rule!.read());
  }

  void _onChanged() {
    // Null once `_release` ran: a delivery still on its way when the hook was
    // disposed builds nothing, even while the element stays mounted (plan,
    // D5 rule 5).
    final rule = _rule;
    if (rule == null || !rule.shouldRebuild(hook.buildWhen)) {
      return;
    }
    if (context.mounted) {
      setState(() {});
    }
  }

  void _release() {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    controller
      ..removeListener(_onChanged)
      ..dispose();
    _controller = null;
    _rule = null;
  }

  @override
  void dispose() => _release();

  @override
  Object? get debugValue {
    final controller = _controller;
    return controller == null ? null : valueOf(controller);
  }
}
