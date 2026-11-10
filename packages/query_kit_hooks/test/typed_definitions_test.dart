// Typed query definitions through the hooks: a reference's `options()` is
// the options every hook already takes, so nothing here needed a change to
// the hooks. What the cases prove is that it is so: the types are inferred
// at the call site without a type argument, and a rebuild with a recreated
// reference behaves as the same rebuild with inline raw options.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_hooks/query_kit_hooks.dart';

import 'harness.dart';

// ------------------------------------------------------------ static types

/// A function type with `T` in both positions: `Exactly<S>` is a supertype
/// of `Exactly<T>` only when `S` and `T` are subtypes of each other.
typedef Exactly<T> = T Function(T);

extension StaticType<T> on T {
  /// Compiles only when the receiver's static type is exactly the `X` of
  /// `R = Exactly<X>`: a wider and a narrower type both fail the bound.
  T expectStaticType<R extends Exactly<T>>() => this;
}

// ------------------------------------------------------------- the domain

final class Device {
  const Device(this.id, this.name);

  final String id;
  final String name;

  Device renamed(String name) => Device(id, name);

  @override
  bool operator ==(Object other) =>
      other is Device && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() => 'Device($id, $name)';
}

/// A backend whose every answer takes 10 ms and names the repository that
/// gave it, so a case can tell which fetcher ran.
final class Repo {
  Repo(this.label);

  final String label;

  /// Every request, in order: `detail a`, `list`, `page 0`, `rename a`.
  final List<String> calls = [];

  /// When set, a rename fails.
  bool refuseRenames = false;

  Future<Device> device(String id) {
    calls.add('detail $id');
    return sleep(10).then((_) => Device(id, '$label $id'));
  }

  Future<List<Device>> devices() {
    calls.add('list');
    return sleep(10).then((_) => [Device('a', '$label a')]);
  }

  Future<List<int>> page(int offset) {
    calls.add('page $offset');
    return sleep(10).then(
      (_) => offset >= 4 ? const <int>[] : [offset, offset + 1],
    );
  }

  Future<Device> rename(String id, String name) {
    calls.add('rename $id');
    return sleep(10).then((_) {
      if (refuseRenames) {
        throw StateError('refused');
      }
      return Device(id, name);
    });
  }

  int count(String call) => calls.where((each) => each == call).length;
}

/// The definitions as an application declares them: one class per resource
/// that holds its repository and a namespace.
final class DeviceQueries {
  DeviceQueries(this._repo, {this.configureDetail});

  final Repo _repo;

  /// What a case adds to the detail family's options, per input.
  final QueryObserverOptions<Device> Function(
    QueryObserverOptions<Device> base,
    String id,
  )? configureDetail;

  static final QueryNamespace namespace = QueryNamespace(const ['devices']);

  late final detail = QueryFamily<String, Device>(
    namespace: namespace,
    name: 'detail',
    queryFn: (id, _) => _repo.device(id),
    configure: configureDetail,
  );

  /// No type argument, on purpose: this one pins that the data type Dart
  /// infers from the fetch function reaches the hooks exactly (the
  /// inference case checks `QueryResult<List<Device>>`). App code writes
  /// every definition's type arguments out.
  late final list = QueryDefinition(
    namespace: namespace,
    name: 'list',
    queryFn: (_) => _repo.devices(),
  );

  late final feed = InfiniteQueryDefinition<List<int>, int>(
    namespace: namespace,
    name: 'feed',
    pageFn: (context) => _repo.page(context.pageParam),
    initialPageParam: 0,
    getNextPageParam: (page, _, pageParam, __) =>
        page.isEmpty ? null : pageParam + page.length,
  );

  late final byOwner = InfiniteQueryFamily<String, List<int>, int>(
    namespace: namespace,
    name: 'byOwner',
    pageFn: (owner, context) => _repo.page(context.pageParam),
    initialPageParam: (owner) => 0,
    getNextPageParam: (owner, page, _, pageParam, __) =>
        page.isEmpty ? null : pageParam + page.length,
  );
}

/// The raw key of `detail(id)`, spelled out for the raw twins.
QueryKey detailKey(String id) => QueryKey(['devices', 'detail', id]);

/// A parent that can be rebuilt from outside, around a hook widget.
///
/// [child] is called on every build of the parent: a widget built once
/// would be the same instance each time, and Flutter would not rebuild it.
Widget rebuildable(
  void Function(VoidCallback rebuild) bind,
  Widget Function() child,
) =>
    StatefulBuilder(builder: (context, setState) {
      bind(() => setState(() {}));
      return child();
    });

void main() {
  group('inference: no type argument at the call site', () {
    hookTest('useQuery over options(), copyWith and withSelect',
        (tester, client) async {
      final queries = DeviceQueries(Repo('r'));
      final device = queries.detail('a');

      await tester.pumpApp(
        client,
        HookBuilder(builder: (context) {
          final plain = useQuery(device.options())
              .expectStaticType<Exactly<QueryResult<Device>>>();
          final tuned = useQuery(device.options().copyWith(
                staleTime: const StaleTime.duration(Duration(minutes: 1)),
              )).expectStaticType<Exactly<QueryResult<Device>>>();
          final name = useSelectQuery(
            device.options().withSelect((device) => device.name),
          ).expectStaticType<Exactly<QueryResult<String>>>();
          final all = useQuery(queries.list.options())
              .expectStaticType<Exactly<QueryResult<List<Device>>>>();
          return Text([
            plain.dataOrNull?.name,
            tuned.dataOrNull?.name,
            name.dataOrNull,
            all.dataOrNull?.length,
          ].join('/'));
        }),
      );
      await advance(tester, 11);

      expect(find.text('r a/r a/r a/1'), findsOneWidget);
      // One entry of exactly the declared type: the reference reads it.
      device.read(client).expectStaticType<Exactly<Device?>>();
      expect(device.read(client), const Device('a', 'r a'));
      expect(queries.list.read(client), [const Device('a', 'r a')]);
      expect(
          client.queryCache.find(filters: device.filters())!.dataType, Device);
    });

    hookTest('useInfiniteQuery over a definition, a family and withSelect',
        (tester, client) async {
      final queries = DeviceQueries(Repo('r'));
      late InfiniteQueryController<List<int>, int, InfiniteData<List<int>, int>>
          feed;

      await tester.pumpApp(
        client,
        HookBuilder(builder: (context) {
          feed = useInfiniteQuery(queries.feed.options()).expectStaticType<
              Exactly<
                  InfiniteQueryController<List<int>, int,
                      InfiniteData<List<int>, int>>>>();
          final mine = useInfiniteQuery(queries.byOwner('ada').options())
              .expectStaticType<
                  Exactly<
                      InfiniteQueryController<List<int>, int,
                          InfiniteData<List<int>, int>>>>();
          final flat = useInfiniteQuery(queries.feed.options().withSelect(
                    (data) => [for (final page in data.pages) ...page],
                  ))
              .expectStaticType<
                  Exactly<
                      InfiniteQueryController<List<int>, int, List<int>>>>();
          return Text('${flat.value.dataOrNull} '
              '${mine.value.dataOrNull?.pages.length}');
        }),
      );
      await advance(tester, 11);
      expect(find.text('[0, 1] 1'), findsOneWidget);

      feed.fetchNextPage().ignore();
      await advance(tester, 11);
      expect(find.text('[0, 1, 2, 3] 1'), findsOneWidget);
      queries.feed
          .read(client)
          .expectStaticType<Exactly<InfiniteData<List<int>, int>?>>();
      expect(queries.feed.read(client)!.pages, [
        [0, 1],
        [2, 3],
      ]);
      expect(queries.byOwner('ada').read(client)!.pageParams, [0]);
    });

    hookTest('useQueries and useCombinedQueries over one data type',
        (tester, client) async {
      final queries = DeviceQueries(Repo('r'));

      await tester.pumpApp(
        client,
        HookBuilder(builder: (context) {
          final both = useQueries([
            queries.detail('a').options(),
            queries.detail('b').options(),
          ]).expectStaticType<Exactly<List<QueryResult<Device>>>>();
          final names = useCombinedQueries(
            [queries.detail('a').options(), queries.detail('b').options()],
            (devices) => devices.map((device) => device.name).join(','),
            keys: const [],
          ).expectStaticType<Exactly<CombinedResult<String>>>();
          return Text('${both.length} ${names.dataOrNull}');
        }),
      );
      await advance(tester, 11);

      expect(find.text('2 r a,r b'), findsOneWidget);
      expect(queries.detail('b').read(client), const Device('b', 'r b'));
    });

    hookTest('a typed record of two data types combines',
        (tester, client) async {
      final queries = DeviceQueries(Repo('r'));

      await tester.pumpApp(
        client,
        HookBuilder(builder: (context) {
          final page = (
            useQuery(queries.detail('a').options()),
            useQuery(queries.list.options()),
          )
              .combine((device, all) => '${device.name} of ${all.length}')
              .expectStaticType<Exactly<CombinedResult<String>>>();
          return Text(page.dataOrNull ?? 'pending');
        }),
      );
      await advance(tester, 11);

      expect(find.text('r a of 1'), findsOneWidget);
    });

    hookTest(
        'usePrefetchQuery and usePrefetchInfiniteQuery create entries '
        'of the declared types', (tester, client) async {
      final repo = Repo('r');
      final queries = DeviceQueries(repo);

      await tester.pumpApp(
        client,
        HookBuilder(builder: (context) {
          usePrefetchQuery(queries.detail('a').options());
          usePrefetchInfiniteQuery(queries.feed.options());
          return const SizedBox();
        }),
      );
      await advance(tester, 11);

      expect(repo.calls, ['detail a', 'page 0']);
      // A typed read throws for an entry of any other type.
      expect(queries.detail('a').read(client), const Device('a', 'r a'));
      expect(queries.feed.read(client)!.pages, [
        [0, 1],
      ]);

      // A rebuild over existing entries prefetches nothing.
      await tester.pumpApp(
        client,
        HookBuilder(builder: (context) {
          usePrefetchQuery(DeviceQueries(repo).detail('a').options());
          usePrefetchInfiniteQuery(DeviceQueries(repo).feed.options());
          return const Text('again');
        }),
      );
      await advance(tester, 11);
      expect(repo.calls, ['detail a', 'page 0']);
    });

    hookTest('useIsFetching counts a reference, a family and a namespace',
        (tester, client) async {
      final queries = DeviceQueries(Repo('r'));

      await tester.pumpApp(
        client,
        HookBuilder(builder: (context) {
          final one = useIsFetching(filters: queries.detail('a').filters());
          final family = useIsFetching(filters: queries.detail.filters());
          final all = useIsFetching(filters: DeviceQueries.namespace.filters());
          return Text('$one $family $all');
        }),
      );
      expect(find.text('0 0 0'), findsOneWidget);

      queries.detail('a').fetch(client).ignore();
      queries.detail('b').fetch(client).ignore();
      queries.list.fetch(client).ignore();
      // Outside the namespace: no count sees it.
      client
          .query(QueryOptions<int>(
            queryKey: QueryKey(const ['other']),
            queryFn: (_) => sleep(10).then((_) => 1),
          ))
          .ignore();
      await tester.pump();
      expect(find.text('1 2 3'), findsOneWidget);

      await advance(tester, 11);
      expect(find.text('0 0 0'), findsOneWidget);
    });

    hookTest(
        'useMutation: an optimistic write through a reference, its rollback '
        'and the family invalidated', (tester, client) async {
      final repo = Repo('r');
      final queries = DeviceQueries(repo);
      final device = queries.detail('a');
      late MutationController<Device, String, Device> rename;

      await tester.pumpApp(
        client,
        HookBuilder(builder: (context) {
          final client = useQueryClient();
          final shown = useQuery(device.options());
          // Mutations have no definitions: their type arguments are written
          // as before, and the callbacks reach the cache through references.
          rename = useMutation(MutationOptions<Device, String, Device>(
            mutationFn: (name) => repo.rename('a', name),
            onMutate: (name) async {
              await device.cancel(client);
              final previous =
                  device.read(client).expectStaticType<Exactly<Device?>>();
              device.update(client, (device) => device?.renamed(name));
              return previous;
            },
            onError: (_, __, ___, previous) {
              if (previous != null) {
                device.write(client, previous);
              }
            },
            onSuccess: (renamed, _, __) => device.write(client, renamed),
            onSettled: (_, __, ___, ____, _____) =>
                queries.detail.invalidate(client),
          ));
          return Text(shown.dataOrNull?.name ?? 'pending');
        }),
      );
      await advance(tester, 11);
      expect(find.text('r a'), findsOneWidget);

      // Written before the backend answers, then the family refetched.
      rename.mutate('lamp');
      await tester.pump();
      expect(find.text('lamp'), findsOneWidget);
      await advance(tester, 11);
      expect(repo.count('detail a'), 2);
      await advance(tester, 11);
      expect(find.text('r a'), findsOneWidget); // the backend's own answer

      // A refusal puts back what was there.
      repo.refuseRenames = true;
      rename.mutate('desk');
      await tester.pump();
      expect(find.text('desk'), findsOneWidget);
      await advance(tester, 11);
      expect(find.text('r a'), findsOneWidget);
      // `onSettled` returns the invalidation, and the mutation settles when
      // that refetch has.
      await advance(tester, 11);
      expect(rename.value.isError, isTrue);
      expect(repo.count('detail a'), 3);
    });
  });

  group('a rebuild with a recreated reference is a rebuild with raw options',
      () {
    /// Mounts [optionsOf] under a parent, rebuilds the parent every 30 ms
    /// for 300 ms, and reports what the backend and the builds saw.
    Future<({List<String> calls, int builds, int observers})> rebuildEvery30ms(
      WidgetTester tester,
      QueryClient client,
      QueryObserverOptions<Device> Function(Repo repo) optionsOf,
    ) async {
      final repo = Repo('r');
      var builds = 0;
      late VoidCallback rebuild;
      await tester.pumpApp(
        client,
        rebuildable(
          (bound) => rebuild = bound,
          () => HookBuilder(builder: (context) {
            builds++;
            final result = useQuery(optionsOf(repo));
            return Text(result.dataOrNull?.name ?? 'pending');
          }),
        ),
      );
      await advance(tester, 11);
      for (var i = 0; i < 10; i++) {
        rebuild();
        await advance(tester, 30);
      }
      return (
        calls: repo.calls,
        builds: builds,
        observers: observersOf(client, detailKey('a')),
      );
    }

    hookTest('stale data: no fetch, no extra build', (tester, client) async {
      final typed = await rebuildEvery30ms(
        tester,
        client,
        (repo) => DeviceQueries(repo).detail('a').options(),
      );
      client.clear();
      final raw = await rebuildEvery30ms(
        tester,
        client,
        (repo) => QueryObserverOptions<Device>(
          queryKey: detailKey('a'),
          queryFn: (_) => repo.device('a'),
        ),
      );

      expect(typed.calls, ['detail a']);
      expect(typed.calls, raw.calls);
      expect(typed.builds, raw.builds);
      expect(typed.builds, 12); // two of its own, ten from the parent
      expect((typed.observers, raw.observers), (1, 1));
    });

    hookTest('a refetch interval: the timer is not restarted',
        (tester, client) async {
      const interval = RefetchInterval.every(Duration(milliseconds: 100));
      final typed = await rebuildEvery30ms(
        tester,
        client,
        (repo) => DeviceQueries(
          repo,
          configureDetail: (base, _) =>
              base.copyWith(refetchInterval: interval),
        ).detail('a').options(),
      );
      await tester.pumpWidget(const SizedBox());
      client.clear();
      final raw = await rebuildEvery30ms(
        tester,
        client,
        (repo) => QueryObserverOptions<Device>(
          queryKey: detailKey('a'),
          queryFn: (_) => repo.device('a'),
          refetchInterval: interval,
        ),
      );

      // A timer restarted by every rebuild, 30 ms apart, would never reach
      // 100 ms: one fetch in all.
      expect(typed.calls.length, greaterThanOrEqualTo(3));
      expect(typed.calls, raw.calls);
      expect(typed.builds, raw.builds);
    });

    hookTest('an infinite definition recreated on every build fetches no page',
        (tester, client) async {
      final repo = Repo('r');
      var builds = 0;
      late VoidCallback rebuild;
      await tester.pumpApp(
        client,
        rebuildable(
          (bound) => rebuild = bound,
          () => HookBuilder(builder: (context) {
            builds++;
            final feed = useInfiniteQuery(DeviceQueries(repo).feed.options());
            return Text('${feed.value.dataOrNull?.pages}');
          }),
        ),
      );
      await advance(tester, 11);
      for (var i = 0; i < 5; i++) {
        rebuild();
        await advance(tester, 30);
      }
      expect(builds, 7); // two of its own, five from the parent
      expect(repo.calls, ['page 0']);
    });

    hookTest(
        'a new definition instance with another fetcher: the rebuild fetches '
        'nothing, the next fetch uses the new one', (tester, client) async {
      final first = Repo('first');
      final second = Repo('second');
      var repo = first;
      late VoidCallback rebuild;
      await tester.pumpApp(
        client,
        rebuildable(
          (bound) => rebuild = bound,
          () => HookBuilder(builder: (context) {
            final result = useQuery(DeviceQueries(repo).detail('a').options());
            return Text(result.dataOrNull?.name ?? 'pending');
          }),
        ),
      );
      await advance(tester, 11);
      expect(find.text('first a'), findsOneWidget);

      repo = second;
      rebuild();
      await advance(tester, 11);
      expect(first.calls, ['detail a']);
      expect(second.calls, isEmpty);

      // Any reference to the entry will do: they are equal.
      DeviceQueries(first).detail('a').invalidate(client).ignore();
      await advance(tester, 11);
      expect(find.text('second a'), findsOneWidget);
      expect(first.calls, ['detail a']);
      expect(second.calls, ['detail a']);
    });
  });

  group('Enabled.when over outside state is asked again on a rebuild', () {
    hookTest('set by the definition', (tester, client) async {
      final repo = Repo('r');
      var gate = false;
      late VoidCallback rebuild;
      await tester.pumpApp(
        client,
        rebuildable(
          (bound) => rebuild = bound,
          () => HookBuilder(builder: (context) {
            final queries = DeviceQueries(
              repo,
              configureDetail: (base, _) =>
                  base.copyWith(enabled: Enabled.when((_) => gate)),
            );
            final result = useQuery(queries.detail('a').options());
            return Text(result.dataOrNull?.name ?? 'pending');
          }),
        ),
      );
      await advance(tester, 11);
      expect(repo.calls, isEmpty);

      gate = true;
      rebuild();
      await advance(tester, 11);
      expect(repo.calls, ['detail a']);
      expect(find.text('r a'), findsOneWidget);
    });

    hookTest('set for one use with copyWith', (tester, client) async {
      final repo = Repo('r');
      final queries = DeviceQueries(repo);
      var gate = false;
      late VoidCallback rebuild;
      await tester.pumpApp(
        client,
        rebuildable(
          (bound) => rebuild = bound,
          () => HookBuilder(builder: (context) {
            final result = useQuery(queries.detail('a').options().copyWith(
                  enabled: Enabled.when((_) => gate),
                ));
            return Text(result.dataOrNull?.name ?? 'pending');
          }),
        ),
      );
      await advance(tester, 11);
      expect(repo.calls, isEmpty);

      gate = true;
      rebuild();
      await advance(tester, 11);
      expect(repo.calls, ['detail a']);
      expect(find.text('r a'), findsOneWidget);
    });
  });

  group(
      'a held Enabled.when over outside state is asked again by a rebuild '
      'whose options are equal to the last ones', () {
    // One definition and one callback for every build: the options the hook
    // hands the observer are equal each time, and only the observer
    // comparing the callback's answer with its last result tells the
    // rebuild apart.
    hookTest('useQuery', (tester, client) async {
      final repo = Repo('r');
      var allowed = false;
      final enabled = Enabled.when((_) => allowed);
      final current = QueryDefinition<Device>(
        namespace: DeviceQueries.namespace,
        name: 'current',
        queryFn: (_) => repo.device('a'),
        configure: (base) => base.copyWith(enabled: enabled),
      );
      expect(
        client.defaultQueryObserverOptions<Device, Device>(current.options()),
        client.defaultQueryObserverOptions<Device, Device>(current.options()),
      );
      var updates = 0;
      final stop = client.queryCache.subscribe((event) {
        if (event is QueryObserverOptionsUpdated) updates++;
      });
      addTearDown(stop);
      late VoidCallback rebuild;
      await tester.pumpApp(
        client,
        rebuildable(
          (bound) => rebuild = bound,
          () => HookBuilder(builder: (context) {
            final result = useQuery(current.options());
            return Text(result.dataOrNull?.name ?? 'pending');
          }),
        ),
      );
      await advance(tester, 11);
      rebuild();
      await advance(tester, 11);
      expect(repo.calls, isEmpty);

      allowed = true;
      rebuild();
      await advance(tester, 11);
      expect(repo.calls, ['detail a']);
      expect(find.text('r a'), findsOneWidget);
      expect(updates, 0, reason: 'every build handed equal options');
    });

    hookTest('useInfiniteQuery', (tester, client) async {
      final repo = Repo('r');
      var allowed = false;
      final enabled = Enabled.when((_) => allowed);
      final feed = InfiniteQueryDefinition<List<int>, int>(
        namespace: DeviceQueries.namespace,
        name: 'held feed',
        pageFn: (context) => repo.page(context.pageParam),
        initialPageParam: 0,
        getNextPageParam: (page, _, pageParam, __) =>
            page.isEmpty ? null : pageParam + page.length,
        configure: (base) => base.copyWith(enabled: enabled),
      );
      var updates = 0;
      final stop = client.queryCache.subscribe((event) {
        if (event is QueryObserverOptionsUpdated) updates++;
      });
      addTearDown(stop);
      late VoidCallback rebuild;
      await tester.pumpApp(
        client,
        rebuildable(
          (bound) => rebuild = bound,
          () => HookBuilder(builder: (context) {
            final result = useInfiniteQuery(feed.options());
            return Text('pages=${result.value.dataOrNull?.pages.length ?? 0}');
          }),
        ),
      );
      await advance(tester, 11);
      rebuild();
      await advance(tester, 11);
      expect(repo.calls, isEmpty);

      allowed = true;
      rebuild();
      await advance(tester, 11);
      expect(repo.calls, ['page 0']);
      expect(find.text('pages=1'), findsOneWidget);
      expect(updates, 0, reason: 'every build handed equal options');
    });
  });

  group('lifecycle', () {
    hookTest('a parameter change moves the observer to the other entry',
        (tester, client) async {
      final repo = Repo('r');
      var id = 'a';
      late VoidCallback rebuild;
      await tester.pumpApp(
        client,
        rebuildable(
          (bound) => rebuild = bound,
          () => HookBuilder(builder: (context) {
            final result = useQuery(DeviceQueries(repo).detail(id).options());
            return Text(result.dataOrNull?.name ?? 'pending');
          }),
        ),
      );
      await advance(tester, 11);
      expect(find.text('r a'), findsOneWidget);

      id = 'b';
      rebuild();
      await tester.pump();
      expect(find.text('pending'), findsOneWidget);
      expect(observersOf(client, detailKey('a')), 0);
      expect(observersOf(client, detailKey('b')), 1);
      await advance(tester, 11);
      expect(find.text('r b'), findsOneWidget);
      expect(repo.calls, ['detail a', 'detail b']);
    });

    hookTest('a client switch through the provider re-creates the observer',
        (tester, client) async {
      final other = QueryClient();
      addTearDown(other.clear);
      final queries = DeviceQueries(Repo('r'));
      final device = queries.detail('a');
      Widget tree(QueryClient client) => app(
            client,
            HookBuilder(builder: (context) {
              final result = useQuery(device.options());
              return Text(result.dataOrNull?.name ?? 'pending');
            }),
          );

      await tester.pumpWidget(tree(client));
      await advance(tester, 11);
      expect(device.read(client), const Device('a', 'r a'));

      await tester.pumpWidget(tree(other));
      expect(find.text('pending'), findsOneWidget);
      expect(observersOf(client, device.key.rawKey), 0);
      expect(observersOf(other, device.key.rawKey), 1);
      await advance(tester, 11);
      expect(find.text('r a'), findsOneWidget);
      expect(device.read(other), const Device('a', 'r a'));
      // The other client's collection timer, before the teardown checks.
      await tester.pumpWidget(const SizedBox());
      other.clear();
    });

    hookTest('unmount: the observer goes, and the entry after its gcTime',
        (tester, client) async {
      final queries = DeviceQueries(
        Repo('r'),
        configureDetail: (base, _) => base.copyWith(
          gcTime: const GcTime.duration(Duration(milliseconds: 50)),
        ),
      );
      final device = queries.detail('a');
      await tester.pumpApp(
        client,
        HookBuilder(builder: (context) {
          final result = useQuery(device.options());
          return Text(result.dataOrNull?.name ?? 'pending');
        }),
      );
      await advance(tester, 11);
      expect(observersOf(client, device.key.rawKey), 1);

      await tester.pumpApp(client, const SizedBox());
      expect(observersOf(client, device.key.rawKey), 0);
      expect(device.state(client), isNotNull);
      await advance(tester, 51);
      expect(device.state(client), isNull);
    });

    hookTest('ref.cancel stops the fetch in flight and puts the state back',
        (tester, client) async {
      final repo = Repo('r');
      final device = DeviceQueries(repo).detail('a');
      late QueryResult<Device> shown;
      await tester.pumpApp(
        client,
        HookBuilder(builder: (context) {
          shown = useQuery(device.options());
          return Text(shown.dataOrNull?.name ?? 'pending');
        }),
      );
      await tester.pump();
      expect(shown.isFetching, isTrue);

      await device.cancel(client);
      await tester.pump();
      expect(shown.isFetching, isFalse);
      expect(shown, isA<QueryPending<Device>>());
      await advance(tester, 11);
      expect(find.text('pending'), findsOneWidget);

      device.refetch(client).ignore();
      await advance(tester, 11);
      expect(find.text('r a'), findsOneWidget);
    });
  });

  group('writes and invalidation rebuild exactly the hooks they reach', () {
    late Map<String, int> builds;

    // Generic, not `QueryObserverOptions<Object>`: options handed through a
    // wider parameter type make the hook observe an `Object` entry, which
    // the references' typed writes then refuse.
    Widget reader<T>(String name, QueryObserverOptions<T> options) =>
        HookBuilder(builder: (context) {
          builds[name] = (builds[name] ?? 0) + 1;
          final result = useQuery(options);
          return Text('$name ${result.dataOrNull}');
        });

    Future<DeviceQueries> mountThree(
      WidgetTester tester,
      QueryClient client,
      Repo repo,
    ) async {
      builds = {};
      final queries = DeviceQueries(repo);
      await tester.pumpApp(
        client,
        Column(children: [
          reader('a', queries.detail('a').options()),
          reader('b', queries.detail('b').options()),
          reader('list', queries.list.options()),
        ]),
      );
      await advance(tester, 11);
      return queries;
    }

    /// Which readers built since [before].
    Set<String> rebuiltSince(Map<String, int> before) => {
          for (final MapEntry(:key, :value) in builds.entries)
            if (value != before[key]) key,
        };

    hookTest('write, update and updateAll', (tester, client) async {
      final queries = await mountThree(tester, client, Repo('r'));

      var before = {...builds};
      queries.detail('a').write(client, const Device('a', 'written'));
      await tester.pump();
      expect(rebuiltSince(before), {'a'});

      before = {...builds};
      queries.detail('b').update(client, (device) => device?.renamed('moved'));
      await tester.pump();
      expect(rebuiltSince(before), {'b'});

      before = {...builds};
      queries.detail.updateAll(client, (device) => device?.renamed('all'));
      await tester.pump();
      expect(rebuiltSince(before), {'a', 'b'});
      expect(find.text('a Device(a, all)'), findsOneWidget);
      expect(find.text('b Device(b, all)'), findsOneWidget);
    });

    hookTest('invalidate a reference, a family, a namespace',
        (tester, client) async {
      final repo = Repo('r');
      final queries = await mountThree(tester, client, repo);
      repo.calls.clear();

      var before = {...builds};
      queries.detail('a').invalidate(client).ignore();
      await advance(tester, 11);
      expect(repo.calls, ['detail a']);
      expect(rebuiltSince(before), {'a'});

      repo.calls.clear();
      before = {...builds};
      queries.detail.invalidate(client).ignore();
      await advance(tester, 11);
      expect(repo.calls, unorderedEquals(['detail a', 'detail b']));
      expect(rebuiltSince(before), {'a', 'b'});

      repo.calls.clear();
      before = {...builds};
      DeviceQueries.namespace.invalidate(client).ignore();
      await advance(tester, 11);
      expect(repo.calls, unorderedEquals(['detail a', 'detail b', 'list']));
      expect(rebuiltSince(before), {'a', 'b', 'list'});
    });
  });

  hookTest(
      'a reference as a hook key: equal on a rebuild, another on an input '
      'change', (tester, client) async {
    final repo = Repo('r');
    var id = 'a';
    var builds = 0;
    var effects = 0;
    var memos = 0;
    late VoidCallback rebuild;
    await tester.pumpApp(
      client,
      rebuildable(
        (bound) => rebuild = bound,
        () => HookBuilder(builder: (context) {
          builds++;
          // A new definition instance and a new reference every build.
          final device = DeviceQueries(repo).detail(id);
          useEffect(() {
            effects++;
            return null;
          }, [device]);
          final memo = useMemoized(() => ++memos, [device]);
          return Text('$memo');
        }),
      ),
    );
    expect((effects, memos), (1, 1));

    for (var i = 0; i < 3; i++) {
      rebuild();
      await tester.pump();
    }
    expect((builds, effects, memos), (4, 1, 1));

    id = 'b';
    rebuild();
    await tester.pump();
    expect((effects, memos), (2, 2));
  });

  hookTest(
      'a list of two data types to useQueries infers Object, and makes '
      'entries the references then refuse (outside the guarantee)',
      (tester, client) async {
    final queries = DeviceQueries(Repo('r'));
    late List<QueryResult<Object>> results;
    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        results = useQueries([
          queries.detail('a').options(),
          queries.list.options(),
        ]).expectStaticType<Exactly<List<QueryResult<Object>>>>();
        return const SizedBox();
      }),
    );
    await advance(tester, 11);

    expect(results.map((result) => result.dataOrNull), [
      const Device('a', 'r a'),
      [const Device('a', 'r a')],
    ]);
    expect(
      client.queryCache.find(filters: queries.detail('a').filters())!.dataType,
      Object,
    );
    expect(() => queries.detail('a').read(client),
        throwsA(isA<QueryDataTypeError>()));
    expect(() => queries.list.write(client, const []),
        throwsA(isA<QueryDataTypeError>()));
  });
}
