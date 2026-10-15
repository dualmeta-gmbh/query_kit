// Options that cannot be applied, in every call style.
//
// A seed whose `InitialData.compute` throws makes the observer refuse the new
// options and keep the old ones (the core's update is atomic); a reader with
// no provider above cannot resolve its client. Before ASTRA-B1 the builder
// widgets did both in `didUpdateWidget`, and Flutter's own elements drop a
// child whose update threw without ever disposing it: the observer, and its
// `refetchInterval`, ran on with the whole tree gone. The first fix released
// the controller on the throw, which the fresh verifier showed wrong for a
// parent that keeps the child (V-1) and incomplete for the client lookup
// (V-2). The builders now do both in `build`, as the keyless styles always
// did: a failure is an ordinary build error, the state stays, shows the error
// widget, recovers on the next options that apply, and is disposed as usual.
// PORTING_NOTES, "Independent reviews 2026-10-15".
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'harness.dart';

InitialData<T> _throwingSeed<T>() =>
    InitialData<T>.compute(() => throw StateError('seed'));

/// One reader per call style, polling the key `old` and then handed the
/// throwing options for `next`.
final Map<
    String,
    Widget Function(
        {required bool rejected, required void Function() onFetch})> _styles = {
  'QueryBuilder': ({required rejected, required onFetch}) => QueryBuilder<int>(
        options: _options(rejected: rejected, onFetch: onFetch),
        builder: (_, result) => Text('${result.dataOrNull}'),
      ),
  'InfiniteQueryBuilder': ({required rejected, required onFetch}) =>
      InfiniteQueryBuilder<int, int, InfiniteData<int, int>>(
        options: InfiniteQueryObserverOptions<int, int>(
          queryKey: QueryKey([rejected ? 'next' : 'old']),
          initialPageParam: 1,
          pageFn: (context) {
            onFetch();
            return context.pageParam;
          },
          getNextPageParam: (_, __, ___, ____) => null,
          refetchInterval: const RefetchInterval.every(Duration(seconds: 1)),
          initialData: rejected ? _throwingSeed() : null,
        ),
        builder: (_, controller) =>
            Text('${controller.value.dataOrNull?.pages.first}'),
      ),
  'QueriesBuilder': ({required rejected, required onFetch}) =>
      QueriesBuilder<int, int>(
        queries: [_options(rejected: rejected, onFetch: onFetch)],
        builder: (_, results) => Text('${results.first.dataOrNull}'),
      ),
  'context.query': ({required rejected, required onFetch}) =>
      _ContextReader(_options(rejected: rejected, onFetch: onFetch)),
  'QueryMixin': ({required rejected, required onFetch}) =>
      _MixinReader(_options(rejected: rejected, onFetch: onFetch)),
};

QueryObserverOptions<int> _options({
  required bool rejected,
  required void Function() onFetch,
}) =>
    QueryObserverOptions<int>(
      queryKey: QueryKey([rejected ? 'next' : 'old']),
      queryFn: (_) {
        onFetch();
        return 1;
      },
      refetchInterval: const RefetchInterval.every(Duration(seconds: 1)),
      initialData: rejected ? _throwingSeed() : null,
    );

void main() {
  for (final MapEntry(key: style, value: view) in _styles.entries) {
    queryWidgetTest(
        '$style releases what it holds when an options update throws, '
        'and stops polling', (tester, client) async {
      var fetches = 0;
      void onFetch() => fetches++;
      await tester.pumpApp(client, view(rejected: false, onFetch: onFetch));
      await tester.pumpAndSettle();
      final old = client.queryCache
          .find(filters: QueryFilters(queryKey: QueryKey(['old'])))!;
      expect(old.observersCount, 1);

      await tester.pumpApp(client, view(rejected: true, onFetch: onFetch));
      expect(tester.takeException(), isA<StateError>());
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      final before = fetches;
      await tester.pump(const Duration(seconds: 3));
      expect(old.observersCount, 0, reason: 'the reader has left the tree');
      expect(fetches, before, reason: 'nobody is left to show a poll');
    });
  }

  // The state outlives the failure: it holds what it held, and the next
  // options that apply carry on with the same controller.
  for (final MapEntry(key: style, value: view) in _styles.entries) {
    queryWidgetTest(
        '$style keeps its observer through options that throw, and recovers',
        (tester, client) async {
      var fetches = 0;
      void onFetch() => fetches++;
      await tester.pumpApp(client, view(rejected: false, onFetch: onFetch));
      await tester.pumpAndSettle();
      final old = client.queryCache
          .find(filters: QueryFilters(queryKey: QueryKey(['old'])))!;

      await tester.pumpApp(client, view(rejected: true, onFetch: onFetch));
      expect(tester.takeException(), isA<StateError>());
      expect(find.byType(ErrorWidget), findsOneWidget);
      expect(old.observersCount, 1, reason: 'the reader is still mounted');

      await tester.pumpApp(client, view(rejected: false, onFetch: onFetch));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorWidget), findsNothing);
      expect(find.text('1'), findsOneWidget);
      expect(old.observersCount, 1);
    });
  }

  queryWidgetTest(
      'a refetch in flight survives options that throw, and lands after '
      'the recovery', (tester, client) async {
    final done = Completer<int>();
    var cancelled = false;
    QueryResult<int>? shown;
    Widget tree({required bool rejected}) => QueryBuilder<int>(
          options: QueryObserverOptions<int>(
            queryKey: QueryKey([rejected ? 'next' : 'old']),
            queryFn: (context) {
              context.signal.onCancel(() => cancelled = true);
              return done.future;
            },
            staleTime: StaleTime.infinite,
            initialData:
                rejected ? _throwingSeed() : const InitialData.value(1),
          ),
          builder: (_, result) {
            shown = result;
            return Text('data=${result.dataOrNull}');
          },
        );
    await tester.pumpApp(client, tree(rejected: false));
    final refetch = shown!.refetch();
    await tester.pump();

    await tester.pumpApp(client, tree(rejected: true));
    expect(tester.takeException(), isA<StateError>());
    await tester.pumpApp(client, tree(rejected: false));
    done.complete(7);
    await tester.pump();
    expect(((await refetch).dataOrNull, cancelled), (7, false));
    await tester.pump();
    expect(find.text('data=7'), findsOneWidget);
  });

  queryWidgetTest(
      'a MutationBuilder keeps its run and its per-call callbacks through '
      'options that throw', (tester, _) async {
    final client = tester.adopt(_RejectingClient());
    final done = Completer<int>();
    var callbacks = 0;
    MutationController<int, int, void>? shown;
    final options =
        MutationOptions<int, int, void>(mutationFn: (_) => done.future);
    Widget tree() => MutationBuilder<int, int, void>(
          options: options,
          builder: (_, controller) {
            shown = controller;
            return Text('mutation=${controller.value.status.name}');
          },
        );
    await tester.pumpApp(client, tree());
    final original = shown!;
    final run = original.mutateAsync(1,
        callbacks: MutateCallbacks(onSuccess: (_, __, ___) => callbacks++));
    await tester.pump();

    client.reject = true;
    await tester.pumpApp(client, tree());
    expect(tester.takeException(), isA<StateError>());
    client.reject = false;
    await tester.pumpApp(client, tree());
    expect(find.text('mutation=pending'), findsOneWidget);

    done.complete(7);
    expect(await run, 7);
    await tester.pump();
    expect((identical(shown, original), callbacks), (true, 1));
    expect(find.text('mutation=success'), findsOneWidget);
  });

  // V-2: the client lookup throws too, and went before the first fix's
  // release.
  for (final collection in [false, true]) {
    final style = collection ? 'QueriesBuilder' : 'QueryBuilder';
    queryWidgetTest(
        '$style with no provider left to resolve its client releases what '
        'it holds when it goes', (tester, client) async {
      Widget tree(QueryClient? explicit) => Directionality(
            textDirection: TextDirection.ltr,
            child: collection
                ? QueriesBuilder<int, int>(
                    client: explicit,
                    queries: [_options(rejected: false, onFetch: () {})],
                    builder: (_, results) =>
                        Text('${results.single.dataOrNull}'),
                  )
                : QueryBuilder<int>(
                    client: explicit,
                    options: _options(rejected: false, onFetch: () {}),
                    builder: (_, result) => Text('${result.dataOrNull}'),
                  ),
          );
      await tester.pumpWidget(tree(client));
      await tester.pump();
      final old = client.queryCache
          .find(filters: QueryFilters(queryKey: QueryKey(['old'])))!;
      expect(old.observersCount, 1);

      await tester.pumpWidget(tree(null));
      expect(tester.takeException(), isA<FlutterError>());
      await tester.pumpWidget(const SizedBox());
      expect(old.observersCount, 0);
    });
  }

  queryWidgetTest(
      'a QueryBuilder moved to another client with options that throw holds '
      'nothing on either', (tester, client) async {
    final other = tester.adopt(QueryClient());
    Widget tree(QueryClient explicit, {required bool rejected}) =>
        QueryBuilder<int>(
          client: explicit,
          options: _options(rejected: rejected, onFetch: () {}),
          builder: (_, result) => Text('${result.dataOrNull}'),
        );
    await tester.pumpApp(client, tree(client, rejected: false));
    await tester.pump();
    final old = client.queryCache.findAll().single;

    await tester.pumpApp(client, tree(other, rejected: true));
    expect(tester.takeException(), isA<StateError>());
    expect(old.observersCount, 0);
    expect(
        other.queryCache.findAll().where((q) => q.observersCount > 0), isEmpty);
  });

  // A header delegate builds its child during layout, where nothing catches
  // a throw from `didUpdateWidget`: the element stays on screen. In `build`
  // the throw is caught there too, and the state keeps what it held.
  queryWidgetTest(
      'a QueryBuilder updated during layout keeps its observer through '
      'options that throw', (tester, client) async {
    var rejected = false;
    await tester.pumpApp(
      client,
      CustomScrollView(slivers: [
        SliverPersistentHeader(delegate: _Header(() => rejected)),
        const SliverToBoxAdapter(child: SizedBox(height: 3000)),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('row=1'), findsOneWidget);
    final old = client.queryCache
        .find(filters: QueryFilters(queryKey: QueryKey(['old'])))!;

    rejected = true;
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -30));
    await tester.pump();
    expect(tester.takeException(), isA<StateError>());
    expect(old.observersCount, 1);

    rejected = false;
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -30));
    await tester.pump();
    expect(find.text('row=1'), findsOneWidget);
    client.setQueryData<int>(QueryKey(['old']), 2);
    await tester.pump();
    expect(find.text('row=2'), findsOneWidget);
    expect(old.observersCount, 1);
  });

  // Flutter does not dispose what it abandons below a `didUpdateWidget`
  // that threw, siblings included; a throw in `build` abandons nothing.
  queryWidgetTest(
      'a sibling of a QueryBuilder whose options throw is disposed with the '
      'tree', (tester, client) async {
    var fetches = 0;
    Widget view({required bool rejected}) => Column(children: [
          // An error widget wants all the height a column offers.
          SizedBox(
            height: 100,
            child: QueryBuilder<int>(
              options: _options(rejected: rejected, onFetch: () {}),
              builder: (_, result) => Text('a=${result.dataOrNull}'),
            ),
          ),
          QueryBuilder<int>(
            options: QueryObserverOptions<int>(
              queryKey: QueryKey(['sibling']),
              queryFn: (_) => ++fetches,
              refetchInterval:
                  const RefetchInterval.every(Duration(seconds: 1)),
            ),
            builder: (_, result) => Text('b=${result.dataOrNull}'),
          ),
        ]);
    await tester.pumpApp(client, view(rejected: false));
    await tester.pumpAndSettle();

    await tester.pumpApp(client, view(rejected: true));
    expect(tester.takeException(), isA<StateError>());
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    final before = fetches;
    await tester.pump(const Duration(seconds: 3));
    expect(client.queryCache.findAll().map((q) => q.observersCount), [0, 0]);
    expect(fetches, before);
  });
}

/// A header whose child is rebuilt from the header's layout when the shrink
/// offset moves, never from its parent's update (`shouldRebuild` is false).
class _Header extends SliverPersistentHeaderDelegate {
  _Header(this.rejected);
  final bool Function() rejected;

  @override
  double get minExtent => 40;
  @override
  double get maxExtent => 120;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      QueryBuilder<int>(
        options: QueryObserverOptions<int>(
          queryKey: QueryKey([rejected() ? 'next' : 'old']),
          queryFn: (_) => 1,
          initialData: rejected() ? _throwingSeed() : null,
        ),
        builder: (_, result) => Text('row=${result.dataOrNull}'),
      );

  @override
  bool shouldRebuild(_Header oldDelegate) => false;
}

/// A client whose mutation defaulting can be made to throw: the one way
/// `MutationController.setOptions` fails.
class _RejectingClient extends QueryClient {
  bool reject = false;

  @override
  DefaultedMutationOptions<A, B, C> defaultMutationOptions<A, B, C>(
      MutationOptions<A, B, C> options) {
    if (reject) throw StateError('rejected');
    return super.defaultMutationOptions(options);
  }
}

class _ContextReader extends StatelessWidget {
  const _ContextReader(this.options);
  final QueryObserverOptions<int> options;

  @override
  Widget build(BuildContext context) =>
      Text('${context.query(options, id: 'one read').dataOrNull}');
}

class _MixinReader extends StatefulWidget {
  const _MixinReader(this.options);
  final QueryObserverOptions<int> options;

  @override
  State<_MixinReader> createState() => _MixinReaderState();
}

class _MixinReaderState extends State<_MixinReader> with QueryMixin {
  @override
  Widget build(BuildContext context) =>
      Text('${watchQuery(widget.options, id: 'one read').dataOrNull}');
}
