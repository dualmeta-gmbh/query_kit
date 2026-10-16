// Ported from
// query/packages/react-query/src/__tests__/QueryClientProvider.test.tsx at
// 50680b98c. Each case keeps upstream's name, and its upstream line is in
// the comment above it. What was adapted or omitted, and why, is in
// PORTING_NOTES.md. The provider is the binding's `QueryClientProvider`,
// written out here rather than through the harness's `app`, because it is
// what these cases are about. Each case's cache is made before its client,
// as upstream's is, and handed to it by the harness's `createClient`.
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_hooks/query_kit_hooks.dart';

import 'harness.dart';

/// Upstream's `Page`: a query, and its data in a heading.
Widget _page(QueryKey key, String answer) => HookBuilder(builder: (context) {
      final data = useQuery(QueryObserverOptions<String>(
        queryKey: key,
        queryFn: (_) => sleep(10).then((_) => answer),
      )).dataOrNull;

      return Column(children: [Text(data ?? '')]);
    });

void main() {
  // QueryClientProvider.test.tsx:21
  late QueryCache queryCache21;
  hookTest('sets a specific cache for all queries to use',
      (tester, client) async {
    final key = queryKey();

    final queryCache = queryCache21;

    await tester.pumpWidget(QueryClientProvider(
      client: client,
      observeAppLifecycle: false,
      child: MaterialApp(home: _page(key, 'test')),
    ));

    await advance(tester, 11);
    expect(find.text('test'), findsOneWidget);

    expect(
      queryCache.find(filters: QueryFilters(queryKey: key))?.state.data,
      'test',
    );
  }, createClient: () => QueryClient(queryCache: queryCache21 = QueryCache()));

  // QueryClientProvider.test.tsx:52
  late QueryCache queryCache52;
  hookTest('allows multiple caches to be partitioned', (tester, client) async {
    final key1 = queryKey();
    final key2 = queryKey();

    final queryCache1 = queryCache52;
    final queryCache2 = QueryCache();

    final queryClient1 = client;
    final queryClient2 = QueryClient(queryCache: queryCache2);
    addTearDown(queryClient2.clear);

    await tester.pumpWidget(MaterialApp(
      home: Column(children: [
        QueryClientProvider(
          client: queryClient1,
          observeAppLifecycle: false,
          child: _page(key1, 'test1'),
        ),
        QueryClientProvider(
          client: queryClient2,
          observeAppLifecycle: false,
          child: _page(key2, 'test2'),
        ),
      ]),
    ));

    await advance(tester, 11);
    expect(find.text('test1'), findsOneWidget);
    expect(find.text('test2'), findsOneWidget);

    expect(
      queryCache1.find(filters: QueryFilters(queryKey: key1))?.state.data,
      'test1',
    );
    expect(queryCache1.find(filters: QueryFilters(queryKey: key2)), isNull);
    expect(queryCache2.find(filters: QueryFilters(queryKey: key1)), isNull);
    expect(
      queryCache2.find(filters: QueryFilters(queryKey: key2))?.state.data,
      'test2',
    );

    // The second client's teardown, as `hookTest` does it for the first:
    // its gc timer must go before the test ends.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    queryClient2.clear();
  }, createClient: () => QueryClient(queryCache: queryCache52 = QueryCache()));

  // QueryClientProvider.test.tsx:108
  late QueryCache queryCache108;
  hookTest(
      "uses defaultOptions for queries when they don't provide their own "
      'config', (tester, client) async {
    final key = queryKey();

    final queryCache = queryCache108;

    await tester.pumpWidget(QueryClientProvider(
      client: client,
      observeAppLifecycle: false,
      child: MaterialApp(home: _page(key, 'test')),
    ));

    await advance(tester, 11);
    expect(find.text('test'), findsOneWidget);

    expect(
      queryCache.find(filters: QueryFilters(queryKey: key))?.options.gcTime,
      GcTime.never,
    );
  },
      createClient: () => QueryClient(
            queryCache: queryCache108 = QueryCache(),
            defaultOptions: const DefaultOptions(
              queries: QueryDefaults(gcTime: GcTime.never),
            ),
          ));

  group('useQueryClient', () {
    // QueryClientProvider.test.tsx:147 — upstream's message is React
    // Query's; this one is the binding's `QueryClientProvider.of`, which
    // `useQueryClient` is. Both say what is missing and what to do about it,
    // and the whole message is asserted (PORTING_NOTES).
    hookTest('should throw an error if no query client has been set',
        (tester, client) async {
      await tester.pumpWidget(MaterialApp(
        home: HookBuilder(builder: (context) {
          useQueryClient();
          return const SizedBox();
        }),
      ));

      expect(
        tester.takeException(),
        isA<FlutterError>().having(
          (error) => error.message,
          'message',
          'No QueryClientProvider found above this widget. Wrap your app '
              '(or the subtree that uses queries) in '
              'QueryClientProvider(client: …).',
        ),
      );
    });
  });
}
