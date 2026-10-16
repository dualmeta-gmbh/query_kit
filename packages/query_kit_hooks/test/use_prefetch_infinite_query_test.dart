// Ported from
// query/packages/react-query/src/__tests__/usePrefetchInfiniteQuery.test.tsx
// at 50680b98c. Each case keeps upstream's name, and its upstream line is in
// the comment above it. What was adapted or omitted, and why, is in
// PORTING_NOTES.md.
//
// Every upstream case reads through `useSuspenseInfiniteQuery` inside a
// `React.Suspense`, which Flutter does not have (plan, D14). A reader here is
// `useInfiniteQuery` over `suspense(options)`, which holds what
// `useSuspenseInfiniteQuery` puts on the options it observes. Its pending
// branch is the suspense fallback, in place of the reader.
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_hooks/query_kit_hooks.dart';

import 'harness.dart';

/// What `useSuspenseInfiniteQuery` observes for [options]:
/// `ensureSuspenseTimers` raises `staleTime` to at least 1000 ms, and
/// `ensurePreventErrorBoundaryRetry` sets `retryOnMount: false` while no
/// error boundary has been reset.
InfiniteQueryObserverOptions<TPageData, TPageParam>
    suspense<TPageData, TPageParam>(
  InfiniteQueryOptions<TPageData, TPageParam> options,
) =>
        InfiniteQueryObserverOptions<TPageData, TPageParam>(
          queryKey: options.queryKey,
          pageFn: options.pageFn,
          initialPageParam: options.initialPageParam,
          getNextPageParam: options.getNextPageParam,
          getPreviousPageParam: options.getPreviousPageParam,
          maxPages: options.maxPages,
          staleTime: const StaleTime.duration(Duration(seconds: 1)),
          retryOnMount: false,
        );

void main() {
  // usePrefetchInfiniteQuery.test.tsx:29 — adapted (D14): the reader is
  // `useInfiniteQuery` over `suspense(…)`, and its pending branch is the
  // fallback.
  hookTest('should prefetch an infinite query if query state does not exist',
      (tester, client) async {
    var fallbackCalls = 0;
    Widget fallback() => Builder(builder: (context) {
          fallbackCalls++;
          return const Text('Loading...');
        });
    const data = [
      'Do you fetch on render?',
      'Or do you render as you fetch?',
      'Either way, Tanstack Query helps you!',
    ];

    var queryFnCalls = 0;
    final queryOpts = InfiniteQueryOptions<String, int>(
      queryKey: queryKey(),
      pageFn: (context) {
        queryFnCalls++;
        return sleep(10).then((_) => data[context.pageParam]);
      },
      initialPageParam: 0,
      getNextPageParam: (_, allPages, __, ___) =>
          allPages.length < data.length ? allPages.length : null,
    );

    Widget page() => HookBuilder(builder: (context) {
          final state = useInfiniteQuery(suspense(queryOpts));
          if (state.value.isPending) {
            return fallback();
          }
          return Column(children: [
            for (final page in state.value.dataOrNull!.pages)
              Text('data: $page'),
            TextButton(
              onPressed: state.fetchNextPage,
              child: const Text('Next Page'),
            ),
          ]);
        });

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        usePrefetchInfiniteQuery(queryOpts.copyWith(pages: data.length));
        return page();
      }),
    );

    await advance(tester, 30);
    expect(find.text('data: Do you fetch on render?'), findsOneWidget);
    await click(tester, 'Next Page');
    expect(find.text('data: Or do you render as you fetch?'), findsOneWidget);
    await click(tester, 'Next Page');
    expect(
      find.text('data: Either way, Tanstack Query helps you!'),
      findsOneWidget,
    );
    expect(fallbackCalls, 1);
    expect(queryFnCalls, 3);
  });

  // usePrefetchInfiniteQuery.test.tsx:88 — adapted (D14): the reader is
  // `useInfiniteQuery` over `suspense(…)`; without the 1000 ms floor it
  // would refetch the cached pages on mount.
  hookTest(
      'should not display fallback if the query cache is already populated',
      (tester, client) async {
    var fallbackCalls = 0;
    Widget fallback() => Builder(builder: (context) {
          fallbackCalls++;
          return const Text('Loading...');
        });
    const data = [
      'Prefetch rocks!',
      'No waterfalls, boy!',
      'Tanstack Query #ftw',
    ];

    var queryFnCalls = 0;
    final queryOpts = InfiniteQueryOptions<String, int>(
      queryKey: queryKey(),
      pageFn: (context) {
        queryFnCalls++;
        return sleep(10).then((_) => data[context.pageParam]);
      },
      initialPageParam: 0,
      getNextPageParam: (_, allPages, __, ___) =>
          allPages.length < data.length ? allPages.length : null,
    );

    client.infiniteQuery(queryOpts.copyWith(pages: 3)).ignore();
    await advance(tester, 30);
    queryFnCalls = 0;

    Widget page() => HookBuilder(builder: (context) {
          final state = useInfiniteQuery(suspense(queryOpts));
          if (state.value.isPending) {
            return fallback();
          }
          return Column(children: [
            for (final page in state.value.dataOrNull!.pages)
              Text('data: $page'),
            TextButton(
              onPressed: state.fetchNextPage,
              child: const Text('Next Page'),
            ),
          ]);
        });

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        usePrefetchInfiniteQuery(queryOpts);
        return page();
      }),
    );

    expect(find.text('data: Prefetch rocks!'), findsOneWidget);
    await click(tester, 'Next Page');
    expect(find.text('data: No waterfalls, boy!'), findsOneWidget);
    await click(tester, 'Next Page');
    expect(find.text('data: Tanstack Query #ftw'), findsOneWidget);
    expect(queryFnCalls, 0);
    expect(fallbackCalls, 0);
  });
}
