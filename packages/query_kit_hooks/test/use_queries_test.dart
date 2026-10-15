// Ported from query/packages/react-query/src/__tests__/useQueries.test.tsx
// at 50680b98c. Spike selection (AP0 of docs/plans/hooks-package.md).
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_hooks/query_kit_hooks.dart';

import 'harness.dart';

void main() {
  // useQueries.test.tsx:871 — upstream's raw combiner returns 'pending'
  // while any source is; `CombinedResult` is `CombinedPending` then, and the
  // combiner runs once every source has data (#82).
  hookTest('should re-render once combine returns a different reference',
      (tester, client) async {
    final key1 = queryKey();
    final key2 = queryKey();
    final key3 = queryKey();
    var renders = 0;

    await tester.pumpApp(
      client,
      HookProbe((context) {
        final data = useCombinedQueries(
          [
            QueryObserverOptions<String>(
              queryKey: QueryKey([key1]),
              queryFn: (_) => sleep(10).then((_) => 'first result'),
            ),
            QueryObserverOptions<String>(
              queryKey: QueryKey([key2]),
              queryFn: (_) => sleep(15).then((_) => 'second result'),
            ),
            QueryObserverOptions<String>(
              queryKey: QueryKey([key3]),
              queryFn: (_) => sleep(20).then((_) => 'third result'),
            ),
          ],
          (results) => 'foo',
          keys: const [],
        );
        renders++;
        return Text('data: ${data.dataOrNull ?? 'pending'}');
      }),
    );

    await advance(tester, 0);
    expect(find.text('data: pending'), findsOneWidget);
    await advance(tester, 21);
    expect(find.text('data: foo'), findsOneWidget);

    // one with pending, one with foo
    expect(renders, 2);
  });

  // useQueries.test.tsx:1142 — the identity combiner over raw results is
  // plain `useQueries` here (review H-05): the length is asserted on every
  // build, as upstream does.
  hookTest(
      'should return correct results when queries count changes with stable '
      'combine reference', (tester, client) async {
    final key = queryKey();
    final results = <({int n, int length})>[];

    await tester.pumpApp(
      client,
      HookProbe((context) {
        final n = useState(0);
        final queries = useQueries([
          for (var i = 0; i < n.value; i++)
            QueryObserverOptions<int>(
              queryKey: QueryKey([...key.parts, i]),
              queryFn: (_) => i,
            ),
        ]);
        results.add((n: n.value, length: queries.length));
        return Column(children: [
          Text('n: ${n.value}'),
          Text('length: ${queries.length}'),
          TextButton(
            onPressed: () => n.value++,
            child: const Text('Increase'),
          ),
        ]);
      }),
    );

    expect(find.text('n: 0'), findsOneWidget);
    expect(find.text('length: 0'), findsOneWidget);

    await click(tester, 'Increase');
    await advance(tester, 0);

    expect(find.text('n: 1'), findsOneWidget);
    expect(find.text('length: 1'), findsOneWidget);

    await click(tester, 'Increase');
    await advance(tester, 0);

    expect(find.text('n: 2'), findsOneWidget);
    expect(find.text('length: 2'), findsOneWidget);

    for (final result in results) {
      expect(result.length, result.n);
    }
  });

  // useQueries.test.tsx:490 — partially portable (review H-05). Upstream's
  // first three renders show the empty, the partial and the complete
  // combination; `CombinedResult` is pending until every source has data,
  // so there is no partial state to assert. What ports is the invariant at
  // the end: a refetch that brings the same data does not rebuild, with a
  // `buildWhen` on the data standing in for upstream's tracked properties.
  hookTest('should track property access through combine function',
      (tester, client) async {
    final key1 = queryKey();
    final key2 = queryKey();
    var count = 0;
    final results = <CombinedResult<String>>[];

    await tester.pumpApp(
      client,
      HookProbe((context) {
        final queries = useCombinedQueries(
          [
            QueryObserverOptions<String>(
              queryKey: key1,
              queryFn: (_) => sleep(5).then((_) => 'first result $count'),
            ),
            QueryObserverOptions<String>(
              queryKey: key2,
              queryFn: (_) => sleep(50).then((_) => 'second result $count'),
            ),
          ],
          (values) => values.join(','),
          keys: const [],
          buildWhen: (previous, current) =>
              previous.dataOrNull != current.dataOrNull,
        );
        results.add(queries);
        return Column(children: [
          Text('data: ${queries.dataOrNull ?? ''}'),
          TextButton(
            onPressed: queries.refetch,
            child: const Text('refetch'),
          ),
        ]);
      }),
    );

    await advance(tester, 51);
    expect(find.text('data: first result 0,second result 0'), findsOneWidget);
    // Upstream: 3 (empty, partial, complete). Here: pending, complete.
    expect(results, hasLength(2));

    count++;

    await click(tester, 'refetch');
    await advance(tester, 51);
    expect(find.text('data: first result 1,second result 1'), findsOneWidget);

    final length = results.length;
    expect(results.last.dataOrNull, 'first result 1,second result 1');

    await click(tester, 'refetch');
    await advance(tester, 100);
    // no further re-render because data didn't change
    expect(results, hasLength(length));
  });
}
