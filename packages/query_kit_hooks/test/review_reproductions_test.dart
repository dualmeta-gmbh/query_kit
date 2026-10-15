// Reproductions of the plan reviews' findings (Astra H-01, H-03, H-04;
// Fable P2-1), each written to fail without the fix it names, and the
// hot-reload probe AP0 asks for.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_hooks/query_kit_hooks.dart';

import 'harness.dart';

void main() {
  // H-01: two sources fail, the second is then repaired. The combination
  // stays `CombinedError` with the first error — equal to the one built —
  // but `retry` now acts on fewer sources. A gate on the value alone would
  // keep the stale `retry`, which refetches the repaired source too.
  hookTest('combined: a change in what retry acts on rebuilds',
      (tester, client) async {
    final keyA = queryKey();
    final keyB = queryKey();
    final errorA = StateError('a');
    var fetchesB = 0;
    var builds = 0;
    final built = <CombinedResult<String>>[];

    await tester.pumpApp(
      client,
      HookProbe((context) {
        builds++;
        final combined = useCombinedQueries(
          [
            QueryObserverOptions<String>(
              queryKey: keyA,
              queryFn: (_) => sleep(5).then((_) => throw errorA),
              retry: RetryPolicy.never,
            ),
            QueryObserverOptions<String>(
              queryKey: keyB,
              queryFn: (_) {
                fetchesB++;
                return sleep(5).then((_) => throw StateError('b'));
              },
              retry: RetryPolicy.never,
            ),
          ],
          (values) => values.join(','),
          keys: const [],
        );
        built.add(combined);
        return TextButton(
          onPressed: combined.retry,
          child: const Text('retry'),
        );
      }),
    );
    await advance(tester, 6);
    expect(built.last, isA<CombinedError<String>>());
    expect(fetchesB, 1);
    final before = built.last;
    final buildsBefore = builds;

    client.setQueryData<String>(keyB, 'repaired');
    await advance(tester, 0);

    // The value did not move ...
    expect(built.last, before);
    // ... but what `retry` acts on did, so the hook rebuilt.
    expect(builds, buildsBefore + 1);

    await click(tester, 'retry');
    await advance(tester, 6);
    expect(fetchesB, 1, reason: 'retry refetched the repaired source');
  });

  // H-03: a count delivery the notify manager queued before the hook let go
  // finds the hook disposed and does nothing. The fetch starts in a
  // sibling's build, so the provider defers the delivery past the frame in
  // which the probe throws before its hook (and flutter_hooks disposes it).
  hookTest('count: a delivery queued before disposal adds no build',
      (tester, client) async {
    final key = queryKey();
    var phase = 0;
    var builds = 0;
    late void Function() next;

    await tester.pumpApp(
      client,
      StatefulBuilder(builder: (context, setState) {
        next = () => setState(() => phase++);
        return Column(children: [
          Builder(builder: (context) {
            if (phase == 1) {
              client
                  .query(QueryOptions<String>(
                    queryKey: key,
                    queryFn: (_) => sleep(10).then((_) => 'data'),
                  ))
                  .ignore();
            }
            return const SizedBox();
          }),
          // Bounded, so the error widget does not overflow the column.
          SizedBox(
            height: 50,
            child: HookProbe((context) {
              builds++;
              if (phase == 1) {
                throw StateError('before the hook');
              }
              return Text('isFetching: ${useIsFetching()}');
            }),
          ),
        ]);
      }),
    );
    expect(find.text('isFetching: 0'), findsOneWidget);
    expect(builds, 1);

    next();
    await tester.pump();
    expect(tester.takeException(), isStateError);
    expect(builds, 2);

    // The deferred delivery has run; nothing asked for another build.
    await tester.pump();
    await tester.pump();
    expect(builds, 2);
    expect(tester.takeException(), isNull);

    await advance(tester, 11);
  });

  // H-04, the mutation half: a throw before `useMutation` disposes its
  // controller. The run goes on and its options' callbacks run; the
  // per-call callbacks are dropped; the hook that replaces it starts idle.
  hookTest('a throw before useMutation: run continues, per-call dropped',
      (tester, client) async {
    var throwNow = false;
    var optionsSuccess = 0;
    var callSuccess = 0;
    late void Function() rebuild;
    MutationResult<String, String>? last;

    await tester.pumpApp(
      client,
      StatefulBuilder(builder: (context, setState) {
        rebuild = () => setState(() {});
        return HookProbe((context) {
          if (throwNow) {
            throw StateError('before the hook');
          }
          final mutation = useMutation(MutationOptions.simple<String, String>(
            mutationFn: (text) => sleep(10).then((_) => text),
            onSuccess: (_, __, ___) => optionsSuccess++,
          ));
          last = mutation.value;
          return TextButton(
            onPressed: () => mutation.mutate(
              'todo',
              callbacks: MutateCallbacks(
                onSuccess: (_, __, ___) => callSuccess++,
              ),
            ),
            child: const Text('mutate'),
          );
        });
      }),
    );

    await click(tester, 'mutate');
    await advance(tester, 0);
    expect(last!.isPending, isTrue);

    throwNow = true;
    rebuild();
    await tester.pump();
    expect(tester.takeException(), isStateError);

    throwNow = false;
    rebuild();
    await tester.pump();
    expect(last!.isIdle, isTrue, reason: 'the replacement starts idle');

    await advance(tester, 11);
    expect(optionsSuccess, 1);
    expect(callSuccess, 0);
    expect(last!.isIdle, isTrue);
    expect(client.mutationCache.mutations.single.state.status,
        MutationStatus.success);
  });

  // H-04, the query half: a throw before `useQuery` removes the query's
  // last observer. A query function that consumed its signal is cancelled
  // and reverted, so the next build fetches again.
  hookTest('a throw before useQuery cancels a signal-consuming fetch',
      (tester, client) async {
    final key = queryKey();
    var throwNow = false;
    var fetches = 0;
    var cancelled = 0;
    late void Function() rebuild;

    await tester.pumpApp(
      client,
      StatefulBuilder(builder: (context, setState) {
        rebuild = () => setState(() {});
        return HookProbe((context) {
          if (throwNow) {
            throw StateError('before the hook');
          }
          final result = useQuery(QueryObserverOptions<String>(
            queryKey: key,
            queryFn: (context) {
              fetches++;
              context.signal.onCancel(() => cancelled++);
              return sleep(10).then((_) => 'data $fetches');
            },
          ));
          return Text(result.dataOrNull ?? 'pending');
        });
      }),
    );
    await advance(tester, 5);
    expect(fetches, 1);

    throwNow = true;
    rebuild();
    await tester.pump();
    expect(tester.takeException(), isStateError);
    final state = client.getQueryState<String>(key)!;
    expect(cancelled, 1);
    expect(state.fetchStatus, FetchStatus.idle);
    expect(state.status, QueryStatus.pending);

    throwNow = false;
    rebuild();
    await advance(tester, 11);
    expect(fetches, 2);
    expect(find.text('data 2'), findsOneWidget);
  });

  // Fable P2-1: an untyped `getQueryState` throws once the entry exists, so
  // the prefetch hook looks the key up untyped.
  hookTest('usePrefetchQuery: a build with the entry present does not throw',
      (tester, client) async {
    final key = queryKey();
    var fetches = 0;
    late void Function() rebuild;

    await tester.pumpApp(
      client,
      StatefulBuilder(builder: (context, setState) {
        rebuild = () => setState(() {});
        return HookProbe((context) {
          usePrefetchQuery(QueryOptions<String>(
            queryKey: key,
            queryFn: (_) {
              fetches++;
              return sleep(10).then((_) => 'data');
            },
          ));
          return const SizedBox();
        });
      }),
    );
    rebuild();
    await tester.pump();
    await advance(tester, 11);
    rebuild();
    await tester.pump();

    expect(fetches, 1);
    expect(client.getQueryData<String>(key), 'data');
    // What the plan's first spelling would have done on the second build:
    expect(() => client.getQueryState<dynamic>(key),
        throwsA(isA<QueryDataTypeError>()));
  });

  hookTest('hot reload keeps the observer', (tester, client) async {
    final key = queryKey();
    var fetches = 0;

    await tester.pumpApp(
      client,
      HookProbe((context) {
        final result = useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) {
            fetches++;
            return sleep(5).then((_) => 'data');
          },
        ));
        return Text(result.dataOrNull ?? 'pending');
      }),
    );
    await advance(tester, 6);
    final observer = client.queryCache
        .find(filters: QueryFilters(queryKey: key))!
        .observersCount;

    // The returned future waits for a frame; the pump is that frame.
    unawaited(tester.binding.reassembleApplication());
    await tester.pump();
    await advance(tester, 6);

    expect(find.text('data'), findsOneWidget);
    expect(fetches, 1);
    expect(
      client.queryCache
          .find(filters: QueryFilters(queryKey: key))!
          .observersCount,
      observer,
    );
  });
}
