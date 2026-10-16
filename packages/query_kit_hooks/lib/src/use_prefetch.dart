/// `usePrefetchQuery` and `usePrefetchInfiniteQuery`.
library;

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

/// Starts fetching the query [options] describe if the cache holds no entry
/// for its key, and returns nothing.
///
/// Call it in a widget above the one that reads the data, which reads it
/// with [useQuery] or any other call style. The parent builds first, so the
/// fetch is already running when the reader subscribes, and the reader joins
/// it instead of starting its own: fetch, then render.
///
/// Any entry counts, not only a successful one: a query that is still
/// fetching, one that failed, and one left pending by a cancelled fetch are
/// all left alone. A reader that mounts can still refetch such an entry, as
/// its own options allow; this hook never does. Calling it on every build
/// costs one lookup by key.
///
/// It holds no observer and never rebuilds the widget. Pass [client] to use
/// a client other than the nearest [QueryClientProvider]'s.
void usePrefetchQuery<TQueryData>(
  QueryOptions<TQueryData> options, {
  QueryClient? client,
}) {
  final resolved = _clientOf(client);
  if (_absent(resolved, options.queryKey)) {
    resolved.query(options).ignore();
  }
}

/// [usePrefetchQuery] for an infinite query: starts fetching the pages
/// [options] describe if the cache holds no entry for its key, and returns
/// nothing.
///
/// A first fetch loads the first page, or as many as
/// [InfiniteQueryOptions.pages] asks for. The widget that reads the pages
/// reads them with [useInfiniteQuery] or any other call style, and pages on
/// from there.
///
/// As with [usePrefetchQuery], any entry under the key — fetching, failed or
/// pending — is left alone, and the widget is never rebuilt.
void usePrefetchInfiniteQuery<TPageData, TPageParam>(
  InfiniteQueryOptions<TPageData, TPageParam> options, {
  QueryClient? client,
}) {
  final resolved = _clientOf(client);
  if (_absent(resolved, options.queryKey)) {
    resolved.infiniteQuery(options).ignore();
  }
}

// `useContext` either way, so a call outside a hook widget's build fails
// the same with or without `client:`.
QueryClient _clientOf(QueryClient? client) {
  final context = useContext();
  return client ?? QueryClientProvider.of(context);
}

// Untyped on purpose (plan D11, review P2-1): `getQueryState` without a type
// argument asks for a `dynamic` entry, which no entry is, so it would throw
// `QueryDataTypeError` on the build after the prefetch created one. `exact`
// is `find`'s default, spelled out because `findAll`'s is a prefix match: a
// longer key under this one is not this entry.
bool _absent(QueryClient client, QueryKey key) =>
    client.queryCache.find(
      filters: QueryFilters(queryKey: key, exact: true),
    ) ==
    null;
