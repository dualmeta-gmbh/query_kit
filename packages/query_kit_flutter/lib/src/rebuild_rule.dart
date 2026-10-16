/// The rebuild decision every call style makes: what a reader's last build
/// read, and whether a notification is worth a frame.
///
/// "Read the value and what is observed beside it, rebuild only if that
/// moved, then ask `buildWhen`" is one decision, because every reader is owed
/// the same guarantee: nothing rebuilds for a notification carrying what the
/// reader is already showing. It owns nothing — no controller, no
/// subscription, no reader — so the binding's own `ReadEntry` and an adapter
/// package such as `query_kit_hooks` share it rather than copy it.
library;

// Exported by `adapter.dart`, with `BuildWhen`: ADR-0004 (map #92, D4).

import 'package:flutter/foundation.dart';

import 'query_controller.dart';

/// Whether a reader should rebuild for a change from [previous] to [current]
/// — the `buildWhen` every call style takes.
///
/// It is asked only when the value really changed: a notification carrying
/// what the reader is already showing never rebuilds, predicate or not. When
/// it returns `false`, the reader keeps showing [previous] — unless something
/// else rebuilds it — and the next change is compared against what it
/// shows.
///
/// ```dart
/// // Rebuild only when the task's name changes:
/// final task = context.query(
///   taskQuery(id),
///   buildWhen: (previous, current) =>
///       previous.dataOrNull?.name != current.dataOrNull?.name,
/// );
/// ```
///
/// {@category Reading queries}
typedef BuildWhen<T> = bool Function(T previous, T current);

/// What one reader's last build read from a controller, and whether what the
/// controller holds now is worth a frame.
///
/// This is the decision behind every call style of `query_kit_flutter`, for
/// packages that read queries in a shape of their own — `query_kit_hooks` is
/// one. It holds no controller and listens to nothing: the caller subscribes,
/// owns and disposes whatever it reads, and asks [shouldRebuild] from its own
/// listener.
///
/// ```dart
/// final rule = RebuildRule.of(controller);
///
/// // In the build:
/// final result = rule.read();
///
/// // In the listener:
/// if (rule.shouldRebuild(buildWhen)) markNeedsBuild();
/// ```
///
/// [RebuildRule.of] is the rule the call styles use for one of the binding's
/// controllers. A reading shape of its own — several controllers' results
/// under an equality of its own, say — gives the parts one by one to the
/// unnamed constructor.
///
/// A change to this class is a major version of `query_kit_flutter`.
final class RebuildRule<T> {
  /// A rule over [value] and [observedState]: the controller's value, and
  /// everything a reader can see of the controller as one value with value
  /// equality.
  ///
  /// For most controllers both are the value. An infinite query's controller
  /// also keeps its paging flags beside the result — a fetch that switches
  /// direction leaves the result untouched — so its observed state is
  /// `InfiniteQueryController.observedState`, the result and the flags
  /// together.
  ///
  /// [beside] is the part of [observedState] that is not in [value], when
  /// there is one: for an infinite query, the paging flags alone. A reader
  /// shows it, but `buildWhen` compares values and never sees it, so when it
  /// moves the reader rebuilds whatever `buildWhen` says of the value. Leave
  /// it out where the observed state is the value, or the value under an
  /// equality of its own.
  ///
  /// ```dart
  /// final rule = RebuildRule<QueryResult<Post>>(
  ///   value: () => feed.value,
  ///   observedState: () => (feed.value, feed.hasNextPage),
  ///   beside: () => feed.hasNextPage,
  /// );
  /// ```
  RebuildRule({
    required T Function() value,
    required Object? Function() observedState,
    Object? Function()? beside,
  })  : _value = value,
        _observedState = observedState,
        _beside = beside;

  /// The rule the call styles use for [controller]: its value, everything a
  /// reader can see of it, and the part of that beside the value — for an
  /// `InfiniteQueryController`, the paging flags.
  ///
  /// An adapter over the binding's controllers takes this one rather than
  /// spelling the parts out, so whatever a later version of the binding
  /// shows beside a controller's value is in its readers' rule too. It reads
  /// [controller] and nothing more: the caller still listens to it and
  /// disposes it.
  RebuildRule.of(ValueListenable<T> controller)
      : this(
          value: () => controller.value,
          observedState: () => observedStateOf(controller),
          beside: () => besideOf(controller),
        );

  final T Function() _value;
  final Object? Function() _observedState;
  final Object? Function()? _beside;

  /// The value the last build read, valid while [_recorded].
  late T _built;

  /// Whether a build has read through this rule yet. Nothing built means
  /// anything the controller says is news.
  bool _recorded = false;

  /// What the observed state was when [_built] was recorded.
  Object? _builtState;

  /// What [_beside] was when [_built] was recorded.
  Object? _builtBeside;

  /// Reads the current value and records it as this build's, together with
  /// the observed state and what is beside the value.
  ///
  /// All three are read before any is recorded, so a read that throws leaves
  /// the last one standing, and nothing it did not finish counts as built.
  T read() {
    final Object? state = _observedState();
    final Object? beside = _beside?.call();
    final T value = _value();
    _builtState = state;
    _builtBeside = beside;
    _recorded = true;
    return _built = value;
  }

  /// Whether what the controller holds now is worth a frame, given what
  /// [read] last recorded.
  ///
  /// * Nothing read yet: yes.
  /// * The observed state equal to the one built: no, before [buildWhen] is
  ///   even asked. The first build reads the result straight after the
  ///   subscribe started the fetch, and the observer's notification about
  ///   that very fetch arrives after the frame — a rebuild with nothing new
  ///   in it. Results carry value equality, so "nothing new" is `==`.
  /// * What is beside the value moved, with the value or without it: yes,
  ///   before [buildWhen] is asked. It cannot judge what it is not shown,
  ///   and a "no" would leave the reader showing the stale half — "Load
  ///   more" with no next page. Without a `beside`, the same holds when the
  ///   observed state moved and the value is equal.
  /// * Otherwise, as [buildWhen] says; with none, yes.
  bool shouldRebuild(BuildWhen<T>? buildWhen) {
    if (!_recorded) {
      return true;
    }
    if (_observedState() == _builtState) {
      return false;
    }
    final beside = _beside;
    if (beside != null && beside() != _builtBeside) {
      return true;
    }
    final current = _value();
    if (current == _built) {
      return true;
    }
    return buildWhen == null || buildWhen(_built, current);
  }
}
