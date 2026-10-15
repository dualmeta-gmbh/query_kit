/// TanStack Query's hooks for Flutter: `useQuery`, `useMutation` and the
/// rest, on `flutter_hooks`, reading the same cache as `query_kit_flutter`'s
/// four call styles.
///
/// The binding is re-exported, so this one import is enough besides
/// `flutter_hooks`' own:
///
/// ```dart
/// import 'package:flutter_hooks/flutter_hooks.dart';
/// import 'package:query_kit_hooks/query_kit_hooks.dart';
/// ```
library;

export 'package:query_kit_flutter/query_kit_flutter.dart';

export 'src/use_counts.dart';
export 'src/use_infinite_query.dart';
export 'src/use_mutation.dart';
export 'src/use_prefetch.dart';
export 'src/use_queries.dart';
export 'src/use_query.dart';
export 'src/use_query_client.dart';
