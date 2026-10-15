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

// Exported alone by `adapter.dart`: ADR-0004 (map #92, D4).

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
/// final rule = RebuildRule<QueryResult<Task>>(
///   value: () => controller.value,
///   observedState: () => controller.value,
/// );
///
/// // In the build:
/// final result = rule.read();
///
/// // In the listener:
/// if (rule.shouldRebuild(buildWhen)) markNeedsBuild();
/// ```
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
  RebuildRule({
    required T Function() value,
    required Object? Function() observedState,
  })  : _value = value,
        _observedState = observedState;

  final T Function() _value;
  final Object? Function() _observedState;

  /// The value the last build read, valid while [_recorded].
  late T _built;

  /// Whether a build has read through this rule yet. Nothing built means
  /// anything the controller says is news.
  bool _recorded = false;

  /// What the observed state was when [_built] was recorded.
  Object? _builtState;

  /// Reads the current value and records it as this build's, together with
  /// the observed state beside it.
  T read() {
    _builtState = _observedState();
    _recorded = true;
    return _built = _value();
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
  /// * Only the half beside the value moved: yes. There is nothing for
  ///   [buildWhen] to compare, and the reader is showing the stale half.
  /// * Otherwise, as [buildWhen] says; with none, yes.
  bool shouldRebuild(BuildWhen<T>? buildWhen) {
    if (!_recorded) {
      return true;
    }
    if (_observedState() == _builtState) {
      return false;
    }
    final current = _value();
    if (current == _built) {
      return true;
    }
    return buildWhen == null || buildWhen(_built, current);
  }
}
