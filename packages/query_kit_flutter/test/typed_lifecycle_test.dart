/// References read in the four call styles, over the lifetime of a widget:
/// two clients side by side and a provider that switches its client,
/// unmount, a cancellation while a widget waits, and the typed writes and
/// invalidations made from outside a build reaching exactly the readers
/// they address.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'harness.dart';
import 'typed_support.dart';

/// A provider for [client] around [child], lifecycle observation off as
/// the harness's [app] has it.
Widget _provide(QueryClient client, Widget child) => QueryClientProvider(
      client: client,
      observeAppLifecycle: false,
      child: child,
    );

void main() {
  for (final style in Style.values) {
    group('${style.name}:', () {
      queryWidgetTest('two clients read the same reference independently',
          (tester, first) async {
        final second = tester.adopt(QueryClient());
        final trace = <String>[];
        final shown = (first: <String>[], second: <String>[]);
        final detail = detailFamily(Api(trace));
        await tester.pumpWidget(MaterialApp(
          home: Column(children: [
            _provide(
              first,
              readPlain(style, detail('a').options(),
                  seen: (result) => shown.first.add(describe(result))),
            ),
            _provide(
              second,
              readPlain(style, detail('a').options(),
                  seen: (result) => shown.second.add(describe(result))),
            ),
          ]),
        ));
        await tester.pump();
        expect(trace, ['fetch A1', 'fetch A2'], reason: 'one fetch per client');
        expect(detail('a').read(first), const Device('a', 'A1'));
        expect(detail('a').read(second), const Device('a', 'A2'));

        detail('a').write(first, const Device('a', 'written'));
        await tester.pump();
        expect(shown.first.last, 'show a@written success/idle stale');
        expect(shown.second.last, 'show a@A2 success/idle stale');

        final refetch = detail('a').invalidate(second);
        await tester.pump();
        await refetch;
        expect(trace, ['fetch A1', 'fetch A2', 'fetch A3']);
        expect(shown.first.last, 'show a@written success/idle stale');
        expect(shown.second.last, 'show a@A3 success/idle stale');
      });

      queryWidgetTest(
          "a provider's client switch moves the reader to the new client, as "
          'it does raw options', (tester, first) async {
        final traces = <String, List<String>>{};
        for (final (name, make)
            in <(String, QueryObserverOptions<Device> Function(Api))>[
          ('raw options', (api) => rawDetail(api, 'a')),
          (
            'a family recreated per build',
            (api) => detailFamily(api)('a').options()
          ),
          (
            'a definition recreated per build',
            (api) => currentDefinition(api).options()
          ),
        ]) {
          final from = tester.adopt(QueryClient());
          final to = tester.adopt(QueryClient());
          final trace = traces[name] = <String>[];
          final api = Api(trace);
          Widget tree(QueryClient client) => app(
              client,
              readPlain(style, make(api),
                  seen: (result) => trace.add(describe(result))));
          await tester.pumpWidget(tree(from));
          await tester.pump();
          trace.add('-- switch');
          await tester.pumpWidget(tree(to));
          await tester.pump();
          await tester.pump();
          expect(from.queryCache.queries.single.observersCount, 0,
              reason: '$name: the old client keeps no observer');
          expect(to.queryCache.queries.single.observersCount, 1, reason: name);
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
        }
        for (final MapEntry(:key, :value) in traces.entries) {
          expect(value, traces['raw options'], reason: key);
        }
        final switched = traces['raw options']!;
        expect(switched.sublist(switched.indexOf('-- switch')),
            containsAllInOrder(['fetch A2', 'show a@A2 success/idle stale']));
      });

      queryWidgetTest(
          'unmount releases the observer: no poll after it, and the entry '
          'goes at its gc time', (tester, client) async {
        final trace = <String>[];
        final detail = detailFamily(
          Api(trace),
          policy: (base) => base.copyWith(
            gcTime: const GcTime.duration(Duration(seconds: 2)),
            refetchInterval: const RefetchInterval.every(Duration(seconds: 1)),
          ),
        );
        await tester.pumpApp(
            client, readPlain(style, detail('a').options(), seen: (_) {}));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(trace, ['fetch A1', 'fetch A2']);

        await tester.pumpWidget(app(client, const SizedBox()));
        await tester.pump();
        final entry = client.queryCache.get<Device>(detail('a').key.rawKey)!;
        expect(entry.observersCount, 0);
        await tester.pump(const Duration(milliseconds: 1500));
        expect(trace, ['fetch A1', 'fetch A2'], reason: 'no poll unmounted');
        expect(detail('a').state(client), isNotNull);
        await tester.pump(const Duration(milliseconds: 600));
        expect(detail('a').state(client), isNull, reason: 'collected');
      });

      for (final withData in [false, true]) {
        queryWidgetTest(
            'cancelling the reference while its widget waits reverts it, '
            'as cancelling raw options does '
            '(${withData ? 'a refetch' : 'the first fetch'})',
            (tester, _) async {
          final namespace = devicesNamespace();
          final cancels = <String, Future<void> Function(QueryClient client)>{
            'raw cancelQueries': (client) => client.cancelQueries(
                filters: QueryFilters(queryKey: detailKey('a'), exact: true)),
            'the reference': (client) =>
                _waiting(Completer())('a').cancel(client),
            'the family': (client) => _waiting(Completer()).cancel(client),
            'the namespace': namespace.cancel,
          };
          final traces = <String, List<String>>{};
          for (final MapEntry(key: name, value: cancel) in cancels.entries) {
            final client = tester.adopt(QueryClient());
            final trace = traces[name] = <String>[];
            final answer = Completer<Device>();
            if (withData) {
              detailFamily(Api(trace))('a')
                  .write(client, const Device('a', 'cached'));
            }
            await tester.pumpApp(
                client,
                readPlain(style, _waiting(answer)('a').options(),
                    seen: (result) => trace.add(describe(result))));
            await tester.pump();
            trace.add('-- cancel');
            final done = cancel(client);
            await tester.pump();
            await done;
            answer.complete(const Device('a', 'late'));
            await tester.pump();
            await tester.pumpWidget(const SizedBox());
            await tester.pump();
          }
          for (final MapEntry(:key, :value) in traces.entries) {
            expect(value, traces['raw cancelQueries'], reason: key);
          }
          final after = traces['raw cancelQueries']!;
          expect(
            after.last,
            withData
                ? 'show a@cached success/idle stale'
                : 'show - pending/idle stale',
            reason: 'reverted, and the late answer was dropped',
          );
        });
      }

      queryWidgetTest(
          'writes and invalidations from outside a build rebuild exactly the '
          'readers they address', (tester, client) async {
        final trace = <String>[];
        final api = Api(trace);
        final detail = detailFamily(api);
        final current = currentDefinition(api);
        final feed = feedFamily(api);
        final namespace = devicesNamespace();
        final other = QueryDefinition<Device>(
          namespace: QueryNamespace(const ['other']),
          name: 'one',
          queryFn: (_) => api.device('other'),
        );
        final builds = <String, int>{};
        final lastShown = <String, String>{};
        void Function(QueryResult<Object?>) count(String name) => (result) {
              builds[name] = (builds[name] ?? 0) + 1;
              lastShown[name] = switch (result.dataOrNull) {
                final InfiniteData<List<int>, int> data =>
                  data.pages.expand((page) => page).join(','),
                final data => '$data',
              };
            };
        await tester.pumpApp(
          client,
          Column(children: [
            readPlain(style, detail('a').options(), seen: count('a')),
            readPlain(style, detail('b').options(), seen: count('b')),
            readPlain(style, current.options(), seen: count('current')),
            readInfinite(style, feed('a').options(),
                seen: (controller) => count('feed')(controller.value)),
            readPlain(style, other.options(), seen: count('other')),
          ]),
        );
        await tester.pump();

        Future<Set<String>> rebuiltBy(
            FutureOr<void> Function() operation) async {
          final before = Map.of(builds);
          final pending = operation();
          await tester.pump();
          await pending;
          await tester.pump();
          return {
            for (final MapEntry(:key, :value) in builds.entries)
              if (value != before[key]) key,
          };
        }

        expect(
            await rebuiltBy(
                () => detail('a').write(client, const Device('a', 'W'))),
            {'a'});
        expect(lastShown['a'], 'a@W');

        expect(
            await rebuiltBy(
                () => detail('b').update(client, (d) => d?.bump('U'))),
            {'b'});
        expect(lastShown['b'], 'b@U');

        expect(
            await rebuiltBy(
                () => detail.updateAll(client, (d) => d?.bump('ALL'))),
            {'a', 'b'});
        expect((lastShown['a'], lastShown['b']), ('a@ALL', 'b@ALL'));

        expect(
            await rebuiltBy(
                () => current.write(client, const Device('c', 'W'))),
            {'current'});

        expect(
            await rebuiltBy(() => feed('a').update(
                client,
                (data) => data == null
                    ? null
                    : InfiniteData(
                        pages: [
                          [7],
                          ...data.pages
                        ],
                        pageParams: [-1, ...data.pageParams],
                      ))),
            {'feed'});
        expect(lastShown['feed'], '7,0,1');

        expect(
            await rebuiltBy(() => feed.updateAll(
                client,
                (data) => data == null
                    ? null
                    : InfiniteData(
                        pages: data.pages.skip(1).toList(),
                        pageParams: data.pageParams.skip(1).toList(),
                      ))),
            {'feed'});
        expect(lastShown['feed'], '0,1');

        trace.clear();
        expect(await rebuiltBy(() => detail('a').invalidate(client)), {'a'});
        expect(trace, hasLength(1));

        trace.clear();
        expect(await rebuiltBy(() => detail.invalidate(client)), {'a', 'b'});
        expect(trace, hasLength(2));

        trace.clear();
        expect(await rebuiltBy(() => namespace.invalidate(client)),
            {'a', 'b', 'current', 'feed'});
        expect(trace, hasLength(4), reason: 'every entry under devices');

        trace.clear();
        expect(await rebuiltBy(() => other.invalidate(client)), {'other'});
        expect(trace, ['fetch A2'], reason: "other's second request");
      });

      for (final fail in [false, true]) {
        queryWidgetTest(
            'a mutation in this style writes optimistically through the '
            'reference and ${fail ? 'rolls back' : 'keeps the answer'}',
            (tester, client) async {
          final trace = <String>[];
          final detail = detailFamily(Api(trace));
          final device = detail('a');
          final reply = Completer<Device>();
          final options = MutationOptions(
            mutationFn: (String version) async {
              final answer = await reply.future;
              if (fail) throw StateError('refused');
              return answer;
            },
            onMutate: (String version) async {
              await device.cancel(client);
              final previous = device.read(client)
                ?..expectStaticType<Exactly<Device>>();
              device.update(client, (current) => current?.bump(version));
              return previous;
            },
            onSuccess: (data, _, __) =>
                trace.add('wrote ${device.write(client, data)}'),
            onError: (_, __, ___, previous) {
              previous.expectStaticType<Exactly<Device?>>();
              if (previous != null) {
                trace.add('rolled back to ${device.write(client, previous)}');
              }
            },
            onSettled: (_, __, ___, ____, _____) => detail.invalidate(client),
          )..expectStaticType<
              Exactly<MutationOptions<Device, String, Device>>>();
          final shown = <String>[];
          MutationController<Device, String, Device>? mutation;
          await tester.pumpApp(
            client,
            Column(children: [
              ContextReader<Device>(device.options(),
                  (result) => shown.add('${result.dataOrNull}')),
              _Mutator(style, options, (controller) => mutation = controller),
            ]),
          );
          await tester.pump();
          expect(shown.last, 'a@A1');

          mutation!.mutate('optimistic');
          // `onMutate` awaits the cancellation first, so the optimistic
          // write lands a few microtasks into this frame; the next one
          // shows it.
          await tester.pump();
          await tester.pump();
          expect(shown.last, 'a@optimistic');

          reply.complete(const Device('a', 'server'));
          await tester.pump();
          await tester.pump();
          await tester.pump();
          // The write and the family's invalidation run in one frame, so
          // the reader goes from the optimistic value to the refetch.
          expect(trace, [
            'fetch A1',
            fail ? 'rolled back to a@A1' : 'wrote a@server',
            'fetch A2',
          ]);
          expect(shown.last, 'a@A2');
        });
      }
    });
  }
}

/// A mutation in [style]; [take] receives the controller every build.
class _Mutator extends StatefulWidget {
  const _Mutator(this.style, this.options, this.take);

  final Style style;
  final MutationOptions<Device, String, Device> options;
  final void Function(MutationController<Device, String, Device>) take;

  @override
  State<_Mutator> createState() => _MutatorState();
}

class _MutatorState extends State<_Mutator> with QueryMixin {
  MutationController<Device, String, Device>? _own;

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.style) {
      case Style.controller:
        widget.take(_own ??= MutationController(
            QueryClientProvider.of(context), widget.options));
      case Style.builder:
        return MutationBuilder(
          options: widget.options,
          builder: (_, mutation) {
            widget.take(mutation);
            return const SizedBox();
          },
        );
      case Style.mixin:
        widget.take(watchMutation(widget.options));
      case Style.context:
        widget.take(context.mutation(widget.options));
    }
    return const SizedBox();
  }
}

/// A family whose fetch waits for [answer].
QueryFamily<String, Device> _waiting(Completer<Device> answer) =>
    QueryFamily<String, Device>(
      namespace: devicesNamespace(),
      name: 'detail',
      queryFn: (_, __) => answer.future,
    );
