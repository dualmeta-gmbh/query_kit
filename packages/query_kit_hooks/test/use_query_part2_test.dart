// Ported from query/packages/react-query/src/__tests__/useQuery.test.tsx at
// 50680b98c, lines 3601–7096. Each case keeps upstream's name, and its
// upstream line is in the comment above it. What was adapted or
// omitted, and why, is in PORTING_NOTES.md.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_hooks/query_kit_hooks.dart';

import 'harness.dart';

typedef _Todo = ({String name, String priority});

/// `failureReason?.message` for the `StateError`s these cases throw.
String _message(Object? error) => (error as StateError?)?.message ?? 'null';

void main() {
  // useQuery.test.tsx:3601
  hookTest('should not refetch if not stale after a prefetch',
      (tester, client) async {
    final key = queryKey();
    var queryFnCalls = 0;
    var prefetchQueryFnCalls = 0;

    client
        .query(QueryOptions<String>(
          queryKey: key,
          queryFn: (_) {
            prefetchQueryFnCalls++;
            return sleep(10).then((_) => 'not yet...');
          },
          staleTime: const StaleTime.duration(Duration(seconds: 1)),
        ))
        .ignore();

    await advance(tester, 0);

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) {
            queryFnCalls++;
            return 'data';
          },
          staleTime: const StaleTime.duration(Duration(seconds: 1)),
        ));
        return const SizedBox();
      }),
    );

    await advance(tester, 0);

    expect(prefetchQueryFnCalls, 1);
    expect(queryFnCalls, 0);

    // The prefetch's sleep is still running.
    await advance(tester, 10);
  });

  // useQuery.test.tsx:3635
  hookTest('should reset failureCount on successful fetch',
      (tester, client) async {
    final key = queryKey();
    var counter = 0;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final query = useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) {
            if (counter < 2) {
              counter++;
              return Future<String>.error(StateError('error'));
            } else {
              return Future.value('data');
            }
          },
          retryDelay: const RetryDelay.fixed(Duration(milliseconds: 10)),
        ));

        return Column(children: [
          Text('failureCount ${query.failureCount}'),
          Text('failureReason ${_message(query.failureReason)}'),
        ]);
      }),
    );

    await advance(tester, 11);
    expect(find.text('failureCount 2'), findsOneWidget);
    expect(find.text('failureReason error'), findsOneWidget);
    await advance(tester, 11);
    expect(find.text('failureCount 0'), findsOneWidget);
    expect(find.text('failureReason null'), findsOneWidget);
  });

  // useQuery.test.tsx:3673 — the prefetch writes a String and the hook's
  // queryFn an int under one key, so both read the typed cache as `Object`.
  hookTest('should use prefetched data for dependent query',
      (tester, client) async {
    final key = queryKey();
    var count = 0;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final enabled = useState(false);
        final isPrefetched = useState(false);

        final query = useQuery(QueryObserverOptions<Object>(
          queryKey: key,
          queryFn: (_) async {
            count++;
            await sleep(10);
            return count;
          },
          enabled: enabled.value ? Enabled.yes : Enabled.no,
        ));

        useEffect(() {
          Future<void> prefetch() async {
            await client
                .query(QueryOptions<Object>(
                  queryKey: key,
                  queryFn: (_) => Future<Object>.value('prefetched data'),
                ))
                .then<void>((_) {}, onError: (Object _) {});
            isPrefetched.value = true;
          }

          prefetch().ignore();
          return null;
        }, const []);

        return Column(children: [
          if (isPrefetched.value) const Text('isPrefetched'),
          TextButton(
            onPressed: () => enabled.value = true,
            child: const Text('setKey'),
          ),
          Text('data: ${query.dataOrNull}'),
        ]);
      }),
    );

    await advance(tester, 0);
    expect(find.text('isPrefetched'), findsOneWidget);
    await click(tester, 'setKey');
    expect(find.text('data: prefetched data'), findsOneWidget);
    await advance(tester, 11);
    expect(find.text('data: 1'), findsOneWidget);
    expect(count, 1);
  });

  // useQuery.test.tsx:3726
  hookTest('should support dependent queries via the enable config option',
      (tester, client) async {
    final key = queryKey();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final shouldFetch = useState(false);

        final query = useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) => sleep(10).then((_) => 'data'),
          enabled: shouldFetch.value ? Enabled.yes : Enabled.no,
        ));

        return Column(children: [
          Text('FetchStatus: ${query.fetchStatus.name}'),
          Text('Data: ${query.dataOrNull ?? 'no data'}'),
          if (!shouldFetch.value)
            TextButton(
              onPressed: () => shouldFetch.value = true,
              child: const Text('fetch'),
            ),
        ]);
      }),
    );

    expect(find.text('FetchStatus: idle'), findsOneWidget);
    expect(find.text('Data: no data'), findsOneWidget);

    await click(tester, 'fetch');

    await advance(tester, 0);
    expect(find.text('FetchStatus: fetching'), findsOneWidget);
    await advance(tester, 11);
    expect(find.text('FetchStatus: idle'), findsOneWidget);
    expect(find.text('Data: data'), findsOneWidget);
  });

  // useQuery.test.tsx:3763
  hookTest('should mark query as fetching, when using initialData',
      (tester, client) async {
    final key = queryKey();
    final results = <QueryResult<String>>[];

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final result = useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) => sleep(10).then((_) => 'serverData'),
          initialData: const InitialData.value('initialData'),
        ));
        results.add(result);
        return Text('data: ${result.dataOrNull}');
      }),
    );

    expect(find.text('data: initialData'), findsOneWidget);
    await advance(tester, 11);
    expect(find.text('data: serverData'), findsOneWidget);

    expect(results, hasLength(2));
    expect(results[0].dataOrNull, 'initialData');
    expect(results[0].isFetching, isTrue);
    expect(results[1].dataOrNull, 'serverData');
    expect(results[1].isFetching, isFalse);
  });

  // useQuery.test.tsx:3788
  hookTest('should initialize state properly, when initialData is falsy',
      (tester, client) async {
    final key = queryKey();
    final rec = Recorder<QueryResult<int>>();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        rec.build(useQuery(
          QueryObserverOptions<int>(
            queryKey: key,
            queryFn: (_) => 1,
            initialData: const InitialData.value(0),
          ),
          buildWhen: rec.buildWhen,
        ));
        return const SizedBox();
      }),
    );

    await advance(tester, 0);

    expect(rec.builds, hasLength(2));
    expect(rec.builds[0].dataOrNull, 0);
    expect(rec.builds[0].isFetching, isTrue);
    expect(rec.builds[1].dataOrNull, 1);
    expect(rec.builds[1].isFetching, isFalse);
  });

  // useQuery.test.tsx:3811
  hookTest(
      'should show the correct data when switching keys with initialData, '
      'placeholderData & staleTime', (tester, client) async {
    final key = queryKey();

    const allTodos = <_Todo>[
      (name: 'todo A', priority: 'high'),
      (name: 'todo B', priority: 'medium'),
    ];

    const initialTodos = allTodos;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final filterState = useState('');
        final filter = filterState.value;

        final todos = useQuery(QueryObserverOptions<List<_Todo>>(
          queryKey: QueryKey([...key.parts, filter]),
          queryFn: (_) => Future.value(allTodos
              .where((todo) => filter.isEmpty || todo.priority == filter)
              .toList()),
          initialData:
              InitialData.compute(() => filter == '' ? initialTodos : null),
          placeholderData: const PlaceholderData.keepPrevious(),
          staleTime: const StaleTime.duration(Duration(seconds: 5)),
        )).dataOrNull;

        return Column(children: [
          Text('Current Todos, filter: ${filter.isEmpty ? 'all' : filter}'),
          TextButton(
            onPressed: () => filterState.value = '',
            child: const Text('All'),
          ),
          TextButton(
            onPressed: () => filterState.value = 'high',
            child: const Text('High'),
          ),
          for (final todo in todos ?? const <_Todo>[])
            Text('${todo.name} - ${todo.priority}'),
        ]);
      }),
    );

    expect(find.text('Current Todos, filter: all'), findsOneWidget);

    await click(tester, 'High');
    await advance(tester, 0);
    expect(find.text('Current Todos, filter: high'), findsOneWidget);
    await click(tester, 'All');
    await advance(tester, 0);
    expect(find.text('todo B - medium'), findsOneWidget);
  });

  // useQuery.test.tsx:3871
  hookTest('data should persist when enabled is changed to false',
      (tester, client) async {
    final key = queryKey();
    final results = <QueryResult<String>>[];

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final shouldFetch = useState(true);
        final result = useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) => 'fetched data',
          enabled: shouldFetch.value ? Enabled.yes : Enabled.no,
          initialData: InitialData.value(
              shouldFetch.value ? 'initial' : 'initial falsy'),
        ));
        results.add(result);
        return Column(children: [
          Text(result.dataOrNull ?? ''),
          Text(shouldFetch.value ? 'enabled' : 'disabled'),
          TextButton(
            onPressed: () => shouldFetch.value = false,
            child: const Text('enable'),
          ),
        ]);
      }),
    );

    await advance(tester, 0);
    expect(find.text('fetched data'), findsOneWidget);
    expect(find.text('enabled'), findsOneWidget);

    await click(tester, 'enable');

    await advance(tester, 0);
    expect(find.text('fetched data'), findsOneWidget);
    expect(find.text('disabled'), findsOneWidget);

    expect(results, hasLength(3));
    expect(results[0].dataOrNull, 'initial');
    expect(results[0].isStale, isTrue);
    expect(results[1].dataOrNull, 'fetched data');
    expect(results[1].isStale, isTrue);
    // disabled observers are not stale
    expect(results[2].dataOrNull, 'fetched data');
    expect(results[2].isStale, isFalse);
  });

  // useQuery.test.tsx:3921
  hookTest('should support enabled:false in query object syntax',
      (tester, client) async {
    final key = queryKey();
    var queryFnCalls = 0;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final fetchStatus = useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) {
            queryFnCalls++;
            return 'data';
          },
          enabled: Enabled.no,
        )).fetchStatus;
        return Text('fetchStatus: ${fetchStatus.name}');
      }),
    );

    expect(queryFnCalls, 0);
    expect(
      client.queryCache.find(filters: QueryFilters(queryKey: key)),
      isNotNull,
    );
    expect(find.text('fetchStatus: idle'), findsOneWidget);
  });

  // useQuery.test.tsx:3943
  hookTest(
      'should init to status:pending, fetchStatus:idle when enabled is false',
      (tester, client) async {
    final key = queryKey();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final query = useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) => 'data',
          enabled: Enabled.no,
        ));

        return Text('status: ${query.status.name}, ${query.fetchStatus.name}');
      }),
    );

    await advance(tester, 0);
    expect(find.text('status: pending, idle'), findsOneWidget);
  });

  // useQuery.test.tsx:3968
  hookTest(
      'should not schedule garbage collection, if gcTimeout is set to '
      '`Infinity`', (tester, client) async {
    final key = queryKey();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final query = useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) => 'fetched data',
          gcTime: GcTime.never,
        ));
        return Text(query.dataOrNull ?? '');
      }),
    );

    await advance(tester, 0);
    expect(find.text('fetched data'), findsOneWidget);

    final timers =
        await timersCreatedBy(() => tester.pumpWidget(const SizedBox()));

    expect(timers, isEmpty);
  });

  // useQuery.test.tsx:3991
  hookTest(
      'should schedule garbage collection, if gcTimeout is not set to '
      'infinity', (tester, client) async {
    final key = queryKey();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final query = useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) => 'fetched data',
          gcTime: const GcTime.duration(Duration(minutes: 10)), // 10 Minutes
        ));
        return Text(query.dataOrNull ?? '');
      }),
    );

    await advance(tester, 0);
    expect(find.text('fetched data'), findsOneWidget);

    final timers =
        await timersCreatedBy(() => tester.pumpWidget(const SizedBox()));

    expect(timers, isNotEmpty);
    expect(timers.last, const Duration(minutes: 10));
  });

  // useQuery.test.tsx:4018
  hookTest('should not cause memo churn when data does not change',
      (tester, client) async {
    final key = queryKey();
    var queryFnCalls = 0;
    var memoFnCalls = 0;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final result = useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) => sleep(10).then((_) {
            queryFnCalls++;
            return 'data';
          }),
        ));

        useMemoized(() {
          memoFnCalls++;
          return result.dataOrNull;
        }, [result.dataOrNull]);

        return Column(children: [
          Text('status ${result.status.name}'),
          Text('isFetching ${result.isFetching ? 'true' : 'false'}'),
          TextButton(
            onPressed: result.refetch,
            child: const Text('refetch'),
          ),
        ]);
      }),
    );

    await advance(tester, 0);
    expect(find.text('status pending'), findsOneWidget);
    await advance(tester, 11);
    expect(find.text('status success'), findsOneWidget);
    await click(tester, 'refetch');
    await advance(tester, 0);
    expect(find.text('isFetching true'), findsOneWidget);
    await advance(tester, 11);
    expect(find.text('isFetching false'), findsOneWidget);
    expect(queryFnCalls, 2);
    expect(memoFnCalls, 2);
  });

  // useQuery.test.tsx:4068
  hookTest('should update data upon interval changes', (tester, client) async {
    final key = queryKey();
    var count = 0;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final interval = useState(200);
        final data = useQuery(QueryObserverOptions<int>(
          queryKey: key,
          queryFn: (_) => count++,
          refetchInterval:
              RefetchInterval.every(Duration(milliseconds: interval.value)),
        )).dataOrNull;

        useEffect(() {
          if (data == 2) {
            afterFrame(() => interval.value = 0);
          }
          return null;
        }, [data]);

        return Text('count: $data');
      }),
    );

    // mount
    await advance(tester, 0);
    expect(find.text('count: 0'), findsOneWidget);
    await advance(tester, 201);
    expect(find.text('count: 1'), findsOneWidget);
    await advance(tester, 201);
    expect(find.text('count: 2'), findsOneWidget);
  });

  // useQuery.test.tsx:4100
  hookTest('should refetch in an interval depending on function result',
      (tester, client) async {
    final key = queryKey();
    var count = 0;
    final states = <QueryResult<int>>[];

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final queryInfo = useQuery(QueryObserverOptions<int>(
          queryKey: key,
          queryFn: (_) => sleep(10).then((_) => count++),
          refetchInterval: RefetchInterval.dynamic((query) =>
              ((query.state.data as int?) ?? 0) < 2
                  ? const Duration(milliseconds: 10)
                  : null),
        ));
        states.add(queryInfo);
        return Text('count: ${queryInfo.dataOrNull}');
      }),
    );

    await advance(tester, 51);
    expect(find.text('count: 2'), findsOneWidget);

    expect(states, hasLength(6));
    final expected = <(QueryStatus, bool, int?)>[
      (QueryStatus.pending, true, null),
      (QueryStatus.success, false, 0),
      (QueryStatus.success, true, 0),
      (QueryStatus.success, false, 1),
      (QueryStatus.success, true, 1),
      (QueryStatus.success, false, 2),
    ];
    for (var i = 0; i < expected.length; i++) {
      expect(
        (states[i].status, states[i].isFetching, states[i].dataOrNull),
        expected[i],
        reason: 'states[$i]',
      );
    }
  });

  // useQuery.test.tsx:4165
  hookTest('should not interval fetch with a refetchInterval of 0',
      (tester, client) async {
    final key = queryKey();
    var queryFnCalls = 0;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final queryInfo = useQuery(QueryObserverOptions<int>(
          queryKey: key,
          queryFn: (_) {
            queryFnCalls++;
            return 1;
          },
          refetchInterval: const RefetchInterval.every(Duration.zero),
        ));

        return Text('count: ${queryInfo.dataOrNull}');
      }),
    );

    await advance(tester, 0);
    expect(find.text('count: 1'), findsOneWidget);

    // extra sleep to make sure we're not re-fetching
    await advance(tester, 10);

    expect(queryFnCalls, 1);
  });

  // useQuery.test.tsx:4189 — upstream's `getByText('')` matches any element
  // with no text of its own, so it holds whatever renders; this asserts the
  // text the key's JSON renders instead.
  hookTest('should accept an empty string as query key',
      (tester, client) async {
    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final result = useQuery(QueryObserverOptions<QueryKey>(
          queryKey: QueryKey(['']),
          queryFn: (ctx) => ctx.queryKey,
        ));
        return Text(jsonEncode(result.dataOrNull?.parts));
      }),
    );

    await advance(tester, 0);
    expect(find.text('[""]'), findsOneWidget);
  });

  // useQuery.test.tsx:4204
  hookTest('should accept an object as query key', (tester, client) async {
    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final result = useQuery(QueryObserverOptions<QueryKey>(
          queryKey: QueryKey([
            {'a': 'a'},
          ]),
          queryFn: (ctx) => ctx.queryKey,
        ));
        return Text(jsonEncode(result.dataOrNull?.parts));
      }),
    );

    await advance(tester, 0);
    expect(find.text('[{"a":"a"}]'), findsOneWidget);
  });

  // useQuery.test.tsx:4219
  hookTest('should refetch if any query instance becomes enabled',
      (tester, client) async {
    final key = queryKey();
    var queryFnCalls = 0;

    String queryFn(QueryFunctionContext _) {
      queryFnCalls++;
      return 'data';
    }

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final enabled = useState(false);
        final result = useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: queryFn,
          enabled: enabled.value ? Enabled.yes : Enabled.no,
        ));
        return Column(children: [
          // Upstream's `Disabled`.
          HookBuilder(builder: (context) {
            useQuery(QueryObserverOptions<String>(
              queryKey: key,
              queryFn: queryFn,
              enabled: Enabled.no,
            ));
            return const SizedBox();
          }),
          Text(result.dataOrNull ?? ''),
          TextButton(
            onPressed: () => enabled.value = true,
            child: const Text('enable'),
          ),
        ]);
      }),
    );

    expect(queryFnCalls, 0);
    await click(tester, 'enable');
    await advance(tester, 0);
    expect(find.text('data'), findsOneWidget);
    expect(queryFnCalls, 1);
  });

  // useQuery.test.tsx:4251
  hookTest('should use placeholder data while the query loads',
      (tester, client) async {
    final key1 = queryKey();
    final rec = Recorder<QueryResult<String>>();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final state = rec.build(useQuery(
          QueryObserverOptions<String>(
            queryKey: key1,
            queryFn: (_) => 'data',
            placeholderData: const PlaceholderData.value('placeholder'),
          ),
          buildWhen: rec.buildWhen,
        ));

        return Column(children: [
          Text('Data: ${state.dataOrNull}'),
          Text('Status: ${state.status.name}'),
        ]);
      }),
    );
    await advance(tester, 0);
    expect(find.text('Data: data'), findsOneWidget);

    expect(rec.builds, hasLength(2));
    expect(rec.builds[0].isSuccess, isTrue);
    expect(rec.builds[0].isPlaceholderData, isTrue);
    expect(rec.builds[0].dataOrNull, 'placeholder');
    expect(rec.builds[1].isSuccess, isTrue);
    expect(rec.builds[1].isPlaceholderData, isFalse);
    expect(rec.builds[1].dataOrNull, 'data');
  });

  // useQuery.test.tsx:4291 — D8: `setCount(1)` lands after the first frame
  // and the fetch's result before the next one, so upstream's second and
  // third renders are one build here. Its second render is `setCount`'s, not
  // a delivery, so `delivered` holds the observer's one change: the data.
  hookTest('should use placeholder data even for disabled queries',
      (tester, client) async {
    final key1 = queryKey();
    final rec = Recorder<QueryResult<String>>();
    final counts = <int>[];

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final count = useState(0);

        final state = rec.build(useQuery(
          QueryObserverOptions<String>(
            queryKey: key1,
            queryFn: (_) => 'data',
            placeholderData: const PlaceholderData.value('placeholder'),
            enabled: count.value == 0 ? Enabled.yes : Enabled.no,
          ),
          buildWhen: rec.buildWhen,
        ));
        counts.add(count.value);

        useEffect(() {
          afterFrame(() => count.value = 1);
          return null;
        }, const []);

        return Column(children: [
          Text('Data: ${state.dataOrNull}'),
          Text('Status: ${state.status.name}'),
        ]);
      }),
    );
    await advance(tester, 0);
    expect(find.text('Data: data'), findsOneWidget);

    expect(rec.builds, hasLength(2));
    expect(rec.builds[0].isSuccess, isTrue);
    expect(rec.builds[0].isPlaceholderData, isTrue);
    expect(rec.builds[0].dataOrNull, 'placeholder');
    expect(counts[0], 0);
    // Upstream's states[1] (placeholder, count 1) merged into this build.
    expect(rec.builds[1].isSuccess, isTrue);
    expect(rec.builds[1].isPlaceholderData, isFalse);
    expect(rec.builds[1].dataOrNull, 'data');
    expect(counts[1], 1);

    expect(rec.delivered, hasLength(1));
    expect(rec.delivered[0].isSuccess, isTrue);
    expect(rec.delivered[0].isPlaceholderData, isFalse);
    expect(rec.delivered[0].dataOrNull, 'data');
  });

  // useQuery.test.tsx:4352
  hookTest('placeholder data should run through select',
      (tester, client) async {
    final key1 = queryKey();
    final rec = Recorder<QueryResult<String>>();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final state = rec.build(useSelectQuery(
          QuerySelectOptions<int, String>(
            queryKey: key1,
            queryFn: (_) => 1,
            placeholderData: const PlaceholderData.value(23),
            select: (data) => '${data * 2}',
          ),
          buildWhen: rec.buildWhen,
        ));

        return Column(children: [
          Text('Data: ${state.dataOrNull}'),
          Text('Status: ${state.status.name}'),
        ]);
      }),
    );
    await advance(tester, 0);
    expect(find.text('Data: 2'), findsOneWidget);

    expect(rec.builds, hasLength(2));
    expect(rec.builds[0].isSuccess, isTrue);
    expect(rec.builds[0].isPlaceholderData, isTrue);
    expect(rec.builds[0].dataOrNull, '46');
    expect(rec.builds[1].isSuccess, isTrue);
    expect(rec.builds[1].isPlaceholderData, isFalse);
    expect(rec.builds[1].dataOrNull, '2');
  });

  // useQuery.test.tsx:4393
  hookTest('placeholder data function result should run through select',
      (tester, client) async {
    final key1 = queryKey();
    final rec = Recorder<QueryResult<String>>();
    var placeholderFunctionRunCount = 0;

    Widget page() => HookBuilder(builder: (context) {
          final state = rec.build(useSelectQuery(
            QuerySelectOptions<int, String>(
              queryKey: key1,
              queryFn: (_) => 1,
              placeholderData: PlaceholderData.compute((_, __) {
                placeholderFunctionRunCount++;
                return 23;
              }),
              select: (data) => '${data * 2}',
            ),
            buildWhen: rec.buildWhen,
          ));

          return Column(children: [
            Text('Data: ${state.dataOrNull}'),
            Text('Status: ${state.status.name}'),
          ]);
        });

    await tester.pumpApp(client, page());
    await advance(tester, 0);
    expect(find.text('Data: 2'), findsOneWidget);

    // rendered.rerender(<Page />)
    await tester.pumpApp(client, page());

    expect(rec.builds, hasLength(3));
    expect(rec.builds[0].isSuccess, isTrue);
    expect(rec.builds[0].isPlaceholderData, isTrue);
    expect(rec.builds[0].dataOrNull, '46');
    expect(rec.builds[1].isSuccess, isTrue);
    expect(rec.builds[1].isPlaceholderData, isFalse);
    expect(rec.builds[1].dataOrNull, '2');
    expect(rec.builds[2].isSuccess, isTrue);
    expect(rec.builds[2].isPlaceholderData, isFalse);
    expect(rec.builds[2].dataOrNull, '2');

    expect(placeholderFunctionRunCount, 1);
  });

  // useQuery.test.tsx:4447
  hookTest('select should only run when dependencies change if memoized',
      (tester, client) async {
    final key1 = queryKey();
    var selectRun = 0;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final count = useState(2);
        final select = useCallback<String Function(int)>((data) {
          selectRun++;
          return 'selected ${data + count.value}';
        }, [count.value]);
        final state = useSelectQuery(QuerySelectOptions<int, String>(
          queryKey: key1,
          queryFn: (_) => sleep(10).then((_) => 0),
          select: select,
          placeholderData: const PlaceholderData.value(99),
        ));
        return Column(children: [
          Text('Data: ${state.dataOrNull}'),
          TextButton(
            onPressed: () => count.value++,
            child: Text('inc: ${count.value}'),
          ),
        ]);
      }),
    );
    expect(find.text('Data: selected 101'), findsOneWidget); // 99 + 2
    expect(selectRun, 1);

    await advance(tester, 11);
    expect(find.text('Data: selected 2'), findsOneWidget); // 0 + 2
    expect(selectRun, 2);

    await click(tester, 'inc: 2');

    await advance(tester, 11);
    expect(find.text('Data: selected 3'), findsOneWidget); // 0 + 3
    expect(selectRun, 3);
  });

  // useQuery.test.tsx:4491
  hookTest('select should always return the correct state',
      (tester, client) async {
    final key1 = queryKey();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final countState = useState(2);
        final forceValue = useState(1);
        final count = countState.value;

        final state = useSelectQuery(QuerySelectOptions<int, String>(
          queryKey: key1,
          queryFn: (_) => sleep(10).then((_) => 0),
          select: useCallback<String Function(int)>(
            (data) => 'selected ${data + count}',
            [count],
          ),
          placeholderData: const PlaceholderData.value(99),
        ));

        return Column(children: [
          Text('Data: ${state.dataOrNull}'),
          Text('forceValue: ${forceValue.value}'),
          TextButton(
            onPressed: () => countState.value++,
            child: Text('inc: $count'),
          ),
          TextButton(
            onPressed: () => forceValue.value++,
            child: const Text('forceUpdate'),
          ),
        ]);
      }),
    );

    expect(find.text('Data: selected 101'), findsOneWidget); // 99 + 2

    await advance(tester, 11);
    expect(find.text('Data: selected 2'), findsOneWidget); // 0 + 2

    await click(tester, 'inc: 2');

    await advance(tester, 11);
    expect(find.text('Data: selected 3'), findsOneWidget); // 0 + 3

    await click(tester, 'forceUpdate');

    expect(find.text('forceValue: 2'), findsOneWidget);
    // data should still be 3 after an independent re-render
    await advance(tester, 11);
    expect(find.text('Data: selected 3'), findsOneWidget);
  });

  // useQuery.test.tsx:4541
  hookTest('select should structurally share data', (tester, client) async {
    final key1 = queryKey();
    final states = <List<int>>[];

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final forceValue = useState(1);

        final state = useSelectQuery(QuerySelectOptions<List<int>, List<int>>(
          queryKey: key1,
          queryFn: (_) => sleep(10).then((_) => [1, 2]),
          select: (res) => res.map((x) => x + 1).toList(),
        ));

        useEffect(() {
          final data = state.dataOrNull;
          if (data != null) {
            states.add(data);
          }
          return null;
        }, [state.dataOrNull]);

        return Column(children: [
          Text('Data: ${jsonEncode(state.dataOrNull)}'),
          Text('forceValue: ${forceValue.value}'),
          TextButton(
            onPressed: () => forceValue.value++,
            child: const Text('forceUpdate'),
          ),
        ]);
      }),
    );

    await advance(tester, 11);
    expect(find.text('Data: [2,3]'), findsOneWidget);
    expect(states, hasLength(1));

    await click(tester, 'forceUpdate');

    await advance(tester, 11);
    expect(find.text('forceValue: 2'), findsOneWidget);
    expect(find.text('Data: [2,3]'), findsOneWidget);

    // effect should not be triggered again due to structural sharing
    expect(states, hasLength(1));
  });

  // useQuery.test.tsx:4586
  hookTest(
      'should cancel the query function when there are no more subscriptions',
      (tester, client) async {
    final key = queryKey();
    var cancelFnCalls = 0;

    Future<String> queryFn(QueryFunctionContext context) {
      final promise = Completer<String>();
      context.signal.onCancel(() {
        cancelFnCalls++;
        if (!promise.isCompleted) {
          promise.completeError('Cancelled');
        }
      });
      sleep(20).then((_) {
        if (!promise.isCompleted) {
          promise.complete('OK');
        }
      });
      return promise.future;
    }

    await tester.pumpApp(
      client,
      Blink(
        duration: 5,
        child: HookBuilder(builder: (context) {
          final state = useQuery(QueryObserverOptions<String>(
            queryKey: key,
            queryFn: queryFn,
          ));
          return Text('Status: ${state.status.name}');
        }),
      ),
    );

    await advance(tester, 6);
    expect(find.text('off'), findsOneWidget);

    expect(cancelFnCalls, greaterThan(0));

    // The query function's sleep is still running.
    await advance(tester, 14);
  });

  // useQuery.test.tsx:4622
  hookTest(
      'should cancel the query if the signal was consumed and there are no '
      'more subscriptions', (tester, client) async {
    final key = queryKey();
    final states = <int, QueryResult<String>>{};

    Future<String> queryFn(QueryFunctionContext context) async {
      final limit = context.queryKey.parts[1]! as int;
      final String value;
      if (limit.isOdd) {
        context.signal; // consumed
        value = 'abort';
      } else {
        value = 'data $limit';
      }
      await sleep(25);
      return value;
    }

    Widget page(int limit) => HookBuilder(builder: (context) {
          final state = useQuery(QueryObserverOptions<String>(
            queryKey: QueryKey([key, limit]),
            queryFn: queryFn,
          ));
          states[limit] = state;
          return Column(children: [
            Text('Status: ${state.status.name}'),
            Text('data: ${state.dataOrNull}'),
          ]);
        });

    await tester.pumpApp(
      client,
      Blink(
        duration: 5,
        child: Column(children: [page(0), page(1), page(2), page(3)]),
      ),
    );

    await advance(tester, 6);
    expect(find.text('off'), findsOneWidget);
    await advance(tester, 20);

    expect(states, hasLength(4));

    QueryState<Object?> stateOf(int limit) => client.queryCache
        .find(filters: QueryFilters(queryKey: QueryKey([key, limit])))!
        .state;

    expect(stateOf(0).data, 'data 0');
    expect(stateOf(0).status, QueryStatus.success);
    expect(stateOf(0).dataUpdateCount, 1);

    expect(stateOf(1).data, isNull);
    expect(stateOf(1).status, QueryStatus.pending);
    expect(stateOf(1).fetchStatus, FetchStatus.idle);

    expect(stateOf(2).data, 'data 2');
    expect(stateOf(2).status, QueryStatus.success);
    expect(stateOf(2).dataUpdateCount, 1);

    expect(stateOf(3).data, isNull);
    expect(stateOf(3).status, QueryStatus.pending);
    expect(stateOf(3).fetchStatus, FetchStatus.idle);
  });

  // useQuery.test.tsx:4688
  hookTest('should refetch when quickly switching to a failed query',
      (tester, client) async {
    final key = queryKey();
    final rec = Recorder<QueryResult<String>>();

    Future<String> queryFn(QueryFunctionContext _) =>
        sleep(50).then((_) => 'OK');

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final id = useState(1);
        final hasChanged = useState(false);

        rec.build(useQuery(
          QueryObserverOptions<String>(
            queryKey: QueryKey([key, id.value]),
            queryFn: queryFn,
          ),
          buildWhen: rec.buildWhen,
        ));

        useEffect(() {
          afterFrame(() {
            id.value = id.value == 1 ? 2 : 1;
            hasChanged.value = true;
          });
          return null;
        }, [hasChanged.value]);

        return const SizedBox();
      }),
    );

    await advance(tester, 51);
    expect(rec.builds, hasLength(4));
    // Load query 1
    expect(rec.builds[0].status, QueryStatus.pending);
    expect(rec.builds[0].errorOrNull, isNull);
    // Load query 2
    expect(rec.builds[1].status, QueryStatus.pending);
    expect(rec.builds[1].errorOrNull, isNull);
    // Load query 1
    expect(rec.builds[2].status, QueryStatus.pending);
    expect(rec.builds[2].errorOrNull, isNull);
    // Loaded query 1
    expect(rec.builds[3].status, QueryStatus.success);
    expect(rec.builds[3].errorOrNull, isNull);

    // Query 2's fetch is still running.
    await advance(tester, 10);
  });

  // useQuery.test.tsx:4736
  hookTest('should update query state and refetch when reset with resetQueries',
      (tester, client) async {
    final key = queryKey();
    final rec = Recorder<QueryResult<int>>();
    var count = 0;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final state = rec.build(useQuery(
          QueryObserverOptions<int>(
            queryKey: key,
            queryFn: (_) => sleep(10).then((_) {
              count++;
              return count;
            }),
            staleTime: StaleTime.infinite,
          ),
          buildWhen: rec.buildWhen,
        ));

        return Column(children: [
          TextButton(
            onPressed: () =>
                client.resetQueries(filters: QueryFilters(queryKey: key)),
            child: const Text('reset'),
          ),
          Text('data: ${state.dataOrNull ?? 'null'}'),
          Text('isFetching: ${state.isFetching}'),
        ]);
      }),
    );

    await advance(tester, 11);
    expect(find.text('data: 1'), findsOneWidget);
    await click(tester, 'reset');

    await advance(tester, 11);
    expect(rec.builds, hasLength(4));
    expect(find.text('data: 2'), findsOneWidget);

    expect(count, 2);

    final expected = <(int?, bool, bool, bool, bool)>[
      (null, true, true, false, true),
      (1, false, false, true, false),
      (null, true, true, false, true),
      (2, false, false, true, false),
    ];
    for (var i = 0; i < expected.length; i++) {
      final state = rec.builds[i];
      expect(
        (
          state.dataOrNull,
          state.isPending,
          state.isFetching,
          state.isSuccess,
          state.isStale,
        ),
        expected[i],
        reason: 'states[$i]',
      );
    }
  });

  // useQuery.test.tsx:4807
  hookTest(
      'should update query state and not refetch when resetting a disabled '
      'query with resetQueries', (tester, client) async {
    final key = queryKey();
    final rec = Recorder<QueryResult<int>>();
    var count = 0;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final state = rec.build(useQuery(
          QueryObserverOptions<int>(
            queryKey: key,
            queryFn: (_) => sleep(10).then((_) {
              count++;
              return count;
            }),
            staleTime: StaleTime.infinite,
            enabled: Enabled.no,
          ),
          buildWhen: rec.buildWhen,
        ));

        final refetch = state.refetch;

        return Column(children: [
          TextButton(
            onPressed: refetch,
            child: const Text('refetch'),
          ),
          TextButton(
            onPressed: () =>
                client.resetQueries(filters: QueryFilters(queryKey: key)),
            child: const Text('reset'),
          ),
          Text('data: ${state.dataOrNull ?? 'null'}'),
        ]);
      }),
    );

    expect(find.text('data: null'), findsOneWidget);
    await click(tester, 'refetch');

    await advance(tester, 11);
    expect(find.text('data: 1'), findsOneWidget);
    await click(tester, 'reset');

    await advance(tester, 0);
    expect(find.text('data: null'), findsOneWidget);
    expect(rec.builds, hasLength(4));

    expect(count, 1);

    final expected = <(int?, bool, bool, bool, bool)>[
      (null, true, false, false, false),
      (null, true, true, false, false),
      (1, false, false, true, false),
      (null, true, false, false, false),
    ];
    for (var i = 0; i < expected.length; i++) {
      final state = rec.builds[i];
      expect(
        (
          state.dataOrNull,
          state.isPending,
          state.isFetching,
          state.isSuccess,
          state.isStale,
        ),
        expected[i],
        reason: 'states[$i]',
      );
    }
  });

  // useQuery.test.tsx:4912 — no `queryKeyHashFn`: keys compare by `==`, so
  // the entry is read back with an equal key built anew.
  hookTest(
      'should hash query keys that contain bigints given a supported query '
      'hash function', (tester, client) async {
    final first = queryKey();
    final key = QueryKey([first, BigInt.one]);

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) => 'test',
        ));
        return const SizedBox();
      }),
    );

    await advance(tester, 0);

    final query = client.queryCache.find(
      filters: QueryFilters(queryKey: QueryKey([first, BigInt.from(1)])),
    );
    expect(query?.state.data, 'test');
  });

  // useQuery.test.tsx:4935
  hookTest('should refetch when changed enabled to true in error state',
      (tester, client) async {
    final key = queryKey();
    var queryFnCalls = 0;

    Future<String> queryFn(QueryFunctionContext _) {
      queryFnCalls++;
      return sleep(10)
          .then<String>((_) => throw StateError('Suspense Error Bingo'));
    }

    Widget page(bool enabled) => HookBuilder(builder: (context) {
          final result = useQuery(QueryObserverOptions<String>(
            queryKey: key,
            queryFn: queryFn,
            enabled: enabled ? Enabled.yes : Enabled.no,
            retry: RetryPolicy.never,
            retryOnMount: false,
            refetchOnMount: RefetchOn.never,
            refetchOnWindowFocus: RefetchOn.never,
          ));

          if (result.isPending) {
            return const Text('status: pending');
          }
          if (result.errorOrNull is StateError) {
            return const Text('error');
          }
          return const Text('rendered');
        });

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final enabled = useState(true);
        return Column(children: [
          page(enabled.value),
          TextButton(
            onPressed: () => enabled.value = !enabled.value,
            child: const Text('retry'),
          ),
        ]);
      }),
    );

    // initial state check
    expect(find.text('status: pending'), findsOneWidget);

    // render error state component
    await advance(tester, 11);
    expect(find.text('error'), findsOneWidget);
    expect(queryFnCalls, 1);

    // change to enabled to false
    await click(tester, 'retry');
    await advance(tester, 11);
    expect(find.text('error'), findsOneWidget);
    expect(queryFnCalls, 1);

    // change to enabled to true
    await click(tester, 'retry');
    expect(queryFnCalls, 2);

    // The refetch's sleep is still running.
    await advance(tester, 11);
  });

  // useQuery.test.tsx:4996
  hookTest(
      'should refetch when query key changed when previous status is error',
      (tester, client) async {
    Widget page(int id) => HookBuilder(builder: (context) {
          final result = useQuery(QueryObserverOptions<String>(
            queryKey: QueryKey([id]),
            queryFn: (_) => sleep(10).then((_) {
              if (id.isOdd) {
                throw StateError('Error');
              } else {
                return 'data';
              }
            }),
            retry: RetryPolicy.never,
            retryOnMount: false,
            refetchOnMount: RefetchOn.never,
            refetchOnWindowFocus: RefetchOn.never,
          ));

          if (result.isPending) {
            return const Text('status: pending');
          }
          if (result.errorOrNull is StateError) {
            return const Text('error');
          }
          return const Text('rendered');
        });

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final id = useState(1);
        return Column(children: [
          page(id.value),
          TextButton(
            onPressed: () => id.value++,
            child: const Text('change'),
          ),
        ]);
      }),
    );

    // initial state check
    expect(find.text('status: pending'), findsOneWidget);

    // render error state component
    await advance(tester, 11);
    expect(find.text('error'), findsOneWidget);

    // change to unmount query
    await click(tester, 'change');
    await advance(tester, 11);
    expect(find.text('rendered'), findsOneWidget);

    // change to mount new query
    await click(tester, 'change');
    await advance(tester, 11);
    expect(find.text('error'), findsOneWidget);
  });

  // useQuery.test.tsx:5056
  hookTest(
      'should refetch when query key changed when switching between '
      'erroneous queries', (tester, client) async {
    Widget page(bool id) => HookBuilder(builder: (context) {
          final result = useQuery(QueryObserverOptions<String>(
            queryKey: QueryKey([id]),
            queryFn: (_) =>
                sleep(10).then<String>((_) => throw StateError('Error')),
            retry: RetryPolicy.never,
            retryOnMount: false,
            refetchOnMount: RefetchOn.never,
            refetchOnWindowFocus: RefetchOn.never,
          ));
          if (result.isFetching) {
            return const Text('status: fetching');
          }
          if (result.errorOrNull is StateError) {
            return const Text('error');
          }
          return const Text('rendered');
        });

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final value = useState(true);
        return Column(children: [
          page(value.value),
          TextButton(
            onPressed: () => value.value = !value.value,
            child: const Text('change'),
          ),
        ]);
      }),
    );

    // initial state check
    expect(find.text('status: fetching'), findsOneWidget);

    // render error state component
    await advance(tester, 11);
    expect(find.text('error'), findsOneWidget);

    // change to mount second query
    await click(tester, 'change');
    expect(find.text('status: fetching'), findsOneWidget);
    await advance(tester, 11);
    expect(find.text('error'), findsOneWidget);

    // change to mount first query again
    await click(tester, 'change');
    expect(find.text('status: fetching'), findsOneWidget);
    await advance(tester, 11);
    expect(find.text('error'), findsOneWidget);
  });

  // useQuery.test.tsx:5112
  hookTest(
      'should have no error in pending state when refetching after error '
      'occurred', (tester, client) async {
    final key = queryKey();
    final rec = Recorder<QueryResult<int>>();
    final error = StateError('oops');

    var count = 0;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final state = rec.build(useQuery(
          QueryObserverOptions<int>(
            queryKey: key,
            queryFn: (_) => sleep(10).then((_) {
              if (count == 0) {
                count++;
                throw error;
              }
              return 5;
            }),
            retry: RetryPolicy.never,
          ),
          buildWhen: rec.buildWhen,
        ));

        if (state.isPending) {
          return const Text('status: pending');
        }
        if (state.errorOrNull is StateError) {
          return Column(children: [
            const Text('error'),
            TextButton(
              onPressed: state.refetch,
              child: const Text('refetch'),
            ),
          ]);
        }
        return Text('data: ${state.dataOrNull}');
      }),
    );

    await advance(tester, 11);
    expect(find.text('error'), findsOneWidget);

    await click(tester, 'refetch');
    await advance(tester, 11);
    expect(find.text('data: 5'), findsOneWidget);

    expect(rec.builds, hasLength(4));

    expect(rec.builds[0].status, QueryStatus.pending);
    expect(rec.builds[0].dataOrNull, isNull);
    expect(rec.builds[0].errorOrNull, isNull);

    expect(rec.builds[1].status, QueryStatus.error);
    expect(rec.builds[1].dataOrNull, isNull);
    expect(rec.builds[1].errorOrNull, same(error));

    expect(rec.builds[2].status, QueryStatus.pending);
    expect(rec.builds[2].dataOrNull, isNull);
    expect(rec.builds[2].errorOrNull, isNull);

    expect(rec.builds[3].status, QueryStatus.success);
    expect(rec.builds[3].dataOrNull, 5);
    expect(rec.builds[3].errorOrNull, isNull);
  });

  group('networkMode online', () {
    // useQuery.test.tsx:5186
    hookTest('online queries should not start fetching if you are offline',
        (tester, client) async {
      client.onlineManager.setOnline(false);

      final key = queryKey();
      final states = <FetchStatus>[];

      await tester.pumpApp(
        client,
        HookBuilder(builder: (context) {
          final state = useQuery(QueryObserverOptions<String>(
            queryKey: key,
            queryFn: (_) => sleep(10).then((_) => 'data'),
          ));

          useEffect(() {
            states.add(state.fetchStatus);
            return null;
          });

          return Column(children: [
            Text('status: ${state.status.name}, isPaused: ${state.isPaused}'),
            Text('data: ${state.dataOrNull}'),
          ]);
        }),
      );

      expect(find.text('status: pending, isPaused: true'), findsOneWidget);

      client.onlineManager.setOnline(true);

      await advance(tester, 11);
      expect(find.text('status: success, isPaused: false'), findsOneWidget);
      expect(find.text('data: data'), findsOneWidget);

      expect(states, [
        FetchStatus.paused,
        FetchStatus.fetching,
        FetchStatus.idle,
      ]);
    });

    // useQuery.test.tsx:5227
    hookTest('online queries should not refetch if you are offline',
        (tester, client) async {
      final key = queryKey();
      var count = 0;

      await tester.pumpApp(
        client,
        HookBuilder(builder: (context) {
          final state = useQuery(QueryObserverOptions<String>(
            queryKey: key,
            queryFn: (_) async {
              count++;
              await sleep(10);
              return 'data$count';
            },
          ));

          return Column(children: [
            Text('status: ${state.status.name}, '
                'fetchStatus: ${state.fetchStatus.name}, '
                'failureCount: ${state.failureCount}'),
            Text('failureReason: ${state.failureReason ?? 'null'}'),
            Text('data: ${state.dataOrNull}'),
            TextButton(
              onPressed: () => client.invalidateQueries(
                  filters: QueryFilters(queryKey: key)),
              child: const Text('invalidate'),
            ),
          ]);
        }),
      );

      await advance(tester, 11);
      expect(find.text('data: data1'), findsOneWidget);

      client.onlineManager.setOnline(false);

      await click(tester, 'invalidate');

      await advance(tester, 11);
      expect(
        find.text('status: success, fetchStatus: paused, failureCount: 0'),
        findsOneWidget,
      );
      expect(find.text('failureReason: null'), findsOneWidget);

      client.onlineManager.setOnline(true);

      await advance(tester, 0);
      expect(
        find.text('status: success, fetchStatus: fetching, failureCount: 0'),
        findsOneWidget,
      );
      expect(find.text('failureReason: null'), findsOneWidget);
      await advance(tester, 11);
      expect(
        find.text('status: success, fetchStatus: idle, failureCount: 0'),
        findsOneWidget,
      );
      expect(find.text('failureReason: null'), findsOneWidget);

      expect(find.text('data: data2'), findsOneWidget);
    });

    // useQuery.test.tsx:5290
    hookTest('online queries should not refetch if you are offline and refocus',
        (tester, client) async {
      final key = queryKey();
      var count = 0;

      await tester.pumpApp(
        client,
        HookBuilder(builder: (context) {
          final state = useQuery(QueryObserverOptions<String>(
            queryKey: key,
            queryFn: (_) async {
              count++;
              await sleep(10);
              return 'data$count';
            },
          ));

          return Column(children: [
            Text('status: ${state.status.name}, '
                'fetchStatus: ${state.fetchStatus.name}'),
            Text('data: ${state.dataOrNull}'),
            TextButton(
              onPressed: () => client.invalidateQueries(
                  filters: QueryFilters(queryKey: key)),
              child: const Text('invalidate'),
            ),
          ]);
        }),
      );

      await advance(tester, 11);
      expect(find.text('data: data1'), findsOneWidget);

      client.onlineManager.setOnline(false);
      await click(tester, 'invalidate');

      await advance(tester, 0);
      expect(find.text('status: success, fetchStatus: paused'), findsOneWidget);

      client.focusManager.onFocus();

      await advance(tester, 11);
      expect(find.text('data: data2'), findsNothing);
      expect(count, 1);
    });

    // useQuery.test.tsx:5338
    hookTest('online queries should not refetch while already paused',
        (tester, client) async {
      final key = queryKey();
      var count = 0;

      client.onlineManager.setOnline(false);

      await tester.pumpApp(
        client,
        HookBuilder(builder: (context) {
          final state = useQuery(QueryObserverOptions<String>(
            queryKey: key,
            queryFn: (_) async {
              count++;
              await sleep(10);
              return 'data$count';
            },
          ));

          return Column(children: [
            Text('status: ${state.status.name}, '
                'fetchStatus: ${state.fetchStatus.name}'),
            Text('data: ${state.dataOrNull}'),
            TextButton(
              onPressed: () => client.invalidateQueries(
                  filters: QueryFilters(queryKey: key)),
              child: const Text('invalidate'),
            ),
          ]);
        }),
      );

      await advance(tester, 0);
      expect(find.text('status: pending, fetchStatus: paused'), findsOneWidget);

      await click(tester, 'invalidate');

      await advance(tester, 11);
      // invalidation should not trigger a refetch
      expect(find.text('status: pending, fetchStatus: paused'), findsOneWidget);

      expect(count, 0);
    });

    // useQuery.test.tsx:5384
    hookTest(
        'online queries should not refetch while already paused if data is in '
        'the cache', (tester, client) async {
      final key = queryKey();
      var count = 0;

      client.onlineManager.setOnline(false);

      await tester.pumpApp(
        client,
        HookBuilder(builder: (context) {
          final state = useQuery(QueryObserverOptions<String>(
            queryKey: key,
            queryFn: (_) async {
              count++;
              await sleep(10);
              return 'data$count';
            },
            initialData: const InitialData.value('initial'),
          ));

          return Column(children: [
            Text('status: ${state.status.name}, '
                'fetchStatus: ${state.fetchStatus.name}'),
            Text('data: ${state.dataOrNull}'),
            TextButton(
              onPressed: () => client.invalidateQueries(
                  filters: QueryFilters(queryKey: key)),
              child: const Text('invalidate'),
            ),
          ]);
        }),
      );

      expect(find.text('status: success, fetchStatus: paused'), findsOneWidget);
      expect(find.text('data: initial'), findsOneWidget);

      await click(tester, 'invalidate');

      await advance(tester, 11);

      // invalidation should not trigger a refetch
      expect(find.text('status: success, fetchStatus: paused'), findsOneWidget);

      expect(count, 0);
    });

    // useQuery.test.tsx:5432
    hookTest(
        'online queries should not get stuck in fetching state when pausing '
        'multiple times', (tester, client) async {
      final key = queryKey();
      var count = 0;

      client.onlineManager.setOnline(false);

      await tester.pumpApp(
        client,
        HookBuilder(builder: (context) {
          final state = useQuery(QueryObserverOptions<String>(
            queryKey: key,
            queryFn: (_) async {
              count++;
              await sleep(10);
              return 'data$count';
            },
            initialData: const InitialData.value('initial'),
          ));

          return Column(children: [
            Text('status: ${state.status.name}, '
                'fetchStatus: ${state.fetchStatus.name}'),
            Text('data: ${state.dataOrNull}'),
            TextButton(
              onPressed: () => client.invalidateQueries(
                  filters: QueryFilters(queryKey: key)),
              child: const Text('invalidate'),
            ),
          ]);
        }),
      );

      expect(find.text('status: success, fetchStatus: paused'), findsOneWidget);
      expect(find.text('data: initial'), findsOneWidget);

      // triggers one pause
      await click(tester, 'invalidate');

      await advance(tester, 11);
      expect(find.text('status: success, fetchStatus: paused'), findsOneWidget);

      // triggers a second pause
      client.focusManager.onFocus();

      client.onlineManager.setOnline(true);

      await advance(tester, 11);
      expect(find.text('status: success, fetchStatus: idle'), findsOneWidget);
      expect(find.text('data: data1'), findsOneWidget);

      expect(count, 1);
    });

    // useQuery.test.tsx:5492
    hookTest('online queries should pause retries if you are offline',
        (tester, client) async {
      final key = queryKey();
      var count = 0;

      await tester.pumpApp(
        client,
        HookBuilder(builder: (context) {
          final state = useQuery(QueryObserverOptions<String>(
            queryKey: key,
            queryFn: (_) async {
              count++;
              await sleep(10);
              throw StateError('failed$count');
            },
            retry: const RetryPolicy.times(2),
            retryDelay: const RetryDelay.fixed(Duration(milliseconds: 10)),
          ));

          return Column(children: [
            Text('status: ${state.status.name}, '
                'fetchStatus: ${state.fetchStatus.name}, '
                'failureCount: ${state.failureCount}'),
            Text('failureReason: ${_message(state.failureReason)}'),
          ]);
        }),
      );

      expect(
        find.textContaining('status: pending, fetchStatus: fetching'),
        findsOneWidget,
      );

      client.onlineManager.setOnline(false);

      await advance(tester, 31);

      expect(
        find.text('status: pending, fetchStatus: paused, failureCount: 1'),
        findsOneWidget,
      );
      expect(find.text('failureReason: failed1'), findsOneWidget);

      expect(count, 1);

      client.onlineManager.setOnline(true);

      await advance(tester, 31);
      expect(
        find.text('status: error, fetchStatus: idle, failureCount: 3'),
        findsOneWidget,
      );
      expect(find.text('failureReason: failed3'), findsOneWidget);

      expect(count, 3);
    });

    // useQuery.test.tsx:5546
    hookTest(
        'online queries should not fetch if paused initial load and we go '
        'online after unmount', (tester, client) async {
      final key = queryKey();
      var count = 0;

      final component = HookBuilder(builder: (context) {
        final state = useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (ctx) async {
            ctx.signal; // upstream destructures `{ signal: _signal }`
            count++;
            await sleep(10);
            return 'signal$count';
          },
        ));

        return Column(children: [
          Text('status: ${state.status.name}, '
              'fetchStatus: ${state.fetchStatus.name}'),
          Text('data: ${state.dataOrNull}'),
        ]);
      });

      client.onlineManager.setOnline(false);

      await tester.pumpApp(
        client,
        HookBuilder(builder: (context) {
          final show = useState(true);

          return Column(children: [
            if (show.value) component,
            TextButton(
              onPressed: () => show.value = false,
              child: const Text('hide'),
            ),
          ]);
        }),
      );

      expect(find.text('status: pending, fetchStatus: paused'), findsOneWidget);

      await click(tester, 'hide');

      client.onlineManager.setOnline(true);

      await advance(tester, 11);
      final state = client.getQueryState<String>(key);
      expect(state?.fetchStatus, FetchStatus.idle);
      expect(state?.status, QueryStatus.pending);

      expect(count, 0);
    });

    // useQuery.test.tsx:5603
    hookTest(
        'online queries should re-fetch if paused and we go online even if '
        'already unmounted (because not cancelled)', (tester, client) async {
      final key = queryKey();
      var count = 0;

      client.setQueryData<String>(key, 'initial');

      final component = HookBuilder(builder: (context) {
        final state = useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) async {
            count++;
            await sleep(10);
            return 'data$count';
          },
        ));

        return Column(children: [
          Text('status: ${state.status.name}, '
              'fetchStatus: ${state.fetchStatus.name}'),
          Text('data: ${state.dataOrNull}'),
        ]);
      });

      client.onlineManager.setOnline(false);

      await tester.pumpApp(
        client,
        HookBuilder(builder: (context) {
          final show = useState(true);

          return Column(children: [
            if (show.value) component,
            TextButton(
              onPressed: () => show.value = false,
              child: const Text('hide'),
            ),
          ]);
        }),
      );

      expect(find.text('status: success, fetchStatus: paused'), findsOneWidget);

      await click(tester, 'hide');

      client.onlineManager.setOnline(true);

      await advance(tester, 11);
      final state = client.getQueryState<String>(key);
      expect(state?.fetchStatus, FetchStatus.idle);
      expect(state?.status, QueryStatus.success);

      // give it a bit more time to make sure queryFn is not called again
      expect(count, 1);
    });

    // useQuery.test.tsx:5663
    hookTest(
        'online queries should not fetch if paused and we go online when '
        'cancelled and no refetchOnReconnect', (tester, client) async {
      final key = queryKey();
      var count = 0;

      client.onlineManager.setOnline(false);

      await tester.pumpApp(
        client,
        HookBuilder(builder: (context) {
          final state = useQuery(QueryObserverOptions<String>(
            queryKey: key,
            queryFn: (_) async {
              count++;
              await sleep(10);
              return 'data$count';
            },
            refetchOnReconnect: RefetchOn.never,
          ));

          return Column(children: [
            TextButton(
              onPressed: () =>
                  client.cancelQueries(filters: QueryFilters(queryKey: key)),
              child: const Text('cancel'),
            ),
            Text('status: ${state.status.name}, '
                'fetchStatus: ${state.fetchStatus.name}'),
            Text('data: ${state.dataOrNull}'),
          ]);
        }),
      );

      expect(find.text('status: pending, fetchStatus: paused'), findsOneWidget);

      await click(tester, 'cancel');

      await advance(tester, 11);
      expect(find.text('status: pending, fetchStatus: idle'), findsOneWidget);

      expect(count, 0);

      client.onlineManager.setOnline(true);

      await advance(tester, 11);

      expect(find.text('status: pending, fetchStatus: idle'), findsOneWidget);

      expect(count, 0);
    });

    // useQuery.test.tsx:5718
    hookTest(
        'online queries should fetch if paused and we go online even if '
        'already unmounted when refetch was not cancelled',
        (tester, client) async {
      final key = queryKey();
      var count = 0;

      final component = HookBuilder(builder: (context) {
        final state = useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) {
            count++;
            return Future.value('data$count');
          },
        ));

        return Column(children: [
          Text('status: ${state.status.name}, '
              'fetchStatus: ${state.fetchStatus.name}'),
          Text('data: ${state.dataOrNull}'),
        ]);
      });

      await tester.pumpApp(
        client,
        HookBuilder(builder: (context) {
          final show = useState(true);

          return Column(children: [
            if (show.value) component,
            TextButton(
              onPressed: () => show.value = false,
              child: const Text('hide'),
            ),
            TextButton(
              onPressed: () => client.invalidateQueries(
                  filters: QueryFilters(queryKey: key)),
              child: const Text('invalidate'),
            ),
          ]);
        }),
      );

      await advance(tester, 11);
      expect(find.text('status: success, fetchStatus: idle'), findsOneWidget);

      client.onlineManager.setOnline(false);

      await click(tester, 'invalidate');

      await advance(tester, 0);
      expect(find.text('status: success, fetchStatus: paused'), findsOneWidget);

      await click(tester, 'hide');

      client.onlineManager.setOnline(true);

      await advance(tester, 11);

      final state = client.getQueryState<String>(key);
      expect(state?.fetchStatus, FetchStatus.idle);
      expect(state?.status, QueryStatus.success);

      expect(count, 2);
    });
  });

  group('networkMode always', () {
    // useQuery.test.tsx:5788
    hookTest('always queries should start fetching even if you are offline',
        (tester, client) async {
      client.onlineManager.setOnline(false);

      final key = queryKey();
      var count = 0;

      await tester.pumpApp(
        client,
        HookBuilder(builder: (context) {
          final state = useQuery(QueryObserverOptions<String>(
            queryKey: key,
            queryFn: (_) async {
              count++;
              await sleep(10);
              return 'data $count';
            },
            networkMode: NetworkMode.always,
          ));

          return Column(children: [
            Text('status: ${state.status.name}, isPaused: ${state.isPaused}'),
            Text('data: ${state.dataOrNull}'),
          ]);
        }),
      );

      await advance(tester, 11);
      expect(find.text('status: success, isPaused: false'), findsOneWidget);
      expect(find.text('data: data 1'), findsOneWidget);
    });

    // useQuery.test.tsx:5824
    hookTest('always queries should not pause retries', (tester, client) async {
      client.onlineManager.setOnline(false);

      final key = queryKey();
      var count = 0;

      await tester.pumpApp(
        client,
        HookBuilder(builder: (context) {
          final state = useQuery(QueryObserverOptions<String>(
            queryKey: key,
            queryFn: (_) async {
              count++;
              await sleep(10);
              throw StateError('error $count');
            },
            networkMode: NetworkMode.always,
            retry: const RetryPolicy.times(1),
            retryDelay: const RetryDelay.fixed(Duration(milliseconds: 5)),
          ));

          final error = state.errorOrNull;
          return Column(children: [
            Text('status: ${state.status.name}, isPaused: ${state.isPaused}'),
            Text('error: ${error is StateError ? error.message : ''}'),
          ]);
        }),
      );

      await advance(tester, 26);
      expect(find.text('status: error, isPaused: false'), findsOneWidget);
      expect(find.text('error: error 2'), findsOneWidget);

      expect(count, 2);
    });
  });

  group('networkMode offlineFirst', () {
    // useQuery.test.tsx:5868
    hookTest(
        'offlineFirst queries should start fetching if you are offline, but '
        'pause retries', (tester, client) async {
      client.onlineManager.setOnline(false);

      final key = queryKey();
      var count = 0;

      await tester.pumpApp(
        client,
        HookBuilder(builder: (context) {
          final state = useQuery(QueryObserverOptions<String>(
            queryKey: key,
            queryFn: (_) async {
              count++;
              await sleep(10);
              throw StateError('failed$count');
            },
            retry: const RetryPolicy.times(2),
            retryDelay: const RetryDelay.fixed(Duration(milliseconds: 1)),
            networkMode: NetworkMode.offlineFirst,
          ));

          return Column(children: [
            Text('status: ${state.status.name}, '
                'fetchStatus: ${state.fetchStatus.name}, '
                'failureCount: ${state.failureCount}'),
            Text('failureReason: ${_message(state.failureReason)}'),
          ]);
        }),
      );

      await advance(tester, 12);
      expect(
        find.text('status: pending, fetchStatus: paused, failureCount: 1'),
        findsOneWidget,
      );
      expect(find.text('failureReason: failed1'), findsOneWidget);

      expect(count, 1);

      client.onlineManager.setOnline(true);

      await advance(tester, 22);
      expect(
        find.text('status: error, fetchStatus: idle, failureCount: 3'),
        findsOneWidget,
      );
      expect(find.text('failureReason: failed3'), findsOneWidget);

      expect(count, 3);
    });
  });

  // useQuery.test.tsx:6068 — `retryOnMount: () => false` is the bool
  // `false`: query_kit's option is `bool?` (inventory, G for the callback
  // cases 6973/7004).
  hookTest('should have status=error on mount when a query has failed',
      (tester, client) async {
    final key = queryKey();
    final states = <QueryResult<String>>[];
    final error = StateError('oops');

    Future<String> queryFn(QueryFunctionContext _) => Future.error(error);

    await client
        .query(QueryOptions<String>(queryKey: key, queryFn: queryFn))
        .then<void>((_) {}, onError: (Object _) {});

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final state = useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: queryFn,
          retry: RetryPolicy.never,
          retryOnMount: false,
        ));
        states.add(state);
        return const SizedBox();
      }),
    );

    await advance(tester, 0);
    expect(states, hasLength(1));

    expect(states[0].status, QueryStatus.error);
    expect(states[0].errorOrNull, same(error));
  });

  // useQuery.test.tsx:6102
  hookTest('setQueryData - should respect updatedAt', (tester, client) async {
    final key = queryKey();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final state = useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) => 'data',
        ));
        return Column(children: [
          Text('data: ${state.dataOrNull}'),
          Text('dataUpdatedAt: ${state.dataUpdatedAt?.millisecondsSinceEpoch}'),
          TextButton(
            onPressed: () {
              client.setQueryData<String>(
                key,
                'newData',
                updatedAt: DateTime.fromMillisecondsSinceEpoch(100),
              );
            },
            child: const Text('setQueryData'),
          ),
        ]);
      }),
    );

    await advance(tester, 0);
    expect(find.text('data: data'), findsOneWidget);
    await click(tester, 'setQueryData');
    await advance(tester, 0);
    expect(find.text('data: newData'), findsOneWidget);
    expect(find.text('dataUpdatedAt: 100'), findsOneWidget);
  });

  // useQuery.test.tsx:6134
  hookTest('errorUpdateCount should increased on each fetch failure',
      (tester, client) async {
    final key = queryKey();
    final error = StateError('oops');

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final result = useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) => Future<String>.error(error),
          retry: RetryPolicy.never,
        ));
        return Column(children: [
          TextButton(
            onPressed: result.refetch,
            child: const Text('refetch'),
          ),
          Text('data: ${result.errorUpdateCount}'),
        ]);
      }),
    );

    await advance(tester, 0);
    expect(find.text('data: 1'), findsOneWidget);
    await click(tester, 'refetch');
    await advance(tester, 0);
    expect(find.text('data: 2'), findsOneWidget);
    await click(tester, 'refetch');
    await advance(tester, 0);
    expect(find.text('data: 3'), findsOneWidget);
  });

  // useQuery.test.tsx:6167
  hookTest('should use provided custom queryClient', (tester, client) async {
    final key = queryKey();
    Future<String> queryFn(QueryFunctionContext _) async =>
        Future.value('custom client');

    // `render(<Page></Page>)`: no provider above the hook.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HookBuilder(builder: (context) {
          final data = useQuery(
            QueryObserverOptions<String>(queryKey: key, queryFn: queryFn),
            client: client,
          ).dataOrNull;

          return Text('data: $data');
        }),
      ),
    ));

    await advance(tester, 0);
    expect(find.text('data: custom client'), findsOneWidget);
  });

  // useQuery.test.tsx:6191
  hookTest('should be notified of updates between create and subscribe',
      (tester, client) async {
    final key = queryKey();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final result = useQuery(QueryObserverOptions<int>(
          enabled: Enabled.no,
          queryKey: key,
          queryFn: (_) => sleep(10).then((_) => 5),
        ));

        final mounted = useRef<bool?>(null);
        // this simulates a synchronous update between the time the query is
        // created and the time it is subscribed to that could be missed
        // otherwise
        if (mounted.value == null) {
          mounted.value = true;
          client.setQueryData<int>(key, 1);
        }

        return Column(children: [
          Text('status: ${result.status.name}'),
          Text('data: ${result.dataOrNull}'),
        ]);
      }),
    );

    await advance(tester, 11);
    expect(find.text('status: success'), findsOneWidget);
    expect(find.text('data: 1'), findsOneWidget);
  });

  // useQuery.test.tsx:6223
  hookTest(
      'should reuse same data object reference when queryKey changes back to '
      'some cached data', (tester, client) async {
    final key = queryKey();
    var spy = 0;

    Future<Map<String, Object?>> fetchNumber(int id) async {
      await sleep(5);
      return {
        'numbers': {
          'current': {'id': id},
        },
      };
    }

    Map<String, Object?> selector(Map<String, Object?> data) =>
        (data['numbers']! as Map<String, Object?>)['current']!
            as Map<String, Object?>;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final idState = useState(1);
        final id = idState.value;

        final data = useSelectQuery(
          QuerySelectOptions<Map<String, Object?>, Map<String, Object?>>(
            select: selector,
            queryKey: QueryKey([key, 'user', id]),
            queryFn: (_) => fetchNumber(id),
          ),
        ).dataOrNull;

        useEffect(() {
          spy++;
          return null;
        }, [data]);

        return Column(children: [
          TextButton(
            onPressed: () => idState.value = 1,
            child: const Text('1'),
          ),
          TextButton(
            onPressed: () => idState.value = 2,
            child: const Text('2'),
          ),
          Text('Rendered Id: ${data?['id']}'),
        ]);
      }),
    );
    expect(spy, 1);

    spy = 0;
    await advance(tester, 6);
    expect(find.text('Rendered Id: 1'), findsOneWidget);
    expect(spy, 1);

    spy = 0;
    await click(tester, '2');
    await advance(tester, 6);
    expect(find.text('Rendered Id: 2'), findsOneWidget);
    expect(spy, 2); // called with undefined because id changed

    spy = 0;
    await click(tester, '1');
    await advance(tester, 6);
    expect(find.text('Rendered Id: 1'), findsOneWidget);
    expect(spy, 1);

    spy = 0;
    await click(tester, '2');
    await advance(tester, 6);
    expect(find.text('Rendered Id: 2'), findsOneWidget);
    expect(spy, 1);
  });

  // useQuery.test.tsx:6289
  hookTest(
      'should reuse same data object reference when queryKey changes and '
      'placeholderData is present', (tester, client) async {
    final key = queryKey();
    var spy = 0;

    Future<Map<String, Object?>> fetchNumber(int id) async {
      await sleep(5);
      return {
        'numbers': {
          'current': {'id': id},
        },
      };
    }

    Map<String, Object?> selector(Map<String, Object?> data) =>
        (data['numbers']! as Map<String, Object?>)['current']!
            as Map<String, Object?>;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final idState = useState(1);
        final id = idState.value;

        final data = useSelectQuery(
          QuerySelectOptions<Map<String, Object?>, Map<String, Object?>>(
            select: selector,
            queryKey: QueryKey([key, 'user', id]),
            queryFn: (_) => fetchNumber(id),
            // A new instance on every build, as upstream's object literal.
            placeholderData: PlaceholderData.value(<String, Object?>{
              'numbers': {
                'current': {'id': 99},
              },
            }),
          ),
        ).dataOrNull;

        useEffect(() {
          spy++;
          return null;
        }, [data]);

        return Column(children: [
          TextButton(
            onPressed: () => idState.value = 1,
            child: const Text('1'),
          ),
          TextButton(
            onPressed: () => idState.value = 2,
            child: const Text('2'),
          ),
          Text('Rendered Id: ${data?['id']}'),
        ]);
      }),
    );
    expect(spy, 1);

    spy = 0;
    expect(find.text('Rendered Id: 99'), findsOneWidget);
    await advance(tester, 6);
    expect(find.text('Rendered Id: 1'), findsOneWidget);
    expect(spy, 1);

    spy = 0;
    await click(tester, '2');
    expect(find.text('Rendered Id: 99'), findsOneWidget);
    await advance(tester, 6);
    expect(find.text('Rendered Id: 2'), findsOneWidget);
    expect(spy, 2); // called with undefined because id changed

    spy = 0;
    await click(tester, '1');
    await advance(tester, 6);
    expect(find.text('Rendered Id: 1'), findsOneWidget);
    expect(spy, 1);

    spy = 0;
    await click(tester, '2');
    await advance(tester, 6);
    expect(find.text('Rendered Id: 2'), findsOneWidget);
    expect(spy, 1);
  });

  // useQuery.test.tsx:6378
  hookTest(
      'should keep the previous data when placeholderData is set and cache '
      'is used', (tester, client) async {
    final key = queryKey();
    final states = <QueryResult<int>>[];
    const steps = [0, 1, 0, 2];

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final count = useState(0);
        final step = steps[count.value];
        final state = useQuery(QueryObserverOptions<int>(
          staleTime: StaleTime.infinite,
          queryKey: QueryKey([...key.parts, step]),
          queryFn: (_) => sleep(10).then((_) => step),
          placeholderData: const PlaceholderData.keepPrevious(),
        ));
        states.add(state);
        return Column(children: [
          Text('data: ${state.dataOrNull}'),
          TextButton(
            onPressed: () => count.value++,
            child: const Text('setCount'),
          ),
        ]);
      }),
    );

    await advance(tester, 11);
    expect(find.text('data: 0'), findsOneWidget);

    await click(tester, 'setCount');

    await advance(tester, 11);
    expect(find.text('data: 1'), findsOneWidget);

    await click(tester, 'setCount');

    await advance(tester, 11);
    expect(find.text('data: 0'), findsOneWidget);

    await click(tester, 'setCount');

    await advance(tester, 11);
    expect(find.text('data: 2'), findsOneWidget);

    final expected = <(int?, bool, bool, bool)>[
      // Initial
      (null, true, false, false),
      // Fetched
      (0, false, true, false),
      // Set state
      (0, true, true, true),
      // New data
      (1, false, true, false),
      // Set state with existing data
      (0, false, true, false),
      // Set state where the placeholder value should come from cache request
      (0, true, true, true),
      // New data
      (2, false, true, false),
    ];
    for (var i = 0; i < expected.length; i++) {
      expect(
        (
          states[i].dataOrNull,
          states[i].isFetching,
          states[i].isSuccess,
          states[i].isPlaceholderData,
        ),
        expected[i],
        reason: 'states[$i]',
      );
    }
  });

  // useQuery.test.tsx:6495 — `skipToken` is `Enabled.no` (plan, D14): the
  // queryFn stays, and `enabled` follows the prop instead.
  hookTest('should respect skipToken and refetch when skipToken is taken away',
      (tester, client) async {
    final key = queryKey();

    Widget page(bool enabled) => HookBuilder(builder: (context) {
          final result = useQuery(QueryObserverOptions<String>(
            queryKey: QueryKey([key]),
            queryFn: (_) => sleep(10).then((_) => Future.value('data')),
            enabled: enabled ? Enabled.yes : Enabled.no,
            retry: RetryPolicy.never,
            retryOnMount: false,
            refetchOnMount: RefetchOn.never,
            refetchOnWindowFocus: RefetchOn.never,
          ));

          return Column(children: [
            Text('status: ${result.status.name}'),
            Text('data: ${result.dataOrNull}'),
          ]);
        });

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final enabled = useState(false);

        return Column(children: [
          page(enabled.value),
          TextButton(
            onPressed: () => enabled.value = !enabled.value,
            child: const Text('enable'),
          ),
        ]);
      }),
    );

    expect(find.text('status: pending'), findsOneWidget);

    await click(tester, 'enable');
    await advance(tester, 11);
    expect(find.text('status: success'), findsOneWidget);
    expect(find.text('data: data'), findsOneWidget);
  });

  // useQuery.test.tsx:6570 — `notifyOnChangeProps: 'all'` is the default
  // here: a hook without `buildWhen` rebuilds for every change.
  hookTest('should return correct optimistic result when fetching after error',
      (tester, client) async {
    final key = queryKey();
    final error = StateError('oh no');
    final results = <QueryResult<String>>[];

    final page = HookBuilder(builder: (context) {
      final query = useQuery(QueryObserverOptions<String>(
        queryKey: key,
        queryFn: (_) => sleep(10).then<String>((_) => throw error),
        retry: RetryPolicy.never,
      ));
      results.add(query);
      return Column(children: [
        Text('status: ${query.status.name}, ${query.fetchStatus.name}'),
        Text('error: ${(query.errorOrNull as StateError?)?.message}'),
      ]);
    });

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final enabled = useState(true);
        return Column(children: [
          TextButton(
            onPressed: () => enabled.value = !enabled.value,
            child: const Text('toggle'),
          ),
          if (enabled.value) page,
        ]);
      }),
    );

    await advance(tester, 11);
    expect(find.text('status: error, idle'), findsOneWidget);

    await click(tester, 'toggle');
    await click(tester, 'toggle');

    await advance(tester, 11);
    expect(find.text('status: error, idle'), findsOneWidget);

    expect(results, hasLength(4));

    // initial fetch
    expect(results[0].status, QueryStatus.pending);
    expect(results[0].fetchStatus, FetchStatus.fetching);
    expect(results[0].errorOrNull, isNull);
    expect(results[0].errorUpdatedAt, isNull);
    expect(results[0].errorUpdateCount, 0);
    expect(results[0].isLoading, isTrue);
    expect(results[0].failureCount, 0);
    expect(results[0].failureReason, isNull);

    // error state
    expect(results[1].status, QueryStatus.error);
    expect(results[1].fetchStatus, FetchStatus.idle);
    expect(results[1].errorOrNull, same(error));
    expect(results[1].errorUpdateCount, 1);
    expect(results[1].isLoading, isFalse);
    expect(results[1].failureCount, 1);
    expect(results[1].failureReason, same(error));
    expect(results[1].errorUpdatedAt, isNotNull);

    // refetch, optimistic state, no errors anymore
    expect(results[2].status, QueryStatus.pending);
    expect(results[2].fetchStatus, FetchStatus.fetching);
    expect(results[2].errorOrNull, isNull);
    expect(results[2].errorUpdateCount, 1);
    expect(results[2].isLoading, isTrue);
    expect(results[2].failureCount, 0);
    expect(results[2].failureReason, isNull);
    expect(results[2].errorUpdatedAt, isNotNull);

    // final state
    expect(results[3].status, QueryStatus.error);
    expect(results[3].fetchStatus, FetchStatus.idle);
    expect(results[3].errorOrNull, same(error));
    expect(results[3].errorUpdateCount, 2);
    expect(results[3].isLoading, isFalse);
    expect(results[3].failureCount, 1);
    expect(results[3].failureReason, same(error));
    expect(results[3].errorUpdatedAt, isNotNull);
  });

  // useQuery.test.tsx:7004 — upstream's `retryOnMount` is a callback whose
  // never being called is half of the case; query_kit's option is a `bool`
  // (plan, D14), so that half is omitted and `retryOnMount: false` stands in.
  // The other half — the remount refetches, three queryFn calls — is ported.
  hookTest('should not call retryOnMount callback when the query has data',
      (tester, client) async {
    final key = queryKey();
    var count = 0;
    var queryFnCalls = 0;

    Future<String> queryFn(QueryFunctionContext _) async {
      queryFnCalls++;
      await sleep(10);
      count++;
      if (count == 1) {
        return 'data';
      }
      throw StateError('oops');
    }

    Widget page() => HookBuilder(builder: (context) {
          final result = useQuery(QueryObserverOptions<String>(
            queryKey: key,
            queryFn: queryFn,
            retry: RetryPolicy.never,
            staleTime: StaleTime.zero,
            refetchOnMount: RefetchOn.ifStale,
            retryOnMount: false,
          ));
          final error = result.errorOrNull;

          return Column(children: [
            Text(result.dataOrNull ?? 'no data'),
            Text(error is StateError ? error.message : 'no error'),
            TextButton(
              onPressed: result.refetch,
              child: const Text('refetch'),
            ),
          ]);
        });

    await tester.pumpApp(client, page());
    await advance(tester, 11);
    expect(find.text('data'), findsOneWidget);

    await click(tester, 'refetch');
    await advance(tester, 11);
    expect(find.text('data'), findsOneWidget);
    expect(find.text('oops'), findsOneWidget);

    // rendered.unmount()
    await tester.pumpWidget(const SizedBox());

    await tester.pumpApp(client, page());
    await advance(tester, 11);

    expect(queryFnCalls, 3);
  });
}
