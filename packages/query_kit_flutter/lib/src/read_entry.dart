/// One controller a reader watches, owned by the entry that watches it.
///
/// Whether a notification is worth a frame is [RebuildRule]'s decision, the
/// one every call style shares (and an adapter package with them). What an
/// entry adds is what the rule leaves to its caller, and what the owners
/// differ in stays outside both:
///
/// * **Who is told, and whether the reader is still there.** [ReadEntry.new]
///   takes the callback: `setState` behind `mounted` for a `State`,
///   `markNeedsBuild` behind its own check for an `Element`.
/// * **What owns the controller's identity.** A builder widget creates one
///   controller from its own options; `ReadSet` keeps a map of them by the
///   identity a keyless read was made under, and releases what a build
///   stopped asking for.
library;

import 'package:flutter/foundation.dart';

import 'query_controller.dart';
import 'rebuild_rule.dart';

/// One controller a reader watches, and what its last build read from it.
///
/// The entry listens to [controller] from the moment it is created until
/// [dispose], and calls [rebuild] for every notification that carries
/// something the reader is not already showing. [read] is the other half: a
/// build says what it is showing, so the next notification can be compared
/// against it.
class ReadEntry<T> {
  /// Watches [controller] and calls [rebuild] when a notification of its is
  /// worth a frame.
  ///
  /// Whether the reader is still there is [rebuild]'s business: a `State`
  /// checks `mounted`, an `Element` checks its own.
  ReadEntry(this.controller, this.rebuild) {
    controller.addListener(_onChanged);
  }

  /// The controller this entry watches, owned by this entry: [dispose]
  /// disposes it.
  final ValueListenable<T> controller;

  /// Called for a notification that moved something the reader can see.
  final VoidCallback rebuild;

  /// The decision, over the controller's value and [observedStateOf] it: the
  /// result for every controller but an infinite query's, which keeps its
  /// paging flags beside the result — [besideOf] it, so a `buildWhen` that
  /// declines the result cannot hold them back. The rule an adapter gets for
  /// the same controller.
  late final RebuildRule<T> _rule = RebuildRule.of(controller);

  /// The predicate the last build handed over, asked once the value is known
  /// to have moved.
  BuildWhen<T>? _buildWhen;

  /// Reads the controller's current value and records it as this build's,
  /// both halves, together with the [buildWhen] this build filters by.
  ///
  /// A build re-states its predicate because a widget's may change between
  /// builds; a reader with no predicate simply leaves it out.
  T read({BuildWhen<T>? buildWhen}) {
    _buildWhen = buildWhen;
    return _rule.read();
  }

  void _onChanged() {
    if (_rule.shouldRebuild(_buildWhen)) {
      rebuild();
    }
  }

  /// Stops watching and disposes the controller.
  void dispose() {
    controller.removeListener(_onChanged);
    (controller as ChangeNotifier).dispose();
  }
}
