// Ported from query/packages/react-query/src/__tests__/useQuery.test.tsx at
// 50680b98c. Spike selection (AP0 of docs/plans/hooks-package.md); each case
// keeps upstream's name, and its upstream line is in the comment above it.
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_hooks/query_kit_hooks.dart';

import 'harness.dart';

void main() {
  // useQuery.test.tsx:72
  hookTest('should return the correct states for a successful query',
      (tester, client) async {
    final key = queryKey();
    final states = <QueryResult<String>>[];

    await tester.pumpApp(
      client,
      HookProbe((context) {
        final state = useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) => sleep(10).then((_) => 'test'),
        ));
        states.add(state);
        return switch (state) {
          QueryPending() => const Text('pending'),
          QueryError(:final error) => Text('$error'),
          QuerySuccess(:final data) => Text(data),
        };
      }),
    );

    await advance(tester, 11);
    expect(find.text('test'), findsOneWidget);

    expect(states, hasLength(2));

    final first = states[0];
    expect(first, isA<QueryPending<String>>());
    expect(first.dataOrNull, isNull);
    expect(first.dataUpdatedAt, isNull);
    expect(first.errorOrNull, isNull);
    expect(first.errorUpdatedAt, isNull);
    expect(first.failureCount, 0);
    expect(first.failureReason, isNull);
    expect(first.errorUpdateCount, 0);
    expect(first.isError, isFalse);
    expect(first.isFetched, isFalse);
    expect(first.isFetchedAfterMount, isFalse);
    expect(first.isFetching, isTrue);
    expect(first.isPaused, isFalse);
    expect(first.isPending, isTrue);
    expect(first.isLoading, isTrue);
    expect(first.isPlaceholderData, isFalse);
    expect(first.isRefetching, isFalse);
    expect(first.isStale, isTrue);
    expect(first.isSuccess, isFalse);
    expect(first.isEnabled, isTrue);
    expect(first.status, QueryStatus.pending);
    expect(first.fetchStatus, FetchStatus.fetching);

    final second = states[1];
    expect(second, isA<QuerySuccess<String>>());
    expect(second.dataOrNull, 'test');
    expect(second.dataUpdatedAt, isNotNull);
    expect(second.errorOrNull, isNull);
    expect(second.errorUpdatedAt, isNull);
    expect(second.failureCount, 0);
    expect(second.failureReason, isNull);
    expect(second.errorUpdateCount, 0);
    expect(second.isError, isFalse);
    expect(second.isFetched, isTrue);
    expect(second.isFetchedAfterMount, isTrue);
    expect(second.isFetching, isFalse);
    expect(second.isPaused, isFalse);
    expect(second.isPending, isFalse);
    expect(second.isLoading, isFalse);
    expect(second.isPlaceholderData, isFalse);
    expect(second.isRefetching, isFalse);
    expect(second.isStale, isTrue);
    expect(second.isSuccess, isTrue);
    expect(second.isEnabled, isTrue);
    expect(second.status, QueryStatus.success);
    expect(second.fetchStatus, FetchStatus.idle);
  });

  // useQuery.test.tsx:435
  hookTest('should pick up a query when re-mounting with gcTime 0',
      (tester, client) async {
    final key = queryKey();
    final states = <QueryResult<String>>[];

    Widget component(String value) => HookProbe(
          key: ValueKey(value),
          (context) {
            final state = useQuery(QueryObserverOptions<String>(
              queryKey: key,
              queryFn: (_) => sleep(10).then((_) => 'data: $value'),
              gcTime: const GcTime.duration(Duration.zero),
            ));
            states.add(state);
            return Text(state.dataOrNull ?? '');
          },
        );

    await tester.pumpApp(
      client,
      HookProbe((context) {
        final toggle = useState(false);
        return Column(children: [
          TextButton(
            onPressed: () => toggle.value = true,
            child: const Text('toggle'),
          ),
          if (toggle.value) component('2') else component('1'),
        ]);
      }),
    );

    await advance(tester, 11);
    expect(find.text('data: 1'), findsOneWidget);

    await click(tester, 'toggle');

    await advance(tester, 11);
    expect(find.text('data: 2'), findsOneWidget);

    expect(states, hasLength(4));
    // First load
    expect(states[0].isPending, isTrue);
    expect(states[0].isSuccess, isFalse);
    expect(states[0].isFetching, isTrue);
    // First success
    expect(states[1].isPending, isFalse);
    expect(states[1].isSuccess, isTrue);
    expect(states[1].isFetching, isFalse);
    // Switch, goes to fetching
    expect(states[2].isPending, isFalse);
    expect(states[2].isSuccess, isTrue);
    expect(states[2].isFetching, isTrue);
    // Second success
    expect(states[3].isPending, isFalse);
    expect(states[3].isSuccess, isTrue);
    expect(states[3].isFetching, isFalse);
  });

  // useQuery.test.tsx:1128
  hookTest('should not fetch when switching to a disabled query',
      (tester, client) async {
    final key = queryKey();
    final states = <QueryResult<int>>[];

    await tester.pumpApp(
      client,
      HookProbe((context) {
        final count = useState(0);
        final state = useQuery(QueryObserverOptions<int>(
          queryKey: QueryKey([...key.parts, count.value]),
          queryFn: (_) {
            final value = count.value;
            return sleep(5).then((_) => value);
          },
          enabled: count.value == 0 ? Enabled.yes : Enabled.no,
        ));
        states.add(state);
        return Column(children: [
          TextButton(
            onPressed: () => count.value = 1,
            child: const Text('increment'),
          ),
          Text('data: ${state.dataOrNull ?? 'undefined'}'),
          Text('count: ${count.value}'),
        ]);
      }),
    );

    await advance(tester, 6);
    expect(find.text('data: 0'), findsOneWidget);

    await click(tester, 'increment');

    await advance(tester, 6);
    expect(find.text('count: 1'), findsOneWidget);
    expect(find.text('data: undefined'), findsOneWidget);

    expect(states, hasLength(3));
    // Fetch query
    expect(states[0].dataOrNull, isNull);
    expect(states[0].isFetching, isTrue);
    expect(states[0].isSuccess, isFalse);
    // Fetched query
    expect(states[1].dataOrNull, 0);
    expect(states[1].isFetching, isFalse);
    expect(states[1].isSuccess, isTrue);
    // Switch to disabled query
    expect(states[2].dataOrNull, isNull);
    expect(states[2].isFetching, isFalse);
    expect(states[2].isSuccess, isFalse);
  });

  // useQuery.test.tsx:1185
  hookTest('should keep the previous data when placeholderData is set',
      (tester, client) async {
    final key = queryKey();
    final states = <QueryResult<int>>[];

    await tester.pumpApp(
      client,
      HookProbe((context) {
        final count = useState(0);
        final state = useQuery(QueryObserverOptions<int>(
          queryKey: QueryKey([...key.parts, count.value]),
          queryFn: (_) {
            final value = count.value;
            return sleep(10).then((_) => value);
          },
          placeholderData: const PlaceholderData.keepPrevious(),
        ));
        states.add(state);
        return Column(children: [
          Text('data: ${state.dataOrNull}'),
          TextButton(
            onPressed: () => count.value = 1,
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

    // Initial
    expect(states[0].dataOrNull, isNull);
    expect(states[0].isFetching, isTrue);
    expect(states[0].isSuccess, isFalse);
    expect(states[0].isPlaceholderData, isFalse);
    // Fetched
    expect(states[1].dataOrNull, 0);
    expect(states[1].isFetching, isFalse);
    expect(states[1].isSuccess, isTrue);
    expect(states[1].isPlaceholderData, isFalse);
    // Set state
    expect(states[2].dataOrNull, 0);
    expect(states[2].isFetching, isTrue);
    expect(states[2].isSuccess, isTrue);
    expect(states[2].isPlaceholderData, isTrue);
    // New data
    expect(states[3].dataOrNull, 1);
    expect(states[3].isFetching, isFalse);
    expect(states[3].isSuccess, isTrue);
    expect(states[3].isPlaceholderData, isFalse);
  });

  // useQuery.test.tsx:1606
  hookTest(
      'should keep the previous data on disabled query when placeholderData '
      'is set', (tester, client) async {
    final key = queryKey();
    final states = <QueryResult<int>>[];

    await tester.pumpApp(
      client,
      HookProbe((context) {
        final count = useState(0);
        final state = useQuery(QueryObserverOptions<int>(
          queryKey: QueryKey([...key.parts, count.value]),
          queryFn: (_) {
            final value = count.value;
            return sleep(10).then((_) => value);
          },
          enabled: Enabled.no,
          placeholderData: const PlaceholderData.keepPrevious(),
        ));
        states.add(state);
        return Column(children: [
          TextButton(
            onPressed: state.refetch,
            child: const Text('refetch'),
          ),
          TextButton(
            onPressed: () => count.value = 1,
            child: const Text('setCount'),
          ),
          Text('data: ${state.dataOrNull ?? 'undefined'}'),
        ]);
      }),
    );

    expect(find.text('data: undefined'), findsOneWidget);

    await click(tester, 'refetch');

    await advance(tester, 11);
    expect(find.text('data: 0'), findsOneWidget);

    await click(tester, 'setCount');

    await advance(tester, 11);
    expect(find.text('data: 0'), findsOneWidget);

    await click(tester, 'refetch');

    await advance(tester, 11);
    expect(find.text('data: 1'), findsOneWidget);

    expect(states, hasLength(6));

    void expectState(
        int i, int? data, bool fetching, bool success, bool placeholder) {
      expect(states[i].dataOrNull, data, reason: 'states[$i].data');
      expect(states[i].isFetching, fetching, reason: 'states[$i].isFetching');
      expect(states[i].isSuccess, success, reason: 'states[$i].isSuccess');
      expect(states[i].isPlaceholderData, placeholder,
          reason: 'states[$i].isPlaceholderData');
    }

    // Disabled query
    expectState(0, null, false, false, false);
    // Fetching query
    expectState(1, null, true, false, false);
    // Fetched query
    expectState(2, 0, false, true, false);
    // Set state
    expectState(3, 0, false, true, true);
    // Fetching new query
    expectState(4, 0, true, true, true);
    // Fetched new query
    expectState(5, 1, false, true, false);
  });

  // useQuery.test.tsx:1932
  hookTest('should re-render when a query becomes stale',
      (tester, client) async {
    final key = queryKey();
    final states = <QueryResult<String>>[];

    await tester.pumpApp(
      client,
      HookProbe((context) {
        final state = useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) => 'test',
          staleTime: const StaleTime.duration(Duration(milliseconds: 50)),
        ));
        states.add(state);
        return const SizedBox();
      }),
    );

    await advance(tester, 100);

    expect(states, hasLength(3));
    expect(states[0].isStale, isTrue);
    expect(states[1].isStale, isFalse);
    expect(states[2].isStale, isTrue);
  });

  // useQuery.test.tsx:1956
  hookTest(
      'should re-render disabled observers when other observers trigger a '
      'query (#8741)', (tester, client) async {
    final key = queryKey();

    QueryResult<({int? id, String name})> useUserInfoQuery(
            {required int? id, required bool enabled}) =>
        useQuery(QueryObserverOptions<({int? id, String name})>(
          queryKey: QueryKey([...key.parts, id]),
          queryFn: (_) => sleep(10).then((_) => (id: id, name: 'John')),
          enabled: id != null && enabled ? Enabled.yes : Enabled.no,
        ));

    Widget userInfo(int? id) => HookProbe((context) {
          final searchQuery = useUserInfoQuery(id: id, enabled: true);
          return Text('UserInfo data is ${searchQuery.dataOrNull}');
        });

    await tester.pumpApp(
      client,
      HookProbe((context) {
        final id = useState<int?>(null);
        final searchQuery = useUserInfoQuery(id: id.value, enabled: false);
        return Column(children: [
          Text('User fetching status is ${searchQuery.fetchStatus.name}'),
          userInfo(id.value),
          TextButton(
            onPressed: () => id.value = 42,
            child: const Text('Set ID and trigger user load'),
          ),
        ]);
      }),
    );

    expect(find.text('User fetching status is idle'), findsOneWidget);

    await click(tester, 'Set ID and trigger user load');

    await advance(tester, 0);
    expect(find.text('User fetching status is fetching'), findsOneWidget);
    await advance(tester, 11);
    expect(find.text('UserInfo data is (id: 42, name: John)'), findsOneWidget);

    expect(find.text('User fetching status is idle'), findsOneWidget);
  });

  // useQuery.test.tsx:2300
  hookTest('should update query options', (tester, client) async {
    final key = queryKey();

    Future<String> queryFn(QueryFunctionContext _) =>
        sleep(10).then((_) => 'data1');

    await tester.pumpApp(
      client,
      HookProbe((context) {
        useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: queryFn,
          retryDelay: const RetryDelay.fixed(Duration(milliseconds: 10)),
        ));
        useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: queryFn,
          retryDelay: const RetryDelay.fixed(Duration(milliseconds: 20)),
        ));
        return const SizedBox();
      }),
    );

    expect(
      client.queryCache
          .find(filters: QueryFilters(queryKey: key))!
          .options
          .retryDelay,
      const RetryDelay.fixed(Duration(milliseconds: 20)),
    );
  });

  // useQuery.test.tsx:2316
  hookTest('should batch re-renders', (tester, client) async {
    final key = queryKey();
    var renders = 0;

    Future<String> queryFn(QueryFunctionContext _) =>
        sleep(15).then((_) => 'data');

    await tester.pumpApp(
      client,
      HookProbe((context) {
        final query1 = useQuery(
            QueryObserverOptions<String>(queryKey: key, queryFn: queryFn));
        final query2 = useQuery(
            QueryObserverOptions<String>(queryKey: key, queryFn: queryFn));
        renders++;
        return Text('${query1.dataOrNull} ${query2.dataOrNull}');
      }),
    );

    await advance(tester, 16);
    expect(find.text('data data'), findsOneWidget);

    // Should be 2 instead of 3
    expect(renders, 2);
  });

  // useQuery.test.tsx:700
  hookTest(
      'should not re-run a stable select when it re-renders if selector '
      'throws an error', (tester, client) async {
    final key = queryKey();
    final error = StateError('Select Error');
    var runs = 0;

    await tester.pumpApp(
      client,
      HookProbe((context) {
        final rerender = useState(0);
        final select = useCallback<String Function(String)>((_) {
          runs++;
          throw error;
        }, const []);
        final state = useSelectQuery(QuerySelectOptions<String, String>(
          queryKey: key,
          queryFn: (_) => runs == 0 ? 'test' : 'test2',
          select: select,
        ));
        return Column(children: [
          Text('error: ${(state.errorOrNull as StateError?)?.message}'),
          TextButton(
            onPressed: () => rerender.value++,
            child: const Text('rerender'),
          ),
          TextButton(
            onPressed: state.refetch,
            child: const Text('refetch'),
          ),
        ]);
      }),
    );

    await advance(tester, 0);
    expect(find.text('error: Select Error'), findsOneWidget);
    expect(runs, 1);
    await click(tester, 'rerender');
    await advance(tester, 0);
    expect(runs, 1);
    await click(tester, 'refetch');
    await advance(tester, 0);
    expect(runs, 2);
  });

  // useQuery.test.tsx:738 — upstream tracks which result properties the
  // component reads (`data` only) and skips the `isFetching` flip of the
  // refetch. Dart has no tracked properties; the same intent is a
  // `buildWhen` on the data (#15, plan D8).
  hookTest(
      'should track properties and only re-render when a tracked property '
      'changes', (tester, client) async {
    final key = queryKey();
    final states = <QueryResult<String>>[];
    var count = 0;

    await tester.pumpApp(
      client,
      HookProbe((context) {
        final state = useQuery(
          QueryObserverOptions<String>(
            queryKey: key,
            queryFn: (_) => sleep(10).then((_) {
              count++;
              return 'test$count';
            }),
          ),
          buildWhen: (previous, current) =>
              previous.dataOrNull != current.dataOrNull,
        );
        states.add(state);
        return Column(children: [
          Text(state.dataOrNull ?? ''),
          TextButton(
            onPressed: state.refetch,
            child: const Text('refetch'),
          ),
        ]);
      }),
    );

    await advance(tester, 11);
    expect(find.text('test1'), findsOneWidget);

    await click(tester, 'refetch');

    await advance(tester, 11);
    expect(find.text('test2'), findsOneWidget);

    expect(states, hasLength(3));
    expect(states[0].dataOrNull, isNull);
    expect(states[1].dataOrNull, 'test1');
    expect(states[2].dataOrNull, 'test2');
  });

  // useQuery.test.tsx:3763
  hookTest('should mark query as fetching, when using initialData',
      (tester, client) async {
    final key = queryKey();
    final results = <QueryResult<String>>[];

    await tester.pumpApp(
      client,
      HookProbe((context) {
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

  // useQuery.test.tsx:3871
  hookTest('data should persist when enabled is changed to false',
      (tester, client) async {
    final key = queryKey();
    final results = <QueryResult<String>>[];

    await tester.pumpApp(
      client,
      HookProbe((context) {
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

  // useQuery.test.tsx:4100
  hookTest('should refetch in an interval depending on function result',
      (tester, client) async {
    final key = queryKey();
    var count = 0;
    final states = <QueryResult<int>>[];

    await tester.pumpApp(
      client,
      HookProbe((context) {
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

  // useQuery.test.tsx:4447
  hookTest('select should only run when dependencies change if memoized',
      (tester, client) async {
    final key1 = queryKey();
    var selectRun = 0;

    await tester.pumpApp(
      client,
      HookProbe((context) {
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

    Widget page(int limit) => HookProbe((context) {
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

  // useQuery.test.tsx:5056
  hookTest(
      'should refetch when query key changed when switching between '
      'erroneous queries', (tester, client) async {
    Widget page(bool id) => HookProbe((context) {
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
      HookProbe((context) {
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
      HookProbe((context) {
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

  // useQuery.test.tsx:6191
  hookTest('should be notified of updates between create and subscribe',
      (tester, client) async {
    final key = queryKey();

    await tester.pumpApp(
      client,
      HookProbe((context) {
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

  // useQuery.test.tsx:6378
  hookTest(
      'should keep the previous data when placeholderData is set and cache '
      'is used', (tester, client) async {
    final key = queryKey();
    final states = <QueryResult<int>>[];
    const steps = [0, 1, 0, 2];

    await tester.pumpApp(
      client,
      HookProbe((context) {
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

  // useQuery.test.tsx:6570 — `notifyOnChangeProps: 'all'` is the default
  // here: a hook without `buildWhen` rebuilds for every change.
  hookTest('should return correct optimistic result when fetching after error',
      (tester, client) async {
    final key = queryKey();
    final error = StateError('oh no');
    final results = <QueryResult<String>>[];

    final page = HookProbe((context) {
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
      HookProbe((context) {
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
}
