// What the hooks do that upstream's suites cannot say: Flutter's element
// lifecycle, the client a hook resolves, and flutter_hooks' own rules
// (plan, D5–D7 and D13).
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_hooks/query_kit_hooks.dart';

import 'harness.dart';

int observersOf(QueryClient client, QueryKey key) =>
    client.queryCache
        .find(filters: QueryFilters(queryKey: key))
        ?.observersCount ??
    0;

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
        return HookProbe((context) {
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
          HookProbe((context) {
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
      home: HookProbe((context) {
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
      HookProbe((context) {
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

    Widget probe() => HookProbe(
          key: globalKey,
          (context) {
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
      HookProbe((context) {
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
    final observer = client.queryCache
        .find(filters: QueryFilters(queryKey: key))!
        .observersCount;
    expect(observer, 1);

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
      HookProbe((context) {
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
          return HookProbe((context) {
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
        HookProbe((context) {
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
}
