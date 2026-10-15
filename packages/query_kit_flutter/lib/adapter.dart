/// The binding's rebuild decision, for packages that read queries in a shape
/// of their own.
///
/// This library is not for apps: an app imports
/// `package:query_kit_flutter/query_kit_flutter.dart` and reads queries in one
/// of its four call styles. It is for an adapter package that puts another
/// reading shape over the same controllers — `query_kit_hooks`, the hooks on
/// `flutter_hooks`, is one — and owes its readers the guarantee those four
/// give: nothing rebuilds for a notification carrying what the reader is
/// already showing.
///
/// [RebuildRule] is that decision and nothing else. It owns no controller and
/// listens to nothing, so the adapter keeps the controller's lifetime and the
/// subscription in its own hands, and the binding's call styles use the same
/// rule rather than a copy.
///
/// ```dart
/// import 'package:query_kit_flutter/adapter.dart';
/// import 'package:query_kit_flutter/query_kit_flutter.dart';
/// ```
///
/// What this library exports is covered by semantic versioning like the
/// rest of the package: a change to it is a major version.
library;

// Why a separate library, and why only the rule: ADR-0004 (map #92, D4).

export 'src/rebuild_rule.dart' show RebuildRule;
