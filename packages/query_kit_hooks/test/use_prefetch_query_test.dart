// Ported from
// query/packages/react-query/src/__tests__/usePrefetchQuery.test.tsx at
// 50680b98c. Each case keeps upstream's name, and its upstream line is in
// the comment above it. What was adapted or omitted, and why, is in
// PORTING_NOTES.md.
//
// Every upstream case reads through `useSuspenseQuery` inside a
// `React.Suspense`, which Flutter does not have (plan, D14). A reader here is
// `useQuery` over `suspense(options)`, which holds what `useSuspenseQuery`
// puts on the options it observes. Its pending branch is the suspense
// fallback, in place of the reader and everything it wraps, and its error
// branch is the error boundary's fallback.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_hooks/query_kit_hooks.dart';

import 'harness.dart';

/// What `useSuspenseQuery` observes for [options]: `ensureSuspenseTimers`
/// raises `staleTime` to at least 1000 ms, and
/// `ensurePreventErrorBoundaryRetry` sets `retryOnMount: false` while no
/// error boundary has been reset, which no case here does before its reader
/// mounts.
QueryObserverOptions<T> suspense<T>(QueryOptions<T> options) =>
    QueryObserverOptions<T>(
      queryKey: options.queryKey,
      queryFn: options.queryFn,
      staleTime: const StaleTime.duration(Duration(seconds: 1)),
      retryOnMount: false,
    );

void main() {
  // usePrefetchQuery.test.tsx:31 — adapted (D14): the reader is `useQuery`
  // over `suspense(…)`, and its pending branch is the fallback.
  hookTest('should prefetch query if query state does not exist',
      (tester, client) async {
    var queryFnCalls = 0;
    final queryOpts = QueryOptions<String>(
      queryKey: queryKey(),
      queryFn: (_) {
        queryFnCalls++;
        return sleep(10).then((_) => 'prefetchQuery');
      },
    );

    final componentQueryOpts = queryOpts.copyWith(
      queryFn: (_) => sleep(10).then((_) => 'useSuspenseQuery'),
    );

    Widget page() => HookBuilder(builder: (context) {
          final state = useQuery(suspense(componentQueryOpts));
          if (state.isPending) {
            return const Text('Loading...');
          }
          return Text('data: ${state.dataOrNull}');
        });

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        usePrefetchQuery(queryOpts);
        return page();
      }),
    );

    expect(find.text('Loading...'), findsOneWidget);

    await advance(tester, 10);
    expect(find.text('data: prefetchQuery'), findsOneWidget);
    expect(queryFnCalls, 1);
  });

  // usePrefetchQuery.test.tsx:66 — adapted (D14): the reader is `useQuery`
  // over `suspense(…)`; without the 1000 ms floor it would refetch the
  // prefetched data on mount. Upstream's `fetching: true` text is rendered
  // by nothing, so the case also asserts that nothing fetches.
  hookTest('should not prefetch query if query state exists',
      (tester, client) async {
    var queryFnCalls = 0;
    final queryOpts = QueryOptions<String>(
      queryKey: queryKey(),
      queryFn: (_) {
        queryFnCalls++;
        return sleep(10).then((_) => 'The usePrefetchQuery hook is smart!');
      },
    );

    Widget page() => HookBuilder(builder: (context) {
          final state = useQuery(suspense(queryOpts));
          if (state.isPending) {
            return const Text('Loading...');
          }
          return Text('data: ${state.dataOrNull}');
        });

    // The type argument is needed: `unawaited`'s parameter would infer
    // `void`, and the cache is typed.
    unawaited(client.query<String>(queryOpts));
    await advance(tester, 10);
    queryFnCalls = 0;
    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        usePrefetchQuery(queryOpts);
        return page();
      }),
    );

    expect(find.text('fetching: true'), findsNothing);
    expect(client.isFetching(), 0);
    expect(
      find.text('data: The usePrefetchQuery hook is smart!'),
      findsOneWidget,
    );
    expect(queryFnCalls, 0);
  });

  // usePrefetchQuery.test.tsx:101 — adapted (D14): the reader is `useQuery`
  // over `suspense(…)`, and its error branch is the error boundary's
  // fallback. `retryOnMount: false` is what keeps the reader from
  // refetching, as it keeps `useSuspenseQuery` from it.
  hookTest('should let errors fall through and not refetch failed queries',
      (tester, client) async {
    var queryFnCalls = 0;
    var failOnce = true;
    final queryOpts = QueryOptions<String>(
      queryKey: queryKey(),
      queryFn: (_) {
        queryFnCalls++;
        if (failOnce) {
          failOnce = false;
          return sleep(10).then((_) => throw StateError('Oops! Server error!'));
        }
        return sleep(10).then((_) => 'Not an error');
      },
    );

    Widget page() => HookBuilder(builder: (context) {
          final state = useQuery(suspense(queryOpts));
          if (state.isError) {
            return const Text('Oops!');
          }
          if (state.isPending) {
            return const Text('Loading...');
          }
          return Text('data: ${state.dataOrNull}');
        });

    unawaited(prefetch(client, queryOpts));
    await advance(tester, 10);
    queryFnCalls = 0;
    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        usePrefetchQuery(queryOpts);
        return page();
      }),
    );

    expect(find.text('Oops!'), findsOneWidget);
    expect(find.text('data: Not an error'), findsNothing);
    expect(queryFnCalls, 0);
  });

  // usePrefetchQuery.test.tsx:240 — adapted (D14): each reader is
  // `useQuery` over `suspense(…)` and builds the fallback, not its children,
  // while pending, which is the waterfall a suspense boundary makes.
  hookTest('should not create a suspense waterfall if prefetch is fired',
      (tester, client) async {
    final calls = <String, int>{};
    QueryOptions<String> options(String name, String data) =>
        QueryOptions<String>(
          queryKey: queryKey(),
          queryFn: (_) {
            calls[name] = (calls[name] ?? 0) + 1;
            return sleep(10).then((_) => data);
          },
        );
    final firstQueryOpts = options('first', 'Prefetch is nice!');
    final secondQueryOpts = options('second', 'Prefetch is really nice!!');
    final thirdQueryOpts =
        options('third', 'Prefetch does not create waterfalls!!');

    var fallbackCalls = 0;
    Widget fallback() => Builder(builder: (context) {
          fallbackCalls++;
          return const Text('Loading...');
        });

    Widget query(QueryOptions<String> options, [Widget? child]) =>
        HookBuilder(builder: (context) {
          final state = useQuery(suspense(options));
          if (state.isPending) {
            return fallback();
          }
          return Column(children: [
            Text('data: ${state.dataOrNull}'),
            if (child != null) child,
          ]);
        });

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        usePrefetchQuery(firstQueryOpts);
        usePrefetchQuery(secondQueryOpts);
        usePrefetchQuery(thirdQueryOpts);

        return query(
          firstQueryOpts,
          query(secondQueryOpts, query(thirdQueryOpts)),
        );
      }),
    );

    expect(
      client.getQueryState<String>(firstQueryOpts.queryKey)?.fetchStatus,
      FetchStatus.fetching,
    );
    expect(
      client.getQueryState<String>(secondQueryOpts.queryKey)?.fetchStatus,
      FetchStatus.fetching,
    );
    expect(
      client.getQueryState<String>(thirdQueryOpts.queryKey)?.fetchStatus,
      FetchStatus.fetching,
    );
    expect(find.text('Loading...'), findsOneWidget);
    await advance(tester, 10);
    expect(find.text('data: Prefetch is nice!'), findsOneWidget);
    expect(find.text('data: Prefetch is really nice!!'), findsOneWidget);
    expect(
      find.text('data: Prefetch does not create waterfalls!!'),
      findsOneWidget,
    );
    expect(fallbackCalls, 1);
    expect(calls['first'], 1);
    expect(calls['second'], 1);
    expect(calls['third'], 1);
  });
}
