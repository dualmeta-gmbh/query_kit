// Ported from query/packages/react-query/src/__tests__/useQueries.test.tsx
// at 50680b98c. Each case keeps upstream's name, and its upstream line is in
// the comment above it. What was adapted or omitted, and why, is in
// PORTING_NOTES.md.
//
// Upstream's `useQueries({ queries, combine })` is two hooks here (plan,
// D10): `useQueries` returns the results, and a `combine` is
// `useCombinedQueries`, whose `CombinedResult` stays pending until every
// source has data and whose combiner reruns only when a value or one of its
// `keys` changed.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_hooks/query_kit_hooks.dart';

import 'harness.dart';

/// Upstream's `render(<Page />)` for a page that passes its own client: no
/// provider above the hook.
Widget _render(Widget child) => MaterialApp(home: Scaffold(body: child));

/// What each result in [results] holds, in order — upstream's
/// `toMatchObject([{ data: … }, …])`.
List<T?> _data<T>(List<QueryResult<T>> results) =>
    [for (final result in results) result.dataOrNull];

void main() {
  // useQueries.test.tsx:25
  hookTest('should return the correct states', (tester, client) async {
    final key1 = queryKey();
    final key2 = queryKey();
    final results = <List<QueryResult<int>>>[];

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final result = useQueries([
          QueryObserverOptions<int>(
            queryKey: key1,
            queryFn: (_) => sleep(10).then((_) => 1),
          ),
          QueryObserverOptions<int>(
            queryKey: key2,
            queryFn: (_) => sleep(200).then((_) => 2),
          ),
        ]);
        results.add(result);

        return Text('data1: ${result[0].dataOrNull ?? 'null'}, '
            'data2: ${result[1].dataOrNull ?? 'null'}');
      }),
    );

    await advance(tester, 201);
    expect(find.text('data1: 1, data2: 2'), findsOneWidget);

    expect(results, hasLength(3));
    expect(_data(results[0]), [null, null]);
    expect(_data(results[1]), [1, null]);
    expect(_data(results[2]), [1, 2]);
  });

  // useQueries.test.tsx:94 — D8: `useQueries` takes no `buildWhen`, so
  // upstream's tracked properties have no stand-in and the refetch's
  // fetching state is a build of its own: 3 builds become 4, and upstream's
  // `results[2]` is `results[3]`.
  hookTest('should track results', (tester, client) async {
    final key1 = queryKey();
    final results = <List<QueryResult<int>>>[];
    var count = 0;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final result = useQueries([
          QueryObserverOptions<int>(
            queryKey: key1,
            queryFn: (_) => sleep(10).then((_) {
              count++;
              return count;
            }),
          ),
        ]);
        results.add(result);

        return Column(children: [
          Text('data: ${result[0].dataOrNull ?? 'null'}'),
          TextButton(
            onPressed: () => result[0].refetch(),
            child: const Text('refetch'),
          ),
        ]);
      }),
    );

    await advance(tester, 11);
    expect(find.text('data: 1'), findsOneWidget);

    expect(results, hasLength(2));
    expect(_data(results[0]), [null]);
    expect(_data(results[1]), [1]);

    await click(tester, 'refetch');

    await advance(tester, 11);
    expect(find.text('data: 2'), findsOneWidget);

    // Upstream: only one render for the data update, none for the
    // isFetching transition. Here the transition builds.
    expect(results, hasLength(4));
    expect(_data(results[2]), [1]);
    expect(results[2][0].isFetching, isTrue);

    expect(_data(results[3]), [2]);
  });

  // useQueries.test.tsx:309
  hookTest('should use provided custom queryClient', (tester, client) async {
    final key = queryKey();
    Future<String> queryFn(QueryFunctionContext _) async =>
        Future.value('custom client');

    await tester.pumpWidget(_render(HookBuilder(builder: (context) {
      final queries = useQueries(
        [QueryObserverOptions<String>(queryKey: key, queryFn: queryFn)],
        client: client,
      );

      return Text('data: ${queries[0].dataOrNull ?? ''}');
    })));

    await advance(tester, 0);
    expect(find.text('data: custom client'), findsOneWidget);
  });

  // useQueries.test.tsx:337 — D10: the `combine` is `useCombinedQueries`.
  // The assertion is unchanged.
  hookTest('should combine queries', (tester, client) async {
    final key1 = queryKey();
    final key2 = queryKey();

    await tester.pumpWidget(_render(HookBuilder(builder: (context) {
      final queries = useCombinedQueries(
        [
          QueryObserverOptions<String>(
            queryKey: key1,
            queryFn: (_) => Future.value('first result'),
          ),
          QueryObserverOptions<String>(
            queryKey: key2,
            queryFn: (_) => Future.value('second result'),
          ),
        ],
        (values) => (combined: true, res: values.join(',')),
        keys: const [],
        client: client,
      );
      final data = queries.dataOrNull;

      return Text('data: ${data?.combined} ${data?.res ?? ''}');
    })));

    await advance(tester, 0);
    expect(find.text('data: true first result,second result'), findsOneWidget);
  });

  // useQueries.test.tsx:381 — D10: the `combine` is `useCombinedQueries`,
  // and the effect is keyed on its `CombinedResult`, which compares by
  // value, where upstream's key is the shared object's identity. The
  // assertions are unchanged.
  hookTest('should not return new instances when called without queries',
      (tester, client) async {
    final key = queryKey();
    final ids = <int>[];
    var resultChanged = 0;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final count = useState(0);
        final result = useCombinedQueries(
          [
            for (final id in ids)
              QueryObserverOptions<Map<String, Object?>>(
                queryKey: QueryKey([key, id]),
                queryFn: (_) => Future.value({
                  'id': id,
                  'content': {'value': Random().nextDouble()},
                }),
              ),
          ],
          (_) => {'empty': 'object'},
          keys: const [],
        );

        useEffect(() {
          resultChanged++;
          return null;
        }, [result]);

        return Column(children: [
          Text('count: ${count.value}'),
          Text('data: ${jsonEncode(result.dataOrNull)}'),
          TextButton(
            onPressed: () => count.value++,
            child: const Text('inc'),
          ),
        ]);
      }),
    );

    await advance(tester, 0);
    expect(find.text('data: {"empty":"object"}'), findsOneWidget);
    expect(find.text('count: 0'), findsOneWidget);

    expect(resultChanged, 1);

    await click(tester, 'inc');

    await advance(tester, 0);
    expect(find.text('count: 1'), findsOneWidget);
    // there should be no further effect calls because the returned object is
    // structurally shared
    expect(resultChanged, 1);
  });

  // useQueries.test.tsx:434 — strengthened, not under D8/D10/D14: React's
  // `render` flushes a render loop before it returns, a Flutter rebuild
  // loop shows only in later frames. The count is asserted again after a
  // frame.
  hookTest('should not have infinite render loops with empty queries (#6645)',
      (tester, client) async {
    var renderCount = 0;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final result = useQueries(const <QueryObserverOptions<String>>[]);

        useEffect(() {
          renderCount++;
          return null;
        });

        return Text('data: ${jsonEncode(_data(result))}');
      }),
    );

    expect(renderCount, 1);

    await advance(tester, 0);
    expect(find.text('data: []'), findsOneWidget);
    expect(renderCount, 1);
  });

  // useQueries.test.tsx:454 — D10: the `combine` is `useCombinedQueries`,
  // and the combiner gets the values, `values[0]` and `values[1]` for
  // upstream's destructured results. The assertion is unchanged.
  hookTest('should only call combine with query results',
      (tester, client) async {
    final key1 = queryKey();
    final key2 = queryKey();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final result = useCombinedQueries(
          [
            QueryObserverOptions<String>(
              queryKey: key1,
              queryFn: (_) => sleep(5).then((_) => 'query1'),
            ),
            QueryObserverOptions<String>(
              queryKey: key2,
              queryFn: (_) => sleep(20).then((_) => 'query2'),
            ),
          ],
          (values) => {
            'data': {'query1': values[0], 'query2': values[1]},
          },
          keys: const [],
        );

        return Text('data: ${jsonEncode(result.dataOrNull)}');
      }),
    );

    await advance(tester, 21);
    expect(
      find.text('data: {"data":{"query1":"query1","query2":"query2"}}'),
      findsOneWidget,
    );
  });

  // useQueries.test.tsx:490 — D10, partially: `CombinedResult` is pending
  // until every source has data, so upstream's empty, partial and complete
  // first renders are a pending build and a complete one, and 3 builds
  // become 2. Upstream's tracked properties are a `buildWhen` on the data
  // (`CombinedResult` equality sees the fetch flags too). From there on
  // upstream's assertions hold: 4 builds after the first refetch, and no
  // build for a refetch that brings the same data.
  hookTest('should track property access through combine function',
      (tester, client) async {
    final key1 = queryKey();
    final key2 = queryKey();
    var count = 0;
    final results = <CombinedResult<({bool combined, String res})>>[];

    await tester.pumpWidget(_render(HookBuilder(builder: (context) {
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
        (values) => (combined: true, res: values.join(',')),
        keys: const [],
        buildWhen: (previous, current) =>
            previous.dataOrNull != current.dataOrNull,
        client: client,
      );

      results.add(queries);
      final data = queries.dataOrNull;

      return Column(children: [
        Text('data: ${data?.combined} ${data?.res ?? ''}'),
        TextButton(
          onPressed: queries.refetch,
          child: const Text('refetch'),
        ),
      ]);
    })));

    await advance(tester, 51);
    expect(
      find.text('data: true first result 0,second result 0'),
      findsOneWidget,
    );

    // Upstream: 3 (empty, partial, complete). Here: pending, complete.
    expect(results, hasLength(2));

    expect(results[0], isA<CombinedPending<({bool combined, String res})>>());

    expect(
      results[1].dataOrNull,
      (combined: true, res: 'first result 0,second result 0'),
    );

    count++;

    await click(tester, 'refetch');

    await advance(tester, 51);
    expect(
      find.text('data: true first result 1,second result 1'),
      findsOneWidget,
    );

    final length = results.length;

    expect([4, 5, 6], contains(results.length));

    expect(
      results.last.dataOrNull,
      (combined: true, res: 'first result 1,second result 1'),
    );

    await click(tester, 'refetch');

    await advance(tester, 100);
    // no further re-render because data didn't change
    expect(results, hasLength(length));
  });

  // useQueries.test.tsx:589 — D14, a raw `combine`: upstream's combine reads
  // `isLoading` of the raw results, which a `CombinedResult` does not
  // carry, so its body runs in the build over `useQueries`' results. The
  // assertions are unchanged.
  hookTest(
      'should synchronously track properties of all observer even if a '
      'property (isLoading) is only accessed on one observer (#7000)',
      (tester, client) async {
    final key = queryKey();
    final ids = [1, 2];

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final results = useQueries([
          for (final id in ids)
            QueryObserverOptions<({int id, String title})>(
              queryKey: QueryKey([key, id]),
              queryFn: (_) => sleep(10).then((_) {
                if (id == 2) {
                  throw StateError('FAILURE');
                }
                return (id: id, title: 'Post $id');
              }),
              retry: RetryPolicy.never,
            ),
        ]);
        // `.any` stops early, as upstream's `.some` does.
        final isLoading = results.any((result) => result.isLoading);

        return Text('Loading Status: ${isLoading ? 'Loading...' : 'Loaded'}');
      }),
    );

    expect(find.text('Loading Status: Loading...'), findsOneWidget);

    await advance(tester, 11);
    expect(find.text('Loading Status: Loaded'), findsOneWidget);
  });

  // useQueries.test.tsx:630 — D10: the combiner's capture is named in
  // `keys`, where upstream reruns an inline combine on every render. The
  // assertions are unchanged.
  hookTest('should not have stale closures with combine (#6648)',
      (tester, client) async {
    final key = queryKey();

    await tester.pumpWidget(_render(HookBuilder(builder: (context) {
      final countState = useState(0);
      final count = countState.value;
      final queries = useCombinedQueries(
        [
          QueryObserverOptions<String>(
            queryKey: key,
            queryFn: (_) => Future.value('result'),
          ),
        ],
        (values) => (count: count, res: values.join(',')),
        keys: [count],
        client: client,
      );
      final data = queries.dataOrNull;

      return Column(children: [
        Text('data: ${data?.count} ${data?.res ?? ''}'),
        TextButton(
          onPressed: () => countState.value++,
          child: const Text('inc'),
        ),
      ]);
    })));

    await advance(tester, 0);
    expect(find.text('data: 0 result'), findsOneWidget);

    await click(tester, 'inc');

    await advance(tester, 0);
    expect(find.text('data: 1 result'), findsOneWidget);
  });

  // useQueries.test.tsx:674 — D10: `React.useCallback(…, [])` is
  // `keys: const []`, and the combiner runs only once every source has data
  // and then only when a value changed. Upstream's call counts 3, 3, 4, 7
  // are 1, 1, 1, 3: no call for a pending source, none for an unchanged
  // refetch (upstream's invariant), none for a rerender, and one per source
  // that brings a new value.
  hookTest('should optimize combine if it is a stable reference',
      (tester, client) async {
    final key1 = queryKey();
    final key2 = queryKey();

    final spy = <({bool combined, String res})>[];
    var value = 0;

    await tester.pumpWidget(_render(HookBuilder(builder: (context) {
      final state = useState(0);
      final queries = useCombinedQueries(
        [
          QueryObserverOptions<String>(
            queryKey: key1,
            queryFn: (_) => sleep(10).then((_) => 'first result:$value'),
          ),
          QueryObserverOptions<String>(
            queryKey: key2,
            queryFn: (_) => sleep(20).then((_) => 'second result:$value'),
          ),
        ],
        (values) {
          final result = (combined: true, res: values.join(','));
          spy.add(result);
          return result;
        },
        keys: const [],
        client: client,
      );
      final data = queries.dataOrNull;

      return Column(children: [
        Text('data: ${data?.combined} ${data?.res ?? ''}'),
        TextButton(
          onPressed: () => state.value = state.value + 1,
          child: const Text('rerender'),
        ),
      ]);
    })));

    await advance(tester, 21);
    expect(
      find.text('data: true first result:0,second result:0'),
      findsOneWidget,
    );

    // Upstream: both pending, one pending, both resolved (3).
    expect(spy, hasLength(1));

    unawaited(client.refetchQueries());

    await advance(tester, 21);
    // no increase because result hasn't changed
    expect(spy, hasLength(1));

    await click(tester, 'rerender');

    // Upstream: one extra call due to recomputing the combined result on
    // rerender (4).
    expect(spy, hasLength(1));

    value = 1;

    unawaited(client.refetchQueries());

    await advance(tester, 21);
    expect(
      find.text('data: true first result:1,second result:1'),
      findsOneWidget,
    );

    // Upstream: both pending -> one pending -> both resolved (7). Here one
    // call per source that resolved with a new value.
    expect(spy, hasLength(3));
  });

  // useQueries.test.tsx:753 — D10: `React.useCallback(…, [state])` is
  // `keys: [state]`. Upstream's call counts 3, 4 are 1, 2: the combiner
  // runs once every source has data, and again when its key changes.
  hookTest('should re-run combine if the functional reference changes',
      (tester, client) async {
    final key1 = queryKey();
    final key2 = queryKey();

    final spy = <({bool combined, int state, String res})>[];

    await tester.pumpWidget(_render(HookBuilder(builder: (context) {
      final stateValue = useState(0);
      final state = stateValue.value;
      final queries = useCombinedQueries(
        [
          QueryObserverOptions<String>(
            queryKey: QueryKey([key1]),
            queryFn: (_) => sleep(10).then((_) => 'first result'),
          ),
          QueryObserverOptions<String>(
            queryKey: QueryKey([key2]),
            queryFn: (_) => sleep(20).then((_) => 'second result'),
          ),
        ],
        (values) {
          final result = (combined: true, state: state, res: values.join(','));
          spy.add(result);
          return result;
        },
        keys: [state],
        client: client,
      );
      final data = queries.dataOrNull;

      return Column(children: [
        Text('data: ${data?.state} ${data?.res ?? ''}'),
        TextButton(
          onPressed: () => stateValue.value = state + 1,
          child: const Text('rerender'),
        ),
      ]);
    })));

    await advance(tester, 21);
    expect(
      find.text('data: 0 first result,second result'),
      findsOneWidget,
    );

    // Upstream: both pending, one pending, both resolved (3).
    expect(spy, hasLength(1));

    await click(tester, 'rerender');

    // state changed, re-run combine (upstream: 4)
    expect(spy, hasLength(2));
  });

  // useQueries.test.tsx:871 — D10: upstream's combiner returns 'pending'
  // while any source is; `CombinedResult` is `CombinedPending` then, and the
  // combiner runs once every source has data. The assertions are unchanged.
  hookTest('should re-render once combine returns a different reference',
      (tester, client) async {
    final key1 = queryKey();
    final key2 = queryKey();
    final key3 = queryKey();

    var renders = 0;

    await tester.pumpWidget(_render(HookBuilder(builder: (context) {
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
        (_) => 'foo',
        keys: const [],
        client: client,
      );

      renders++;

      return Text('data: ${data.dataOrNull ?? 'pending'}');
    })));

    await advance(tester, 0);
    expect(find.text('data: pending'), findsOneWidget);
    await advance(tester, 21);
    expect(find.text('data: foo'), findsOneWidget);

    // one with pending, one with foo
    expect(renders, 2);
  });

  // useQueries.test.tsx:926 — D10: upstream's combiner returns 'pending'
  // while any source is, `CombinedPending` here. The assertions are
  // unchanged.
  hookTest('should track properties correctly with combine',
      (tester, client) async {
    final key1 = queryKey();
    final key2 = queryKey();
    final key3 = queryKey();

    await tester.pumpWidget(_render(HookBuilder(builder: (context) {
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
        (values) => values.join(', '),
        keys: const [],
        client: client,
      );

      return Column(children: [
        Text('data: ${data.dataOrNull ?? 'pending'}'),
        TextButton(
          onPressed: () {
            client.setQueryData<String>(
                QueryKey([key1]), 'first result updated');
          },
          child: const Text('update'),
        ),
      ]);
    })));

    await advance(tester, 0);
    expect(find.text('data: pending'), findsOneWidget);
    await advance(tester, 21);
    expect(
      find.text('data: first result, second result, third result'),
      findsOneWidget,
    );

    await click(tester, 'update');

    await advance(tester, 21);
    expect(
      find.text('data: first result updated, second result, third result'),
      findsOneWidget,
    );
  });

  // useQueries.test.tsx:993 — D10: `React.useCallback(…, [])` is
  // `keys: const []`, and the combiner runs only once every source has
  // data. Upstream's call counts 3, 3, 3 are 1, 1, 1; the invariant, no
  // call for an unrelated rebuild, is upstream's.
  hookTest('should not re-run stable combine on unrelated re-render',
      (tester, client) async {
    final key1 = queryKey();
    final key2 = queryKey();

    final spy = <({bool combined, String res})>[];

    await tester.pumpWidget(_render(HookBuilder(builder: (context) {
      final unrelatedState = useState(0);

      final queries = useCombinedQueries(
        [
          QueryObserverOptions<String>(
            queryKey: key1,
            queryFn: (_) => sleep(10).then((_) => 'first result'),
          ),
          QueryObserverOptions<String>(
            queryKey: key2,
            queryFn: (_) => sleep(20).then((_) => 'second result'),
          ),
        ],
        (values) {
          final result = (combined: true, res: values.join(','));
          spy.add(result);
          return result;
        },
        keys: const [],
        client: client,
      );
      final data = queries.dataOrNull;

      return Column(children: [
        Text('data: ${data?.combined} ${data?.res ?? ''}'),
        Text('unrelated: ${unrelatedState.value}'),
        TextButton(
          onPressed: () => unrelatedState.value++,
          child: const Text('increment'),
        ),
      ]);
    })));

    await advance(tester, 21);
    expect(
      find.text('data: true first result,second result'),
      findsOneWidget,
    );

    // Upstream: initial renders: both pending, one pending, both resolved
    // (3).
    expect(spy, hasLength(1));

    await click(tester, 'increment');

    await advance(tester, 0);

    expect(find.text('unrelated: 1'), findsOneWidget);

    // combine should NOT re-run for unrelated re-render with stable reference
    expect(spy, hasLength(1));

    await click(tester, 'increment');

    await advance(tester, 0);

    expect(find.text('unrelated: 2'), findsOneWidget);

    // still no extra calls to combine
    expect(spy, hasLength(1));
  });

  // useQueries.test.tsx:1070
  hookTest('should not cause infinite re-renders when removing last query',
      (tester, client) async {
    var renderCount = 0;
    final key1 = queryKey();
    final key2 = queryKey();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final queries = useState([
          QueryObserverOptions<String>(
            queryKey: key1,
            queryFn: (_) => 'data1',
          ),
          QueryObserverOptions<String>(
            queryKey: key2,
            queryFn: (_) => 'data2',
          ),
        ]);
        renderCount++;

        final result = useQueries(queries.value);

        return Column(children: [
          Text('renders: $renderCount'),
          Text('queries: ${result.length}'),
          TextButton(
            onPressed: () {
              queries.value = [
                QueryObserverOptions<String>(
                  queryKey: key1,
                  queryFn: (_) => 'data1',
                ),
              ];
            },
            child: const Text('remove last'),
          ),
          TextButton(
            onPressed: () {
              queries.value = [
                QueryObserverOptions<String>(
                  queryKey: key2,
                  queryFn: (_) => 'data2',
                ),
              ];
            },
            child: const Text('remove first'),
          ),
        ]);
      }),
    );

    await advance(tester, 0);
    renderCount = 0;

    await click(tester, 'remove last');
    await advance(tester, 100);

    expect(renderCount, lessThan(10));
    expect(find.text('queries: 1'), findsOneWidget);

    renderCount = 0;

    await click(tester, 'remove first');
    await advance(tester, 100);

    expect(renderCount, lessThan(10));
    expect(find.text('queries: 1'), findsOneWidget);
  });

  // useQueries.test.tsx:1142 — the identity `combine` is plain `useQueries`
  // (plan, D10). The length is asserted on every build, as upstream does.
  hookTest(
      'should return correct results when queries count changes with stable '
      'combine reference', (tester, client) async {
    final key = queryKey();

    final results = <({int n, int length})>[];

    await tester.pumpWidget(_render(HookBuilder(builder: (context) {
      final n = useState(0);

      final queries = useQueries(
        [
          for (var i = 0; i < n.value; i++)
            QueryObserverOptions<int>(
              queryKey: QueryKey([...key.parts, i]),
              queryFn: (_) => i,
            ),
        ],
        client: client,
      );

      results.add((n: n.value, length: queries.length));

      return Column(children: [
        Text('n: ${n.value}'),
        Text('length: ${queries.length}'),
        TextButton(
          onPressed: () => n.value++,
          child: const Text('Increase'),
        ),
      ]);
    })));

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
}
