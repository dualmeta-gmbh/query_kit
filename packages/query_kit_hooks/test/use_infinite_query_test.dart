// Ported from
// query/packages/react-query/src/__tests__/useInfiniteQuery.test.tsx at
// 50680b98c. Spike selection (AP0 of docs/plans/hooks-package.md). The hook
// returns the controller, so each build records a snapshot of the result and
// the paging flags beside it.
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_hooks/query_kit_hooks.dart';

import 'harness.dart';

typedef Snapshot<T> = ({
  QueryResult<T> result,
  bool hasNextPage,
  bool hasPreviousPage,
  bool isFetchingNextPage,
  bool isFetchingPreviousPage,
  bool isFetchNextPageError,
  bool isFetchPreviousPageError,
});

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
    );

void main() {
  // useInfiniteQuery.test.tsx:48
  hookTest('should return the correct states for a successful query',
      (tester, client) async {
    final key = queryKey();
    final states = <Snapshot<InfiniteData<int, int>>>[];

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final state = useInfiniteQuery(InfiniteQueryObserverOptions<int, int>(
          queryKey: key,
          pageFn: (context) => sleep(10).then((_) => context.pageParam),
          getNextPageParam: (lastPage, _, __, ___) => lastPage + 1,
          initialPageParam: 0,
        ));
        states.add(snapshot(state));
        return const SizedBox();
      }),
    );

    await advance(tester, 11);

    expect(states, hasLength(2));

    final first = states[0];
    expect(first.result.dataOrNull, isNull);
    expect(first.result.dataUpdatedAt, isNull);
    expect(first.result.errorOrNull, isNull);
    expect(first.result.failureCount, 0);
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
    expect(first.result.isPlaceholderData, isFalse);
    expect(first.result.isRefetching, isFalse);
    expect(first.result.isStale, isTrue);
    expect(first.result.isSuccess, isFalse);
    expect(first.result.isEnabled, isTrue);
    expect(first.result.status, QueryStatus.pending);
    expect(first.result.fetchStatus, FetchStatus.fetching);

    final second = states[1];
    expect(second.result.dataOrNull!.pages, [0]);
    expect(second.result.dataOrNull!.pageParams, [0]);
    expect(second.result.dataUpdatedAt, isNotNull);
    expect(second.result.errorOrNull, isNull);
    expect(second.result.failureCount, 0);
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
    expect(second.result.isPlaceholderData, isFalse);
    expect(second.result.isRefetching, isFalse);
    expect(second.result.isStale, isTrue);
    expect(second.result.isSuccess, isTrue);
    expect(second.result.isEnabled, isTrue);
    expect(second.result.status, QueryStatus.success);
    expect(second.result.fetchStatus, FetchStatus.idle);
  });

  // useInfiniteQuery.test.tsx:180 — `notifyOnChangeProps: 'all'` is the
  // default here.
  hookTest('should keep the previous data when placeholderData is set',
      (tester, client) async {
    final key = queryKey();
    final states = <Snapshot<InfiniteData<String, int>>>[];

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final order = useState('desc');
        final state =
            useInfiniteQuery(InfiniteQueryObserverOptions<String, int>(
          queryKey: QueryKey([...key.parts, order.value]),
          pageFn: (context) {
            final o = order.value;
            return sleep(10).then((_) => '${context.pageParam}-$o');
          },
          getNextPageParam: (_, __, ___, ____) => 1,
          initialPageParam: 0,
          placeholderData: const PlaceholderData.keepPrevious(),
        ));
        states.add(snapshot(state));
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

    expect(states, hasLength(6));
    final expected = <(List<String>?, bool, bool, bool, bool)>[
      (null, true, false, false, false),
      (['0-desc'], false, false, true, false),
      (['0-desc'], true, true, true, false),
      (['0-desc', '1-desc'], false, false, true, false),
      // Set state
      (['0-desc', '1-desc'], true, false, true, true),
      (['0-asc'], false, false, true, false),
    ];
    for (var i = 0; i < expected.length; i++) {
      final s = states[i];
      expect(s.result.dataOrNull?.pages, expected[i].$1, reason: 'states[$i]');
      expect(
        (
          s.result.isFetching,
          s.isFetchingNextPage,
          s.result.isSuccess,
          s.result.isPlaceholderData,
        ),
        (expected[i].$2, expected[i].$3, expected[i].$4, expected[i].$5),
        reason: 'states[$i]',
      );
    }
  });
}
