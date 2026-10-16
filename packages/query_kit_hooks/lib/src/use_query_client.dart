/// `useQueryClient`.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

// Not a `Hook`: there is nothing to keep between builds, and `of` already
// makes the element depend on the provider. A slot would only add a position
// a conditional call could shift (plan, D7 and D9).

/// The client of the nearest [QueryClientProvider] above the widget —
/// `QueryClientProvider.of` as a hook.
///
/// The widget rebuilds when the provider is given another client. Throws a
/// [FlutterError] when there is no provider above it, as every hook that
/// finds its client there does.
///
/// ```dart
/// final client = useQueryClient();
/// return TextButton(
///   onPressed: () => client.invalidateQueries(
///     filters: QueryFilters(queryKey: tasksKey),
///   ),
///   child: const Text('Refresh'),
/// );
/// ```
QueryClient useQueryClient() => QueryClientProvider.of(useContext());
