/// The one import every fixture takes its API from.
///
/// Phase 0 (TQ0) proves the surface against a prototype, because the facade
/// does not exist in `package:query_kit` yet. Phase 1 (TQ1) points the
/// fixtures at the real exports by deleting the second export below: every
/// fixture then analyzes and runs against the package alone.
library;

export 'package:query_kit/query_kit.dart';

export 'prototype/typed_queries.dart';
