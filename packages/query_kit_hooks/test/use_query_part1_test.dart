// Ported from query/packages/react-query/src/__tests__/useQuery.test.tsx at
// 50680b98c, lines 1–3600. Each case keeps upstream's name, and its
// upstream line is in the comment above it. What was adapted or
// omitted, and why, is in PORTING_NOTES.md.
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_hooks/query_kit_hooks.dart';

import 'harness.dart';

void main() {
  // useQuery.test.tsx:48
  hookTest('should allow to set default data value', (tester, client) async {
    final key = queryKey();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final data = useQuery(QueryObserverOptions<String>(
              queryKey: key,
              queryFn: (_) => sleep(10).then((_) => 'test'),
            )).dataOrNull ??
            'default';
        return Text(data);
      }),
    );

    expect(find.text('default'), findsOneWidget);

    await advance(tester, 11);
    expect(find.text('test'), findsOneWidget);
  });

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

  // useQuery.test.tsx:159
  hookTest('should return the correct states for an unsuccessful query',
      (tester, client) async {
    final key = queryKey();
    final rec = Recorder<QueryResult<String>>();
    var index = 0;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final state = rec.build(useQuery(
          QueryObserverOptions<String>(
            queryKey: key,
            queryFn: (_) =>
                Future<String>.error(StateError('rejected #${++index}')),
            retry: const RetryPolicy.times(1),
            retryDelay: const RetryDelay.fixed(Duration(milliseconds: 1)),
          ),
          buildWhen: rec.buildWhen,
        ));
        return Column(children: [
          Text('Status: ${state.status.name}'),
          Text('Failure Count: ${state.failureCount}'),
          Text('Failure Reason: ${_message(state.failureReason) ?? ''}'),
        ]);
      }),
    );

    await advance(tester, 2);
    expect(find.text('Status: error'), findsOneWidget);

    final first = rec.builds[0];
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

    expect(rec.builds, hasLength(3));
    expect(rec.delivered, rec.builds.sublist(1));

    final second = rec.builds[1];
    expect(second, isA<QueryPending<String>>());
    expect(second.dataOrNull, isNull);
    expect(second.dataUpdatedAt, isNull);
    expect(second.errorOrNull, isNull);
    expect(second.errorUpdatedAt, isNull);
    expect(second.failureCount, 1);
    expect(_message(second.failureReason), 'rejected #1');
    expect(second.errorUpdateCount, 0);
    expect(second.isError, isFalse);
    expect(second.isFetched, isFalse);
    expect(second.isFetchedAfterMount, isFalse);
    expect(second.isFetching, isTrue);
    expect(second.isPaused, isFalse);
    expect(second.isPending, isTrue);
    expect(second.isLoading, isTrue);
    expect(second.isPlaceholderData, isFalse);
    expect(second.isRefetching, isFalse);
    expect(second.isStale, isTrue);
    expect(second.isSuccess, isFalse);
    expect(second.isEnabled, isTrue);
    expect(second.status, QueryStatus.pending);
    expect(second.fetchStatus, FetchStatus.fetching);

    final third = rec.builds[2];
    expect(third, isA<QueryError<String>>());
    expect(third.dataOrNull, isNull);
    expect(third.dataUpdatedAt, isNull);
    expect(_message(third.errorOrNull), 'rejected #2');
    expect(third.errorUpdatedAt, isNotNull);
    expect(third.failureCount, 2);
    expect(_message(third.failureReason), 'rejected #2');
    expect(third.errorUpdateCount, 1);
    expect(third.isError, isTrue);
    expect(third.isFetched, isTrue);
    expect(third.isFetchedAfterMount, isTrue);
    expect(third.isFetching, isFalse);
    expect(third.isPaused, isFalse);
    expect(third.isPending, isFalse);
    expect(third.isLoading, isFalse);
    expect((third as QueryError<String>).isLoadingError, isTrue);
    expect(third.isPlaceholderData, isFalse);
    expect(third.isRefetchError, isFalse);
    expect(third.isRefetching, isFalse);
    expect(third.isStale, isTrue);
    expect(third.isSuccess, isFalse);
    expect(third.isEnabled, isTrue);
    expect(third.status, QueryStatus.error);
    expect(third.fetchStatus, FetchStatus.idle);
  });

  // useQuery.test.tsx:275
  hookTest(
      'should set isFetchedAfterMount to true after a query has been fetched',
      (tester, client) async {
    final key = queryKey();

    await prefetch(
      client,
      QueryOptions<String>(queryKey: key, queryFn: (_) => 'prefetched'),
    );

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final result = useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) => 'new data',
        ));
        return Column(children: [
          Text('data: ${result.dataOrNull}'),
          Text('isFetched: ${result.isFetched}'),
          Text('isFetchedAfterMount: ${result.isFetchedAfterMount}'),
        ]);
      }),
    );

    expect(find.text('data: prefetched'), findsOneWidget);
    expect(find.text('isFetched: true'), findsOneWidget);
    expect(find.text('isFetchedAfterMount: false'), findsOneWidget);

    await advance(tester, 0);
    expect(find.text('data: new data'), findsOneWidget);
    expect(find.text('isFetched: true'), findsOneWidget);
    expect(find.text('isFetchedAfterMount: true'), findsOneWidget);
  });

  // useQuery.test.tsx:311
  hookTest(
      'should not cancel an ongoing fetch when refetch is called with '
      'cancelRefetch=false if we have data already', (tester, client) async {
    final key = queryKey();
    var fetchCount = 0;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final refetch = useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) async {
            fetchCount++;
            await sleep(10);
            return 'data';
          },
          enabled: Enabled.no,
          initialData: const InitialData.value('initialData'),
        )).refetch;

        useEffect(() {
          final timers = [
            Timer(_ms(5), refetch),
            Timer(_ms(5), () => refetch(cancelRefetch: false)),
          ];
          return () => _cancelAll(timers);
        }, [refetch]);

        return const SizedBox();
      }),
    );

    await advance(tester, 15);
    // first refetch only, second refetch is ignored
    expect(fetchCount, 1);
  });

  // useQuery.test.tsx:346
  hookTest(
      'should cancel an ongoing fetch when refetch is called '
      '(cancelRefetch=true) if we have data already', (tester, client) async {
    final key = queryKey();
    var fetchCount = 0;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final refetch = useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) async {
            fetchCount++;
            await sleep(10);
            return 'data';
          },
          enabled: Enabled.no,
          initialData: const InitialData.value('initialData'),
        )).refetch;

        useEffect(() {
          final timers = [
            Timer(_ms(5), refetch),
            Timer(_ms(5), refetch),
          ];
          return () => _cancelAll(timers);
        }, [refetch]);

        return const SizedBox();
      }),
    );

    await advance(tester, 15);
    // first refetch (gets cancelled) and second refetch
    expect(fetchCount, 2);
  });

  // useQuery.test.tsx:381
  hookTest(
      'should not cancel an ongoing fetch when refetch is called '
      '(cancelRefetch=true) if we do not have data yet',
      (tester, client) async {
    final key = queryKey();
    var fetchCount = 0;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final refetch = useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) async {
            fetchCount++;
            await sleep(10);
            return 'data';
          },
          enabled: Enabled.no,
        )).refetch;

        useEffect(() {
          final timers = [
            Timer(_ms(5), refetch),
            Timer(_ms(5), refetch),
          ];
          return () => _cancelAll(timers);
        }, [refetch]);

        return const SizedBox();
      }),
    );

    await advance(tester, 15);
    // first refetch will not get cancelled, second one gets skipped
    expect(fetchCount, 1);
  });

  // useQuery.test.tsx:415
  hookTest('should be able to watch a query without providing a query function',
      (tester, client) async {
    final key = queryKey();
    final rec = Recorder<QueryResult<String>>();

    client.setQueryDefaults(key, QueryDefaults(queryFn: (_) => 'data'));

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        rec.build(useQuery(
          QueryObserverOptions<String>(queryKey: key),
          buildWhen: rec.buildWhen,
        ));
        return const SizedBox();
      }),
    );

    await advance(tester, 0);
    expect(rec.builds, hasLength(2));
    expect(rec.builds[0].dataOrNull, isNull);
    expect(rec.builds[1].dataOrNull, 'data');
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

  // useQuery.test.tsx:507 — `notifyOnChangeProps: ['isPending',
  // 'isSuccess', 'data']` is a `buildWhen` over the same three fields (#15,
  // plan D8).
  hookTest(
      'should not get into an infinite loop when removing a query with gcTime '
      '0 and rerendering', (tester, client) async {
    final key = queryKey();
    final rec = Recorder<QueryResult<String>>();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final rerender = useState(0);

        final state = rec.build(useQuery(
          QueryObserverOptions<String>(
            queryKey: key,
            queryFn: (_) => sleep(5).then((_) => 'data'),
            gcTime: const GcTime.duration(Duration.zero),
          ),
          buildWhen: rec.around((previous, current) =>
              previous.isPending != current.isPending ||
              previous.isSuccess != current.isSuccess ||
              previous.dataOrNull != current.dataOrNull),
        ));

        return Column(children: [
          Text(state.dataOrNull ?? ''),
          TextButton(
            onPressed: () {
              client.removeQueries(filters: QueryFilters(queryKey: key));
              rerender.value++;
            },
            child: const Text('remove'),
          ),
        ]);
      }),
    );

    await advance(tester, 6);
    expect(find.text('data'), findsOneWidget);

    await click(tester, 'remove');

    await advance(tester, 6);
    expect(find.text('data'), findsOneWidget);

    expect(rec.builds, hasLength(4));
    // First load
    expect(rec.builds[0].isPending, isTrue);
    expect(rec.builds[0].isSuccess, isFalse);
    expect(rec.builds[0].dataOrNull, isNull);
    // First success
    expect(rec.builds[1].isPending, isFalse);
    expect(rec.builds[1].isSuccess, isTrue);
    expect(rec.builds[1].dataOrNull, 'data');
    // Remove
    expect(rec.builds[2].isPending, isTrue);
    expect(rec.builds[2].isSuccess, isFalse);
    expect(rec.builds[2].dataOrNull, isNull);
    // Second success
    expect(rec.builds[3].isPending, isFalse);
    expect(rec.builds[3].isSuccess, isTrue);
    expect(rec.builds[3].dataOrNull, 'data');
  });

  // useQuery.test.tsx:577
  hookTest(
      'should fetch when refetchOnMount is false and nothing has been fetched '
      'yet', (tester, client) async {
    final key = queryKey();
    final rec = Recorder<QueryResult<String>>();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        rec.build(useQuery(
          QueryObserverOptions<String>(
            queryKey: key,
            queryFn: (_) => 'test',
            refetchOnMount: RefetchOn.never,
          ),
          buildWhen: rec.buildWhen,
        ));
        return const SizedBox();
      }),
    );

    await advance(tester, 0);
    expect(rec.builds, hasLength(2));
    expect(rec.builds[0].dataOrNull, isNull);
    expect(rec.builds[1].dataOrNull, 'test');
  });

  // useQuery.test.tsx:599
  hookTest(
      'should not fetch when refetchOnMount is false and data has been fetched '
      'already', (tester, client) async {
    final key = queryKey();
    final rec = Recorder<QueryResult<String>>();

    client.setQueryData(key, 'prefetched');

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        rec.build(useQuery(
          QueryObserverOptions<String>(
            queryKey: key,
            queryFn: (_) => 'test',
            refetchOnMount: RefetchOn.never,
          ),
          buildWhen: rec.buildWhen,
        ));
        return const SizedBox();
      }),
    );
    expect(rec.builds, hasLength(1));
    expect(rec.builds[0].dataOrNull, 'prefetched');
  });

  // useQuery.test.tsx:621
  hookTest('should be able to select a part of the data with select',
      (tester, client) async {
    final key = queryKey();
    final rec = Recorder<QueryResult<String>>();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final state = rec.build(useSelectQuery(
          QuerySelectOptions<({String name}), String>(
            queryKey: key,
            queryFn: (_) => (name: 'test'),
            select: (data) => data.name,
          ),
          buildWhen: rec.buildWhen,
        ));
        return Text(state.dataOrNull ?? '');
      }),
    );

    await advance(tester, 0);
    expect(find.text('test'), findsOneWidget);

    expect(rec.builds, hasLength(2));
    expect(rec.builds[0].dataOrNull, isNull);
    expect(rec.builds[1].dataOrNull, 'test');
  });

  // useQuery.test.tsx:646
  hookTest(
      'should be able to select a part of the data with select in object '
      'syntax', (tester, client) async {
    final key = queryKey();
    final rec = Recorder<QueryResult<String>>();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final state = rec.build(useSelectQuery(
          QuerySelectOptions<({String name}), String>(
            queryKey: key,
            queryFn: (_) => (name: 'test'),
            select: (data) => data.name,
          ),
          buildWhen: rec.buildWhen,
        ));
        return Text(state.dataOrNull ?? '');
      }),
    );

    await advance(tester, 0);
    expect(find.text('test'), findsOneWidget);

    expect(rec.builds, hasLength(2));
    expect(rec.builds[0].dataOrNull, isNull);
    expect(rec.builds[1].dataOrNull, 'test');
  });

  // useQuery.test.tsx:671
  hookTest('should throw an error when a selector throws',
      (tester, client) async {
    final key = queryKey();
    final rec = Recorder<QueryResult<String>>();
    final error = StateError('Select Error');

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final state = rec.build(useSelectQuery(
          QuerySelectOptions<({String name}), String>(
            queryKey: key,
            queryFn: (_) => (name: 'test'),
            select: (_) => throw error,
          ),
          buildWhen: rec.buildWhen,
        ));
        return Text(state.status.name);
      }),
    );

    await advance(tester, 0);
    expect(find.text('error'), findsOneWidget);

    expect(rec.builds, hasLength(2));

    expect(rec.builds[0].status, QueryStatus.pending);
    expect(rec.builds[0].dataOrNull, isNull);
    expect(rec.builds[1].status, QueryStatus.error);
    expect(rec.builds[1].errorOrNull, same(error));
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

  // useQuery.test.tsx:779
  hookTest('should always re-render if we are tracking props but not using any',
      (tester, client) async {
    final key = queryKey();
    var renderCount = 0;
    final rec = Recorder<QueryResult<String>>();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final state = rec.build(useQuery(
          QueryObserverOptions<String>(queryKey: key, queryFn: (_) => 'test'),
          buildWhen: rec.buildWhen,
        ));

        useEffect(() {
          renderCount++;
          return null;
        }, [state]);

        return const Text('hello');
      }),
    );

    await advance(tester, 0);
    expect(renderCount, 2);
    expect(rec.builds, hasLength(2));
    expect(rec.builds[0].dataOrNull, isNull);
    expect(rec.builds[1].dataOrNull, 'test');
  });

  // useQuery.test.tsx:809
  hookTest('should be able to remove a query', (tester, client) async {
    final key = queryKey();
    final rec = Recorder<QueryResult<int>>();
    var count = 0;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final rerender = useState(0);
        final state = rec.build(useQuery(
          QueryObserverOptions<int>(queryKey: key, queryFn: (_) => ++count),
          buildWhen: rec.buildWhen,
        ));

        return Column(children: [
          TextButton(
            onPressed: () =>
                client.removeQueries(filters: QueryFilters(queryKey: key)),
            child: const Text('remove'),
          ),
          TextButton(
            onPressed: () => rerender.value++,
            child: const Text('rerender'),
          ),
          Text('data: ${state.dataOrNull ?? 'null'}'),
        ]);
      }),
    );

    await advance(tester, 0);
    expect(find.text('data: 1'), findsOneWidget);
    await click(tester, 'remove');

    await advance(tester, 0);
    await click(tester, 'rerender');
    await advance(tester, 0);
    expect(find.text('data: 2'), findsOneWidget);

    expect(rec.builds, hasLength(4));
    // Initial
    expect(rec.builds[0].status, QueryStatus.pending);
    expect(rec.builds[0].dataOrNull, isNull);
    // Fetched
    expect(rec.builds[1].status, QueryStatus.success);
    expect(rec.builds[1].dataOrNull, 1);
    // Remove + Hook state update, batched
    expect(rec.builds[2].status, QueryStatus.pending);
    expect(rec.builds[2].dataOrNull, isNull);
    // Fetched
    expect(rec.builds[3].status, QueryStatus.success);
    expect(rec.builds[3].dataOrNull, 2);
  });

  // useQuery.test.tsx:857
  hookTest('should create a new query when refetching a removed query',
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
            queryFn: (_) => sleep(10).then((_) => ++count),
          ),
          buildWhen: rec.buildWhen,
        ));

        final refetch = state.refetch;

        return Column(children: [
          TextButton(
            onPressed: () =>
                client.removeQueries(filters: QueryFilters(queryKey: key)),
            child: const Text('remove'),
          ),
          TextButton(onPressed: refetch, child: const Text('refetch')),
          Text('data: ${state.dataOrNull ?? 'null'}'),
        ]);
      }),
    );

    await advance(tester, 11);
    expect(find.text('data: 1'), findsOneWidget);
    await click(tester, 'remove');
    await click(tester, 'refetch');
    await advance(tester, 11);
    expect(find.text('data: 2'), findsOneWidget);

    expect(rec.builds, hasLength(4));
    // Initial
    expect(rec.builds[0].dataOrNull, isNull);
    expect(rec.builds[0].dataUpdatedAt, isNull);
    // Fetched
    expect(rec.builds[1].dataOrNull, 1);
    // Switch
    expect(rec.builds[2].dataOrNull, isNull);
    expect(rec.builds[2].dataUpdatedAt, isNull);
    // Fetched
    expect(rec.builds[3].dataOrNull, 2);
  });

  // useQuery.test.tsx:904
  hookTest('should share equal data structures between query results',
      (tester, client) async {
    final key = queryKey();

    final result1 = [
      {'id': '1', 'done': false},
      {'id': '2', 'done': false},
    ];

    final result2 = [
      {'id': '1', 'done': false},
      {'id': '2', 'done': true},
    ];

    final rec = Recorder<QueryResult<List<Map<String, Object>>>>();

    var count = 0;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final state = rec.build(useQuery(
          QueryObserverOptions<List<Map<String, Object>>>(
            queryKey: key,
            queryFn: (_) => sleep(10).then((_) {
              count++;
              return count == 1 ? result1 : result2;
            }),
          ),
          buildWhen: rec.buildWhen,
        ));

        final refetch = state.refetch;

        return Column(children: [
          TextButton(onPressed: refetch, child: const Text('refetch')),
          Text('data: ${state.dataOrNull?[1]['done']}'),
        ]);
      }),
    );

    await advance(tester, 11);
    expect(find.text('data: false'), findsOneWidget);
    await click(tester, 'refetch');
    await advance(tester, 11);
    expect(find.text('data: true'), findsOneWidget);

    expect(rec.builds, hasLength(4));

    final todos = rec.builds[2].dataOrNull;
    final todo1 = todos?[0];
    final todo2 = todos?[1];

    final newTodos = rec.builds[3].dataOrNull;
    final newTodo1 = newTodos?[0];
    final newTodo2 = newTodos?[1];

    expect(todos, result1);
    expect(newTodos, result2);
    expect(newTodos, isNot(same(todos)));
    expect(newTodo1, same(todo1));
    expect(newTodo2, isNot(same(todo2)));
  });

  // useQuery.test.tsx:971
  hookTest(
      'should use query function from hook when the existing query does not '
      'have a query function', (tester, client) async {
    final key = queryKey();

    client.setQueryData(key, 'set');

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final result = useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) => sleep(10).then((_) => 'fetched'),
          initialData: const InitialData.value('initial'),
          staleTime: StaleTime.infinite,
        ));

        return Column(children: [
          Text('isFetching: ${result.isFetching}'),
          TextButton(
            onPressed: () =>
                client.refetchQueries(filters: QueryFilters(queryKey: key)),
            child: const Text('refetch'),
          ),
          Text('data: ${result.dataOrNull}'),
        ]);
      }),
    );

    await advance(tester, 11);
    expect(find.text('data: set'), findsOneWidget);
    await click(tester, 'refetch');
    await advance(tester, 11);
    expect(find.text('data: fetched'), findsOneWidget);
  });

  // useQuery.test.tsx:1005
  hookTest(
      'should update query stale state and refetch when invalidated with '
      'invalidateQueries', (tester, client) async {
    final key = queryKey();
    var count = 0;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final state = useQuery(QueryObserverOptions<int>(
          queryKey: key,
          queryFn: (_) => sleep(10).then((_) {
            count++;
            return count;
          }),
          staleTime: StaleTime.infinite,
        ));

        return Column(children: [
          TextButton(
            onPressed: () =>
                client.invalidateQueries(filters: QueryFilters(queryKey: key)),
            child: const Text('invalidate'),
          ),
          Text('data: ${state.dataOrNull}, isStale: ${state.isStale}, '
              'isFetching: ${state.isFetching}'),
        ]);
      }),
    );

    await advance(tester, 11);
    expect(
      find.text('data: 1, isStale: false, isFetching: false'),
      findsOneWidget,
    );
    await click(tester, 'invalidate');
    await advance(tester, 0);
    expect(
      find.text('data: 1, isStale: true, isFetching: true'),
      findsOneWidget,
    );
    await advance(tester, 11);
    expect(
      find.text('data: 2, isStale: false, isFetching: false'),
      findsOneWidget,
    );
  });

  // useQuery.test.tsx:1050
  hookTest(
      'should not update disabled query when refetching with refetchQueries',
      (tester, client) async {
    final key = queryKey();
    final rec = Recorder<QueryResult<int>>();
    var count = 0;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        rec.build(useQuery(
          QueryObserverOptions<int>(
            queryKey: key,
            queryFn: (_) => sleep(10).then((_) {
              count++;
              return count;
            }),
            enabled: Enabled.no,
          ),
          buildWhen: rec.buildWhen,
        ));

        useEffect(() {
          final timer = Timer(
            _ms(20),
            () => client.refetchQueries(filters: QueryFilters(queryKey: key)),
          );
          return timer.cancel;
        }, const []);

        return const SizedBox();
      }),
    );

    await advance(tester, 31);

    expect(rec.builds, hasLength(1));
    expect(rec.builds[0].dataOrNull, isNull);
    expect(rec.builds[0].isFetching, isFalse);
    expect(rec.builds[0].isSuccess, isFalse);
    expect(rec.builds[0].isStale, isFalse);
  });

  // useQuery.test.tsx:1090
  hookTest(
      'should not refetch disabled query when invalidated with '
      'invalidateQueries', (tester, client) async {
    final key = queryKey();
    final rec = Recorder<QueryResult<int>>();
    var count = 0;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        rec.build(useQuery(
          QueryObserverOptions<int>(
            queryKey: key,
            queryFn: (_) => sleep(10).then((_) {
              count++;
              return count;
            }),
            enabled: Enabled.no,
          ),
          buildWhen: rec.buildWhen,
        ));

        useEffect(() {
          final timer = Timer(
            _ms(10),
            () =>
                client.invalidateQueries(filters: QueryFilters(queryKey: key)),
          );
          return timer.cancel;
        }, const []);

        return const SizedBox();
      }),
    );
    expect(rec.builds, hasLength(1));
    expect(rec.builds[0].dataOrNull, isNull);
    expect(rec.builds[0].isFetching, isFalse);
    expect(rec.builds[0].isSuccess, isFalse);
    expect(rec.builds[0].isStale, isFalse);
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

  // useQuery.test.tsx:1248
  hookTest(
      'should keep the previous data when placeholderData is set and select '
      'fn transform is used', (tester, client) async {
    final key = queryKey();
    final rec = Recorder<QueryResult<int>>();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final count = useState(0);
        final c = count.value;

        final state = rec.build(useSelectQuery(
          QuerySelectOptions<({int count}), int>(
            queryKey: QueryKey([...key.parts, c]),
            queryFn: (_) => sleep(10).then((_) => (count: c)),
            select: (data) => data.count,
            placeholderData: const PlaceholderData.keepPrevious(),
          ),
          buildWhen: rec.buildWhen,
        ));

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
    expect(rec.builds[0].dataOrNull, isNull);
    expect(rec.builds[0].isFetching, isTrue);
    expect(rec.builds[0].isSuccess, isFalse);
    expect(rec.builds[0].isPlaceholderData, isFalse);
    // Fetched
    expect(rec.builds[1].dataOrNull, 0);
    expect(rec.builds[1].isFetching, isFalse);
    expect(rec.builds[1].isSuccess, isTrue);
    expect(rec.builds[1].isPlaceholderData, isFalse);
    // Set state
    expect(rec.builds[2].dataOrNull, 0);
    expect(rec.builds[2].isFetching, isTrue);
    expect(rec.builds[2].isSuccess, isTrue);
    expect(rec.builds[2].isPlaceholderData, isTrue);
    // New data
    expect(rec.builds[3].dataOrNull, 1);
    expect(rec.builds[3].isFetching, isFalse);
    expect(rec.builds[3].isSuccess, isTrue);
    expect(rec.builds[3].isPlaceholderData, isFalse);
  });

  // useQuery.test.tsx:1314
  hookTest(
      'should keep the previous queryKey (from prevQuery) between multiple '
      'pending queries when placeholderData is set and select fn transform '
      'is used', (tester, client) async {
    final keys = <QueryKey>[];
    final key = queryKey();
    final rec = Recorder<QueryResult<int>>();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final count = useState(0);
        final c = count.value;

        final state = rec.build(useSelectQuery(
          QuerySelectOptions<({int count}), int>(
            queryKey: QueryKey([...key.parts, c]),
            queryFn: (_) => sleep(10).then((_) => (count: c)),
            select: (data) => data.count,
            placeholderData: PlaceholderData.compute((prevData, prevQuery) {
              if (prevQuery != null) {
                keys.add(prevQuery.queryKey);
              }
              return prevData;
            }),
          ),
          buildWhen: rec.buildWhen,
        ));

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
    await click(tester, 'setCount');
    await click(tester, 'setCount');

    await advance(tester, 11);
    expect(find.text('data: 3'), findsOneWidget);

    final allPreviousKeysAreTheFirstQueryKey =
        keys.every((k) => k == QueryKey([...key.parts, 0]));

    expect(allPreviousKeysAreTheFirstQueryKey, isTrue);
  });

  // useQuery.test.tsx:1365
  hookTest(
      'should show placeholderData between multiple pending queries when '
      'select fn transform is used', (tester, client) async {
    final key = queryKey();
    final rec = Recorder<QueryResult<int>>();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final count = useState(0);
        final c = count.value;

        final state = rec.build(useSelectQuery(
          QuerySelectOptions<({int count}), int>(
            queryKey: QueryKey([...key.parts, c]),
            queryFn: (_) => sleep(10).then((_) => (count: c)),
            select: (data) => data.count,
            placeholderData: const PlaceholderData.keepPrevious(),
          ),
          buildWhen: rec.buildWhen,
        ));

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
    await click(tester, 'setCount');
    await click(tester, 'setCount');

    await advance(tester, 11);
    expect(find.text('data: 3'), findsOneWidget);
    // Initial
    expect(rec.builds[0].dataOrNull, isNull);
    expect(rec.builds[0].isFetching, isTrue);
    expect(rec.builds[0].isSuccess, isFalse);
    expect(rec.builds[0].isPlaceholderData, isFalse);
    // Fetched
    expect(rec.builds[1].dataOrNull, 0);
    expect(rec.builds[1].isFetching, isFalse);
    expect(rec.builds[1].isSuccess, isTrue);
    expect(rec.builds[1].isPlaceholderData, isFalse);
    // Set state -> count = 1
    expect(rec.builds[2].dataOrNull, 0);
    expect(rec.builds[2].isFetching, isTrue);
    expect(rec.builds[2].isSuccess, isTrue);
    expect(rec.builds[2].isPlaceholderData, isTrue);
    // Set state -> count = 2
    expect(rec.builds[3].dataOrNull, 0);
    expect(rec.builds[3].isFetching, isTrue);
    expect(rec.builds[3].isSuccess, isTrue);
    expect(rec.builds[3].isPlaceholderData, isTrue);
    // Set state -> count = 3
    expect(rec.builds[4].dataOrNull, 0);
    expect(rec.builds[4].isFetching, isTrue);
    expect(rec.builds[4].isSuccess, isTrue);
    expect(rec.builds[4].isPlaceholderData, isTrue);
    // New data
    expect(rec.builds[5].dataOrNull, 3);
    expect(rec.builds[5].isFetching, isFalse);
    expect(rec.builds[5].isSuccess, isTrue);
    expect(rec.builds[5].isPlaceholderData, isFalse);
  });

  // useQuery.test.tsx:1446
  hookTest('should transition to error state when placeholderData is set',
      (tester, client) async {
    final key = queryKey();
    final rec = Recorder<QueryResult<int>>();

    Widget page(int count) => HookBuilder(builder: (context) {
          final state = rec.build(useQuery(
            QueryObserverOptions<int>(
              queryKey: QueryKey([...key.parts, count]),
              queryFn: (_) => sleep(10).then((_) {
                if (count == 2) {
                  throw StateError('Error test');
                }
                return count;
              }),
              retry: RetryPolicy.never,
              placeholderData: const PlaceholderData.keepPrevious(),
            ),
            buildWhen: rec.buildWhen,
          ));

          return Column(children: [
            Text('data: ${state.dataOrNull}'),
            Text('error: ${_message(state.errorOrNull) ?? ''}'),
            Text('placeholder data: ${state.isPlaceholderData}'),
          ]);
        });

    await tester.pumpApp(client, page(0));

    await advance(tester, 11);
    expect(find.text('data: 0'), findsOneWidget);
    await tester.pumpApp(client, page(1));
    await advance(tester, 11);
    expect(find.text('data: 1'), findsOneWidget);
    await tester.pumpApp(client, page(2));
    await advance(tester, 11);
    expect(find.text('error: Error test'), findsOneWidget);

    expect(rec.builds, hasLength(6));
    // Initial
    expect(rec.builds[0].dataOrNull, isNull);
    expect(rec.builds[0].isFetching, isTrue);
    expect(rec.builds[0].status, QueryStatus.pending);
    expect(rec.builds[0].errorOrNull, isNull);
    expect(rec.builds[0].isPlaceholderData, isFalse);
    // Fetched
    expect(rec.builds[1].dataOrNull, 0);
    expect(rec.builds[1].isFetching, isFalse);
    expect(rec.builds[1].status, QueryStatus.success);
    expect(rec.builds[1].errorOrNull, isNull);
    expect(rec.builds[1].isPlaceholderData, isFalse);
    // rerender Page 1
    expect(rec.builds[2].dataOrNull, 0);
    expect(rec.builds[2].isFetching, isTrue);
    expect(rec.builds[2].status, QueryStatus.success);
    expect(rec.builds[2].errorOrNull, isNull);
    expect(rec.builds[2].isPlaceholderData, isTrue);
    // New data
    expect(rec.builds[3].dataOrNull, 1);
    expect(rec.builds[3].isFetching, isFalse);
    expect(rec.builds[3].status, QueryStatus.success);
    expect(rec.builds[3].errorOrNull, isNull);
    expect(rec.builds[3].isPlaceholderData, isFalse);
    // rerender Page 2
    expect(rec.builds[4].dataOrNull, 1);
    expect(rec.builds[4].isFetching, isTrue);
    expect(rec.builds[4].status, QueryStatus.success);
    expect(rec.builds[4].errorOrNull, isNull);
    expect(rec.builds[4].isPlaceholderData, isTrue);
    // Error
    expect(rec.builds[5].dataOrNull, isNull);
    expect(rec.builds[5].isFetching, isFalse);
    expect(rec.builds[5].status, QueryStatus.error);
    expect(rec.builds[5].isPlaceholderData, isFalse);
    expect(_message(rec.builds[5].errorOrNull), 'Error test');
  });

  // useQuery.test.tsx:1537
  hookTest(
      'should not show initial data from next query if placeholderData is set',
      (tester, client) async {
    final key = queryKey();
    final rec = Recorder<QueryResult<int>>();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final count = useState(0);
        final c = count.value;

        final state = rec.build(useQuery(
          QueryObserverOptions<int>(
            queryKey: QueryKey([...key.parts, c]),
            queryFn: (_) => sleep(10).then((_) => c),
            initialData: const InitialData.value(99),
            placeholderData: const PlaceholderData.keepPrevious(),
          ),
          buildWhen: rec.buildWhen,
        ));

        return Column(children: [
          Text('data: ${state.dataOrNull}, count: $c, isFetching: '
              '${state.isFetching}'),
          TextButton(
            onPressed: () => count.value = 1,
            child: const Text('inc'),
          ),
        ]);
      }),
    );

    await advance(tester, 11);
    expect(find.text('data: 0, count: 0, isFetching: false'), findsOneWidget);

    await click(tester, 'inc');

    await advance(tester, 11);
    expect(find.text('data: 1, count: 1, isFetching: false'), findsOneWidget);

    expect(rec.builds, hasLength(4));

    // Initial
    expect(rec.builds[0].dataOrNull, 99);
    expect(rec.builds[0].isFetching, isTrue);
    expect(rec.builds[0].isSuccess, isTrue);
    expect(rec.builds[0].isPlaceholderData, isFalse);
    // Fetched
    expect(rec.builds[1].dataOrNull, 0);
    expect(rec.builds[1].isFetching, isFalse);
    expect(rec.builds[1].isSuccess, isTrue);
    expect(rec.builds[1].isPlaceholderData, isFalse);
    // Set state
    expect(rec.builds[2].dataOrNull, 99);
    expect(rec.builds[2].isFetching, isTrue);
    expect(rec.builds[2].isSuccess, isTrue);
    expect(rec.builds[2].isPlaceholderData, isFalse);
    // New data
    expect(rec.builds[3].dataOrNull, 1);
    expect(rec.builds[3].isFetching, isFalse);
    expect(rec.builds[3].isSuccess, isTrue);
    expect(rec.builds[3].isPlaceholderData, isFalse);
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

  // useQuery.test.tsx:1697
  hookTest(
      'should keep the previous data on disabled query when placeholderData '
      'is set and switching query key multiple times', (tester, client) async {
    final key = queryKey();
    final rec = Recorder<QueryResult<int>>();

    client.setQueryData(QueryKey([...key.parts, 10]), 10);

    await advance(tester, 10);

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final count = useState(10);
        final c = count.value;

        final state = rec.build(useQuery(
          QueryObserverOptions<int>(
            queryKey: QueryKey([...key.parts, c]),
            queryFn: (_) => sleep(10).then((_) => c),
            enabled: Enabled.no,
            placeholderData: const PlaceholderData.keepPrevious(),
          ),
          buildWhen: rec.buildWhen,
        ));

        final refetch = state.refetch;

        useEffect(() {
          final timers = [
            Timer(_ms(20), () => count.value = 11),
            Timer(_ms(30), () => count.value = 12),
            Timer(_ms(40), refetch),
          ];
          return () => _cancelAll(timers);
        }, [refetch]);

        return const SizedBox();
      }),
    );

    await advance(tester, 51);

    expect(rec.builds, hasLength(5));

    // Disabled query
    expect(rec.builds[0].dataOrNull, 10);
    expect(rec.builds[0].isFetching, isFalse);
    expect(rec.builds[0].isSuccess, isTrue);
    expect(rec.builds[0].isPlaceholderData, isFalse);
    // Set state
    expect(rec.builds[1].dataOrNull, 10);
    expect(rec.builds[1].isFetching, isFalse);
    expect(rec.builds[1].isSuccess, isTrue);
    expect(rec.builds[1].isPlaceholderData, isTrue);
    // State update
    expect(rec.builds[2].dataOrNull, 10);
    expect(rec.builds[2].isFetching, isFalse);
    expect(rec.builds[2].isSuccess, isTrue);
    expect(rec.builds[2].isPlaceholderData, isTrue);
    // Refetch
    expect(rec.builds[3].dataOrNull, 10);
    expect(rec.builds[3].isFetching, isTrue);
    expect(rec.builds[3].isSuccess, isTrue);
    expect(rec.builds[3].isPlaceholderData, isTrue);
    // Refetch done
    expect(rec.builds[4].dataOrNull, 12);
    expect(rec.builds[4].isFetching, isFalse);
    expect(rec.builds[4].isSuccess, isTrue);
    expect(rec.builds[4].isPlaceholderData, isFalse);
  });

  // useQuery.test.tsx:1778
  hookTest(
      'should use the correct query function when components use different '
      'configurations', (tester, client) async {
    final key = queryKey();
    final rec = Recorder<QueryResult<int>>();

    final firstComponent = HookBuilder(builder: (context) {
      final state = rec.build(useQuery(
        QueryObserverOptions<int>(
          queryKey: key,
          queryFn: (_) => sleep(10).then((_) => 1),
        ),
        buildWhen: rec.buildWhen,
      ));
      final refetch = state.refetch;

      return Column(children: [
        TextButton(onPressed: refetch, child: const Text('refetch')),
        Text('data: ${state.dataOrNull}'),
      ]);
    });

    final secondComponent = HookBuilder(builder: (context) {
      useQuery(QueryObserverOptions<int>(queryKey: key, queryFn: (_) => 2));
      return const SizedBox();
    });

    await tester.pumpApp(
      client,
      Column(children: [firstComponent, secondComponent]),
    );

    await advance(tester, 11);
    expect(find.text('data: 1'), findsOneWidget);
    await click(tester, 'refetch');

    await advance(tester, 11);
    expect(rec.builds, hasLength(4));

    expect(rec.builds[0].dataOrNull, isNull);
    expect(rec.builds[1].dataOrNull, 1);
    expect(rec.builds[2].dataOrNull, 1);
    // This state should be 1 instead of 2
    expect(rec.builds[3].dataOrNull, 1);
  });

  // useQuery.test.tsx:1838
  hookTest('should be able to set different stale times for a query',
      (tester, client) async {
    final key = queryKey();
    final rec1 = Recorder<QueryResult<String>>();
    final rec2 = Recorder<QueryResult<String>>();

    unawaited(prefetch(
      client,
      QueryOptions<String>(
        queryKey: key,
        queryFn: (_) => sleep(10).then((_) => 'prefetch'),
      ),
    ));

    await advance(tester, 20);

    final firstComponent = HookBuilder(builder: (context) {
      rec1.build(useQuery(
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) => sleep(10).then((_) => 'one'),
          staleTime: const StaleTime.duration(Duration(milliseconds: 100)),
        ),
        buildWhen: rec1.buildWhen,
      ));
      return const SizedBox();
    });

    final secondComponent = HookBuilder(builder: (context) {
      rec2.build(useQuery(
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) => sleep(10).then((_) => 'two'),
          staleTime: const StaleTime.duration(Duration(milliseconds: 10)),
        ),
        buildWhen: rec2.buildWhen,
      ));
      return const SizedBox();
    });

    await tester.pumpApp(
      client,
      Column(children: [firstComponent, secondComponent]),
    );

    await advance(tester, 200);

    expect(rec1.builds, hasLength(4));
    expect(rec2.builds, hasLength(3));

    // First render
    expect(rec1.builds[0].dataOrNull, 'prefetch');
    expect(rec1.builds[0].isStale, isFalse);
    // Second useQuery started fetching
    expect(rec1.builds[1].dataOrNull, 'prefetch');
    expect(rec1.builds[1].isStale, isFalse);
    // Second useQuery data came in
    expect(rec1.builds[2].dataOrNull, 'two');
    expect(rec1.builds[2].isStale, isFalse);
    // Data became stale after 100ms
    expect(rec1.builds[3].dataOrNull, 'two');
    expect(rec1.builds[3].isStale, isTrue);

    // First render, data is stale and starts fetching
    expect(rec2.builds[0].dataOrNull, 'prefetch');
    expect(rec2.builds[0].isStale, isTrue);
    // Second useQuery data came in
    expect(rec2.builds[1].dataOrNull, 'two');
    expect(rec2.builds[1].isStale, isFalse);
    // Data became stale after 5ms
    expect(rec2.builds[2].dataOrNull, 'two');
    expect(rec2.builds[2].isStale, isTrue);
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

  group('notifyOnChangeProps', () {
    // useQuery.test.tsx:2016 — `notifyOnChangeProps: ['data']` is a
    // `buildWhen` on the data (#15, plan D8).
    hookTest(
        'should not re-render when it should only re-render only data change '
        'and the selected data did not change', (tester, client) async {
      final key = queryKey();
      final rec = Recorder<QueryResult<String>>();

      await tester.pumpApp(
        client,
        HookBuilder(builder: (context) {
          final state = rec.build(useSelectQuery(
            QuerySelectOptions<({String name}), String>(
              queryKey: key,
              queryFn: (_) => (name: 'test'),
              select: (data) => data.name,
            ),
            buildWhen: rec.around((previous, current) =>
                previous.dataOrNull != current.dataOrNull),
          ));

          return Column(children: [
            Text(state.dataOrNull ?? ''),
            TextButton(
              onPressed: state.refetch,
              child: const Text('refetch'),
            ),
          ]);
        }),
      );

      await advance(tester, 0);
      expect(find.text('test'), findsOneWidget);

      await click(tester, 'refetch');

      await advance(tester, 0);
      expect(find.text('test'), findsOneWidget);

      expect(rec.builds[0].dataOrNull, isNull);
      expect(rec.builds[1].dataOrNull, 'test');

      // make sure no additional renders happen
      await advance(tester, 50);
      expect(rec.builds, hasLength(2));
    });

    // useQuery.test.tsx:2055 — `notifyOnChangeProps: ['data']` is a
    // `buildWhen` on the data (#15, plan D8).
    hookTest(
        'should not re-render when it should only re-render on data changes '
        'and the data did not change', (tester, client) async {
      final key = queryKey();
      final rec = Recorder<QueryResult<String>>();

      await tester.pumpApp(
        client,
        HookBuilder(builder: (context) {
          final state = rec.build(useQuery(
            QueryObserverOptions<String>(
              queryKey: key,
              queryFn: (_) => sleep(5).then((_) => 'test'),
            ),
            buildWhen: rec.around((previous, current) =>
                previous.dataOrNull != current.dataOrNull),
          ));

          return Column(children: [
            TextButton(
              onPressed: () async {
                await state.refetch();
              },
              child: const Text('refetch'),
            ),
            Text(state.dataOrNull ?? ''),
          ]);
        }),
      );

      await advance(tester, 6);
      expect(find.text('test'), findsOneWidget);

      await click(tester, 'refetch');

      // sleep is required to make sure no additional renders happen after
      // click
      await advance(tester, 20);

      expect(rec.builds, hasLength(2));
      expect(rec.builds[0].dataOrNull, isNull);
      expect(rec.builds[0].status, QueryStatus.pending);
      expect(rec.builds[0].isFetching, isTrue);
      expect(rec.builds[1].dataOrNull, 'test');
      expect(rec.builds[1].status, QueryStatus.success);
      expect(rec.builds[1].isFetching, isFalse);
    });

    group('function', () {
      // useQuery.test.tsx:2109 — `notifyOnChangeProps: () => ['data']` is a
      // `buildWhen` on the data (#15, plan D8).
      hookTest(
          'should not re-render when it should only re-render on data '
          'changes and the data did not change', (tester, client) async {
        final key = queryKey();
        final rec = Recorder<QueryResult<String>>();

        await tester.pumpApp(
          client,
          HookBuilder(builder: (context) {
            final state = rec.build(useQuery(
              QueryObserverOptions<String>(
                queryKey: key,
                queryFn: (_) => sleep(5).then((_) => 'test'),
              ),
              buildWhen: rec.around((previous, current) =>
                  previous.dataOrNull != current.dataOrNull),
            ));

            return Column(children: [
              TextButton(
                onPressed: () async {
                  await state.refetch();
                },
                child: const Text('refetch'),
              ),
              Text(state.dataOrNull ?? ''),
            ]);
          }),
        );

        await advance(tester, 6);
        expect(find.text('test'), findsOneWidget);

        await click(tester, 'refetch');

        await advance(tester, 20);

        expect(rec.builds, hasLength(2));
        expect(rec.builds[0].dataOrNull, isNull);
        expect(rec.builds[0].status, QueryStatus.pending);
        expect(rec.builds[0].isFetching, isTrue);
        expect(rec.builds[1].dataOrNull, 'test');
        expect(rec.builds[1].status, QueryStatus.success);
        expect(rec.builds[1].isFetching, isFalse);
      });

      // useQuery.test.tsx:2159 — the `notifyOnChangeProps` callback that
      // answers `'all'` or `[]` from a ref is a `buildWhen` that answers
      // from the same ref (#15, plan D8).
      hookTest(
          'should not re-render when change props are not actively being '
          'tracked', (tester, client) async {
        final key = queryKey();
        final rec = Recorder<QueryResult<String>>();

        await tester.pumpApp(
          client,
          HookBuilder(builder: (context) {
            final fetchCounterRef = useRef(0);
            final trackChangesRef = useRef(true);

            final notifyOnChangeProps =
                useCallback<BuildWhen<QueryResult<String>>>(
              (previous, current) => trackChangesRef.value,
              const [],
            );

            final state = rec.build(useQuery(
              QueryObserverOptions<String>(
                queryKey: key,
                queryFn: (_) => sleep(5).then(
                  (_) => 'fetch counter: ${++fetchCounterRef.value}',
                ),
              ),
              buildWhen: rec.around(notifyOnChangeProps),
            ));

            return Column(children: [
              TextButton(
                onPressed: () async {
                  await state.refetch();
                },
                child: const Text('refetch'),
              ),
              TextButton(
                onPressed: () => trackChangesRef.value = true,
                child: const Text('enableTracking'),
              ),
              TextButton(
                onPressed: () => trackChangesRef.value = false,
                child: const Text('disableTracking'),
              ),
              Text(state.dataOrNull ?? ''),
            ]);
          }),
        );

        await advance(tester, 6);
        expect(find.text('fetch counter: 1'), findsOneWidget);

        expect(rec.builds, hasLength(2));
        expect(rec.builds[0].dataOrNull, isNull);
        expect(rec.builds[0].isFetching, isTrue);
        expect(rec.builds[0].status, QueryStatus.pending);
        expect(rec.builds[1].dataOrNull, 'fetch counter: 1');
        expect(rec.builds[1].status, QueryStatus.success);
        expect(rec.builds[1].isFetching, isFalse);

        // disable tracking and refetch to check for re-renders
        await click(tester, 'disableTracking');
        await click(tester, 'refetch');

        await advance(tester, 20);
        // still expect to only have two re-renders from the initial fetch
        expect(rec.builds, hasLength(2));

        // enable tracking and refetch to check for re-renders
        await click(tester, 'enableTracking');
        await click(tester, 'refetch');

        await advance(tester, 6);
        expect(find.text('fetch counter: 3'), findsOneWidget);
        await advance(tester, 20);

        expect(rec.builds, hasLength(4));
        expect(rec.builds[2].dataOrNull, 'fetch counter: 2');
        expect(rec.builds[2].status, QueryStatus.success);
        expect(rec.builds[2].isFetching, isTrue);
        expect(rec.builds[3].dataOrNull, 'fetch counter: 3');
        expect(rec.builds[3].status, QueryStatus.success);
        expect(rec.builds[3].isFetching, isFalse);
      });
    });
  });

  // useQuery.test.tsx:2263
  hookTest('should not override initial data in dependent queries',
      (tester, client) async {
    final key1 = queryKey();
    final key2 = queryKey();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final first = useQuery(QueryObserverOptions<String>(
          queryKey: key1,
          queryFn: (_) => 'data',
          enabled: Enabled.no,
          initialData: const InitialData.value('init'),
        ));

        final second = useQuery(QueryObserverOptions<String>(
          queryKey: key2,
          queryFn: (_) => 'data',
          enabled: Enabled.no,
          initialData: const InitialData.value('init'),
        ));

        return Column(children: [
          Text('First Data: ${first.dataOrNull}'),
          Text('Second Data: ${second.dataOrNull}'),
          Text('First Status: ${first.status.name}'),
          Text('Second Status: ${second.status.name}'),
        ]);
      }),
    );

    expect(find.text('First Data: init'), findsOneWidget);
    expect(find.text('Second Data: init'), findsOneWidget);
    expect(find.text('First Status: success'), findsOneWidget);
    expect(find.text('Second Status: success'), findsOneWidget);
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

  // useQuery.test.tsx:2367
  hookTest(
      'should start with status pending, fetchStatus idle if enabled is false',
      (tester, client) async {
    final key1 = queryKey();
    final key2 = queryKey();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final first = useQuery(QueryObserverOptions<String>(
          queryKey: key1,
          queryFn: (_) => sleep(10).then((_) => 'data'),
          enabled: Enabled.no,
        ));
        final second = useQuery(QueryObserverOptions<String>(
          queryKey: key2,
          queryFn: (_) => sleep(10).then((_) => 'data'),
        ));

        return Column(children: [
          Text('First Status: ${first.status.name}, '
              '${first.fetchStatus.name}'),
          Text('Second Status: ${second.status.name}, '
              '${second.fetchStatus.name}'),
        ]);
      }),
    );

    // use "act" to wait for state update and prevent console warning

    expect(find.text('First Status: pending, idle'), findsOneWidget);
    await advance(tester, 0);
    expect(find.text('Second Status: pending, fetching'), findsOneWidget);
    await advance(tester, 11);
    expect(find.text('Second Status: success, idle'), findsOneWidget);
  });

  // useQuery.test.tsx:2412
  hookTest('should be in "pending" state by default', (tester, client) async {
    final key = queryKey();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final status = useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) => sleep(10).then((_) => 'test'),
        )).status;

        return Text('status: ${status.name}');
      }),
    );

    expect(find.text('status: pending'), findsOneWidget);

    // The fetch's `sleep` would outlive the case.
    await advance(tester, 10);
  });

  // useQuery.test.tsx:2429
  hookTest('should not refetch query on focus when `enabled` is set to `false`',
      (tester, client) async {
    final key = queryKey();
    var queryFnCalls = 0;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final data = useQuery(QueryObserverOptions<String>(
              queryKey: key,
              queryFn: (_) {
                queryFnCalls++;
                return 'data';
              },
              enabled: Enabled.no,
            )).dataOrNull ??
            'default';

        return Text(data);
      }),
    );

    await advance(tester, 0);
    expect(find.text('default'), findsOneWidget);

    await focusWindow(tester, client);

    expect(queryFnCalls, 0);
  });

  // useQuery.test.tsx:2461
  hookTest(
      'should not refetch stale query on focus when `refetchOnWindowFocus` is '
      'set to `false`', (tester, client) async {
    final key = queryKey();
    final rec = Recorder<QueryResult<int>>();
    var count = 0;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        rec.build(useQuery(
          QueryObserverOptions<int>(
            queryKey: key,
            queryFn: (_) => count++,
            staleTime: StaleTime.zero,
            refetchOnWindowFocus: RefetchOn.never,
          ),
          buildWhen: rec.buildWhen,
        ));
        return const SizedBox();
      }),
    );

    await advance(tester, 10);

    await focusWindow(tester, client);

    await advance(tester, 10);

    expect(rec.builds, hasLength(2));
    expect(rec.builds[0].dataOrNull, isNull);
    expect(rec.builds[0].isFetching, isTrue);
    expect(rec.builds[1].dataOrNull, 0);
    expect(rec.builds[1].isFetching, isFalse);
  });

  // useQuery.test.tsx:2492
  hookTest(
      'should not refetch stale query on focus when `refetchOnWindowFocus` is '
      'set to a function that returns `false`', (tester, client) async {
    final key = queryKey();
    final rec = Recorder<QueryResult<int>>();
    var count = 0;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        rec.build(useQuery(
          QueryObserverOptions<int>(
            queryKey: key,
            queryFn: (_) => count++,
            staleTime: StaleTime.zero,
            refetchOnWindowFocus: RefetchOn.when((_) => RefetchOn.never),
          ),
          buildWhen: rec.buildWhen,
        ));
        return const SizedBox();
      }),
    );

    await advance(tester, 10);

    await focusWindow(tester, client);

    await advance(tester, 10);

    expect(rec.builds, hasLength(2));
    expect(rec.builds[0].dataOrNull, isNull);
    expect(rec.builds[0].isFetching, isTrue);
    expect(rec.builds[1].dataOrNull, 0);
    expect(rec.builds[1].isFetching, isFalse);
  });

  // useQuery.test.tsx:2523
  hookTest(
      'should not refetch fresh query on focus when `refetchOnWindowFocus` is '
      'set to `true`', (tester, client) async {
    final key = queryKey();
    final rec = Recorder<QueryResult<int>>();
    var count = 0;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        rec.build(useQuery(
          QueryObserverOptions<int>(
            queryKey: key,
            queryFn: (_) => count++,
            staleTime: StaleTime.infinite,
            refetchOnWindowFocus: RefetchOn.ifStale,
          ),
          buildWhen: rec.buildWhen,
        ));
        return const SizedBox();
      }),
    );

    await advance(tester, 10);

    await focusWindow(tester, client);

    await advance(tester, 10);

    expect(rec.builds, hasLength(2));
    expect(rec.builds[0].dataOrNull, isNull);
    expect(rec.builds[0].isFetching, isTrue);
    expect(rec.builds[1].dataOrNull, 0);
    expect(rec.builds[1].isFetching, isFalse);
  });

  // useQuery.test.tsx:2554
  hookTest(
      'should refetch fresh query on focus when `refetchOnWindowFocus` is set '
      'to `always`', (tester, client) async {
    final key = queryKey();
    final rec = Recorder<QueryResult<int>>();
    var count = 0;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final state = rec.build(useQuery(
          QueryObserverOptions<int>(
            queryKey: key,
            queryFn: (_) => sleep(10).then((_) => count++),
            staleTime: StaleTime.infinite,
            refetchOnWindowFocus: RefetchOn.always,
          ),
          buildWhen: rec.buildWhen,
        ));
        return Text(
            'data: ${state.dataOrNull}, isFetching: ${state.isFetching}');
      }),
    );

    await advance(tester, 11);
    expect(find.text('data: 0, isFetching: false'), findsOneWidget);

    await focusWindow(tester, client);

    await advance(tester, 11);
    expect(find.text('data: 1, isFetching: false'), findsOneWidget);
  });

  // useQuery.test.tsx:2590
  hookTest(
      'should calculate focus behavior for `refetchOnWindowFocus` depending on '
      'function', (tester, client) async {
    final key = queryKey();
    final rec = Recorder<QueryResult<int>>();
    var count = 0;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final state = rec.build(useQuery(
          QueryObserverOptions<int>(
            queryKey: key,
            queryFn: (_) => sleep(10).then((_) => count++),
            staleTime: StaleTime.zero,
            retry: const RetryPolicy.times(0),
            refetchOnWindowFocus: RefetchOn.when((query) =>
                ((query.state.data as int?) ?? 0) < 1
                    ? RefetchOn.ifStale
                    : RefetchOn.never),
          ),
          buildWhen: rec.buildWhen,
        ));
        return Text('data: ${state.dataOrNull}');
      }),
    );

    await advance(tester, 11);
    expect(find.text('data: 0'), findsOneWidget);

    expect(rec.builds, hasLength(2));
    expect(rec.builds[0].dataOrNull, isNull);
    expect(rec.builds[0].isFetching, isTrue);
    expect(rec.builds[1].dataOrNull, 0);
    expect(rec.builds[1].isFetching, isFalse);

    await focusWindow(tester, client);

    await advance(tester, 11);
    expect(find.text('data: 1'), findsOneWidget);

    // refetch should happen
    expect(rec.builds, hasLength(4));

    expect(rec.builds[2].dataOrNull, 0);
    expect(rec.builds[2].isFetching, isTrue);
    expect(rec.builds[3].dataOrNull, 1);
    expect(rec.builds[3].isFetching, isFalse);

    await focusWindow(tester, client);

    await advance(tester, 20);

    // no more refetch now
    expect(rec.builds, hasLength(4));
  });

  // useQuery.test.tsx:2640
  hookTest('should refetch fresh query when refetchOnMount is set to always',
      (tester, client) async {
    final key = queryKey();
    final rec = Recorder<QueryResult<String>>();

    await prefetch(
      client,
      QueryOptions<String>(queryKey: key, queryFn: (_) => 'prefetched'),
    );

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        rec.build(useQuery(
          QueryObserverOptions<String>(
            queryKey: key,
            queryFn: (_) => 'data',
            refetchOnMount: RefetchOn.always,
            staleTime: StaleTime.infinite,
          ),
          buildWhen: rec.buildWhen,
        ));
        return const SizedBox();
      }),
    );

    await advance(tester, 0);

    expect(rec.builds, hasLength(2));
    expect(rec.builds[0].dataOrNull, 'prefetched');
    expect(rec.builds[0].isStale, isFalse);
    expect(rec.builds[0].isFetching, isTrue);
    expect(rec.builds[1].dataOrNull, 'data');
    expect(rec.builds[1].isStale, isFalse);
    expect(rec.builds[1].isFetching, isFalse);
  });

  // useQuery.test.tsx:2679
  hookTest('should refetch stale query when refetchOnMount is set to true',
      (tester, client) async {
    final key = queryKey();
    final rec = Recorder<QueryResult<String>>();

    await prefetch(
      client,
      QueryOptions<String>(queryKey: key, queryFn: (_) => 'prefetched'),
    );

    await advance(tester, 0);

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        rec.build(useQuery(
          QueryObserverOptions<String>(
            queryKey: key,
            queryFn: (_) => 'data',
            refetchOnMount: RefetchOn.ifStale,
            staleTime: StaleTime.zero,
          ),
          buildWhen: rec.buildWhen,
        ));
        return const SizedBox();
      }),
    );

    await advance(tester, 0);

    expect(rec.builds, hasLength(2));
    expect(rec.builds[0].dataOrNull, 'prefetched');
    expect(rec.builds[0].isStale, isTrue);
    expect(rec.builds[0].isFetching, isTrue);
    expect(rec.builds[1].dataOrNull, 'data');
    expect(rec.builds[1].isStale, isTrue);
    expect(rec.builds[1].isFetching, isFalse);
  });

  // useQuery.test.tsx:2720
  hookTest('should set status to error if queryFn throws',
      (tester, client) async {
    final key = queryKey();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final result = useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) => Future<String>.error(StateError('Error test')),
          retry: RetryPolicy.never,
        ));

        return Column(children: [
          Text(result.status.name),
          Text(_message(result.errorOrNull) ?? ''),
        ]);
      }),
    );

    await advance(tester, 0);
    expect(find.text('error'), findsOneWidget);
    expect(find.text('Error test'), findsOneWidget);
  });

  // useQuery.test.tsx:2814 — `throwOnError: true` is dropped (plan, D14):
  // errors are data in the result. The query succeeds, so upstream's
  // boundary never runs, and what is left is the case's point: a build that
  // reads nothing of the result still gets the data.
  hookTest(
      'should update with data if we observe no properties and throwOnError',
      (tester, client) async {
    final key = queryKey();
    QueryResult<String>? result;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final query = useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) => Future.value('data'),
        ));

        useEffect(() {
          result = query;
          return null;
        });

        return const SizedBox();
      }),
    );

    await advance(tester, 0);
    expect(client.isFetching(), 0);

    expect(result?.dataOrNull, 'data');
  });

  // useQuery.test.tsx:2841 — `throwOnError: (err) => err.message !==
  // 'Local Error'` is dropped (plan, D14). For this case's error it answers
  // `false`, so upstream's boundary never runs: 6923's mapping.
  hookTest(
      'should set status to error instead of throwing when error should not '
      'be thrown', (tester, client) async {
    final key = queryKey();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final result = useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) => Future<String>.error(StateError('Local Error')),
          retry: RetryPolicy.never,
        ));

        return Column(children: [
          Text(result.status.name),
          Text(_message(result.errorOrNull) ?? ''),
        ]);
      }),
    );

    await advance(tester, 0);
    expect(find.text('error'), findsOneWidget);
    expect(find.text('Local Error'), findsOneWidget);
  });

  // useQuery.test.tsx:2917
  hookTest(
      'should continue retries when observers unmount and remount while '
      'waiting for a retry (#3031)', (tester, client) async {
    final key = queryKey();
    var count = 0;

    final page = HookBuilder(builder: (context) {
      final result = useQuery(QueryObserverOptions<String>(
        queryKey: key,
        queryFn: (_) async {
          count++;
          await sleep(10);
          throw StateError('some error');
        },
        retry: const RetryPolicy.times(2),
        retryDelay: const RetryDelay.fixed(Duration(milliseconds: 100)),
      ));

      return Column(children: [
        Text('error: ${_message(result.errorOrNull) ?? 'null'}'),
        Text('failureCount: ${result.failureCount}'),
        Text('failureReason: ${_message(result.failureReason) ?? ''}'),
      ]);
    });

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final show = useState(true);

        return Column(children: [
          TextButton(
            onPressed: () => show.value = !show.value,
            child: Text(show.value ? 'hide' : 'show'),
          ),
          if (show.value) page,
        ]);
      }),
    );

    await advance(tester, 11);
    expect(find.text('failureCount: 1'), findsOneWidget);
    expect(find.text('failureReason: some error'), findsOneWidget);
    await advance(tester, 90);
    await click(tester, 'hide');
    await advance(tester, 11);
    expect(find.text('show'), findsOneWidget);
    await click(tester, 'show');
    await advance(tester, 11);
    await advance(tester, 110);
    await advance(tester, 110);
    expect(find.text('error: some error'), findsOneWidget);

    expect(count, 4);
  });

  // useQuery.test.tsx:2972
  hookTest(
      'should restart when observers unmount and remount while waiting for a '
      'retry when query was cancelled in between (#3031)',
      (tester, client) async {
    final key = queryKey();
    var count = 0;

    final page = HookBuilder(builder: (context) {
      final result = useQuery(QueryObserverOptions<String>(
        queryKey: key,
        queryFn: (_) async {
          count++;
          await sleep(10);
          throw StateError('some error');
        },
        retry: const RetryPolicy.times(2),
        retryDelay: const RetryDelay.fixed(Duration(milliseconds: 100)),
      ));

      return Column(children: [
        Text('error: ${_message(result.errorOrNull) ?? 'null'}'),
        Text('failureCount: ${result.failureCount}'),
        Text('failureReason: ${_message(result.failureReason) ?? ''}'),
      ]);
    });

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final show = useState(true);

        return Column(children: [
          TextButton(
            onPressed: () => show.value = !show.value,
            child: Text(show.value ? 'hide' : 'show'),
          ),
          TextButton(
            onPressed: () =>
                client.cancelQueries(filters: QueryFilters(queryKey: key)),
            child: const Text('cancel'),
          ),
          if (show.value) page,
        ]);
      }),
    );

    await advance(tester, 11);
    expect(find.text('failureCount: 1'), findsOneWidget);
    expect(find.text('failureReason: some error'), findsOneWidget);
    await click(tester, 'hide');
    await click(tester, 'cancel');
    expect(find.text('show'), findsOneWidget);
    await advance(tester, 1);
    await click(tester, 'show');
    await advance(tester, 11);
    await advance(tester, 110);
    await advance(tester, 110);
    expect(find.text('error: some error'), findsOneWidget);

    // initial fetch (1), which will be cancelled, followed by new mount(2) + 2
    // retries = 4
    expect(count, 4);
  });

  // useQuery.test.tsx:3031
  hookTest('should always fetch if refetchOnMount is set to always',
      (tester, client) async {
    final key = queryKey();
    final rec = Recorder<QueryResult<String>>();

    await prefetch(
      client,
      QueryOptions<String>(queryKey: key, queryFn: (_) => 'prefetched'),
    );

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final state = rec.build(useQuery(
          QueryObserverOptions<String>(
            queryKey: key,
            queryFn: (_) => 'data',
            refetchOnMount: RefetchOn.always,
            staleTime: const StaleTime.duration(Duration(milliseconds: 50)),
          ),
          buildWhen: rec.buildWhen,
        ));
        return Column(children: [
          Text('data: ${state.dataOrNull ?? 'null'}'),
          Text('isFetching: ${state.isFetching}'),
          Text('isStale: ${state.isStale}'),
        ]);
      }),
    );

    await advance(tester, 0);
    expect(find.text('data: data'), findsOneWidget);
    await advance(tester, 52);
    expect(rec.builds, hasLength(3));

    expect(rec.builds[0].dataOrNull, 'prefetched');
    expect(rec.builds[0].isStale, isFalse);
    expect(rec.builds[0].isFetching, isTrue);
    expect(rec.builds[1].dataOrNull, 'data');
    expect(rec.builds[1].isStale, isFalse);
    expect(rec.builds[1].isFetching, isFalse);
    expect(rec.builds[2].dataOrNull, 'data');
    expect(rec.builds[2].isStale, isTrue);
    expect(rec.builds[2].isFetching, isFalse);
  });

  // useQuery.test.tsx:3083
  hookTest('should fetch if initial data is set', (tester, client) async {
    final key = queryKey();
    final rec = Recorder<QueryResult<String>>();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        rec.build(useQuery(
          QueryObserverOptions<String>(
            queryKey: key,
            queryFn: (_) => 'data',
            initialData: const InitialData.value('initial'),
          ),
          buildWhen: rec.buildWhen,
        ));
        return const SizedBox();
      }),
    );

    await advance(tester, 0);

    expect(rec.builds, hasLength(2));

    expect(rec.builds[0].dataOrNull, 'initial');
    expect(rec.builds[0].isStale, isTrue);
    expect(rec.builds[0].isFetching, isTrue);
    expect(rec.builds[1].dataOrNull, 'data');
    expect(rec.builds[1].isStale, isTrue);
    expect(rec.builds[1].isFetching, isFalse);
  });

  // useQuery.test.tsx:3115
  hookTest('should not fetch if initial data is set with a stale time',
      (tester, client) async {
    final key = queryKey();
    final rec = Recorder<QueryResult<String>>();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        rec.build(useQuery(
          QueryObserverOptions<String>(
            queryKey: key,
            queryFn: (_) => 'data',
            staleTime: const StaleTime.duration(Duration(milliseconds: 50)),
            initialData: const InitialData.value('initial'),
          ),
          buildWhen: rec.buildWhen,
        ));
        return const SizedBox();
      }),
    );

    await advance(tester, 52);

    expect(rec.builds, hasLength(2));
    expect(rec.builds[0].dataOrNull, 'initial');
    expect(rec.builds[0].isStale, isFalse);
    expect(rec.builds[0].isFetching, isFalse);
    expect(rec.builds[1].dataOrNull, 'initial');
    expect(rec.builds[1].isStale, isTrue);
    expect(rec.builds[1].isFetching, isFalse);
  });

  // useQuery.test.tsx:3147
  hookTest('should fetch if initial data updated at is older than stale time',
      (tester, client) async {
    final key = queryKey();
    final rec = Recorder<QueryResult<String>>();

    final oneSecondAgo = clock.now().subtract(const Duration(seconds: 1));

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        rec.build(useQuery(
          QueryObserverOptions<String>(
            queryKey: key,
            queryFn: (_) => 'data',
            staleTime: const StaleTime.duration(Duration(milliseconds: 50)),
            initialData: const InitialData.value('initial'),
            initialDataUpdatedAt: oneSecondAgo,
          ),
          buildWhen: rec.buildWhen,
        ));
        return const SizedBox();
      }),
    );

    await advance(tester, 52);

    expect(rec.builds, hasLength(3));
    expect(rec.builds[0].dataOrNull, 'initial');
    expect(rec.builds[0].isStale, isTrue);
    expect(rec.builds[0].isFetching, isTrue);
    expect(rec.builds[1].dataOrNull, 'data');
    expect(rec.builds[1].isStale, isFalse);
    expect(rec.builds[1].isFetching, isFalse);
    expect(rec.builds[2].dataOrNull, 'data');
    expect(rec.builds[2].isStale, isTrue);
    expect(rec.builds[2].isFetching, isFalse);
  });

  // useQuery.test.tsx:3187
  hookTest('should fetch if "initial data updated at" is exactly 0',
      (tester, client) async {
    final key = queryKey();
    final rec = Recorder<QueryResult<String>>();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        rec.build(useQuery(
          QueryObserverOptions<String>(
            queryKey: key,
            queryFn: (_) => 'data',
            staleTime: const StaleTime.duration(Duration(seconds: 10)),
            initialData: const InitialData.value('initial'),
            initialDataUpdatedAt: DateTime.fromMillisecondsSinceEpoch(0),
          ),
          buildWhen: rec.buildWhen,
        ));
        return const SizedBox();
      }),
    );

    await advance(tester, 0);

    expect(rec.builds, hasLength(2));
    expect(rec.builds[0].dataOrNull, 'initial');
    expect(rec.builds[0].isStale, isTrue);
    expect(rec.builds[0].isFetching, isTrue);
    expect(rec.builds[1].dataOrNull, 'data');
    expect(rec.builds[1].isStale, isFalse);
    expect(rec.builds[1].isFetching, isFalse);
  });

  // useQuery.test.tsx:3220
  hookTest('should keep initial data when the query key changes',
      (tester, client) async {
    final key = queryKey();
    final rec = Recorder<QueryResult<({int count})>>();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final count = useState(0);
        final c = count.value;
        rec.build(useQuery(
          QueryObserverOptions<({int count})>(
            queryKey: QueryKey([...key.parts, c]),
            queryFn: (_) => (count: 10),
            staleTime: StaleTime.infinite,
            initialData: InitialData.compute(() => (count: c)),
          ),
          buildWhen: rec.buildWhen,
        ));

        useEffect(() {
          final timer = Timer(_ms(10), () => count.value = 1);
          return timer.cancel;
        }, const []);

        return const SizedBox();
      }),
    );

    await advance(tester, 11);

    expect(rec.builds, hasLength(2));
    // Initial
    expect(rec.builds[0].dataOrNull, (count: 0));
    // Set state
    expect(rec.builds[1].dataOrNull, (count: 1));
  });

  // useQuery.test.tsx:3254
  hookTest(
      'should keep initialData visible alongside the error when a refetch '
      'fails', (tester, client) async {
    final key = queryKey();
    final rec = Recorder<QueryResult<String>>();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        rec.build(useQuery(
          QueryObserverOptions<String>(
            queryKey: key,
            queryFn: (_) => sleep(10).then<String>(
                (_) => Future<String>.error(StateError('Some error'))),
            initialData: const InitialData.value('initial'),
            retry: RetryPolicy.never,
          ),
          buildWhen: rec.buildWhen,
        ));
        return const SizedBox();
      }),
    );

    await advance(tester, 11);

    expect(rec.builds, hasLength(2));
    expect(rec.builds[0].dataOrNull, 'initial');
    expect(rec.builds[0].isError, isFalse);
    expect(rec.builds[1].dataOrNull, 'initial');
    expect(rec.builds[1].isError, isTrue);
  });

  // useQuery.test.tsx:3279
  hookTest('should retry specified number of times', (tester, client) async {
    final key = queryKey();

    var queryFnCalls = 0;
    Future<String> queryFn(QueryFunctionContext _) {
      queryFnCalls++;
      return Future<String>.error(StateError('Error test Barrett'));
    }

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final result = useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: queryFn,
          retry: const RetryPolicy.times(1),
          retryDelay: const RetryDelay.fixed(Duration(milliseconds: 1)),
        ));

        return Column(children: [
          Text(result.status.name),
          Text('Failed ${result.failureCount} times'),
          Text('Failed because ${_message(result.failureReason) ?? ''}'),
        ]);
      }),
    );

    expect(find.text('pending'), findsOneWidget);
    await advance(tester, 2);
    expect(find.text('error'), findsOneWidget);

    // query should fail `retry + 1` times, since first time isn't a "retry"
    expect(find.text('Failed 2 times'), findsOneWidget);
    expect(find.text('Failed because Error test Barrett'), findsOneWidget);

    expect(queryFnCalls, 2);
  });

  // useQuery.test.tsx:3317
  hookTest('should not retry if retry function `false`',
      (tester, client) async {
    final key = queryKey();

    var queryFnCalls = 0;
    Future<String> queryFn(QueryFunctionContext _) {
      queryFnCalls++;
      if (queryFnCalls == 1) {
        return Future<String>.error(StateError('Error test Tanner'));
      }
      return Future<String>.error(StateError('NoRetry'));
    }

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final result = useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: queryFn,
          retryDelay: const RetryDelay.fixed(Duration(milliseconds: 1)),
          retry: RetryPolicy.when((failureCount, error, stackTrace) =>
              _message(error) != 'NoRetry'),
        ));

        return Column(children: [
          Text(result.status.name),
          Text('Failed ${result.failureCount} times'),
          Text('Failed because ${_message(result.failureReason) ?? ''}'),
          Text(_message(result.errorOrNull) ?? ''),
        ]);
      }),
    );

    expect(find.text('pending'), findsOneWidget);
    await advance(tester, 2);
    expect(find.text('error'), findsOneWidget);

    expect(find.text('Failed 2 times'), findsOneWidget);
    expect(find.text('Failed because NoRetry'), findsOneWidget);

    expect(find.text('NoRetry'), findsOneWidget);

    expect(queryFnCalls, 2);
  });

  // useQuery.test.tsx:3362
  hookTest('should extract retryDelay from error', (tester, client) async {
    final key = queryKey();

    var queryFnCalls = 0;
    Future<String> queryFn(QueryFunctionContext _) {
      queryFnCalls++;
      return Future<String>.error(const _DelayError(50));
    }

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final result = useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: queryFn,
          retry: const RetryPolicy.times(1),
          retryDelay: RetryDelay.dynamic((_, error) =>
              Duration(milliseconds: (error as _DelayError).delay)),
        ));

        return Column(children: [
          Text(result.status.name),
          Text('Failed ${result.failureCount} times'),
          Text('Failed because DelayError: '
              '${(result.failureReason as _DelayError?)?.delay}ms'),
        ]);
      }),
    );

    await advance(tester, 0);

    expect(queryFnCalls, 1);

    expect(find.text('Failed because DelayError: 50ms'), findsOneWidget);
    await advance(tester, 51);
    expect(find.text('Failed 2 times'), findsOneWidget);

    expect(queryFnCalls, 2);
  });

  // useQuery.test.tsx:3403
  hookTest('should continue retry after focus regain', (tester, client) async {
    final key = queryKey();

    // make page unfocused
    client.focusManager.setFocused(false);

    var count = 0;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final query = useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) {
            count++;
            return Future<String>.error('fetching error $count');
          },
          retry: const RetryPolicy.times(3),
          retryDelay: const RetryDelay.fixed(Duration(milliseconds: 1)),
        ));

        return Column(children: [
          Text('error ${query.errorOrNull}'),
          Text('status ${query.status.name}'),
          Text('failureCount ${query.failureCount}'),
          Text('failureReason ${query.failureReason ?? ''}'),
        ]);
      }),
    );

    // The query should display the first error result
    await advance(tester, 0);
    expect(find.text('failureCount 1'), findsOneWidget);
    expect(find.text('failureReason fetching error 1'), findsOneWidget);
    expect(find.text('status pending'), findsOneWidget);
    expect(find.text('error null'), findsOneWidget);

    // Check if the query really paused
    await advance(tester, 0);
    expect(find.text('failureCount 1'), findsOneWidget);
    expect(find.text('failureReason fetching error 1'), findsOneWidget);

    // reset visibilityState to original value
    await _regainFocus(tester, client);

    // Wait for the final result
    await advance(tester, 4);
    expect(find.text('failureCount 4'), findsOneWidget);
    expect(find.text('failureReason fetching error 4'), findsOneWidget);
    expect(find.text('status error'), findsOneWidget);
    expect(find.text('error fetching error 4'), findsOneWidget);

    // Check if the query really stopped
    await advance(tester, 10);
    expect(find.text('failureCount 4'), findsOneWidget);
    expect(find.text('failureReason fetching error 4'), findsOneWidget);
  });

  // useQuery.test.tsx:3473
  hookTest(
      'should fetch on mount when a query was already created with '
      'setQueryData', (tester, client) async {
    final key = queryKey();
    final rec = Recorder<QueryResult<String>>();

    client.setQueryData(key, 'prefetched');

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        rec.build(useQuery(
          QueryObserverOptions<String>(queryKey: key, queryFn: (_) => 'data'),
          buildWhen: rec.buildWhen,
        ));
        return const SizedBox();
      }),
    );

    await advance(tester, 0);

    expect(rec.builds, hasLength(2));
    expect(rec.builds[0].dataOrNull, 'prefetched');
    expect(rec.builds[0].isFetching, isTrue);
    expect(rec.builds[0].isStale, isTrue);
    expect(rec.builds[1].dataOrNull, 'data');
    expect(rec.builds[1].isFetching, isFalse);
    expect(rec.builds[1].isStale, isTrue);
  });

  // useQuery.test.tsx:3504
  hookTest('should refetch after focus regain', (tester, client) async {
    final key = queryKey();
    final rec = Recorder<QueryResult<String>>();

    // make page unfocused
    client.focusManager.setFocused(false);

    // set data in cache to check if the hook query fn is actually called
    client.setQueryData(key, 'prefetched');

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final state = rec.build(useQuery(
          QueryObserverOptions<String>(
            queryKey: key,
            queryFn: (_) => sleep(10).then((_) => 'data'),
          ),
          buildWhen: rec.buildWhen,
        ));
        return Text('${state.dataOrNull}, ${state.isStale}, '
            '${state.isFetching}');
      }),
    );

    await advance(tester, 11);
    expect(rec.builds, hasLength(2));

    // reset visibilityState to original value
    await _regainFocus(tester, client);

    await advance(tester, 11);
    expect(rec.builds, hasLength(4));

    expect(rec.builds[0].dataOrNull, 'prefetched');
    expect(rec.builds[0].isFetching, isTrue);
    expect(rec.builds[0].isStale, isTrue);
    expect(rec.builds[1].dataOrNull, 'data');
    expect(rec.builds[1].isFetching, isFalse);
    expect(rec.builds[1].isStale, isTrue);
    expect(rec.builds[2].dataOrNull, 'data');
    expect(rec.builds[2].isFetching, isTrue);
    expect(rec.builds[2].isStale, isTrue);
    expect(rec.builds[3].dataOrNull, 'data');
    expect(rec.builds[3].isFetching, isFalse);
    expect(rec.builds[3].isStale, isTrue);
  });

  // useQuery.test.tsx:3566
  hookTest('should refetch if stale after a prefetch', (tester, client) async {
    final key = queryKey();
    final rec = Recorder<QueryResult<String>>();

    var queryFnCalls = 0;
    String queryFn(QueryFunctionContext _) {
      queryFnCalls++;
      return 'data';
    }

    var prefetchQueryFnCalls = 0;
    String prefetchQueryFn(QueryFunctionContext _) {
      prefetchQueryFnCalls++;
      return 'not yet...';
    }

    await prefetch(
      client,
      QueryOptions<String>(
        queryKey: key,
        queryFn: prefetchQueryFn,
        staleTime: const StaleTime.duration(Duration(milliseconds: 10)),
      ),
    );

    await advance(tester, 10);

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        rec.build(useQuery(
          QueryObserverOptions<String>(queryKey: key, queryFn: queryFn),
          buildWhen: rec.buildWhen,
        ));
        return const SizedBox();
      }),
    );

    await advance(tester, 11);
    expect(rec.builds, hasLength(2));

    expect(prefetchQueryFnCalls, 1);
    expect(queryFnCalls, 1);
  });
}

Duration _ms(int ms) => Duration(milliseconds: ms);

/// The cleanup of an effect that armed [timers] — upstream's
/// `setActTimeout`, cancelled when the effect goes.
void _cancelAll(List<Timer> timers) {
  for (final timer in timers) {
    timer.cancel();
  }
}

/// Upstream's `error?.message` for the `Error`s these cases throw.
String? _message(Object? error) => (error as StateError?)?.message;

/// `visibilityMock.mockRestore()` and the `visibilitychange` event inside
/// one `act`: the page is visible again.
Future<void> _regainFocus(WidgetTester tester, QueryClient client) async {
  client.focusManager.setFocused(true);
  await tester.pump();
}

/// Upstream's `type DelayError = { delay: number }`.
final class _DelayError {
  const _DelayError(this.delay);

  final int delay;
}
