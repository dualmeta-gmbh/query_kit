/// A reference's options handed to every consumer the binding has, with no
/// type argument at the call site: each case pins the static type the
/// consumer infers, exactly (a wider and a narrower one both fail to
/// compile, see [StaticType]), and then runs the consumer to show the
/// typed value arrives.
///
/// The consumers: the four call styles for plain, selected and infinite
/// queries with their `buildWhen`; the listeners; `QueriesController` and
/// `QueriesBuilder`; `combine` and `combineWith` over references' results;
/// `IsFetchingController` and a cache listener narrowed by a target's
/// filters; and the one documented hole, a list of references' options of
/// two data types.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'harness.dart';
import 'typed_support.dart';

/// The declarations an app would hold: a family, a zero-input definition,
/// an infinite family and a zero-input infinite definition, over one
/// backend.
final class _Queries {
  _Queries(this.api);

  final Api api;
  static final namespace = QueryNamespace(const ['devices']);

  late final detail = QueryFamily<String, Device>(
    namespace: namespace,
    name: 'detail',
    queryFn: (id, _) => api.device(id),
  );

  late final list = QueryDefinition<List<Device>>(
    namespace: namespace,
    name: 'list',
    queryFn: (_) async => [await api.device('x'), await api.device('y')],
  );

  late final feed = InfiniteQueryFamily<String, List<int>, int>(
    namespace: namespace,
    name: 'feed',
    pageFn: (id, context) => api.page(id, context.pageParam),
    initialPageParam: (_) => 0,
    getNextPageParam: (_, __, ___, param, ____) => param < 2 ? param + 1 : null,
  );

  late final log = InfiniteQueryDefinition<List<int>, int>(
    namespace: namespace,
    name: 'log',
    pageFn: (context) => api.page('log', context.pageParam),
    initialPageParam: 0,
    getNextPageParam: (_, __, param, ___) => param < 2 ? param + 1 : null,
  );
}

const _minute = StaleTime.duration(Duration(minutes: 1));

void main() {
  late _Queries q;
  setUp(() => q = _Queries(Api(<String>[])));

  group('inference, controller style:', () {
    queryWidgetTest('plain, copyWith and withSelect', (tester, client) async {
      final device = q.detail('a');
      final plain = QueryController.create(client, device.options())
        ..expectStaticType<Exactly<QueryController<Device, Device>>>();
      final copied =
          QueryController(client, device.options().copyWith(staleTime: _minute))
            ..expectStaticType<Exactly<QueryController<Device, Device>>>();
      final selected = QueryController(
          client, device.options().withSelect((device) => device.version))
        ..expectStaticType<Exactly<QueryController<Device, String>>>();
      for (final controller in [plain, copied, selected]) {
        addTearDown(controller.dispose);
      }
      plain.value.expectStaticType<Exactly<QueryResult<Device>>>();
      selected.value.expectStaticType<Exactly<QueryResult<String>>>();
      // The setters take the same options with no type argument either.
      plain.setOptions(device.options().copyWith(staleTime: _minute));
      selected.setOptions(device.options().withSelect((device) => device.id));

      await tester.pumpApp(
          client,
          ListenableBuilder(
            listenable: Listenable.merge([plain, copied, selected]),
            builder: (_, __) =>
                Text('${plain.value.dataOrNull} ${selected.value.dataOrNull}'),
          ));
      await tester.pump();
      expect(find.text('a@A1 a'), findsOneWidget);
    });

    queryWidgetTest('infinite, copyWith and withSelect',
        (tester, client) async {
      final feed = q.feed('a');
      final pages = InfiniteQueryController(client, feed.options())
        ..expectStaticType<
            Exactly<
                InfiniteQueryController<List<int>, int,
                    InfiniteData<List<int>, int>>>>();
      final copied =
          InfiniteQueryController(client, q.log.options().copyWith(maxPages: 2))
            ..expectStaticType<
                Exactly<
                    InfiniteQueryController<List<int>, int,
                        InfiniteData<List<int>, int>>>>();
      final counted = InfiniteQueryController(
          client, feed.options().withSelect((data) => data.pages.length))
        ..expectStaticType<
            Exactly<InfiniteQueryController<List<int>, int, int>>>();
      for (final controller in [pages, copied, counted]) {
        addTearDown(controller.dispose);
      }
      pages.value.expectStaticType<
          Exactly<QueryResult<InfiniteData<List<int>, int>>>>();
      counted.value.expectStaticType<Exactly<QueryResult<int>>>();
      pages.setInfiniteOptions(feed.options().copyWith(staleTime: _minute));

      await tester.pumpApp(
          client,
          ListenableBuilder(
            listenable: Listenable.merge([pages, copied, counted]),
            builder: (_, __) => Text('${counted.value.dataOrNull}'
                ' ${pages.value.dataOrNull?.pages}'),
          ));
      await tester.pump();
      expect(find.text('1 [[0, 1]]'), findsOneWidget);
      await pages.fetchNextPage();
      await tester.pump();
      expect(find.text('2 [[0, 1], [10, 11]]'), findsOneWidget);
    });

    queryWidgetTest('the listeners infer from the controller',
        (tester, client) async {
      final device = QueryController.create(client, q.detail('a').options());
      final feed = InfiniteQueryController(client, q.log.options());
      addTearDown(device.dispose);
      addTearDown(feed.dispose);
      final heard = <String>[];
      final listener = QueryListener(
        controller: device,
        listenWhen: (previous, next) {
          previous.expectStaticType<Exactly<QueryResult<Device>>>();
          return true;
        },
        listener: (context, result) {
          result.expectStaticType<Exactly<QueryResult<Device>>>();
          heard.add('device ${result.dataOrNull}');
        },
        child: const SizedBox(),
      )..expectStaticType<Exactly<QueryListener<Device, Device>>>();
      final infiniteListener = InfiniteQueryListener(
        controller: feed,
        listener: (context, result) {
          result.expectStaticType<
              Exactly<QueryResult<InfiniteData<List<int>, int>>>>();
          heard.add('feed ${result.dataOrNull?.pages}');
        },
        child: const SizedBox(),
      );
      await tester.pumpApp(
          client,
          Column(children: [
            listener,
            infiniteListener,
            ListenableBuilder(
                listenable: Listenable.merge([device, feed]),
                builder: (_, __) => const SizedBox()),
          ]));
      await tester.pump();
      await tester.pump();
      expect(heard, containsAll(['device a@A1', 'feed [[0, 1]]']));
    });
  });

  group('inference, builder style:', () {
    queryWidgetTest('plain, copyWith and withSelect, with buildWhen',
        (tester, client) async {
      final device = q.detail('a');
      final plain = QueryBuilder(
        options: device.options(),
        buildWhen: (previous, current) {
          previous.expectStaticType<Exactly<QueryResult<Device>>>();
          current.expectStaticType<Exactly<QueryResult<Device>>>();
          return true;
        },
        builder: (context, result) {
          result.expectStaticType<Exactly<QueryResult<Device>>>();
          return Text('plain ${result.dataOrNull}');
        },
      )..expectStaticType<Exactly<QueryBuilder<Device>>>();
      final copied = QueryBuilder(
        options: q.list.options().copyWith(staleTime: _minute),
        builder: (context, result) {
          result.expectStaticType<Exactly<QueryResult<List<Device>>>>();
          return Text('list ${result.dataOrNull}');
        },
      )..expectStaticType<Exactly<QueryBuilder<List<Device>>>>();
      final selected = QuerySelectBuilder(
        options: device.options().withSelect((device) => device.version),
        buildWhen: (previous, current) {
          previous.expectStaticType<Exactly<QueryResult<String>>>();
          return true;
        },
        builder: (context, result) {
          result.expectStaticType<Exactly<QueryResult<String>>>();
          return Text('selected ${result.dataOrNull}');
        },
      )..expectStaticType<Exactly<QuerySelectBuilder<Device, String>>>();
      await tester.pumpApp(client, Column(children: [plain, copied, selected]));
      await tester.pump();
      expect(find.text('plain a@A1'), findsOneWidget);
      expect(find.text('list [x@A1, y@A1]'), findsOneWidget);
      expect(find.text('selected A1'), findsOneWidget);
    });

    queryWidgetTest('infinite, copyWith and withSelect, with buildWhen',
        (tester, client) async {
      final pages = InfiniteQueryBuilder(
        options: q.feed('a').options(),
        buildWhen: (previous, current) {
          previous.expectStaticType<
              Exactly<QueryResult<InfiniteData<List<int>, int>>>>();
          return true;
        },
        builder: (context, feed) {
          feed.expectStaticType<
              Exactly<
                  InfiniteQueryController<List<int>, int,
                      InfiniteData<List<int>, int>>>>();
          return TextButton(
            onPressed: feed.fetchNextPage,
            child: Text('pages ${feed.value.dataOrNull?.pages}'),
          );
        },
      )..expectStaticType<
          Exactly<
              InfiniteQueryBuilder<List<int>, int,
                  InfiniteData<List<int>, int>>>>();
      final counted = InfiniteQueryBuilder(
        options: q.log
            .options()
            .copyWith(maxPages: 3)
            .withSelect((data) => data.pages.length),
        builder: (context, feed) {
          feed.expectStaticType<
              Exactly<InfiniteQueryController<List<int>, int, int>>>();
          return Text('count ${feed.value.dataOrNull}');
        },
      )..expectStaticType<Exactly<InfiniteQueryBuilder<List<int>, int, int>>>();
      await tester.pumpApp(client, Column(children: [pages, counted]));
      await tester.pump();
      expect(find.text('pages [[0, 1]]'), findsOneWidget);
      expect(find.text('count 1'), findsOneWidget);
      await tester.tap(find.byType(TextButton));
      await tester.pump();
      await tester.pump();
      expect(find.text('pages [[0, 1], [10, 11]]'), findsOneWidget);
    });
  });

  group('inference, mixin and context.query:', () {
    for (final style in [Style.mixin, Style.context]) {
      queryWidgetTest('${style.name}: plain, copyWith, withSelect, infinite',
          (tester, client) async {
        final shown = <String>[];
        await tester.pumpApp(
            client,
            style == Style.mixin
                ? _MixinInference(q, shown.add)
                : _ContextInference(q, shown.add));
        await tester.pump();
        expect(shown.last, 'a@A1 | [x@A1, y@A1] | A1 | [[0, 1]] | 1');
      });
    }
  });

  group('the queries consumers:', () {
    queryWidgetTest('QueriesController and QueriesBuilder over one family',
        (tester, client) async {
      final ids = ['a', 'b'];
      final controller = QueriesController(
          client, [for (final id in ids) q.detail(id).options()])
        ..expectStaticType<Exactly<QueriesController<Device, Device>>>();
      addTearDown(controller.dispose);
      controller.value.expectStaticType<Exactly<List<QueryResult<Device>>>>();
      final versions = QueriesController(client, [
        for (final id in ids)
          q.detail(id).options().withSelect((device) => device.version),
      ])
        ..expectStaticType<Exactly<QueriesController<Device, String>>>();
      addTearDown(versions.dispose);
      final builder = QueriesBuilder(
        queries: [
          for (final id in ids)
            q.detail(id).options().copyWith(staleTime: _minute),
        ],
        builder: (context, results) {
          results.expectStaticType<Exactly<List<QueryResult<Device>>>>();
          return Text('built ${[for (final r in results) r.dataOrNull]}');
        },
      )..expectStaticType<Exactly<QueriesBuilder<Device, Device>>>();
      await tester.pumpApp(
          client,
          Column(children: [
            builder,
            ListenableBuilder(
                listenable: Listenable.merge([controller, versions]),
                builder: (_, __) => Text('controller '
                    '${[for (final r in controller.value) r.dataOrNull]} '
                    '${[for (final r in versions.value) r.dataOrNull]}')),
          ]));
      await tester.pump();
      expect(find.text('built [a@A1, b@A1]'), findsOneWidget);
      expect(find.text('controller [a@A1, b@A1] [A1, A1]'), findsOneWidget);

      q.detail.updateAll(client, (device) => device?.bump('W'));
      await tester.pump();
      expect(find.text('built [a@W, b@W]'), findsOneWidget);
      expect(find.text('controller [a@W, b@W] [W, W]'), findsOneWidget);
    });

    queryWidgetTest('combine over a record and combineWith over a list',
        (tester, client) async {
      final shown = <String>[];
      await tester.pumpApp(client, Builder(builder: (context) {
        final device = context.query(q.detail('a').options());
        final list = context.query(q.list.options());
        final combined = (device, list).combine((device, list) {
          device.expectStaticType<Exactly<Device>>();
          list.expectStaticType<Exactly<List<Device>>>();
          return '${device.version}/${list.length}';
        })
          ..expectStaticType<Exactly<CombinedResult<String>>>();
        return QueriesBuilder(
          queries: [
            for (final id in ['x', 'y']) q.detail(id).options()
          ],
          builder: (context, details) {
            final page = details.combineWith(list, (details, list) {
              details.expectStaticType<Exactly<List<Device>>>();
              list.expectStaticType<Exactly<List<Device>>>();
              return '${details.length} of ${list.length}';
            })
              ..expectStaticType<Exactly<CombinedResult<String>>>();
            shown.add('${combined.dataOrNull} ${page.dataOrNull}');
            return const SizedBox();
          },
        );
      }));
      await tester.pump();
      await tester.pump();
      expect(shown.last, 'A1/2 2 of 2');
    });

    queryWidgetTest(
        'a mixed list of two data types compiles, infers Object, and makes '
        'Object entries the references then refuse', (tester, client) async {
      final mixed = [q.detail('a').options(), q.list.options()]
        ..expectStaticType<Exactly<List<QueryObserverOptions<Object>>>>();
      final controller = QueriesController(client, mixed)
        ..expectStaticType<Exactly<QueriesController<Object, Object>>>();
      addTearDown(controller.dispose);
      final builder = QueriesBuilder(
        queries: mixed,
        builder: (context, results) {
          results.expectStaticType<Exactly<List<QueryResult<Object>>>>();
          return Text('${[for (final r in results) r.dataOrNull]}');
        },
      )..expectStaticType<Exactly<QueriesBuilder<Object, Object>>>();
      await tester.pumpApp(client, builder);
      await tester.pump();
      // At runtime the fetches run and the results arrive …
      expect(find.text('[a@A1, [x@A1, y@A1]]'), findsOneWidget);
      // … into entries of `Object`, which every typed read refuses.
      expect(client.queryCache.get<Object>(q.detail('a').key.rawKey),
          isA<Query<Object>>());
      expect(
          () => q.detail('a').read(client), throwsA(isA<QueryDataTypeError>()));
      expect(() => q.list.write(client, const []),
          throwsA(isA<QueryDataTypeError>()));
      // A typed reader of the same key then fails its build.
      await tester.pumpApp(
          client,
          QueryBuilder(
              options: q.detail('a').options(),
              builder: (_, result) => Text('${result.dataOrNull}')));
      expect(tester.takeException(), isA<QueryDataTypeError>());
    });

    queryWidgetTest(
        'a mixed list over entries a typed reader made first fails, and '
        'leaves the typed entry as it was', (tester, client) async {
      await tester.pumpApp(
          client,
          QueryBuilder(
              options: q.detail('a').options(),
              builder: (_, result) => Text('typed ${result.dataOrNull}')));
      await tester.pump();
      expect(find.text('typed a@A1'), findsOneWidget);
      final mixed = [q.detail('a').options(), q.list.options()];
      expect(() => QueriesController(client, mixed),
          throwsA(isA<QueryDataTypeError>()));
      expect(q.detail('a').read(client), const Device('a', 'A1'));
    });
  });

  group('counts and cache listeners narrowed by a target:', () {
    queryWidgetTest(
        "IsFetchingController counts a reference's, a family's and a "
        "namespace's fetches", (tester, client) async {
      final gate = Completer<void>();
      final namespace = QueryNamespace(const ['devices']);
      final detail = QueryFamily<String, Device>(
        namespace: namespace,
        name: 'detail',
        queryFn: (id, _) async {
          await gate.future;
          return Device(id, 'x');
        },
      );
      final list = QueryDefinition<List<Device>>(
        namespace: namespace,
        name: 'list',
        queryFn: (_) async {
          await gate.future;
          return const [];
        },
      );
      final other = QueryDefinition<int>(
        namespace: QueryNamespace(const ['other']),
        name: 'n',
        queryFn: (_) async {
          await gate.future;
          return 1;
        },
      );
      final counters = <String, IsFetchingController>{
        'reference':
            IsFetchingController(client, filters: detail('a').filters()),
        'family': IsFetchingController(client, filters: detail.filters()),
        'namespace': IsFetchingController(client, filters: namespace.filters()),
        'all': IsFetchingController(client),
      };
      for (final counter in counters.values) {
        addTearDown(counter.dispose);
      }
      String counts() => [
            for (final MapEntry(:key, :value) in counters.entries)
              '$key ${value.value}',
          ].join(', ');
      await tester.pumpApp(
          client,
          Column(children: [
            for (final options in [
              detail('a').options(),
              detail('b').options(),
            ])
              QueryBuilder(
                  options: options, builder: (_, __) => const SizedBox()),
            QueryBuilder(
                options: list.options(), builder: (_, __) => const SizedBox()),
            QueryBuilder(
                options: other.options(), builder: (_, __) => const SizedBox()),
            ListenableBuilder(
              listenable: Listenable.merge(counters.values.toList()),
              builder: (_, __) => Text(counts()),
            ),
          ]));
      await tester.pump();
      expect(find.text('reference 1, family 2, namespace 3, all 4'),
          findsOneWidget);
      gate.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('reference 0, family 0, namespace 0, all 0'),
          findsOneWidget);
    });

    queryWidgetTest(
        "a cache listener narrowed by a target's filters hears exactly its "
        'entries', (tester, client) async {
      final heard = <String, Set<QueryKey>>{};
      final targets = <String, QueryTarget>{
        'reference': q.detail('a'),
        'family': q.detail,
        'namespace': _Queries.namespace,
      };
      final stops = [
        for (final MapEntry(:key, :value) in targets.entries)
          client.queryCache.subscribe((event) {
            if (value.filters().matches(event.query)) {
              (heard[key] ??= <QueryKey>{}).add(event.query.queryKey);
            }
          }),
      ];
      addTearDown(() {
        for (final stop in stops) {
          stop();
        }
      });
      final elsewhere = QueryDefinition<int>(
        namespace: QueryNamespace(const ['elsewhere']),
        name: 'n',
      );
      await tester.pumpApp(
          client,
          Column(children: [
            for (final options in [
              q.detail('a').options(),
              q.detail('b').options(),
              q.list.options(),
            ])
              QueryBuilder(
                  options: options, builder: (_, __) => const SizedBox()),
          ]));
      await tester.pump();
      elsewhere.write(client, 1);
      expect(heard, {
        'reference': {q.detail('a').key.rawKey},
        'family': {q.detail('a').key.rawKey, q.detail('b').key.rawKey},
        'namespace': {
          q.detail('a').key.rawKey,
          q.detail('b').key.rawKey,
          q.list.key.rawKey,
        },
      });
    });
  });

  group('a selector consumer in each style:', () {
    for (final style in Style.values) {
      queryWidgetTest('${style.name}: the selected value follows a typed write',
          (tester, client) async {
        final shown = <String>[];
        final options =
            q.detail('a').options().withSelect((device) => device.version);
        await tester.pumpApp(
            client,
            switch (style) {
              Style.controller => _SelectController(options, shown.add),
              Style.builder => QuerySelectBuilder(
                  options: options,
                  builder: (_, result) {
                    shown.add('${result.dataOrNull}');
                    return const SizedBox();
                  },
                ),
              Style.mixin => _SelectMixin(options, shown.add),
              Style.context => Builder(builder: (context) {
                  shown.add('${context.selectQuery(options).dataOrNull}');
                  return const SizedBox();
                }),
            });
        await tester.pump();
        expect(shown.last, 'A1');
        q.detail('a').write(client, const Device('a', 'W'));
        await tester.pump();
        expect(shown.last, 'W');
      });
    }
  });
}

class _MixinInference extends StatefulWidget {
  const _MixinInference(this.q, this.show);

  final _Queries q;
  final void Function(String) show;

  @override
  State<_MixinInference> createState() => _MixinInferenceState();
}

class _MixinInferenceState extends State<_MixinInference> with QueryMixin {
  @override
  Widget build(BuildContext context) {
    final q = widget.q;
    final device = watchQuery(
      q.detail('a').options(),
      buildWhen: (previous, current) {
        previous.expectStaticType<Exactly<QueryResult<Device>>>();
        return true;
      },
    )..expectStaticType<Exactly<QueryResult<Device>>>();
    final list = watchQuery(q.list.options().copyWith(staleTime: _minute))
      ..expectStaticType<Exactly<QueryResult<List<Device>>>>();
    final version = watchSelectQuery(
      q.detail('a').options().withSelect((device) => device.version),
      buildWhen: (previous, current) {
        previous.expectStaticType<Exactly<QueryResult<String>>>();
        return true;
      },
    )..expectStaticType<Exactly<QueryResult<String>>>();
    final feed = watchInfiniteQuery(
      q.feed('a').options(),
      buildWhen: (previous, current) {
        previous.expectStaticType<
            Exactly<QueryResult<InfiniteData<List<int>, int>>>>();
        return true;
      },
    )..expectStaticType<
        Exactly<
            InfiniteQueryController<List<int>, int,
                InfiniteData<List<int>, int>>>>();
    final count = watchInfiniteQuery(
        q.log.options().withSelect((data) => data.pages.length))
      ..expectStaticType<
          Exactly<InfiniteQueryController<List<int>, int, int>>>();
    widget.show('${device.dataOrNull} | ${list.dataOrNull} | '
        '${version.dataOrNull} | ${feed.value.dataOrNull?.pages} | '
        '${count.value.dataOrNull}');
    return const SizedBox();
  }
}

class _ContextInference extends StatelessWidget {
  const _ContextInference(this.q, this.show);

  final _Queries q;
  final void Function(String) show;

  @override
  Widget build(BuildContext context) {
    final device = context.query(
      q.detail('a').options(),
      buildWhen: (previous, current) {
        previous.expectStaticType<Exactly<QueryResult<Device>>>();
        return true;
      },
    )..expectStaticType<Exactly<QueryResult<Device>>>();
    final list = context.query(q.list.options().copyWith(staleTime: _minute))
      ..expectStaticType<Exactly<QueryResult<List<Device>>>>();
    final version = context.selectQuery(
      q.detail('a').options().withSelect((device) => device.version),
      buildWhen: (previous, current) {
        previous.expectStaticType<Exactly<QueryResult<String>>>();
        return true;
      },
    )..expectStaticType<Exactly<QueryResult<String>>>();
    final feed = context.infiniteQuery(
      q.feed('a').options(),
      buildWhen: (previous, current) {
        previous.expectStaticType<
            Exactly<QueryResult<InfiniteData<List<int>, int>>>>();
        return true;
      },
    )..expectStaticType<
        Exactly<
            InfiniteQueryController<List<int>, int,
                InfiniteData<List<int>, int>>>>();
    final count = context
        .infiniteQuery(q.log.options().withSelect((data) => data.pages.length))
      ..expectStaticType<
          Exactly<InfiniteQueryController<List<int>, int, int>>>();
    show('${device.dataOrNull} | ${list.dataOrNull} | '
        '${version.dataOrNull} | ${feed.value.dataOrNull?.pages} | '
        '${count.value.dataOrNull}');
    return const SizedBox();
  }
}

class _SelectController extends StatefulWidget {
  const _SelectController(this.options, this.show);

  final QuerySelectOptions<Device, String> options;
  final void Function(String) show;

  @override
  State<_SelectController> createState() => _SelectControllerState();
}

class _SelectControllerState extends State<_SelectController> {
  late final QueryController<Device, String> _controller =
      QueryController(QueryClientProvider.read(context), widget.options);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _controller,
        builder: (_, __) {
          widget.show('${_controller.value.dataOrNull}');
          return const SizedBox();
        },
      );
}

class _SelectMixin extends StatefulWidget {
  const _SelectMixin(this.options, this.show);

  final QuerySelectOptions<Device, String> options;
  final void Function(String) show;

  @override
  State<_SelectMixin> createState() => _SelectMixinState();
}

class _SelectMixinState extends State<_SelectMixin> with QueryMixin {
  @override
  Widget build(BuildContext context) {
    widget.show('${watchSelectQuery(widget.options).dataOrNull}');
    return const SizedBox();
  }
}
