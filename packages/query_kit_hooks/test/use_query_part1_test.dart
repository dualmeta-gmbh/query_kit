// Ported from query/packages/react-query/src/__tests__/useQuery.test.tsx at
// 50680b98c, lines 1–3600. Each case keeps upstream's name, and its
// upstream line is in the comment above it. What was adapted or
// omitted, and why, is in PORTING_NOTES.md.
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
      HookBuilder(builder: (context) {
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

    Widget component(String value) => HookBuilder(
          key: ValueKey(value),
          builder: (context) {
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
      HookBuilder(builder: (context) {
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

  // useQuery.test.tsx:700
  hookTest(
      'should not re-run a stable select when it re-renders if selector '
      'throws an error', (tester, client) async {
    final key = queryKey();
    final error = StateError('Select Error');
    var runs = 0;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
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
      HookBuilder(builder: (context) {
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

  // useQuery.test.tsx:1128
  hookTest('should not fetch when switching to a disabled query',
      (tester, client) async {
    final key = queryKey();
    final states = <QueryResult<int>>[];

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
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
      HookBuilder(builder: (context) {
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
      HookBuilder(builder: (context) {
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
      HookBuilder(builder: (context) {
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

    Widget userInfo(int? id) => HookBuilder(builder: (context) {
          final searchQuery = useUserInfoQuery(id: id, enabled: true);
          return Text('UserInfo data is ${searchQuery.dataOrNull}');
        });

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
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
      HookBuilder(builder: (context) {
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
      HookBuilder(builder: (context) {
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
}
