// Ported from query/packages/react-query/src/__tests__/useIsFetching.test.tsx
// at 50680b98c. Each case keeps upstream's name, and its upstream line is in
// the comment above it. What was adapted or omitted, and why, is in
// PORTING_NOTES.md.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_hooks/query_kit_hooks.dart';

import 'harness.dart';

void main() {
  // See https://github.com/tannerlinsley/react-query/issues/105
  // useIsFetching.test.tsx:18
  hookTest('should update as queries start and stop fetching',
      (tester, client) async {
    final key = queryKey();

    final isFetching = HookBuilder(builder: (context) {
      final isFetching = useIsFetching();

      return Text('isFetching: $isFetching');
    });

    final query = HookBuilder(builder: (context) {
      final ready = useState(false);

      useQuery(QueryObserverOptions<String>(
        queryKey: key,
        queryFn: (_) => sleep(50).then((_) => 'test'),
        enabled: ready.value ? Enabled.yes : Enabled.no,
      ));

      return TextButton(
        onPressed: () => ready.value = true,
        child: const Text('setReady'),
      );
    });

    await tester.pumpApp(client, Column(children: [isFetching, query]));

    expect(find.text('isFetching: 0'), findsOneWidget);

    await click(tester, 'setReady');
    await advance(tester, 0);
    expect(find.text('isFetching: 1'), findsOneWidget);
    await advance(tester, 51);
    expect(find.text('isFetching: 0'), findsOneWidget);
  });

  // useIsFetching.test.tsx:60
  hookTest('should not update state while rendering', (tester, client) async {
    final key1 = queryKey();
    final key2 = queryKey();
    final isFetchingArray = <int>[];

    // Functions, not instances: React re-renders a child element created
    // anew in the parent's render, and Flutter does so for a new widget.
    Widget isFetching() => HookBuilder(builder: (context) {
          isFetchingArray.add(useIsFetching());
          return const SizedBox();
        });
    Widget firstQuery() => HookBuilder(builder: (context) {
          useQuery(QueryObserverOptions<String>(
            queryKey: key1,
            queryFn: (_) => sleep(100).then((_) => 'data1'),
          ));
          return const SizedBox();
        });
    Widget secondQuery() => HookBuilder(builder: (context) {
          useQuery(QueryObserverOptions<String>(
            queryKey: key2,
            queryFn: (_) => sleep(100).then((_) => 'data2'),
          ));
          return const SizedBox();
        });

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final renderSecond = useState(false);
        useEffect(() {
          final timer = Timer(
            const Duration(milliseconds: 50),
            () => renderSecond.value = true,
          );
          return timer.cancel;
        }, const []);
        return Column(children: [
          isFetching(),
          firstQuery(),
          if (renderSecond.value) secondQuery(),
        ]);
      }),
    );

    expect(isFetchingArray[0], 0);
    await advance(tester, 0);
    expect(isFetchingArray[1], 1);
    await advance(tester, 50);
    expect(isFetchingArray[2], 1);
    await advance(tester, 1);
    expect(isFetchingArray[3], 2);
    await advance(tester, 50);
    expect(isFetchingArray[4], 1);
    await advance(tester, 50);
    expect(isFetchingArray[5], 0);

    expect(isFetchingArray, [0, 1, 1, 2, 1, 0]);
  });

  // useIsFetching.test.tsx:129
  hookTest('should be able to filter', (tester, client) async {
    final key1 = queryKey();
    final key2 = queryKey();
    final isFetchingArray = <int>[];

    Widget one() => HookBuilder(builder: (context) {
          useQuery(QueryObserverOptions<String>(
            queryKey: key1,
            queryFn: (_) => sleep(10).then((_) => 'test1'),
          ));
          return const SizedBox();
        });
    Widget two() => HookBuilder(builder: (context) {
          useQuery(QueryObserverOptions<String>(
            queryKey: key2,
            queryFn: (_) => sleep(20).then((_) => 'test2'),
          ));
          return const SizedBox();
        });

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final started = useState(false);
        final isFetching = useIsFetching(filters: QueryFilters(queryKey: key1));

        isFetchingArray.add(isFetching);

        return Column(children: [
          TextButton(
            onPressed: () => started.value = true,
            child: const Text('setStarted'),
          ),
          Text('isFetching: $isFetching'),
          if (started.value) ...[one(), two()],
        ]);
      }),
    );

    expect(find.text('isFetching: 0'), findsOneWidget);

    await click(tester, 'setStarted');
    await advance(tester, 0);
    expect(find.text('isFetching: 1'), findsOneWidget);
    await advance(tester, 11);
    expect(find.text('isFetching: 0'), findsOneWidget);

    // at no point should we have isFetching: 2
    expect(isFetchingArray, isNot(contains(2)));

    await advance(tester, 10); // key2's fetch
  });

  // useIsFetching.test.tsx:188
  hookTest('should show the correct fetching state when mounted after a query',
      (tester, client) async {
    final key = queryKey();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) => sleep(10).then((_) => 'test'),
        ));

        final isFetching = useIsFetching();

        return Column(children: [Text('isFetching: $isFetching')]);
      }),
    );

    expect(find.text('isFetching: 1'), findsOneWidget);
    await advance(tester, 11);
    expect(find.text('isFetching: 0'), findsOneWidget);
  });

  // useIsFetching.test.tsx:214
  var onSuccess = 0;
  hookTest('should use provided custom queryClient', (tester, client) async {
    final key = queryKey();

    // No provider: upstream's `render(<Page />)`.
    await tester.pumpWidget(MaterialApp(
      home: HookBuilder(builder: (context) {
        useQuery(
          QueryObserverOptions<String>(
            queryKey: key,
            queryFn: (_) => sleep(10).then((_) => 'test'),
          ),
          client: client,
        );

        final isFetching =
            useIsFetching(filters: const QueryFilters(), client: client);

        return Column(children: [Text('isFetching: $isFetching')]);
      }),
    ));

    expect(find.text('isFetching: 1'), findsOneWidget);
    await advance(tester, 11);
    expect(find.text('isFetching: 0'), findsOneWidget);
    expect(onSuccess, 1);
  },
      createClient: () => QueryClient(
            queryCache: QueryCache(onSuccess: (_, __) => onSuccess++),
          ));
}
