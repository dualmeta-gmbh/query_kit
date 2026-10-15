/// The one shape every controller-owning hook has: everything in `build`,
/// nothing in `initHook`, the rebuild decided in the listener.
library;

// The shape is the plan's D5.

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:query_kit_flutter/adapter.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

/// A hook that owns a [ChangeNotifier] controller [C] whose value is [T],
/// and returns [R] from it.
abstract base class ControllerHook<R, T> extends Hook<R> {
  /// No `keys`: a changed key is `setOptions` on the same controller.
  // Plan, D6.
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

  /// Everything a reader can see of the controller, as one value with value
  /// equality; the value by default.
  @protected
  Object? observedStateOf(C controller) => valueOf(controller);

  /// The part of [observedStateOf] that is not in the value, which
  /// `buildWhen` never sees and so cannot decline: an infinite query's
  /// paging flags. `null`, nothing, by default.
  @protected
  Object? besideOf(C controller) => null;

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
        beside: () => besideOf(created),
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
    final controller = _controller;
    if (rule == null || controller == null) {
      return;
    }
    try {
      valueOf(controller);
    } on Object {
      // The value itself throws: a combiner that fails, say. Thrown here, it
      // would reach `notifyListeners`, which reports it and builds nothing,
      // so the widget would go on showing what it built. Build instead: the
      // build's read throws it again, where Flutter reports a build's errors
      // and a throw in build disposes this hook (plan, D13), as upstream's
      // render would throw it.
      if (context.mounted) {
        setState(() {});
      }
      return;
    }
    if (rule.shouldRebuild(hook.buildWhen) && context.mounted) {
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
