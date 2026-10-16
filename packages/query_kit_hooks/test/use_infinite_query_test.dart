// Ported from
// query/packages/react-query/src/__tests__/useInfiniteQuery.test.tsx at
// 50680b98c. Each case keeps upstream's name, and its upstream line is in the
// comment above it. What was adapted or omitted, and why, is in
// PORTING_NOTES.md.
//
// The hook returns the controller, which is live, so a case that records
// upstream's `states` takes a snapshot per build: the result and the paging
// flags the controller holds beside it (plan, D9).
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_hooks/query_kit_hooks.dart';

import 'harness.dart';

/// What one build of an infinite query shows: upstream's
/// `UseInfiniteQueryResult`, with the result and the controller's paging
/// flags read at build time.
typedef Snapshot<T> = ({
  QueryResult<T> result,
  bool hasNextPage,
  bool hasPreviousPage,
  bool isFetchingNextPage,
  bool isFetchingPreviousPage,
  bool isFetchNextPageError,
  bool isFetchPreviousPageError,
  bool isRefetching,
  bool isRefetchError,
});

/// Reads [c] as one build shows it.
Snapshot<TData> snapshot<TPageData, TPageParam, TData>(
        InfiniteQueryController<TPageData, TPageParam, TData> c) =>
    (
      result: c.value,
      hasNextPage: c.hasNextPage,
      hasPreviousPage: c.hasPreviousPage,
      isFetchingNextPage: c.isFetchingNextPage,
      isFetchingPreviousPage: c.isFetchingPreviousPage,
      isFetchNextPageError: c.isFetchNextPageError,
      isFetchPreviousPageError: c.isFetchPreviousPageError,
      // The infinite result's own `isRefetching` and `isRefetchError`:
      // a page fetch is not a refetch. `QueryResult.isRefetching` counts both.
      isRefetching: c.isRefetching,
      isRefetchError: c.isRefetchError,
    );

void main() {
  // useInfiniteQuery.test.tsx:48
  hookTest('should return the correct states for a successful query',
      (tester, client) async {
    final key = queryKey();
    final rec = _Rec<InfiniteData<int, int>>();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        rec.build(useInfiniteQuery(
          InfiniteQueryObserverOptions<int, int>(
            queryKey: key,
            pageFn: (context) => sleep(10).then((_) => context.pageParam),
            getNextPageParam: (lastPage, _, __, ___) => lastPage + 1,
            initialPageParam: 0,
          ),
          buildWhen: rec.buildWhen,
        ));
        return const SizedBox();
      }),
    );

    await advance(tester, 11);

    expect(rec.builds, hasLength(2));

    final first = rec.builds[0];
    expect(first.result.dataOrNull, isNull);
    expect(first.result.dataUpdatedAt, isNull);
    expect(first.result.errorOrNull, isNull);
    expect(first.result.errorUpdatedAt, isNull);
    expect(first.result.failureCount, 0);
    expect(first.result.failureReason, isNull);
    expect(first.result.errorUpdateCount, 0);
    expect(first.hasNextPage, isFalse);
    expect(first.hasPreviousPage, isFalse);
    expect(first.result.isError, isFalse);
    expect(first.result.isFetched, isFalse);
    expect(first.result.isFetchedAfterMount, isFalse);
    expect(first.result.isFetching, isTrue);
    expect(first.result.isPaused, isFalse);
    expect(first.isFetchNextPageError, isFalse);
    expect(first.isFetchingNextPage, isFalse);
    expect(first.isFetchPreviousPageError, isFalse);
    expect(first.isFetchingPreviousPage, isFalse);
    expect(first.result.isLoading, isTrue);
    expect(first.result.isPending, isTrue);
    expect(_isLoadingError(first.result), isFalse);
    expect(first.result.isPlaceholderData, isFalse);
    expect(first.isRefetchError, isFalse);
    expect(first.isRefetching, isFalse);
    expect(first.result.isStale, isTrue);
    expect(first.result.isSuccess, isFalse);
    expect(first.result.isEnabled, isTrue);
    expect(first.result.status, QueryStatus.pending);
    expect(first.result.fetchStatus, FetchStatus.fetching);

    final second = rec.builds[1];
    expect(second.result.dataOrNull!.pages, [0]);
    expect(second.result.dataOrNull!.pageParams, [0]);
    expect(second.result.dataUpdatedAt, isNotNull);
    expect(second.result.errorOrNull, isNull);
    expect(second.result.errorUpdatedAt, isNull);
    expect(second.result.failureCount, 0);
    expect(second.result.failureReason, isNull);
    expect(second.result.errorUpdateCount, 0);
    expect(second.hasNextPage, isTrue);
    expect(second.hasPreviousPage, isFalse);
    expect(second.result.isError, isFalse);
    expect(second.result.isFetched, isTrue);
    expect(second.result.isFetchedAfterMount, isTrue);
    expect(second.result.isFetching, isFalse);
    expect(second.result.isPaused, isFalse);
    expect(second.isFetchNextPageError, isFalse);
    expect(second.isFetchingNextPage, isFalse);
    expect(second.isFetchPreviousPageError, isFalse);
    expect(second.isFetchingPreviousPage, isFalse);
    expect(second.result.isLoading, isFalse);
    expect(second.result.isPending, isFalse);
    expect(_isLoadingError(second.result), isFalse);
    expect(second.result.isPlaceholderData, isFalse);
    expect(second.isRefetchError, isFalse);
    expect(second.isRefetching, isFalse);
    expect(second.result.isStale, isTrue);
    expect(second.result.isSuccess, isTrue);
    expect(second.result.isEnabled, isTrue);
    expect(second.result.status, QueryStatus.success);
    expect(second.result.fetchStatus, FetchStatus.idle);
  });

  // useInfiniteQuery.test.tsx:140
  hookTest('should not throw when fetchNextPage returns an error',
      (tester, client) async {
    final key = queryKey();
    var noThrow = false;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        const start = 1;
        final state = useInfiniteQuery(InfiniteQueryObserverOptions<int, int>(
          queryKey: key,
          pageFn: (context) => sleep(10).then((_) {
            if (context.pageParam == 2) throw StateError('error');
            return context.pageParam;
          }),
          retry: const RetryPolicy.times(1),
          retryDelay: const RetryDelay.fixed(Duration(milliseconds: 10)),
          getNextPageParam: (lastPage, _, __, ___) => lastPage + 1,
          initialPageParam: start,
        ));

        final fetchNextPage = state.fetchNextPage;

        useEffect(() {
          final timer = Timer(_ms(20), () {
            fetchNextPage().then((_) {
              noThrow = true;
            }, onError: (Object _) {});
          });
          return timer.cancel;
        }, [fetchNextPage]);

        return const SizedBox();
      }),
    );

    await advance(tester, 50);
    expect(noThrow, isTrue);
  });

  // useInfiniteQuery.test.tsx:180 — `notifyOnChangeProps: 'all'` is the
  // default here.
  hookTest('should keep the previous data when placeholderData is set',
      (tester, client) async {
    final key = queryKey();
    final rec = _Rec<InfiniteData<String, int>>();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final order = useState('desc');

        final state = rec.build(useInfiniteQuery(
          InfiniteQueryObserverOptions<String, int>(
            queryKey: QueryKey([...key.parts, order.value]),
            pageFn: (context) {
              final o = order.value;
              return sleep(10).then((_) => '${context.pageParam}-$o');
            },
            getNextPageParam: (_, __, ___, ____) => 1,
            initialPageParam: 0,
            placeholderData: const PlaceholderData.keepPrevious(),
          ),
          buildWhen: rec.buildWhen,
        ));

        return Column(children: [
          TextButton(
            onPressed: state.fetchNextPage,
            child: const Text('fetchNextPage'),
          ),
          TextButton(
            onPressed: () => order.value = 'asc',
            child: const Text('order'),
          ),
          Text('data: ${state.value.dataOrNull?.pages.join(',') ?? 'null'}'),
          Text('isFetching: ${state.value.isFetching}'),
        ]);
      }),
    );

    await advance(tester, 11);
    expect(find.text('data: 0-desc'), findsOneWidget);

    await click(tester, 'fetchNextPage');
    await advance(tester, 11);
    expect(find.text('data: 0-desc,1-desc'), findsOneWidget);

    await click(tester, 'order');
    await advance(tester, 11);
    expect(find.text('data: 0-asc'), findsOneWidget);
    expect(find.text('isFetching: false'), findsOneWidget);

    expect(rec.builds, hasLength(6));
    _expectMatch(rec.builds[0], {
      'data': null,
      'isFetching': true,
      'isFetchingNextPage': false,
      'isSuccess': false,
      'isPlaceholderData': false,
    });
    _expectMatch(rec.builds[1], {
      'pages': ['0-desc'],
      'isFetching': false,
      'isFetchingNextPage': false,
      'isSuccess': true,
      'isPlaceholderData': false,
    });
    _expectMatch(rec.builds[2], {
      'pages': ['0-desc'],
      'isFetching': true,
      'isFetchingNextPage': true,
      'isSuccess': true,
      'isPlaceholderData': false,
    });
    _expectMatch(rec.builds[3], {
      'pages': ['0-desc', '1-desc'],
      'isFetching': false,
      'isFetchingNextPage': false,
      'isSuccess': true,
      'isPlaceholderData': false,
    });
    // Set state
    _expectMatch(rec.builds[4], {
      'pages': ['0-desc', '1-desc'],
      'isFetching': true,
      'isFetchingNextPage': false,
      'isSuccess': true,
      'isPlaceholderData': true,
    });
    _expectMatch(rec.builds[5], {
      'pages': ['0-asc'],
      'isFetching': false,
      'isFetchingNextPage': false,
      'isSuccess': true,
      'isPlaceholderData': false,
    });
  });

  // useInfiniteQuery.test.tsx:269
  hookTest('should be able to select a part of the data',
      (tester, client) async {
    final key = queryKey();
    final rec = _Rec<InfiniteData<String, int>>();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final state = rec.build(useInfiniteQuery(
          InfiniteQuerySelectOptions<({int count}), int,
              InfiniteData<String, int>>(
            queryKey: key,
            pageFn: (_) => sleep(10).then((_) => (count: 1)),
            select: (data) => InfiniteData(
              pages: data.pages.map((x) => 'count: ${x.count}').toList(),
              pageParams: data.pageParams,
            ),
            getNextPageParam: (_, __, ___, ____) => null,
            initialPageParam: 0,
          ),
          buildWhen: rec.buildWhen,
        ));

        return Text(state.value.dataOrNull?.pages.join(',') ?? '');
      }),
    );

    await advance(tester, 11);
    expect(find.text('count: 1'), findsOneWidget);

    expect(rec.builds, hasLength(2));
    _expectMatch(rec.builds[0], {
      'data': null,
      'isSuccess': false,
    });
    _expectMatch(rec.builds[1], {
      'pages': ['count: 1'],
      'isSuccess': true,
    });
  });

  // useInfiniteQuery.test.tsx:305
  hookTest(
      'should be able to select a new result and not cause infinite renders',
      (tester, client) async {
    final key = queryKey();
    final rec = _Rec<InfiniteData<({int count, double id}), int>>();
    var selectCalled = 0;
    final random = Random();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final state = rec.build(useInfiniteQuery(
          InfiniteQuerySelectOptions<({int count}), int,
              InfiniteData<({int count, double id}), int>>(
            queryKey: key,
            pageFn: (_) => sleep(10).then((_) => (count: 1)),
            select: useCallback((InfiniteData<({int count}), int> data) {
              selectCalled++;
              return InfiniteData<({int count, double id}), int>(
                pages: data.pages
                    .map((x) => (count: x.count, id: random.nextDouble()))
                    .toList(),
                pageParams: data.pageParams,
              );
            }, const []),
            getNextPageParam: (_, __, ___, ____) => null,
            initialPageParam: 0,
          ),
          buildWhen: rec.buildWhen,
        ));

        return Column(children: [
          for (final page in state.value.dataOrNull?.pages ??
              const <({int count, double id})>[])
            Text('count: ${page.count}', key: ValueKey(page.id)),
        ]);
      }),
    );

    await advance(tester, 11);
    expect(find.text('count: 1'), findsOneWidget);

    expect(rec.builds, hasLength(2));
    expect(selectCalled, 1);
    _expectMatch(rec.builds[0], {
      'data': null,
      'isSuccess': false,
    });
    // `{ pages: [{ count: 1 }] }`: a page matches on `count` alone.
    expect(
      rec.builds[1].result.dataOrNull?.pages.map((page) => page.count),
      [1],
    );
    _expectMatch(rec.builds[1], {
      'isSuccess': true,
    });
  });

  // useInfiniteQuery.test.tsx:354
  hookTest('should be able to reverse the data', (tester, client) async {
    final key = queryKey();
    final rec = _Rec<InfiniteData<int, int>>();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final state = rec.build(useInfiniteQuery(
          InfiniteQuerySelectOptions<int, int, InfiniteData<int, int>>(
            queryKey: key,
            pageFn: (context) => sleep(10).then((_) => context.pageParam),
            select: (data) => InfiniteData(
              pages: data.pages.reversed.toList(),
              pageParams: data.pageParams.reversed.toList(),
            ),
            getNextPageParam: (_, __, ___, ____) => 1,
            initialPageParam: 0,
          ),
          buildWhen: rec.buildWhen,
        ));

        return Column(children: [
          TextButton(
            onPressed: state.fetchNextPage,
            child: const Text('fetchNextPage'),
          ),
          Text('data: ${state.value.dataOrNull?.pages.join(',') ?? 'null'}'),
          Text('isFetching: ${state.value.isFetching}'),
        ]);
      }),
    );

    await advance(tester, 11);
    expect(find.text('data: 0'), findsOneWidget);

    await click(tester, 'fetchNextPage');
    await advance(tester, 11);
    expect(find.text('data: 1,0'), findsOneWidget);

    expect(rec.builds, hasLength(4));
    _expectMatch(rec.builds[0], {
      'data': null,
      'isSuccess': false,
    });
    _expectMatch(rec.builds[1], {
      'pages': [0],
      'isSuccess': true,
    });
    _expectMatch(rec.builds[2], {
      'pages': [0],
      'isSuccess': true,
    });
    _expectMatch(rec.builds[3], {
      'pages': [1, 0],
      'isSuccess': true,
    });
  });

  // useInfiniteQuery.test.tsx:410
  hookTest('should be able to fetch a previous page', (tester, client) async {
    final key = queryKey();
    final rec = _Rec<InfiniteData<int, int>>();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        const start = 10;
        final state = rec.build(useInfiniteQuery(
          InfiniteQueryObserverOptions<int, int>(
            queryKey: key,
            pageFn: (context) => sleep(10).then((_) => context.pageParam),
            initialPageParam: start,
            getNextPageParam: (lastPage, _, __, ___) => lastPage + 1,
            getPreviousPageParam: (firstPage, _, __, ___) => firstPage - 1,
          ),
          buildWhen: rec.buildWhen,
        ));

        return Column(children: [
          Text('data: ${state.value.dataOrNull?.pages.join(',') ?? ''}'),
          TextButton(
            onPressed: state.fetchPreviousPage,
            child: const Text('fetch previous page'),
          ),
        ]);
      }),
    );

    await advance(tester, 11);
    expect(find.text('data: 10'), findsOneWidget);

    await click(tester, 'fetch previous page');
    await advance(tester, 11);
    expect(find.text('data: 9,10'), findsOneWidget);

    expect(rec.builds, hasLength(4));
    _expectMatch(rec.builds[0], {
      'data': null,
      'hasNextPage': false,
      'hasPreviousPage': false,
      'isFetching': true,
      'isFetchingNextPage': false,
      'isFetchingPreviousPage': false,
      'isSuccess': false,
    });
    _expectMatch(rec.builds[1], {
      'pages': [10],
      'hasNextPage': true,
      'hasPreviousPage': true,
      'isFetching': false,
      'isFetchingNextPage': false,
      'isFetchingPreviousPage': false,
      'isSuccess': true,
    });
    _expectMatch(rec.builds[2], {
      'pages': [10],
      'hasNextPage': true,
      'hasPreviousPage': true,
      'isFetching': true,
      'isFetchingNextPage': false,
      'isFetchingPreviousPage': true,
      'isSuccess': true,
    });
    _expectMatch(rec.builds[3], {
      'pages': [9, 10],
      'hasNextPage': true,
      'hasPreviousPage': true,
      'isFetching': false,
      'isFetchingNextPage': false,
      'isFetchingPreviousPage': false,
      'isSuccess': true,
    });
  });

  // useInfiniteQuery.test.tsx:487
  hookTest('should be able to refetch when providing page params automatically',
      (tester, client) async {
    final key = queryKey();
    final rec = _Rec<InfiniteData<int, int>>();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final state = rec.build(useInfiniteQuery(
          InfiniteQueryObserverOptions<int, int>(
            queryKey: key,
            pageFn: (context) => sleep(10).then((_) => context.pageParam),
            initialPageParam: 10,
            getPreviousPageParam: (firstPage, _, __, ___) => firstPage - 1,
            getNextPageParam: (lastPage, _, __, ___) => lastPage + 1,
          ),
          buildWhen: rec.buildWhen,
        ));

        return Column(children: [
          TextButton(
            onPressed: state.fetchNextPage,
            child: const Text('fetchNextPage'),
          ),
          TextButton(
            onPressed: state.fetchPreviousPage,
            child: const Text('fetchPreviousPage'),
          ),
          TextButton(
            onPressed: state.refetch,
            child: const Text('refetch'),
          ),
          Text('data: ${state.value.dataOrNull?.pages.join(',') ?? 'null'}'),
          Text('isFetching: ${state.value.isFetching}'),
        ]);
      }),
    );

    await advance(tester, 11);
    expect(find.text('data: 10'), findsOneWidget);
    await click(tester, 'fetchNextPage');

    await advance(tester, 11);
    expect(find.text('data: 10,11'), findsOneWidget);
    await click(tester, 'fetchPreviousPage');

    await advance(tester, 11);
    expect(find.text('data: 9,10,11'), findsOneWidget);

    // `fireEvent.click` and nothing rendered yet: the tap without its frame.
    await tester.tap(find.text('refetch'));
    expect(find.text('isFetching: false'), findsOneWidget);

    await advance(tester, 31);
    expect(rec.builds, hasLength(8));
    // Initial fetch
    _expectMatch(rec.builds[0], {
      'data': null,
      'isFetching': true,
      'isFetchingNextPage': false,
      'isRefetching': false,
    });
    // Initial fetch done
    _expectMatch(rec.builds[1], {
      'pages': [10],
      'isFetching': false,
      'isFetchingNextPage': false,
      'isRefetching': false,
    });
    // Fetch next page
    _expectMatch(rec.builds[2], {
      'pages': [10],
      'isFetching': true,
      'isFetchingNextPage': true,
      'isRefetching': false,
    });
    // Fetch next page done
    _expectMatch(rec.builds[3], {
      'pages': [10, 11],
      'isFetching': false,
      'isFetchingNextPage': false,
      'isRefetching': false,
    });
    // Fetch previous page
    _expectMatch(rec.builds[4], {
      'pages': [10, 11],
      'isFetching': true,
      'isFetchingNextPage': false,
      'isFetchingPreviousPage': true,
      'isRefetching': false,
    });
    // Fetch previous page done
    _expectMatch(rec.builds[5], {
      'pages': [9, 10, 11],
      'isFetching': false,
      'isFetchingNextPage': false,
      'isFetchingPreviousPage': false,
      'isRefetching': false,
    });
    // Refetch
    _expectMatch(rec.builds[6], {
      'pages': [9, 10, 11],
      'isFetching': true,
      'isFetchingNextPage': false,
      'isFetchingPreviousPage': false,
      'isRefetching': true,
    });
    // Refetch done
    _expectMatch(rec.builds[7], {
      'pages': [9, 10, 11],
      'isFetching': false,
      'isFetchingNextPage': false,
      'isFetchingPreviousPage': false,
      'isRefetching': false,
    });
  });

  // useInfiniteQuery.test.tsx:598
  hookTest('should return the correct states when refetch fails',
      (tester, client) async {
    final key = queryKey();
    final rec = _Rec<InfiniteData<int, int>>();
    var isRefetch = false;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final state = rec.build(useInfiniteQuery(
          InfiniteQueryObserverOptions<int, int>(
            queryKey: key,
            pageFn: (context) => sleep(10).then((_) {
              if (isRefetch) throw StateError('refetch');
              return context.pageParam;
            }),
            initialPageParam: 10,
            getPreviousPageParam: (firstPage, _, __, ___) => firstPage - 1,
            getNextPageParam: (lastPage, _, __, ___) => lastPage + 1,
            retry: RetryPolicy.never,
          ),
          buildWhen: rec.buildWhen,
        ));

        return Column(children: [
          TextButton(
            onPressed: () {
              isRefetch = true;
              state.refetch();
            },
            child: const Text('refetch'),
          ),
          Text('data: ${state.value.dataOrNull?.pages.join(',') ?? 'null'}'),
          Text('isFetching: ${state.value.isFetching}'),
        ]);
      }),
    );

    await advance(tester, 11);
    expect(find.text('data: 10'), findsOneWidget);

    // `fireEvent.click` and nothing rendered yet: the tap without its frame.
    await tester.tap(find.text('refetch'));
    expect(find.text('isFetching: false'), findsOneWidget);

    await advance(tester, 11);
    expect(rec.builds, hasLength(4));
    // Initial fetch
    _expectMatch(rec.builds[0], {
      'data': null,
      'isFetching': true,
      'isFetchNextPageError': false,
      'isFetchingNextPage': false,
      'isFetchPreviousPageError': false,
      'isFetchingPreviousPage': false,
      'isRefetchError': false,
      'isRefetching': false,
    });
    // Initial fetch done
    _expectMatch(rec.builds[1], {
      'pages': [10],
      'isFetching': false,
      'isFetchNextPageError': false,
      'isFetchingNextPage': false,
      'isFetchPreviousPageError': false,
      'isFetchingPreviousPage': false,
      'isRefetchError': false,
      'isRefetching': false,
    });
    // Refetch
    _expectMatch(rec.builds[2], {
      'pages': [10],
      'isFetching': true,
      'isFetchNextPageError': false,
      'isFetchingNextPage': false,
      'isFetchPreviousPageError': false,
      'isFetchingPreviousPage': false,
      'isRefetchError': false,
      'isRefetching': true,
    });
    // Refetch failed
    _expectMatch(rec.builds[3], {
      'pages': [10],
      'isFetching': false,
      'isFetchNextPageError': false,
      'isFetchingNextPage': false,
      'isFetchPreviousPageError': false,
      'isFetchingPreviousPage': false,
      'isRefetchError': true,
      'isRefetching': false,
    });
  });

  // useInfiniteQuery.test.tsx:692
  hookTest('should return the correct states when fetchNextPage fails',
      (tester, client) async {
    final key = queryKey();
    final rec = _Rec<InfiniteData<int, int>>();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final state = rec.build(useInfiniteQuery(
          InfiniteQueryObserverOptions<int, int>(
            queryKey: key,
            pageFn: (context) => sleep(10).then((_) {
              if (context.pageParam != 10) throw StateError('page');
              return context.pageParam;
            }),
            initialPageParam: 10,
            getPreviousPageParam: (firstPage, _, __, ___) => firstPage - 1,
            getNextPageParam: (lastPage, _, __, ___) => lastPage + 1,
            retry: RetryPolicy.never,
          ),
          buildWhen: rec.buildWhen,
        ));

        return Column(children: [
          TextButton(
            onPressed: state.fetchNextPage,
            child: const Text('fetchNextPage'),
          ),
          Text('data: ${state.value.dataOrNull?.pages.join(',') ?? 'null'}'),
          Text('isFetching: ${state.value.isFetching}'),
        ]);
      }),
    );

    await advance(tester, 11);
    expect(find.text('data: 10'), findsOneWidget);

    // `fireEvent.click` and nothing rendered yet: the tap without its frame.
    await tester.tap(find.text('fetchNextPage'));
    expect(find.text('isFetching: false'), findsOneWidget);

    await advance(tester, 11);
    expect(rec.builds, hasLength(4));
    // Initial fetch
    _expectMatch(rec.builds[0], {
      'data': null,
      'isFetching': true,
      'isFetchNextPageError': false,
      'isFetchingNextPage': false,
      'isFetchPreviousPageError': false,
      'isFetchingPreviousPage': false,
      'isRefetchError': false,
      'isRefetching': false,
    });
    // Initial fetch done
    _expectMatch(rec.builds[1], {
      'pages': [10],
      'isFetching': false,
      'isFetchNextPageError': false,
      'isFetchingNextPage': false,
      'isFetchPreviousPageError': false,
      'isFetchingPreviousPage': false,
      'isRefetchError': false,
      'isRefetching': false,
    });
    // Fetch next page
    _expectMatch(rec.builds[2], {
      'pages': [10],
      'isFetching': true,
      'isFetchNextPageError': false,
      'isFetchingNextPage': true,
      'isFetchPreviousPageError': false,
      'isFetchingPreviousPage': false,
      'isRefetchError': false,
      'isRefetching': false,
    });
    // Fetch next page failed
    _expectMatch(rec.builds[3], {
      'pages': [10],
      'isFetching': false,
      'isFetchNextPageError': true,
      'isFetchingNextPage': false,
      'isFetchPreviousPageError': false,
      'isFetchingPreviousPage': false,
      'isRefetchError': false,
      'isRefetching': false,
    });
  });

  // useInfiniteQuery.test.tsx:778
  hookTest('should return the correct states when fetchPreviousPage fails',
      (tester, client) async {
    final key = queryKey();
    final rec = _Rec<InfiniteData<int, int>>();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final state = rec.build(useInfiniteQuery(
          InfiniteQueryObserverOptions<int, int>(
            queryKey: key,
            pageFn: (context) => sleep(10).then((_) {
              if (context.pageParam != 10) throw StateError('page');
              return context.pageParam;
            }),
            initialPageParam: 10,
            getPreviousPageParam: (firstPage, _, __, ___) => firstPage - 1,
            getNextPageParam: (lastPage, _, __, ___) => lastPage + 1,
            retry: RetryPolicy.never,
          ),
          buildWhen: rec.buildWhen,
        ));

        return Column(children: [
          TextButton(
            onPressed: state.fetchPreviousPage,
            child: const Text('fetchPreviousPage'),
          ),
          Text('data: ${state.value.dataOrNull?.pages.join(',') ?? 'null'}'),
          Text('isFetching: ${state.value.isFetching}'),
        ]);
      }),
    );

    await advance(tester, 11);
    expect(find.text('data: 10'), findsOneWidget);

    // `fireEvent.click` and nothing rendered yet: the tap without its frame.
    await tester.tap(find.text('fetchPreviousPage'));
    expect(find.text('isFetching: false'), findsOneWidget);

    await advance(tester, 11);
    expect(rec.builds, hasLength(4));
    // Initial fetch
    _expectMatch(rec.builds[0], {
      'data': null,
      'isFetching': true,
      'isFetchNextPageError': false,
      'isFetchingNextPage': false,
      'isFetchPreviousPageError': false,
      'isFetchingPreviousPage': false,
      'isRefetchError': false,
      'isRefetching': false,
    });
    // Initial fetch done
    _expectMatch(rec.builds[1], {
      'pages': [10],
      'isFetching': false,
      'isFetchNextPageError': false,
      'isFetchingNextPage': false,
      'isFetchPreviousPageError': false,
      'isFetchingPreviousPage': false,
      'isRefetchError': false,
      'isRefetching': false,
    });
    // Fetch previous page
    _expectMatch(rec.builds[2], {
      'pages': [10],
      'isFetching': true,
      'isFetchNextPageError': false,
      'isFetchingNextPage': false,
      'isFetchPreviousPageError': false,
      'isFetchingPreviousPage': true,
      'isRefetchError': false,
      'isRefetching': false,
    });
    // Fetch previous page failed
    _expectMatch(rec.builds[3], {
      'pages': [10],
      'isFetching': false,
      'isFetchNextPageError': false,
      'isFetchingNextPage': false,
      'isFetchPreviousPageError': true,
      'isFetchingPreviousPage': false,
      'isRefetchError': false,
      'isRefetching': false,
    });
  });

  // useInfiniteQuery.test.tsx:868
  hookTest('should silently cancel any ongoing fetch when fetching more',
      (tester, client) async {
    final key = queryKey();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        const start = 10;
        final state = useInfiniteQuery(InfiniteQueryObserverOptions<int, int>(
          queryKey: key,
          pageFn: (context) => sleep(50).then((_) => context.pageParam),
          initialPageParam: start,
          getNextPageParam: (lastPage, _, __, ___) => lastPage + 1,
        ));
        final result = state.value;

        return Column(children: [
          TextButton(
            onPressed: state.fetchNextPage,
            child: const Text('fetchNextPage'),
          ),
          TextButton(
            onPressed: state.refetch,
            child: const Text('refetch'),
          ),
          Text('data: ${_json(result.dataOrNull)}'),
          Text('status: ${result.status.name}, ${result.fetchStatus.name}'),
        ]);
      }),
    );

    await advance(tester, 51);
    expect(find.text('status: success, idle'), findsOneWidget);
    expect(find.text('data: {"pages":[10],"pageParams":[10]}'), findsOneWidget);

    await click(tester, 'refetch');
    await advance(tester, 0);
    expect(find.text('status: success, fetching'), findsOneWidget);

    await click(tester, 'fetchNextPage');
    await advance(tester, 51);
    expect(find.text('status: success, idle'), findsOneWidget);
    expect(
      find.text('data: {"pages":[10,11],"pageParams":[10,11]}'),
      findsOneWidget,
    );
  });

  // useInfiniteQuery.test.tsx:913
  hookTest(
      'should silently cancel an ongoing fetchNextPage request when another '
      'fetchNextPage is invoked', (tester, client) async {
    final key = queryKey();
    const start = 10;
    final calls = <InfinitePageContext<int>>[];
    final onAborts = <_Calls>[];
    final abortListeners = <_Calls>[];

    Future<int> fetchPage(InfinitePageContext<int> context) async {
      calls.add(context);
      final onAbort = _Calls();
      final abortListener = _Calls();
      onAborts.add(onAbort);
      abortListeners.add(abortListener);
      context.signal
        ..onCancel(onAbort.call)
        ..onCancel(abortListener.call);
      await sleep(50);
      return context.pageParam;
    }

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final fetchNextPage = useInfiniteQuery(
          InfiniteQueryObserverOptions<int, int>(
            queryKey: key,
            pageFn: fetchPage,
            initialPageParam: start,
            getNextPageParam: (lastPage, _, __, ___) => lastPage + 1,
          ),
        ).fetchNextPage;

        useEffect(() {
          final timers = [
            Timer(_ms(100), fetchNextPage),
            Timer(_ms(110), fetchNextPage),
          ];
          return () => _cancelAll(timers);
        }, [fetchNextPage]);

        return const SizedBox();
      }),
    );

    await advance(tester, 160);

    const expectedCallCount = 3;
    expect(calls, hasLength(expectedCallCount));
    expect(onAborts, hasLength(expectedCallCount));
    expect(abortListeners, hasLength(expectedCallCount));

    var callIndex = 0;
    final firstCtx = calls[callIndex];
    expect(firstCtx.pageParam, start);
    expect(firstCtx.queryKey, key);
    expect(firstCtx.signal, isA<QueryCancelToken>());
    expect(firstCtx.signal.isCancelled, isFalse);
    expect(onAborts[callIndex].count, 0);
    expect(abortListeners[callIndex].count, 0);

    callIndex = 1;
    final secondCtx = calls[callIndex];
    expect(secondCtx.pageParam, 11);
    expect(secondCtx.queryKey, key);
    expect(secondCtx.signal, isA<QueryCancelToken>());
    expect(secondCtx.signal.isCancelled, isTrue);
    expect(onAborts[callIndex].count, 1);
    expect(abortListeners[callIndex].count, 1);

    callIndex = 2;
    final thirdCtx = calls[callIndex];
    expect(thirdCtx.pageParam, 11);
    expect(thirdCtx.queryKey, key);
    expect(thirdCtx.signal, isA<QueryCancelToken>());
    expect(thirdCtx.signal.isCancelled, isFalse);
    expect(onAborts[callIndex].count, 0);
    expect(abortListeners[callIndex].count, 0);
  });

  // useInfiniteQuery.test.tsx:988
  hookTest(
      'should not cancel an ongoing fetchNextPage request when another '
      'fetchNextPage is invoked if `cancelRefetch: false` is used',
      (tester, client) async {
    final key = queryKey();
    const start = 10;
    final calls = <InfinitePageContext<int>>[];
    final onAborts = <_Calls>[];
    final abortListeners = <_Calls>[];

    Future<int> fetchPage(InfinitePageContext<int> context) async {
      calls.add(context);
      final onAbort = _Calls();
      final abortListener = _Calls();
      onAborts.add(onAbort);
      abortListeners.add(abortListener);
      context.signal
        ..onCancel(onAbort.call)
        ..onCancel(abortListener.call);
      await sleep(50);
      return context.pageParam;
    }

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final fetchNextPage = useInfiniteQuery(
          InfiniteQueryObserverOptions<int, int>(
            queryKey: key,
            pageFn: fetchPage,
            initialPageParam: start,
            getNextPageParam: (lastPage, _, __, ___) => lastPage + 1,
          ),
        ).fetchNextPage;

        useEffect(() {
          final timers = [
            Timer(_ms(100), fetchNextPage),
            Timer(_ms(110), () => fetchNextPage(cancelRefetch: false)),
          ];
          return () => _cancelAll(timers);
        }, [fetchNextPage]);

        return const SizedBox();
      }),
    );

    await advance(tester, 160);

    const expectedCallCount = 2;
    expect(calls, hasLength(expectedCallCount));
    expect(onAborts, hasLength(expectedCallCount));
    expect(abortListeners, hasLength(expectedCallCount));

    var callIndex = 0;
    final firstCtx = calls[callIndex];
    expect(firstCtx.pageParam, start);
    expect(firstCtx.queryKey, key);
    expect(firstCtx.signal, isA<QueryCancelToken>());
    expect(firstCtx.signal.isCancelled, isFalse);
    expect(onAborts[callIndex].count, 0);
    expect(abortListeners[callIndex].count, 0);

    callIndex = 1;
    final secondCtx = calls[callIndex];
    expect(secondCtx.pageParam, 11);
    expect(secondCtx.queryKey, key);
    expect(secondCtx.signal, isA<QueryCancelToken>());
    expect(secondCtx.signal.isCancelled, isFalse);
    expect(onAborts[callIndex].count, 0);
    expect(abortListeners[callIndex].count, 0);
  });

  // useInfiniteQuery.test.tsx:1054
  hookTest(
      'should keep fetching first page when not loaded yet and triggering '
      'fetch more', (tester, client) async {
    final key = queryKey();
    final rec = _Rec<InfiniteData<int, int>>();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        const start = 10;
        final state = rec.build(useInfiniteQuery(
          InfiniteQueryObserverOptions<int, int>(
            queryKey: key,
            pageFn: (context) => sleep(50).then((_) => context.pageParam),
            initialPageParam: start,
            getNextPageParam: (lastPage, _, __, ___) => lastPage + 1,
          ),
          buildWhen: rec.buildWhen,
        ));

        final fetchNextPage = state.fetchNextPage;

        useEffect(() {
          final timer = Timer(_ms(10), fetchNextPage);
          return timer.cancel;
        }, [fetchNextPage]);

        return const SizedBox();
      }),
    );

    await advance(tester, 60);

    expect(rec.builds, hasLength(2));
    _expectMatch(rec.builds[0], {
      'hasNextPage': false,
      'data': null,
      'isFetching': true,
      'isFetchingNextPage': false,
      'isSuccess': false,
    });
    _expectMatch(rec.builds[1], {
      'hasNextPage': true,
      'pages': [10],
      'isFetching': false,
      'isFetchingNextPage': false,
      'isSuccess': true,
    });
  });

  // useInfiniteQuery.test.tsx:1102
  hookTest(
      'should stop fetching additional pages when the component is unmounted '
      'and AbortSignal is consumed', (tester, client) async {
    final key = queryKey();
    var fetches = 0;

    final initialData =
        InfiniteData<int, int>(pages: [1, 2, 3, 4], pageParams: [0, 1, 2, 3]);

    Widget list() => HookBuilder(builder: (context) {
          useInfiniteQuery(InfiniteQueryObserverOptions<int, int>(
            queryKey: key,
            pageFn: (context) => sleep(50).then((_) {
              fetches++;
              return context.pageParam * 10;
            }),
            initialData: InitialData.value(initialData),
            initialPageParam: 0,
            getNextPageParam: (_, allPages, __, ___) {
              return allPages.length == 4 ? null : allPages.length;
            },
          ));

          return const SizedBox();
        });

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final show = useState(true);

        useEffect(() {
          final timer = Timer(_ms(75), () => show.value = false);
          return timer.cancel;
        }, const []);

        return show.value ? list() : const SizedBox();
      }),
    );

    await advance(tester, 125);

    expect(fetches, 2);
    final state = client.getQueryState<InfiniteData<int, int>>(key)!;
    expect(state.data, initialData);
    expect(state.status, QueryStatus.success);
    expect(state.error, isNull);

    // Drain: the page function never reads its signal, so the refetch the
    // unmount left behind runs on to its fourth page.
    await advance(tester, 100);
  });

  // useInfiniteQuery.test.tsx:1150
  hookTest('should be able to set new pages with the query client',
      (tester, client) async {
    final key = queryKey();

    var multiplier = 1;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final firstPage = useState(0);

        final state = useInfiniteQuery(InfiniteQueryObserverOptions<int, int>(
          queryKey: key,
          pageFn: (context) =>
              sleep(10).then((_) => multiplier * context.pageParam),
          getNextPageParam: (lastPage, _, __, ___) => lastPage + 1,
          initialPageParam: firstPage.value,
        ));

        return Column(children: [
          TextButton(
            onPressed: () {
              client.setQueryData<InfiniteData<int, int>>(
                key,
                InfiniteData(pages: [7, 8], pageParams: [7, 8]),
              );
              firstPage.value = 7;
            },
            child: const Text('setPages'),
          ),
          TextButton(
            onPressed: state.refetch,
            child: const Text('refetch'),
          ),
          Text('data: ${_json(state.value.dataOrNull)}'),
        ]);
      }),
    );

    await advance(tester, 11);
    expect(find.text('data: {"pages":[0],"pageParams":[0]}'), findsOneWidget);

    await click(tester, 'setPages');
    await advance(tester, 11);
    expect(
      find.text('data: {"pages":[7,8],"pageParams":[7,8]}'),
      findsOneWidget,
    );

    multiplier = 2;

    await click(tester, 'refetch');
    await advance(tester, 21);
    expect(
      find.text('data: {"pages":[14,30],"pageParams":[7,15]}'),
      findsOneWidget,
    );
  });

  // useInfiniteQuery.test.tsx:1207 — the render stream under real timers is
  // the per-build snapshot list under fake time; `takeRender` is the next
  // build.
  hookTest('should only refetch the first page when initialData is provided',
      (tester, client) async {
    final key = queryKey();
    final rec = _Rec<InfiniteData<int, int>>();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final state = rec.build(useInfiniteQuery(
          InfiniteQueryObserverOptions<int, int>(
            queryKey: key,
            pageFn: (context) => sleep(10).then((_) => context.pageParam),
            initialData: InitialData.value(
              InfiniteData(pages: [1], pageParams: [1]),
            ),
            getNextPageParam: (lastPage, _, __, ___) => lastPage + 1,
            initialPageParam: 0,
          ),
          buildWhen: rec.buildWhen,
        ));

        return TextButton(
          onPressed: state.fetchNextPage,
          child: const Text('fetchNextPage'),
        );
      }),
    );

    {
      final snapshot = rec.builds[0];
      _expectMatch(snapshot, {
        'pages': [1],
        'hasNextPage': true,
        'isFetching': true,
        'isFetchingNextPage': false,
        'isSuccess': true,
      });
    }

    await advance(tester, 11);
    {
      final snapshot = rec.builds[1];
      _expectMatch(snapshot, {
        'pages': [1],
        'hasNextPage': true,
        'isFetching': false,
        'isFetchingNextPage': false,
        'isSuccess': true,
      });
    }

    await click(tester, 'fetchNextPage');

    {
      final snapshot = rec.builds[2];
      _expectMatch(snapshot, {
        'pages': [1],
        'hasNextPage': true,
        'isFetching': true,
        'isFetchingNextPage': true,
        'isSuccess': true,
      });
    }
    await advance(tester, 11);
    {
      final snapshot = rec.builds[3];
      _expectMatch(snapshot, {
        'pages': [1, 2],
        'hasNextPage': true,
        'isFetching': false,
        'isFetchingNextPage': false,
        'isSuccess': true,
      });
    }
  });

  // useInfiniteQuery.test.tsx:1284
  hookTest(
      'should keep initialData visible alongside the error when a refetch '
      'fails', (tester, client) async {
    final key = queryKey();
    final rec = _Rec<InfiniteData<int, int>>();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        rec.build(useInfiniteQuery(
          InfiniteQueryObserverOptions<int, int>(
            queryKey: key,
            pageFn: (_) => sleep(10)
                .then((_) => Future<int>.error(StateError('Some error'))),
            initialData: InitialData.value(
              InfiniteData(pages: [1], pageParams: [1]),
            ),
            getNextPageParam: (lastPage, _, __, ___) => lastPage + 1,
            initialPageParam: 0,
            retry: RetryPolicy.never,
          ),
          buildWhen: rec.buildWhen,
        ));

        return const SizedBox();
      }),
    );

    await advance(tester, 11);

    expect(rec.builds, hasLength(2));
    _expectMatch(rec.builds[0], {
      'pages': [1],
      'isError': false,
    });
    _expectMatch(rec.builds[1], {
      'pages': [1],
      'isError': true,
    });
  });

  // useInfiniteQuery.test.tsx:1319
  hookTest(
      'should set hasNextPage to false if getNextPageParam returns '
      'undefined', (tester, client) async {
    final key = queryKey();
    final rec = _Rec<InfiniteData<int, int>>();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        rec.build(useInfiniteQuery(
          InfiniteQueryObserverOptions<int, int>(
            queryKey: key,
            pageFn: (context) => sleep(10).then((_) => context.pageParam),
            getNextPageParam: (_, __, ___, ____) => null,
            initialPageParam: 1,
          ),
          buildWhen: rec.buildWhen,
        ));

        return const SizedBox();
      }),
    );

    await advance(tester, 11);

    expect(rec.builds, hasLength(2));
    _expectMatch(rec.builds[0], {
      'data': null,
      'hasNextPage': false,
      'isFetching': true,
      'isFetchingNextPage': false,
      'isSuccess': false,
    });
    _expectMatch(rec.builds[1], {
      'pages': [1],
      'hasNextPage': false,
      'isFetching': false,
      'isFetchingNextPage': false,
      'isSuccess': true,
    });
  });

  // useInfiniteQuery.test.tsx:1357
  hookTest('should compute hasNextPage correctly using initialData',
      (tester, client) async {
    final key = queryKey();
    final rec = _Rec<InfiniteData<int, int>>();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        rec.build(useInfiniteQuery(
          InfiniteQueryObserverOptions<int, int>(
            queryKey: key,
            pageFn: (context) => sleep(10).then((_) => context.pageParam),
            initialData: InitialData.value(
              InfiniteData(pages: [10], pageParams: [10]),
            ),
            getNextPageParam: (lastPage, _, __, ___) =>
                lastPage == 10 ? 11 : null,
            initialPageParam: 10,
          ),
          buildWhen: rec.buildWhen,
        ));

        return const SizedBox();
      }),
    );

    await advance(tester, 11);

    expect(rec.builds, hasLength(2));
    _expectMatch(rec.builds[0], {
      'pages': [10],
      'hasNextPage': true,
      'isFetching': true,
      'isFetchingNextPage': false,
      'isSuccess': true,
    });
    _expectMatch(rec.builds[1], {
      'pages': [10],
      'hasNextPage': true,
      'isFetching': false,
      'isFetchingNextPage': false,
      'isSuccess': true,
    });
  });

  // useInfiniteQuery.test.tsx:1396
  hookTest(
      'should compute hasNextPage correctly for falsy getFetchMore return '
      'value using initialData', (tester, client) async {
    final key = queryKey();
    final rec = _Rec<InfiniteData<int, int>>();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        rec.build(useInfiniteQuery(
          InfiniteQueryObserverOptions<int, int>(
            queryKey: key,
            pageFn: (context) => sleep(10).then((_) => context.pageParam),
            initialPageParam: 10,
            initialData: InitialData.value(
              InfiniteData(pages: [10], pageParams: [10]),
            ),
            getNextPageParam: (_, __, ___, ____) => null,
          ),
          buildWhen: rec.buildWhen,
        ));

        return const SizedBox();
      }),
    );

    await advance(tester, 11);

    expect(rec.builds, hasLength(2));
    _expectMatch(rec.builds[0], {
      'pages': [10],
      'hasNextPage': false,
      'isFetching': true,
      'isFetchingNextPage': false,
      'isSuccess': true,
    });
    _expectMatch(rec.builds[1], {
      'pages': [10],
      'hasNextPage': false,
      'isFetching': false,
      'isFetchingNextPage': false,
      'isSuccess': true,
    });
  });

  // useInfiniteQuery.test.tsx:1435
  hookTest('should not use selected data when computing hasNextPage',
      (tester, client) async {
    final key = queryKey();
    final rec = _Rec<InfiniteData<String, int>>();

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        rec.build(useInfiniteQuery(
          InfiniteQuerySelectOptions<int, int, InfiniteData<String, int>>(
            queryKey: key,
            pageFn: (context) => sleep(10).then((_) => context.pageParam),
            getNextPageParam: (lastPage, _, __, ___) =>
                lastPage == 1 ? 2 : null,
            select: (data) => InfiniteData(
              pages: data.pages.map((x) => x.toString()).toList(),
              pageParams: data.pageParams,
            ),
            initialPageParam: 1,
          ),
          buildWhen: rec.buildWhen,
        ));

        return const SizedBox();
      }),
    );

    await advance(tester, 11);

    expect(rec.builds, hasLength(2));
    _expectMatch(rec.builds[0], {
      'data': null,
      'hasNextPage': false,
      'isFetching': true,
      'isFetchingNextPage': false,
      'isSuccess': false,
    });
    _expectMatch(rec.builds[1], {
      'pages': ['1'],
      'hasNextPage': true,
      'isFetching': false,
      'isFetchingNextPage': false,
      'isSuccess': true,
    });
  });

  // useInfiniteQuery.test.tsx:1477
  hookTest('should build fresh cursors on refetch', (tester, client) async {
    final key = queryKey();

    List<int> genItems(int size) => [for (var d = 0; d < size; d++) d];
    final items = genItems(15);
    const limit = 3;

    Future<_Result> fetchItemsWithLimit(int cursor, int ts) =>
        sleep(10).then((_) => (
              nextId: cursor + limit,
              prevId: null,
              items: items.sublist(
                min(cursor, items.length),
                min(cursor + limit, items.length),
              ),
              ts: ts,
            ));

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final fetchCountRef = useRef(0);
        final query =
            useInfiniteQuery(InfiniteQueryObserverOptions<_Result, int>(
          queryKey: key,
          pageFn: (context) =>
              fetchItemsWithLimit(context.pageParam, fetchCountRef.value++),
          initialPageParam: 0,
          getNextPageParam: (lastPage, _, __, ___) => lastPage.nextId,
        ));
        final hasNextPage = query.hasNextPage;
        final isFetchingNextPage = query.isFetchingNextPage;

        return Column(children: [
          const Text('Pagination'),
          ...switch (query.value) {
            QueryPending() => [const Text('Loading...')],
            QueryError(:final error) => [Text('Error: $error')],
            QuerySuccess(:final data) => [
                const Text('Data:'),
                for (final (i, page) in data.pages.indexed) ...[
                  Text('Page $i: ${page.ts}'),
                  Wrap(children: [
                    for (final item in page.items) Text('Item: $item'),
                  ]),
                ],
                TextButton(
                  onPressed: !hasNextPage || isFetchingNextPage
                      ? null
                      : query.fetchNextPage,
                  child: Text(isFetchingNextPage
                      ? 'Loading more...'
                      : hasNextPage
                          ? 'Load More'
                          : 'Nothing more to load'),
                ),
                TextButton(
                  onPressed: query.refetch,
                  child: const Text('Refetch'),
                ),
                TextButton(
                  onPressed: () {
                    // Imagine that this mutation happens somewhere else
                    // makes an actual network request
                    // and calls invalidateQueries in an onSuccess
                    items.removeAt(4);
                    client.invalidateQueries(
                      filters: QueryFilters(queryKey: key),
                    );
                  },
                  child: const Text('Remove item'),
                ),
                Text(!isFetchingNextPage ? 'Background Updating...' : ''),
              ],
          },
        ]);
      }),
    );

    expect(find.text('Loading...'), findsOneWidget);
    await advance(tester, 11);
    expect(find.text('Item: 2'), findsOneWidget);
    expect(find.text('Page 0: 0'), findsOneWidget);

    await click(tester, 'Load More');
    await advance(tester, 0);
    expect(find.text('Loading more...'), findsOneWidget);
    await advance(tester, 11);
    expect(find.text('Item: 5'), findsOneWidget);
    expect(find.text('Page 0: 0'), findsOneWidget);
    expect(find.text('Page 1: 1'), findsOneWidget);

    await click(tester, 'Load More');
    await advance(tester, 0);
    expect(find.text('Loading more...'), findsOneWidget);
    await advance(tester, 11);
    expect(find.text('Item: 8'), findsOneWidget);
    expect(find.text('Page 0: 0'), findsOneWidget);
    expect(find.text('Page 1: 1'), findsOneWidget);
    expect(find.text('Page 2: 2'), findsOneWidget);

    await click(tester, 'Refetch');
    await advance(tester, 0);
    expect(find.text('Background Updating...'), findsOneWidget);
    await advance(tester, 31);
    expect(find.text('Item: 8'), findsOneWidget);
    expect(find.text('Page 0: 3'), findsOneWidget);
    expect(find.text('Page 1: 4'), findsOneWidget);
    expect(find.text('Page 2: 5'), findsOneWidget);
    // ensure that Item: 4 is rendered before removing it
    expect(find.text('Item: 4'), findsNWidgets(1));

    // remove Item: 4
    await click(tester, 'Remove item');
    await advance(tester, 0);
    expect(find.text('Background Updating...'), findsOneWidget);
    // ensure that an additional item is rendered (it means that cursors were
    // properly rebuilt)
    await advance(tester, 31);
    expect(find.text('Item: 9'), findsOneWidget);
    expect(find.text('Page 0: 6'), findsOneWidget);
    expect(find.text('Page 1: 7'), findsOneWidget);
    expect(find.text('Page 2: 8'), findsOneWidget);
    // ensure that Item: 4 is no longer rendered
    expect(find.text('Item: 4'), findsNothing);
  });

  // useInfiniteQuery.test.tsx:1612
  hookTest(
      'should compute hasNextPage correctly for falsy getFetchMore return '
      'value on refetching', (tester, client) async {
    final key = queryKey();
    const max = 2;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final fetchCountRef = useRef(0);
        final isRemovedLastPage = useState(false);
        final query =
            useInfiniteQuery(InfiniteQueryObserverOptions<_Result, int>(
          queryKey: key,
          pageFn: (context) {
            final pageParam = context.pageParam;
            final noNext = pageParam == max ||
                (pageParam == max - 1 && isRemovedLastPage.value);
            return sleep(10).then((_) => (
                  items: [
                    for (var d = 0; d < 10; d++) pageParam * _pageSize + d,
                  ],
                  nextId: noNext ? null : pageParam + 1,
                  prevId: pageParam - 1,
                  ts: fetchCountRef.value++,
                ));
          },
          getNextPageParam: (lastPage, _, __, ___) => lastPage.nextId,
          initialPageParam: 0,
        ));
        final result = query.value;
        final hasNextPage = query.hasNextPage;
        final isFetchingNextPage = query.isFetchingNextPage;

        return Column(children: [
          const Text('Pagination'),
          ...switch (result) {
            QueryPending() => [const Text('Loading...')],
            QueryError(:final error) => [Text('Error: $error')],
            QuerySuccess(:final data) => [
                const Text('Data:'),
                for (final (i, page) in data.pages.indexed) ...[
                  Text('Page $i: ${page.ts}'),
                  Wrap(children: [
                    for (final item in page.items) Text('Item: $item'),
                  ]),
                ],
                TextButton(
                  onPressed: !hasNextPage || isFetchingNextPage
                      ? null
                      : query.fetchNextPage,
                  child: Text(isFetchingNextPage
                      ? 'Loading more...'
                      : hasNextPage
                          ? 'Load More'
                          : 'Nothing more to load'),
                ),
                TextButton(
                  onPressed: query.refetch,
                  child: const Text('Refetch'),
                ),
                TextButton(
                  onPressed: () => isRemovedLastPage.value = true,
                  child: const Text('Remove Last Page'),
                ),
                Text(result.isFetching && !isFetchingNextPage
                    ? 'Background Updating...'
                    : ''),
              ],
          },
        ]);
      }),
    );

    expect(find.text('Loading...'), findsOneWidget);
    await advance(tester, 11);
    expect(find.text('Item: 9'), findsOneWidget);
    expect(find.text('Page 0: 0'), findsOneWidget);

    await click(tester, 'Load More');
    await advance(tester, 0);
    expect(find.text('Loading more...'), findsOneWidget);
    await advance(tester, 11);
    expect(find.text('Item: 19'), findsOneWidget);
    expect(find.text('Page 0: 0'), findsOneWidget);
    expect(find.text('Page 1: 1'), findsOneWidget);

    await click(tester, 'Load More');
    await advance(tester, 0);
    expect(find.text('Loading more...'), findsOneWidget);
    await advance(tester, 11);
    expect(find.text('Item: 29'), findsOneWidget);
    expect(find.text('Page 0: 0'), findsOneWidget);
    expect(find.text('Page 1: 1'), findsOneWidget);
    expect(find.text('Page 2: 2'), findsOneWidget);
    expect(find.text('Nothing more to load'), findsOneWidget);

    await click(tester, 'Remove Last Page');
    await click(tester, 'Refetch');
    await advance(tester, 0);
    expect(find.text('Background Updating...'), findsOneWidget);
    await advance(tester, 21);
    expect(find.text('Item: 29'), findsNothing);
    expect(find.text('Page 0: 3'), findsOneWidget);
    expect(find.text('Page 1: 4'), findsOneWidget);
    expect(find.text('Page 2: 5'), findsNothing);
    expect(find.text('Nothing more to load'), findsOneWidget);
  });

  // useInfiniteQuery.test.tsx:1733
  hookTest(
      'should cancel the query function when there are no more '
      'subscriptions', (tester, client) async {
    final key = queryKey();
    var cancelFn = _Calls();

    Future<String> queryFn(InfinitePageContext<int> context) {
      final promise = Completer<String>();
      final cancel = cancelFn = _Calls(() {
        if (!promise.isCompleted) promise.completeError('Cancelled');
      });
      context.signal.onCancel(cancel.call);
      sleep(1000).then((_) {
        if (!promise.isCompleted) promise.complete('OK');
      });
      return promise.future;
    }

    Widget inner() => HookBuilder(builder: (context) {
          final state =
              useInfiniteQuery(InfiniteQueryObserverOptions<String, int>(
            queryKey: key,
            pageFn: queryFn,
            getNextPageParam: (_, __, ___, ____) => null,
            initialPageParam: 0,
          ));
          return Text('Status: ${state.value.status.name}');
        });

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final isVisible = useState(true);

        return Column(children: [
          TextButton(
            onPressed: () => isVisible.value = false,
            child: const Text('hide'),
          ),
          if (isVisible.value) inner(),
          Text(isVisible.value ? 'visible' : 'hidden'),
        ]);
      }),
    );

    expect(find.text('visible'), findsOneWidget);

    await click(tester, 'hide');
    expect(find.text('hidden'), findsOneWidget);

    expect(cancelFn.count, greaterThan(0));

    // Drain the page function's own 1000 ms sleep.
    await advance(tester, 1000);
  });

  // useInfiniteQuery.test.tsx:1783
  hookTest('should use provided custom queryClient', (tester, client) async {
    final key = queryKey();
    Future<String> queryFn(InfinitePageContext<int> _) =>
        sleep(10).then((_) => 'custom client');

    await tester.pumpWidget(MaterialApp(
      home: HookBuilder(builder: (context) {
        final data = useInfiniteQuery(
          InfiniteQueryObserverOptions<String, int>(
            queryKey: key,
            pageFn: queryFn,
            getNextPageParam: (_, __, ___, ____) => null,
            initialPageParam: 0,
          ),
          client: client,
        ).value.dataOrNull;

        return Text('data: ${data?.pages[0] ?? ''}');
      }),
    ));

    await advance(tester, 11);
    expect(find.text('data: custom client'), findsOneWidget);
  });

  // useInfiniteQuery.test.tsx:1807 — D14: `queryFn: postId != null ? queryFn
  // : skipToken` is a fixed `pageFn` with `enabled` following `postId`, the
  // spelling the core documents for `skipToken`.
  hookTest(
      'should not fetch when queryFn is skipToken, and fetch once it is '
      'replaced', (tester, client) async {
    final key = queryKey();
    var queryFnCalls = 0;
    Future<String> queryFn(InfinitePageContext<int> context) {
      queryFnCalls++;
      return sleep(10).then((_) => 'comments for 1 page ${context.pageParam}');
    }

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final postId = useState<String?>(null);

        final result = useInfiniteQuery(
          InfiniteQueryObserverOptions<String, int>(
            queryKey: key,
            pageFn: queryFn,
            enabled: postId.value != null ? Enabled.yes : Enabled.no,
            initialPageParam: 0,
            getNextPageParam: (_, __, ___, ____) => 12,
          ),
        ).value;

        return Column(children: [
          Text('isFetching: ${result.isFetching}'),
          Text('pages: ${result.dataOrNull?.pages.join(', ') ?? 'none'}'),
          TextButton(
            onPressed: () => postId.value = '1',
            child: const Text('set postId'),
          ),
        ]);
      }),
    );

    expect(find.text('isFetching: false'), findsOneWidget);

    await advance(tester, 11);
    expect(queryFnCalls, 0);
    expect(find.text('isFetching: false'), findsOneWidget);
    expect(find.text('pages: none'), findsOneWidget);

    await click(tester, 'set postId');
    await advance(tester, 11);
    expect(queryFnCalls, 1);
    expect(find.text('pages: comments for 1 page 0'), findsOneWidget);
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

/// Upstream's `states` for a hook that returns its controller (plan, D9):
/// [builds] holds one [Snapshot] per build — the result *and* the paging
/// flags, read when the build ran — and [delivered] what the controller
/// handed `buildWhen`, as `Recorder.delivered` does.
///
/// `buildWhen` compares results, so a move of the paging flags alone never
/// reaches it: it rebuilds without asking (`RebuildRule`), and shows up in
/// [builds] only.
final class _Rec<TData> {
  final List<Snapshot<TData>> builds = <Snapshot<TData>>[];
  final List<QueryResult<TData>> delivered = <QueryResult<TData>>[];

  /// Records [controller] as this build shows it and returns it.
  InfiniteQueryController<TPageData, TPageParam, TData>
      build<TPageData, TPageParam>(
    InfiniteQueryController<TPageData, TPageParam, TData> controller,
  ) {
    builds.add(snapshot(controller));
    return controller;
  }

  /// Records what it is asked about and rebuilds — what no `buildWhen` does.
  BuildWhen<QueryResult<TData>> get buildWhen => (previous, current) {
        delivered.add(current);
        return true;
      };
}

/// Upstream's `expect(state).toMatchObject({…})`: every field [expected]
/// names, and no other, equals what [state] showed. `data: undefined` is
/// `'data': null`; `data: { pages: […] }` is `'pages': […]`, which leaves the
/// page params out as `toMatchObject` does.
void _expectMatch(
  Snapshot<InfiniteData<Object?, Object?>> state,
  Map<String, Object?> expected,
) {
  final result = state.result;
  final shown = <String, Object?>{
    'data': result.dataOrNull,
    'pages': result.dataOrNull?.pages,
    'hasNextPage': state.hasNextPage,
    'hasPreviousPage': state.hasPreviousPage,
    'isError': result.isError,
    'isFetching': result.isFetching,
    'isFetchNextPageError': state.isFetchNextPageError,
    'isFetchingNextPage': state.isFetchingNextPage,
    'isFetchPreviousPageError': state.isFetchPreviousPageError,
    'isFetchingPreviousPage': state.isFetchingPreviousPage,
    'isPlaceholderData': result.isPlaceholderData,
    'isRefetchError': state.isRefetchError,
    'isRefetching': state.isRefetching,
    'isSuccess': result.isSuccess,
  };
  for (final MapEntry(:key, :value) in expected.entries) {
    expect(shown.containsKey(key), isTrue, reason: 'no field $key');
    expect(shown[key], value, reason: key);
  }
}

/// `isLoadingError`, which only an error result can be.
bool _isLoadingError(QueryResult<Object?> result) => switch (result) {
      QueryError(:final isLoadingError) => isLoadingError,
      _ => false,
    };

/// `JSON.stringify(data)` for the pages these cases hold; `undefined`
/// renders as nothing.
String _json<TPageData, TPageParam>(
  InfiniteData<TPageData, TPageParam>? data,
) =>
    data == null
        ? ''
        : jsonEncode({'pages': data.pages, 'pageParams': data.pageParams});

/// Upstream's `vi.fn()`: how often it ran, and what it does when it does.
final class _Calls {
  _Calls([this._body]);

  final void Function()? _body;
  int count = 0;

  void call() {
    count++;
    _body?.call();
  }
}

const _pageSize = 10;

/// Upstream's `interface Result`.
typedef _Result = ({List<int> items, int? nextId, int? prevId, int ts});
