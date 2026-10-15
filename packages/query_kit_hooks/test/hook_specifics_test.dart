// What the hooks do that upstream's suites cannot say: Flutter's element
// lifecycle, the client a hook resolves, and flutter_hooks' own rules
// (plan, D5–D7 and D13).
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_hooks/query_kit_hooks.dart';

import 'harness.dart';

void main() {
  hookTest(
      'options rebuilt equal on every build neither refetch nor add a build',
      (tester, client) async {
    final key = queryKey();
    var fetches = 0;
    var builds = 0;
    late void Function() rebuildParent;

    await tester.pumpApp(
      client,
      StatefulBuilder(builder: (context, setState) {
        rebuildParent = () => setState(() {});
        return HookBuilder(builder: (context) {
          builds++;
          final result = useQuery(QueryObserverOptions<String>(
            queryKey: QueryKey([...key.parts]),
            queryFn: (_) {
              fetches++;
              return sleep(10).then((_) => 'data');
            },
          ));
          return Text(result.dataOrNull ?? 'pending');
        });
      }),
    );
    await advance(tester, 11);
    expect(find.text('data'), findsOneWidget);
    expect(builds, 2);

    for (var i = 0; i < 3; i++) {
      rebuildParent();
      await tester.pump();
    }
    await advance(tester, 20);

    expect(fetches, 1);
    expect(builds, 5); // two of its own, three from the parent
    expect(observersOf(client, key), 1);
  });

  hookTest('a client switch through the provider re-creates the observer',
      (tester, client) async {
    final other = QueryClient();
    addTearDown(other.clear);
    final key = queryKey();

    Widget tree(QueryClient c, String answer) => app(
          c,
          HookBuilder(builder: (context) {
            final result = useQuery(QueryObserverOptions<String>(
              queryKey: key,
              queryFn: (_) => sleep(5).then((_) => answer),
            ));
            return Text(result.dataOrNull ?? 'pending');
          }),
        );

    await tester.pumpWidget(tree(client, 'first'));
    await advance(tester, 6);
    expect(find.text('first'), findsOneWidget);
    expect(observersOf(client, key), 1);

    await tester.pumpWidget(tree(other, 'second'));
    expect(find.text('pending'), findsOneWidget);
    expect(observersOf(client, key), 0);
    expect(observersOf(other, key), 1);
    await advance(tester, 6);
    expect(find.text('second'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    other.clear();
  });

  hookTest('`client:` works without a provider', (tester, client) async {
    final key = queryKey();
    await tester.pumpWidget(MaterialApp(
      home: HookBuilder(builder: (context) {
        final result = useQuery(
          QueryObserverOptions<String>(
            queryKey: key,
            queryFn: (_) => sleep(5).then((_) => 'own client'),
          ),
          client: client,
        );
        return Text(result.dataOrNull ?? 'pending');
      }),
    ));
    await advance(tester, 6);
    expect(find.text('own client'), findsOneWidget);
  });

  hookTest('unmounting releases the observer', (tester, client) async {
    final key = queryKey();
    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) => 'data',
        ));
        return const SizedBox();
      }),
    );
    await advance(tester, 0);
    expect(observersOf(client, key), 1);

    await tester.pumpApp(client, const SizedBox());
    expect(observersOf(client, key), 0);
  });

  hookTest('a GlobalKey move keeps the observer and the data',
      (tester, client) async {
    final key = queryKey();
    final globalKey = GlobalKey();
    var fetches = 0;

    Widget probe() => HookBuilder(
          key: globalKey,
          builder: (context) {
            final result = useQuery(QueryObserverOptions<String>(
              queryKey: key,
              queryFn: (_) {
                fetches++;
                return 'data';
              },
            ));
            return Text(result.dataOrNull ?? 'pending');
          },
        );

    await tester.pumpApp(client, Column(children: [probe()]));
    await advance(tester, 0);
    expect(find.text('data'), findsOneWidget);

    await tester.pumpApp(
      client,
      Row(children: [SizedBox(child: probe())]),
    );
    await advance(tester, 0);
    expect(find.text('data'), findsOneWidget);
    expect(fetches, 1);
    expect(observersOf(client, key), 1);
  });

  // D13: flutter_hooks disposes, after a build, every hook that build did
  // not reach — the one that threw included. A throw after the last `use`
  // disposes nothing.
  hookTest('a throw after the last hook keeps the observer',
      (tester, client) async {
    final key = queryKey();
    var fetches = 0;
    var fail = false;
    late void Function() rebuild;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final result = useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) {
            fetches++;
            return 'data';
          },
        ));
        final toggle = useState(0);
        rebuild = () => toggle.value++;
        if (fail) {
          throw StateError('build failed');
        }
        return Text(result.dataOrNull ?? 'pending');
      }),
    );
    await advance(tester, 0);
    expect(observersOf(client, key), 1);

    fail = true;
    rebuild();
    await tester.pump();
    expect(tester.takeException(), isA<StateError>());
    expect(observersOf(client, key), 1);

    fail = false;
    rebuild();
    await tester.pump();
    expect(find.text('data'), findsOneWidget);
    expect(fetches, 1);
  });

  hookTest('a throw before a hook disposes it; the next build starts over',
      (tester, client) async {
    final key = queryKey();
    var fetches = 0;
    var fail = false;
    late void Function() rebuild;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final toggle = useState(0);
        rebuild = () => toggle.value++;
        if (fail) {
          throw StateError('build failed');
        }
        final result = useQuery(QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) {
            fetches++;
            return 'data';
          },
        ));
        return Text(result.dataOrNull ?? 'pending');
      }),
    );
    await advance(tester, 0);
    expect(observersOf(client, key), 1);

    fail = true;
    rebuild();
    await tester.pump();
    expect(tester.takeException(), isA<StateError>());
    // Disposed with the hooks the build did not reach.
    expect(observersOf(client, key), 0);

    fail = false;
    rebuild();
    await tester.pump();
    // A new observer on the cached entry: data at once, no refetch while
    // fresh would be upstream's staleTime question — default is stale, so
    // the remount refetches.
    expect(find.text('data'), findsOneWidget);
    expect(observersOf(client, key), 1);
    await advance(tester, 0);
    expect(fetches, 2);
  });

  // D13, with a fetch in flight in every hook whose query function consumed
  // its signal: such a fetch is cancelled and reverted once its query has no
  // observer left, so what each case cancels is what it disposed. The hooks
  // from the one a build was in when it threw — that one included — to the
  // last go; the hooks before it stay.
  group('a throw in build, fetches in flight (D13)', () {
    final fetches = <QueryKey, int>{};
    final cancels = <QueryKey, int>{};
    QueryObserverOptions<String> options(QueryKey key) =>
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (context) {
            final n = fetches[key] = (fetches[key] ?? 0) + 1;
            context.signal
                .onCancel(() => cancels[key] = (cancels[key] ?? 0) + 1);
            return sleep(10).then((_) => '${key.parts.single} $n');
          },
        );
    String shown(QueryKey a, int n, QueryKey b, int m) =>
        '${a.parts.single} $n ${b.parts.single} $m';

    setUp(() {
      fetches.clear();
      cancels.clear();
    });

    hookTest('inside a hook: it and every hook after it go',
        (tester, client) async {
      final first = queryKey();
      final second = queryKey();
      // Holds an int, so a `useQuery<String>` switching to it throws a
      // QueryDataTypeError from inside the hook's own build.
      final wrongType = queryKey();
      client.setQueryData<int>(wrongType, 1);
      var fail = false;
      late void Function() rebuild;

      await tester.pumpApp(
        client,
        HookBuilder(builder: (context) {
          final toggle = useState(0);
          rebuild = () => toggle.value++;
          final a = useQuery(options(fail ? wrongType : first));
          final b = useQuery(options(second));
          return Text('${a.dataOrNull} ${b.dataOrNull}');
        }),
      );
      await advance(tester, 5);
      expect(fetches, {first: 1, second: 1});

      fail = true;
      rebuild();
      await tester.pump();
      expect(tester.takeException(), isA<QueryDataTypeError>());
      // The hook threw before it left `first`: both observers are gone,
      // and both fetches with them.
      expect(observersOf(client, first), 0);
      expect(observersOf(client, second), 0);
      expect(cancels, {first: 1, second: 1});
      final state = client.getQueryState<String>(first)!;
      expect(state.status, QueryStatus.pending);
      expect(state.fetchStatus, FetchStatus.idle);

      // The next build starts over: new observers, new fetches.
      fail = false;
      rebuild();
      await advance(tester, 11);
      expect(fetches, {first: 2, second: 2});
      expect(find.text(shown(first, 2, second, 2)), findsOneWidget);
    });

    hookTest('between hooks: the hooks before it stay', (tester, client) async {
      final first = queryKey();
      final second = queryKey();
      var fail = false;
      late void Function() rebuild;

      await tester.pumpApp(
        client,
        HookBuilder(builder: (context) {
          final toggle = useState(0);
          rebuild = () => toggle.value++;
          final a = useQuery(options(first));
          if (fail) {
            throw StateError('between the hooks');
          }
          final b = useQuery(options(second));
          return Text('${a.dataOrNull} ${b.dataOrNull}');
        }),
      );
      await advance(tester, 5);
      expect(fetches, {first: 1, second: 1});

      fail = true;
      rebuild();
      await tester.pump();
      expect(tester.takeException(), isStateError);
      expect(observersOf(client, first), 1);
      expect(observersOf(client, second), 0);
      expect(cancels, {second: 1});

      // `first` finishes the fetch it had; `second` starts over.
      fail = false;
      rebuild();
      await advance(tester, 11);
      expect(fetches, {first: 1, second: 2});
      expect(find.text(shown(first, 1, second, 2)), findsOneWidget);
    });

    hookTest('after the last hook: nothing goes', (tester, client) async {
      final first = queryKey();
      final second = queryKey();
      var fail = false;
      late void Function() rebuild;

      await tester.pumpApp(
        client,
        HookBuilder(builder: (context) {
          final toggle = useState(0);
          rebuild = () => toggle.value++;
          final a = useQuery(options(first));
          final b = useQuery(options(second));
          if (fail) {
            throw StateError('after the hooks');
          }
          return Text('${a.dataOrNull} ${b.dataOrNull}');
        }),
      );
      await advance(tester, 5);

      fail = true;
      rebuild();
      await tester.pump();
      expect(tester.takeException(), isStateError);
      expect(observersOf(client, first), 1);
      expect(observersOf(client, second), 1);
      expect(cancels, isEmpty);

      fail = false;
      rebuild();
      await advance(tester, 6);
      expect(fetches, {first: 1, second: 1});
      expect(find.text(shown(first, 1, second, 1)), findsOneWidget);
    });
  });

  // Review P2-2 (not reproduced): `MutationStateController` takes new
  // filters and a new `select` through `setOptions`, and `useIsFetching`
  // reads the filters of the last build. Neither needs a new subscription
  // for objects that are new on every build, and neither adds a build.
  hookTest('filters and select new on every build add no build',
      (tester, client) async {
    final mutationKey = queryKey();
    var builds = 0;
    final seen = <List<MutationStatus>>[];
    late void Function() rebuildParent;

    await tester.pumpApp(
      client,
      Column(children: [
        StatefulBuilder(builder: (context, setState) {
          rebuildParent = () => setState(() {});
          return HookBuilder(builder: (context) {
            builds++;
            final statuses = useMutationState(
              filters: MutationFilters(mutationKey: mutationKey),
              select: (mutation) => mutation.state.status,
            );
            useIsFetching(filters: QueryFilters(queryKey: queryKey()));
            seen.add(statuses);
            return const SizedBox();
          });
        }),
        HookBuilder(builder: (context) {
          final mutation = useMutation(MutationOptions.simple<String, void>(
            mutationKey: mutationKey,
            mutationFn: (_) => sleep(10).then((_) => 'ok'),
          ));
          return TextButton(
            onPressed: () => mutation.mutate(null),
            child: const Text('mutate'),
          );
        }),
      ]),
    );
    expect(builds, 1);

    for (var i = 0; i < 3; i++) {
      rebuildParent();
      await tester.pump();
    }
    await advance(tester, 5);
    expect(builds, 4); // one of its own, three from the parent

    await click(tester, 'mutate');
    await advance(tester, 11);
    expect(seen.last, [MutationStatus.success]);
    expect(seen.skip(4).toList(), [
      [MutationStatus.pending],
      [MutationStatus.success],
    ]);
    expect(builds, 6);
  });

  // AP6's acceptance (plan, D10): `useCombinedQueries` rebuilds when the
  // combination moves, or what its `retry` and `refetch` act on, and for
  // nothing else. H-01 itself is in `review_reproductions_test.dart`.
  group('AP6: useQueries and useCombinedQueries', () {
    // The combiner reads only the first source. The second's new data
    // reaches both hooks — `useQueries` builds for it, and the combiner runs
    // on it — but the combination is equal, so `useCombinedQueries` does not
    // build. A change to the first source does.
    hookTest('a source change that leaves the combination equal adds no build',
        (tester, client) async {
      final keyA = queryKey();
      final keyB = queryKey();
      var combinedBuilds = 0;
      var listBuilds = 0;
      var combinerRuns = 0;
      List<QueryObserverOptions<String>> queries() => [
            QueryObserverOptions<String>(
              queryKey: keyA,
              queryFn: (_) => sleep(5).then((_) => 'a'),
            ),
            QueryObserverOptions<String>(
              queryKey: keyB,
              queryFn: (_) => sleep(5).then((_) => 'b'),
            ),
          ];

      await tester.pumpApp(
        client,
        Column(children: [
          HookBuilder(builder: (context) {
            combinedBuilds++;
            final combined = useCombinedQueries(
              queries(),
              (values) {
                combinerRuns++;
                return values.first;
              },
              keys: const [],
            );
            return Text('combined: ${combined.dataOrNull}');
          }),
          HookBuilder(builder: (context) {
            listBuilds++;
            final results = useQueries(queries());
            return Text('list: ${results.map((r) => r.dataOrNull).join(',')}');
          }),
        ]),
      );
      await advance(tester, 6);
      expect(find.text('combined: a'), findsOneWidget);
      expect(find.text('list: a,b'), findsOneWidget);
      final combinedBefore = combinedBuilds;
      final listBefore = listBuilds;
      final runsBefore = combinerRuns;

      client.setQueryData<String>(keyB, 'b2');
      await advance(tester, 0);

      expect(find.text('list: a,b2'), findsOneWidget);
      expect(listBuilds, listBefore + 1);
      expect(combinerRuns, runsBefore + 1);
      expect(combinedBuilds, combinedBefore);

      client.setQueryData<String>(keyA, 'a2');
      await advance(tester, 0);

      expect(find.text('combined: a2'), findsOneWidget);
      expect(combinedBuilds, combinedBefore + 1);
    });

    // A second angle on H-01: the combination is data, and both sources'
    // background refetches failed. `CombinedData` compares only the first
    // refetch error, so repairing the second source leaves it equal, while
    // `retry` now acts on the first source alone.
    hookTest('a repaired refetch error behind equal data rebuilds once',
        (tester, client) async {
      final keyA = queryKey();
      final keyB = queryKey();
      var fetchesA = 0;
      var fetchesB = 0;
      var builds = 0;
      final built = <CombinedResult<String>>[];
      client
        ..setQueryData<String>(keyA, 'a')
        ..setQueryData<String>(keyB, 'b');

      await tester.pumpApp(
        client,
        HookBuilder(builder: (context) {
          builds++;
          final combined = useCombinedQueries(
            [
              QueryObserverOptions<String>(
                queryKey: keyA,
                queryFn: (_) {
                  fetchesA++;
                  return sleep(5).then((_) => throw StateError('a'));
                },
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
      final before = built.last;
      expect(before.dataOrNull, 'a,b');
      expect(
        (before as CombinedData<String>).refetchError,
        isA<StateError>().having((e) => e.message, 'message', 'a'),
      );
      expect((fetchesA, fetchesB), (1, 1));
      final buildsBefore = builds;

      client.setQueryData<String>(keyB, 'b');
      await advance(tester, 0);

      // The value did not move ...
      expect(built.last, before);
      // ... but what `retry` acts on did, so the hook rebuilt.
      expect(builds, buildsBefore + 1);

      await click(tester, 'retry');
      await advance(tester, 6);
      expect((fetchesA, fetchesB), (2, 1),
          reason: 'retry refetched the repaired source');
    });

    // `buildWhen` compares values; when only the actions moved there is
    // nothing for it to compare, so the hook rebuilds without asking it —
    // here a `buildWhen` that would have said no.
    hookTest('a move in the actions alone does not ask buildWhen',
        (tester, client) async {
      final keyA = queryKey();
      final keyB = queryKey();
      var builds = 0;
      final asked = <(CombinedResult<String>, CombinedResult<String>)>[];
      final built = <CombinedResult<String>>[];

      await tester.pumpApp(
        client,
        HookBuilder(builder: (context) {
          builds++;
          final combined = useCombinedQueries(
            [
              QueryObserverOptions<String>(
                queryKey: keyA,
                queryFn: (_) => sleep(5).then((_) => throw StateError('a')),
                retry: RetryPolicy.never,
              ),
              QueryObserverOptions<String>(
                queryKey: keyB,
                queryFn: (_) => sleep(5).then((_) => throw StateError('b')),
                retry: RetryPolicy.never,
              ),
            ],
            (values) => values.join(','),
            keys: const [],
            buildWhen: (previous, current) {
              asked.add((previous, current));
              return previous.runtimeType != current.runtimeType;
            },
          );
          built.add(combined);
          return const SizedBox();
        }),
      );
      await advance(tester, 6);
      final before = built.last;
      expect(before, isA<CombinedError<String>>());
      expect(before.isFetching, isFalse);
      final buildsBefore = builds;
      final askedBefore = asked.length;

      client.setQueryData<String>(keyB, 'repaired');
      await advance(tester, 0);

      expect(built.last, before);
      expect(builds, buildsBefore + 1);
      expect(asked, hasLength(askedBefore));
    });

    // Second review, S-2: the combiner runs in the listener too, to compare.
    // A throw there reached `notifyListeners`, which reported it and built
    // nothing, so the widget stayed pending and the hook subscribed.
    hookTest('a combiner that throws on delivered data fails the build',
        (tester, client) async {
      final key = queryKey();
      final failure = StateError('combine failed');
      await tester.pumpApp(
        client,
        HookBuilder(builder: (_) {
          final result = useCombinedQueries<String, String, String>(
            [
              QueryObserverOptions<String>(
                queryKey: key,
                queryFn: (_) => sleep(5).then((_) => 'data'),
              ),
            ],
            (_) => throw failure,
            keys: const [],
          );
          return Text(result.isPending ? 'pending' : 'data');
        }),
      );
      expect(find.text('pending'), findsOneWidget);

      await advance(tester, 6);
      expect(tester.takeException(), same(failure));
      await advance(tester, 0);

      // The build threw, so the hook went with it (plan, D13).
      expect(find.text('pending'), findsNothing);
      expect(observersOf(client, key), 0);
    });
  });

  // AP8 (map #92): what the prefetch hooks promise beyond upstream's cases
  // (plan, D7 and D11). Each case runs both hooks, each on its own key.
  group('AP8: usePrefetchQuery and usePrefetchInfiniteQuery', () {
    var failing = false;
    final fetches = <QueryKey, int>{};
    void count(QueryKey key) => fetches[key] = (fetches[key] ?? 0) + 1;

    QueryOptions<String> plain(QueryKey key) => QueryOptions<String>(
          queryKey: key,
          queryFn: (_) {
            count(key);
            final fail = failing;
            return sleep(10).then((_) => fail ? throw StateError('x') : 'data');
          },
        );
    InfiniteQueryOptions<String, int> infinite(QueryKey key) =>
        InfiniteQueryOptions<String, int>(
          queryKey: key,
          pageFn: (context) {
            count(key);
            final fail = failing;
            return sleep(10).then(
              (_) => fail ? throw StateError('x') : 'page ${context.pageParam}',
            );
          },
          initialPageParam: 0,
          getNextPageParam: (_, __, ___, ____) => null,
        );

    // Both prefetch hooks in one widget, which a case can rebuild.
    late void Function() rebuild;
    Widget prefetcher(QueryKey a, QueryKey b, {QueryClient? client}) =>
        StatefulBuilder(builder: (context, setState) {
          rebuild = () => setState(() {});
          return HookBuilder(builder: (context) {
            usePrefetchQuery(plain(a), client: client);
            usePrefetchInfiniteQuery(infinite(b), client: client);
            return const SizedBox();
          });
        });
    // A reader for each key, with default options.
    Widget readers(QueryKey a, QueryKey b) => HookBuilder(builder: (context) {
          final query = useQuery(QueryObserverOptions<String>(
            queryKey: a,
            queryFn: plain(a).queryFn,
          ));
          final pages = useInfiniteQuery(InfiniteQueryObserverOptions(
            queryKey: b,
            pageFn: infinite(b).pageFn,
            initialPageParam: 0,
            getNextPageParam: infinite(b).getNextPageParam,
          ));
          return Text('${query.dataOrNull} ${pages.value.dataOrNull?.pages}');
        });

    setUp(() {
      failing = false;
      fetches.clear();
    });

    // Review P2-1, the infinite twin of review_reproductions_test.dart's
    // `usePrefetchQuery` case.
    hookTest(
        'usePrefetchInfiniteQuery: a build with the entry present does not '
        'throw', (tester, client) async {
      final a = queryKey();
      final b = queryKey();

      await tester.pumpApp(client, prefetcher(a, b));
      rebuild();
      await tester.pump();
      await advance(tester, 11);
      rebuild();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(fetches, {a: 1, b: 1});
      expect(
        client.getQueryData<InfiniteData<String, int>>(b)?.pages,
        ['page 0'],
      );
      // What `getQueryState` without a type argument does once it exists:
      expect(() => client.getQueryState<dynamic>(b),
          throwsA(isA<QueryDataTypeError>()));
    });

    hookTest('a failed entry: the prefetch hooks leave it, a reader refetches',
        (tester, client) async {
      final a = queryKey();
      final b = queryKey();
      failing = true;
      prefetch(client, plain(a)).ignore();
      prefetch(client, infinite(b)).ignore();
      await advance(tester, 10);
      expect(client.getQueryState<String>(a)!.status, QueryStatus.error);
      expect(
        client.getQueryState<InfiniteData<String, int>>(b)!.status,
        QueryStatus.error,
      );
      failing = false;

      await tester.pumpApp(client, prefetcher(a, b));
      rebuild();
      await tester.pump();
      await advance(tester, 20);
      expect(fetches, {a: 1, b: 1});
      expect(client.getQueryState<String>(a)!.status, QueryStatus.error);

      // `retryOnMount` defaults to true: a reader retries what failed.
      await tester.pumpApp(
        client,
        Column(children: [prefetcher(a, b), readers(a, b)]),
      );
      await advance(tester, 11);
      expect(fetches, {a: 2, b: 2});
      expect(find.text('data [page 0]'), findsOneWidget);
    });

    // A fetching entry would not be fetched twice anyway: `client.query`
    // joins a fetch in flight. The entry a cancelled fetch leaves behind,
    // pending and idle, is the one only the hook's lookup leaves alone.
    hookTest('a pending entry: the prefetch hooks leave it, a reader fetches',
        (tester, client) async {
      final a = queryKey();
      final b = queryKey();
      prefetch(client, plain(a)).ignore();
      prefetch(client, infinite(b)).ignore();

      // Fetching: built and rebuilt while the fetch runs.
      await tester.pumpApp(client, prefetcher(a, b));
      await advance(tester, 5);
      rebuild();
      await advance(tester, 6);
      expect(fetches, {a: 1, b: 1});
      expect(client.getQueryData<String>(a), 'data');

      // Pending and idle, as a cancelled first fetch leaves it.
      final c = queryKey();
      final d = queryKey();
      prefetch(client, plain(c)).ignore();
      prefetch(client, infinite(d)).ignore();
      await client.cancelQueries(filters: QueryFilters(queryKey: c));
      await client.cancelQueries(filters: QueryFilters(queryKey: d));
      for (final state in [
        client.getQueryState<String>(c)!,
        client.getQueryState<InfiniteData<String, int>>(d)!,
      ]) {
        expect(state.status, QueryStatus.pending);
        expect(state.fetchStatus, FetchStatus.idle);
      }

      await tester.pumpApp(client, prefetcher(c, d));
      rebuild();
      await tester.pump();
      await advance(tester, 20);
      expect(fetches, {a: 1, b: 1, c: 1, d: 1});
      expect(client.getQueryState<String>(c)!.fetchStatus, FetchStatus.idle);

      await tester.pumpApp(
        client,
        Column(children: [prefetcher(c, d), readers(c, d)]),
      );
      await advance(tester, 11);
      expect(fetches, {a: 1, b: 1, c: 2, d: 2});
      expect(find.text('data [page 0]'), findsOneWidget);
    });

    hookTest('the prefetch hooks hold no observer and never rebuild',
        (tester, client) async {
      final a = queryKey();
      final b = queryKey();
      var builds = 0;

      await tester.pumpApp(
        client,
        HookBuilder(builder: (context) {
          builds++;
          usePrefetchQuery(plain(a));
          usePrefetchInfiniteQuery(infinite(b));
          return const SizedBox();
        }),
      );
      expect(observersOf(client, a), 0);
      expect(observersOf(client, b), 0);
      await advance(tester, 11);

      expect(client.getQueryData<String>(a), 'data');
      expect(builds, 1);
      expect(observersOf(client, a), 0);
      expect(observersOf(client, b), 0);
    });

    // Upstream's `void client.query(options).catch(noop)`: a failure is the
    // entry's state, not an error in the zone.
    hookTest('a fetch the prefetch hooks start fails into the entry',
        (tester, client) async {
      final a = queryKey();
      final b = queryKey();
      failing = true;

      await tester.pumpApp(client, prefetcher(a, b));
      await advance(tester, 11);

      expect(tester.takeException(), isNull);
      expect(client.getQueryState<String>(a)!.status, QueryStatus.error);
      expect(
        client.getQueryState<InfiniteData<String, int>>(b)!.status,
        QueryStatus.error,
      );
      expect(fetches, {a: 1, b: 1});
    });

    // `find` is exact by default and `findAll` is not: a lookup that matched
    // by prefix would take a longer key for this one.
    hookTest('an entry under a longer key is not the entry',
        (tester, client) async {
      final a = queryKey();
      final b = queryKey();
      client.setQueryData<int>(QueryKey([...a.parts, 1]), 1);
      client.setQueryData<int>(QueryKey([...b.parts, 1]), 1);

      await tester.pumpApp(client, prefetcher(a, b));
      await advance(tester, 11);
      expect(fetches, {a: 1, b: 1});
    });

    // D11: the prefetch starts its fetch in the middle of a frame's build,
    // after the counter beside it was built. The cache's notification must
    // reach the counter after the build: with a provider after the frame,
    // without one in a microtask (D7). `phases` records when a delivery
    // scheduled the way `useIsFetching` schedules its own ran.
    for (final provider in [true, false]) {
      hookTest(
          'a useIsFetching built before the prefetch: no setState during '
          'build, ${provider ? 'with a provider' : 'without one'}',
          (tester, client) async {
        final a = queryKey();
        final b = queryKey();
        final own = provider ? null : client;
        final counts = <int>[];
        final phases = <String>[];
        final unsubscribe = client.queryCache.subscribe((_) =>
            client.notifyManager.schedule(
                () => phases.add(WidgetsBinding.instance.schedulerPhase.name)));
        addTearDown(unsubscribe);
        Widget wrap(Widget child) =>
            provider ? app(client, child) : MaterialApp(home: child);

        // The tree exists first, so the next build is a frame's.
        await tester.pumpWidget(wrap(const SizedBox()));
        await tester.pumpWidget(wrap(Column(children: [
          HookBuilder(builder: (context) {
            counts.add(useIsFetching(client: own));
            return const SizedBox();
          }),
          prefetcher(a, b, client: own),
        ])));

        expect(tester.takeException(), isNull);
        expect(counts, [0]);
        expect(phases, isNotEmpty);
        expect(phases.toSet(), {provider ? 'postFrameCallbacks' : 'idle'});

        await tester.pump();
        expect(counts, [0, 2]);
        await advance(tester, 10);
        expect(counts, [0, 2, 0]);
        expect(fetches, {a: 1, b: 1});
      });
    }
  });

  // AP5 (map #92): `useMutation`. D13's mutation rows — a throw before the
  // hook disposes its controller, and a disposed controller does not cancel
  // — then D9's "dispose does not cancel" on an unmount, and the options
  // the controller takes on every build.
  group('AP5: useMutation', () {
    final events = <String>[];
    final signals = <QueryCancelToken>[];
    final results = <MutationResult<String, String>>[];
    var throwBefore = false;
    var throwAfter = false;
    late void Function() rebuild;
    Future<String>? running;

    setUp(() {
      events.clear();
      signals.clear();
      results.clear();
      throwBefore = false;
      throwAfter = false;
      running = null;
    });

    MutationOptions<String, String, void> options({QueryKey? key}) =>
        MutationOptions.simple<String, String>(
          mutationKey: key,
          mutationFnWithContext: (text, context) {
            signals.add(context.signal);
            return sleep(10)
                .then((_) => text == 'fail' ? throw StateError('oops') : text);
          },
          onSuccess: (data, _, __) => events.add('options.onSuccess $data'),
          onError: (_, __, ___, ____) => events.add('options.onError'),
          onSettled: (_, __, ___, ____, _____) =>
              events.add('options.onSettled'),
        );

    MutateCallbacks<String, String, void> perCall() => MutateCallbacks(
          onSuccess: (data, _, __) => events.add('mutate.onSuccess $data'),
          onError: (_, __, ___, ____) => events.add('mutate.onError'),
          onSettled: (_, __, ___, ____, _____) =>
              events.add('mutate.onSettled'),
        );

    // A build that throws before its `useMutation` while `throwBefore` is
    // set, and after it while `throwAfter` is; `rebuild` goes through a
    // hook ahead of both, which a throw does not dispose.
    Widget page({QueryKey? key}) => HookBuilder(builder: (context) {
          final toggle = useState(0);
          rebuild = () => toggle.value++;
          if (throwBefore) {
            throw StateError('before the hook');
          }
          final mutation = useMutation(options(key: key));
          if (throwAfter) {
            throw StateError('after the hook');
          }
          results.add(mutation.value);
          return Column(children: [
            TextButton(
              onPressed: () => mutation.mutate('todo', callbacks: perCall()),
              child: const Text('mutate'),
            ),
            TextButton(
              onPressed: () => mutation.mutate('fail', callbacks: perCall()),
              child: const Text('fail'),
            ),
            TextButton(
              onPressed: () {
                running = mutation.mutateAsync('todo', callbacks: perCall());
              },
              child: const Text('mutateAsync'),
            ),
          ]);
        });

    Future<void> throwInBuild(WidgetTester tester) async {
      rebuild();
      await tester.pump();
      expect(tester.takeException(), isStateError);
    }

    Future<void> recover(WidgetTester tester) async {
      throwBefore = false;
      throwAfter = false;
      rebuild();
      await tester.pump();
    }

    hookTest(
        "a throw before useMutation: the run goes on, and its options' "
        'callbacks run', (tester, client) async {
      await tester.pumpApp(client, page());
      await click(tester, 'mutate');
      await advance(tester, 5);

      throwBefore = true;
      await throwInBuild(tester);
      final mutation = client.mutationCache.mutations.single;
      expect(mutation.state.status, MutationStatus.pending);
      expect(signals.single.isCancelled, isFalse);

      await advance(tester, 6);
      expect(mutation.state.status, MutationStatus.success);
      expect(mutation.state.data, 'todo');
      expect(signals.single.isCancelled, isFalse);
      expect(events, ['options.onSuccess todo', 'options.onSettled']);
    });

    hookTest(
        'a throw before useMutation: the per-call callbacks of mutate are '
        'dropped', (tester, client) async {
      await tester.pumpApp(client, page());
      await click(tester, 'fail');
      await advance(tester, 5);

      throwBefore = true;
      await throwInBuild(tester);
      await advance(tester, 6);
      expect(client.mutationCache.mutations.single.state.status,
          MutationStatus.error);
      expect(events, ['options.onError', 'options.onSettled']);

      // The control: the hook in its place gets the per-call callbacks of
      // a run of its own.
      await recover(tester);
      events.clear();
      await click(tester, 'fail');
      await advance(tester, 11);
      expect(events, [
        'options.onError',
        'options.onSettled',
        'mutate.onError',
        'mutate.onSettled',
      ]);
    });

    hookTest(
        'a throw before useMutation: the replacement starts idle while the '
        'old run goes on', (tester, client) async {
      final key = queryKey();
      await tester.pumpApp(client, page(key: key));
      await click(tester, 'mutate');
      await advance(tester, 5);
      expect(results.last.isPending, isTrue);

      throwBefore = true;
      await throwInBuild(tester);
      await recover(tester);

      // The old run is still going, and its key finds it…
      final old = client.mutationCache
          .findAll(filters: MutationFilters(mutationKey: key));
      expect(old.single.state.status, MutationStatus.pending);
      // …but the hook in its place does not: it starts idle.
      expect(results.last.isIdle, isTrue);
      expect(results.last.variables, isNull);
      final builds = results.length;

      await advance(tester, 6);
      expect(old.single.state.status, MutationStatus.success);
      // It never watched the old run, so the old run's end builds nothing.
      expect(results.length, builds);
      expect(results.last.isIdle, isTrue);
      expect(events, ['options.onSuccess todo', 'options.onSettled']);
    });

    hookTest('a throw after useMutation keeps the controller and the run',
        (tester, client) async {
      await tester.pumpApp(client, page());
      await click(tester, 'mutate');
      await advance(tester, 5);

      throwAfter = true;
      await throwInBuild(tester);
      await recover(tester);
      expect(results.last.isPending, isTrue);
      expect(results.last.variables, 'todo');

      await advance(tester, 6);
      expect(results.last.dataOrNull, 'todo');
      expect(events, [
        'options.onSuccess todo',
        'options.onSettled',
        'mutate.onSuccess todo',
        'mutate.onSettled',
      ]);
    });

    hookTest('unmounting does not cancel a running mutation',
        (tester, client) async {
      await tester.pumpApp(
        client,
        HookBuilder(builder: (context) {
          final show = useState(true);
          return Column(children: [
            TextButton(
              onPressed: () => show.value = false,
              child: const Text('hide'),
            ),
            if (show.value) page(),
          ]);
        }),
      );
      await click(tester, 'mutateAsync');
      await advance(tester, 5);

      await click(tester, 'hide');
      expect(find.text('mutateAsync'), findsNothing);
      final mutation = client.mutationCache.mutations.single;
      expect(mutation.state.status, MutationStatus.pending);
      expect(signals.single.isCancelled, isFalse);

      await advance(tester, 6);
      expect(signals.single.isCancelled, isFalse);
      expect(mutation.state.status, MutationStatus.success);
      expect(await running!, 'todo');
      // The options' callbacks run; the per-call ones went with the widget.
      expect(events, ['options.onSuccess todo', 'options.onSettled']);
    });

    hookTest('a run in flight calls the callbacks of the latest build',
        (tester, client) async {
      final calls = <String>[];
      late void Function() next;

      await tester.pumpApp(
        client,
        HookBuilder(builder: (context) {
          final generation = useState(1);
          next = () => generation.value++;
          final label = 'build ${generation.value}';
          final mutation = useMutation(MutationOptions.simple<String, String>(
            mutationFn: (text) => sleep(10).then((_) => text),
            onSuccess: (_, __, ___) => calls.add('onSuccess of $label'),
            onSettled: (_, __, ___, ____, _____) =>
                calls.add('onSettled of $label'),
          ));
          return TextButton(
            onPressed: () => mutation.mutate('todo'),
            child: const Text('mutate'),
          );
        }),
      );
      await click(tester, 'mutate');
      await advance(tester, 5);

      next();
      await tester.pump();
      await advance(tester, 6);
      expect(calls, ['onSuccess of build 2', 'onSettled of build 2']);
    });

    // No `keys` (D6): a different `mutationKey` is `setOptions` on the same
    // controller, which starts over at idle, as upstream's observer does.
    hookTest('a new mutationKey on a later build starts over at idle',
        (tester, client) async {
      final first = queryKey();
      final second = queryKey();
      var key = first;
      late void Function() next;

      await tester.pumpApp(
        client,
        HookBuilder(builder: (context) {
          final toggle = useState(0);
          next = () => toggle.value++;
          final mutation = useMutation(MutationOptions.simple<String, String>(
            mutationKey: key,
            mutationFn: (text) => sleep(10).then((_) => text),
          ));
          results.add(mutation.value);
          return TextButton(
            onPressed: () => mutation.mutate('todo'),
            child: const Text('mutate'),
          );
        }),
      );
      await click(tester, 'mutate');
      await advance(tester, 11);
      expect(results.last.dataOrNull, 'todo');

      key = second;
      next();
      await tester.pump();
      expect(results.last.isIdle, isTrue);

      await click(tester, 'mutate');
      await advance(tester, 11);
      expect(results.last.dataOrNull, 'todo');
      expect(
        client.mutationCache
            .findAll(filters: MutationFilters(mutationKey: second))
            .single
            .state
            .data,
        'todo',
      );
    });

    hookTest('options new on every build add no build', (tester, client) async {
      var builds = 0;
      late void Function() rebuildParent;

      await tester.pumpApp(
        client,
        StatefulBuilder(builder: (context, setState) {
          rebuildParent = () => setState(() {});
          return HookBuilder(builder: (context) {
            builds++;
            final mutation = useMutation(options());
            return TextButton(
              onPressed: () => mutation.mutate('todo'),
              child: Text(mutation.value.status.name),
            );
          });
        }),
      );
      expect(builds, 1);

      for (var i = 0; i < 3; i++) {
        rebuildParent();
        await tester.pump();
      }
      expect(builds, 4); // one of its own, three from the parent

      await click(tester, 'idle');
      await advance(tester, 11);
      expect(find.text('success'), findsOneWidget);
      expect(builds, 6);
    });

    hookTest('buildWhen decides which result changes rebuild',
        (tester, client) async {
      final built = <String>[];
      var attempts = 0;

      await tester.pumpApp(
        client,
        HookBuilder(builder: (context) {
          final mutation = useMutation(
            MutationOptions.simple<String, String>(
              mutationFn: (text) => sleep(2).then(
                  (_) => ++attempts == 1 ? throw StateError('oops') : text),
              retry: const RetryPolicy.times(1),
              retryDelay: const RetryDelay.fixed(Duration(milliseconds: 5)),
            ),
            buildWhen: (previous, current) => previous.status != current.status,
          );
          final result = mutation.value;
          built.add('${result.status.name} ${result.failureCount}');
          return TextButton(
            onPressed: () => mutation.mutate('todo'),
            child: const Text('mutate'),
          );
        }),
      );
      await click(tester, 'mutate');
      await advance(tester, 10);

      expect(attempts, 2);
      // The failed first attempt changed the failure count, not the status.
      expect(built, ['idle 0', 'pending 0', 'success 0']);
    });
  });
}
