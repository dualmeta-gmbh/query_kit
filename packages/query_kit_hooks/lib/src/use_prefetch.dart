/// `usePrefetchQuery`.
library;

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

/// Starts fetching the query [options] describe if the cache holds no entry
/// for its key — not a successful one, a pending one or a failed one — and
/// returns nothing: the widget that reads the data does so with [useQuery]
/// or any other call style. Cheap on every build: one lookup in a map.
///
/// The lookup is untyped (review P2-1): `getQueryState` without a type
/// argument would ask for a `dynamic` entry, which no entry is, and throw on
/// the build after the prefetch created one.
void usePrefetchQuery<TQueryData>(
  QueryOptions<TQueryData> options, {
  QueryClient? client,
}) {
  final context = useContext();
  final resolved = client ?? QueryClientProvider.of(context);
  final existing = resolved.queryCache.find(
    filters: QueryFilters(queryKey: options.queryKey, exact: true),
  );
  if (existing == null) {
    resolved.query(options).ignore();
  }
}
