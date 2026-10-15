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
}
