// The builders reconcile client and options at the top of `build`, not in
// `didUpdateWidget` (ASTRA-B1, reworked). What that moved, per builder
// widget: the build that applies new options shows their result at once and
// a queued notification does not show it twice; a notification during the
// reconciliation is not lost; `buildWhen` compares against what was shown;
// `Enabled.when` is re-evaluated for every parent update and never for a
// notification; a provider's client swap reaches a cached widget; options
// that keep throwing stay pending and recover; a throwing first build, a
// throwing `client` getter and a mutation finishing under rejected options
// all end clean. Written by the third verifier as probes and kept as they
// are; PORTING_NOTES, "Independent reviews 2026-10-15".
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'harness.dart';

enum _Style { query, select, infinite, collection }

Widget _view(
  _Style style, {
  required String keyName,
  required void Function(QueryResult<int>) show,
  InitialData<int>? seed,
  Enabled? enabled,
  QueryClient? client,
  FutureOr<int> Function()? fetch,
  BuildWhen<QueryResult<int>>? buildWhen,
}) {
  final options = QueryObserverOptions<int>(
    queryKey: QueryKey([keyName]),
    initialData: seed,
    enabled: enabled,
    staleTime: StaleTime.infinite,
    queryFn: (_) => fetch?.call() ?? 1,
  );
  Widget render(QueryResult<int> result) {
    show(result);
    return Text('${result.dataOrNull}:${result.fetchStatus.name}');
  }

  return switch (style) {
    _Style.query => QueryBuilder<int>(
        client: client,
        options: options,
        buildWhen: buildWhen,
        builder: (_, result) => render(result),
      ),
    _Style.select => QuerySelectBuilder<int, int>(
        client: client,
        options: options.withSelect((data) => data),
        buildWhen: buildWhen,
        builder: (_, result) => render(result),
      ),
    _Style.infinite => InfiniteQueryBuilder<int, int, int>(
        client: client,
        options: InfiniteQuerySelectOptions<int, int, int>(
          queryKey: QueryKey([keyName]),
          initialPageParam: 0,
          getNextPageParam: (_, __, ___, ____) => null,
          pageFn: (_) => fetch?.call() ?? 1,
          staleTime: StaleTime.infinite,
          enabled: enabled,
          initialData: seed == null
              ? null
              : InitialData.compute(() => InfiniteData(
                    pages: [seed.seed().data!],
                    pageParams: [0],
                  )),
          select: (data) => data.pages.first,
        ),
        buildWhen: buildWhen,
        builder: (_, controller) => render(controller.value),
      ),
    _Style.collection => QueriesBuilder<int, int>(
        client: client,
        queries: [options],
        builder: (_, results) => render(results.single),
      ),
  };
}

class _ThrowingGetter extends QueryBuilder<int> {
  const _ThrowingGetter({
    required this.resolve,
    required super.options,
    required super.builder,
  });
  final QueryClient Function() resolve;

  @override
  QueryClient get client => resolve();
}

class _RejectingClient extends QueryClient {
  bool reject = false;

  @override
  DefaultedMutationOptions<A, B, C> defaultMutationOptions<A, B, C>(
      MutationOptions<A, B, C> options) {
    if (reject) throw StateError('mutation options');
    return super.defaultMutationOptions(options);
  }
}

void main() {
  for (final style in _Style.values) {
    queryWidgetTest(
        '${style.name}: synchronous notification during reconciliation '
        'is represented by the current build', (tester, client) async {
      client.notifyManager.setScheduler((callback) => callback());
      final shown = <QueryResult<int>>[];
      Widget view(String key, int value) => Directionality(
            textDirection: TextDirection.ltr,
            child: _view(style,
                client: client,
                keyName: key,
                show: shown.add,
                seed: InitialData.value(value)),
          );
      await tester.pumpWidget(view('a', 1));
      expect(shown.single.dataOrNull, 1);
      shown.clear();
      await tester.pumpWidget(view('b', 2));
      expect(tester.takeException(), isNull);
      expect(shown.single.dataOrNull, 2);
      await tester.pump();
      expect(shown, hasLength(1));
    });

    queryWidgetTest(
        '${style.name}: first and updated builds show fetching; '
        'queued notifications do not duplicate either build',
        (tester, client) async {
      final first = Completer<int>();
      final next = Completer<int>();
      final shown = <QueryResult<int>>[];
      await tester.pumpApp(
          client,
          _view(style,
              keyName: 'a', show: shown.add, fetch: () => first.future));
      expect(shown, hasLength(1));
      expect(shown.single.isFetching, isTrue);
      await tester.pump();
      expect(shown, hasLength(1));
      first.complete(1);
      await tester.pumpAndSettle();
      expect(shown.last.dataOrNull, 1);

      shown.clear();
      await tester.pumpApp(
          client,
          _view(style,
              keyName: 'b', show: shown.add, fetch: () => next.future));
      expect(shown, hasLength(1));
      expect(shown.single.isFetching, isTrue);
      expect(shown.single.dataOrNull, isNull);
      await tester.pump();
      expect(shown, hasLength(1));
      next.complete(2);
      await tester.pumpAndSettle();
      expect(shown.last.dataOrNull, 2);
    });

    queryWidgetTest(
        '${style.name}: repeatedly rejected options retry on '
        'notification, then recover without a parent update',
        (tester, client) async {
      var attempts = 0;
      var reject = true;
      QueryResult<int>? shown;
      await tester.pumpApp(
          client,
          _view(style,
              keyName: 'old',
              show: (r) => shown = r,
              seed: const InitialData.value(1)));
      final held = client.queryCache.findAll().single;
      final invalid = _view(style,
          keyName: 'new',
          show: (r) => shown = r,
          seed: InitialData.compute(() {
            attempts++;
            if (reject) throw StateError('seed');
            return 9;
          }));
      await tester.pumpApp(client, invalid);
      expect(tester.takeException(), isA<StateError>());
      expect(find.byType(ErrorWidget), findsOneWidget);
      expect(held.observersCount, 1);
      final before = attempts;

      if (style == _Style.infinite) {
        client.setQueryData<InfiniteData<int, int>>(
            QueryKey(['old']), InfiniteData(pages: [2], pageParams: [0]));
      } else {
        client.setQueryData<int>(QueryKey(['old']), 2);
      }
      await tester.pump();
      expect(tester.takeException(), isA<StateError>());
      expect(attempts, greaterThan(before));
      expect(shown!.dataOrNull, 1,
          reason: 'invalid options must not render old data');
      expect(held.observersCount, 1);

      reject = false;
      if (style == _Style.infinite) {
        client.setQueryData<InfiniteData<int, int>>(
            QueryKey(['old']), InfiniteData(pages: [3], pageParams: [0]));
      } else {
        client.setQueryData<int>(QueryKey(['old']), 3);
      }
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('9:idle'), findsOneWidget);
      expect(held.observersCount, 0);
      expect(client.queryCache.findAll().where((q) => q.observersCount > 0),
          hasLength(1));
    });

    queryWidgetTest(
        '${style.name}: throwing first build can recover and dispose',
        (tester, client) async {
      await tester.pumpApp(
          client,
          _view(style,
              keyName: 'a',
              show: (_) {},
              seed: InitialData.compute(() => throw StateError('first'))));
      expect(tester.takeException(), isA<StateError>());
      expect(client.queryCache.findAll().where((q) => q.observersCount > 0),
          isEmpty);
      await tester.pumpApp(
          client,
          _view(style,
              keyName: 'a', show: (_) {}, seed: const InitialData.value(3)));
      expect(find.text('3:idle'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(client.queryCache.findAll().where((q) => q.observersCount > 0),
          isEmpty);
    });

    queryWidgetTest('${style.name}: cached builder observes provider-only swap',
        (tester, client) async {
      final other = tester.adopt(QueryClient());
      var fetches = 0;
      final view =
          _view(style, keyName: 'a', show: (_) {}, fetch: () => ++fetches);
      await tester.pumpApp(client, view);
      await tester.pumpAndSettle();
      final old = client.queryCache.findAll().single;
      await tester.pumpApp(other, view);
      await tester.pumpAndSettle();
      expect(find.text('2:idle'), findsOneWidget);
      expect(old.observersCount, 0);
      expect(other.queryCache.findAll().single.observersCount, 1);
    });
  }

  queryWidgetTest(
      'same options re-evaluate Enabled.when only on a parent update',
      (tester, client) async {
    var enabled = false;
    var fetches = 0;
    final options = QueryObserverOptions<int>(
      queryKey: QueryKey(['enabled']),
      enabled: Enabled.when((_) => enabled),
      queryFn: (_) => ++fetches,
    );
    Widget view() => QueryBuilder<int>(
        options: options,
        builder: (_, result) =>
            Text('${result.dataOrNull}:${result.isEnabled}'));
    await tester.pumpApp(client, view());
    expect(fetches, 0);
    enabled = true;
    client.setQueryData<int>(QueryKey(['enabled']), 4);
    await tester.pump();
    expect(fetches, 0, reason: 'notification is not an options update');
    await tester.pumpApp(client, view());
    await tester.pumpAndSettle();
    expect(fetches, 1);
    expect(find.text('1:true'), findsOneWidget);
  });

  queryWidgetTest(
      'buildWhen after options update compares the newly shown result',
      (tester, client) async {
    final asked = <(int?, int?)>[];
    Widget view(int factor) => QuerySelectBuilder<int, int>(
          options: QuerySelectOptions<int, int>(
              queryKey: QueryKey(['a']),
              initialData: const InitialData.value(1),
              staleTime: StaleTime.infinite,
              select: (value) => value * factor),
          buildWhen: (a, b) {
            asked.add((a.dataOrNull, b.dataOrNull));
            return false;
          },
          builder: (_, result) => Text('${result.dataOrNull}'),
        );
    await tester.pumpApp(client, view(1));
    await tester.pumpApp(client, view(10));
    await tester.pump();
    expect(find.text('10'), findsOneWidget);
    expect(asked, isEmpty);
    client.setQueryData<int>(QueryKey(['a']), 2);
    await tester.pump();
    expect(asked, [(10, 20)]);
    expect(find.text('10'), findsOneWidget);
  });

  queryWidgetTest('throwing client getter retains ownership and recovers',
      (tester, client) async {
    var reject = false;
    Widget view() => _ThrowingGetter(
          resolve: () {
            if (reject) throw StateError('client');
            return client;
          },
          options: QueryObserverOptions<int>(
              queryKey: QueryKey(['a']),
              initialData: const InitialData.value(1),
              staleTime: StaleTime.infinite),
          builder: (_, result) => Text('${result.dataOrNull}'),
        );
    await tester.pumpApp(client, view());
    final held = client.queryCache.findAll().single;
    reject = true;
    await tester.pumpApp(client, view());
    expect(tester.takeException(), isA<StateError>());
    expect(held.observersCount, 1);
    client.setQueryData<int>(QueryKey(['a']), 2);
    await tester.pump();
    expect(tester.takeException(), isA<StateError>());
    reject = false;
    client.setQueryData<int>(QueryKey(['a']), 3);
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(held.observersCount, 0);
  });

  queryWidgetTest(
      'mutation settles while options keep throwing; valid update '
      'preserves controller, result and per-call callback', (tester, _) async {
    final client = tester.adopt(_RejectingClient());
    final done = Completer<int>();
    var callbacks = 0;
    late MutationController<int, int, void> mutation;
    Widget view() => MutationBuilder<int, int, void>(
          options: MutationOptions(mutationFn: (_) => done.future),
          builder: (_, controller) {
            mutation = controller;
            return Text(controller.value.status.name);
          },
        );
    await tester.pumpApp(client, view());
    final original = mutation;
    final run = mutation.mutateAsync(0,
        callbacks: MutateCallbacks(onSuccess: (_, __, ___) => callbacks++));
    await tester.pump();
    client.reject = true;
    await tester.pumpApp(client, view());
    expect(tester.takeException(), isA<StateError>());
    done.complete(7);
    expect(await run, 7);
    await tester.pump();
    expect(tester.takeException(), isA<StateError>());
    expect(callbacks, 1);
    client.reject = false;
    await tester.pumpApp(client, view());
    expect(identical(mutation, original), isTrue);
    expect(find.text('success'), findsOneWidget);
  });

  queryWidgetTest(
      'QueriesBuilder partial apply is retained, retried, recovered '
      'and released', (tester, client) async {
    var reject = false;
    var attempts = 0;
    final shown = <List<int?>>[];
    Widget view(int factor) => QueriesBuilder<int, int>(
            queries: [
              QuerySelectOptions<int, int>(
                  queryKey: QueryKey(['a']),
                  initialData: const InitialData.value(1),
                  staleTime: StaleTime.infinite,
                  select: (value) => factor * value),
              QueryObserverOptions<int>(
                  queryKey: QueryKey(['b']),
                  initialData: const InitialData.value(2),
                  staleTime: StaleTime.infinite,
                  enabled: Enabled.when((_) {
                    attempts++;
                    if (reject) throw StateError('second');
                    return true;
                  })),
            ],
            builder: (_, results) {
              final values = results.map((r) => r.dataOrNull).toList();
              shown.add(values);
              return Text('$values');
            });
    await tester.pumpApp(client, view(1));
    reject = true;
    await tester.pumpApp(client, view(10));
    expect(tester.takeException(), isA<StateError>());
    // A's selection was applied before B failed. Its queued notification
    // causes one retry, not an endless build/error cycle.
    await tester.pump();
    expect(tester.takeException(), isA<StateError>());
    final before = attempts;
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(attempts, before);
    expect(shown.last, [1, 2]);
    expect(client.queryCache.findAll().map((q) => q.observersCount), [1, 1]);
    reject = false;
    client.setQueryData<int>(QueryKey(['a']), 3);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('[30, 2]'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(client.queryCache.findAll().map((q) => q.observersCount), [0, 0]);
  });
}
