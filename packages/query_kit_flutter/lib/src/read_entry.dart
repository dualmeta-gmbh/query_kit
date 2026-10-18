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
/// something the latest read did not show. Keyless unfiltered reads can
/// also remember when a reread consumed a change before its notification;
/// an owner or another nested part may still show an earlier value. This
/// conservatively requests at most one rebuild for those displaced reads.
/// A read with an own-build proof acknowledges the change instead. A read
/// without a proof may already have refreshed everything, so the flag can
/// still request one conservative extra rebuild.
/// Filtered reads use only the latest read: Flutter provides no general
/// signal that an owner rebuilt with zero reads, so keeping an older value
/// would violate the predicate's `previous` contract. Consequently #108
/// remains for a filtered reread through an outer context; a nested part
/// reading through its own context has its own independent baseline.
class ReadEntry<T> {
  /// Watches [controller] and calls [rebuild] when a notification of its is
  /// worth a frame.
  ///
  /// Whether the reader is still there is [rebuild]'s business: a `State`
  /// checks `mounted`, an `Element` checks its own.
  ReadEntry(
    this.controller,
    this.rebuild, {
    this.preserveUnnotifiedRead = false,
  }) {
    controller.addListener(_onChanged);
  }

  /// The controller this entry watches, owned by this entry: [dispose]
  /// disposes it.
  final ValueListenable<T> controller;

  /// Called for a notification that moved something the reader can see.
  final VoidCallback rebuild;

  /// Keyless reads can be shared by an owner and its descendants. When no
  /// predicate filters them, remember a displaced read until the controller
  /// notifies: rereading a write during build must not consume that pending
  /// notification (#108). Builder widgets have one build and leave this off.
  final bool preserveUnnotifiedRead;

  /// The decision, over the controller's value and [observedStateOf] it: the
  /// result for every controller but an infinite query's, which keeps its
  /// paging flags beside the result — [besideOf] it, so a `buildWhen` that
  /// declines the result cannot hold them back. The rule an adapter gets for
  /// the same controller.
  late final RebuildRule<T> _rule = RebuildRule.of(controller);

  /// Whether an unfiltered reread saw a change before its notification.
  /// Only a boolean is needed: with no predicate, any displaced value calls
  /// for a rebuild, even if several rereads return to the original value.
  /// Consumed when a notification requests a rebuild, cleared by a filtered
  /// read or disposal. No historical values or widget/element graphs held.
  bool _unnotified = false;
  bool _recorded = false;

  /// The predicate the last build handed over, asked once the value is known
  /// to have moved.
  BuildWhen<T>? _buildWhen;

  /// Reads the controller's current value and records it as this build's,
  /// both halves, together with the [buildWhen] this build filters by.
  ///
  /// A build re-states its predicate because a widget's may change between
  /// builds; a reader with no predicate simply leaves it out.
  /// [ownBuildProof] acknowledges that this read is already refreshing the
  /// owner, using ReadSet's existing generation-opening signals. It consumes
  /// any pending change instead of scheduling another build for that read.
  /// No proof is required to preserve a change from another reread.
  T read({BuildWhen<T>? buildWhen, bool ownBuildProof = false}) {
    final unfiltered =
        preserveUnnotifiedRead && buildWhen == null && !ownBuildProof;
    final displaced = unfiltered &&
        _buildWhen == null &&
        _recorded &&
        _rule.shouldRebuild(null);
    // Finish the read before changing the flag or its predicate. A throwing
    // read must leave the last successful read intact (RebuildRule.read).
    final value = _rule.read();
    // A retired owner's value must never reach buildWhen or take the
    // infinite controller's unconditional `beside` path. Flutter exposes no
    // general signal for a build that reads nothing, so filtered reads keep
    // the single latest-read contract from before #108.
    _unnotified = unfiltered && (_unnotified || displaced);
    _buildWhen = buildWhen;
    _recorded = true;
    return value;
  }

  void _onChanged() {
    if (_rule.shouldRebuild(_buildWhen) || _unnotified) {
      _unnotified = false;
      rebuild();
    }
  }

  /// Stops watching and disposes the controller.
  void dispose() {
    _unnotified = false;
    _buildWhen = null;
    _recorded = false;
    controller.removeListener(_onChanged);
    (controller as ChangeNotifier).dispose();
  }
}
