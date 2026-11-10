/// A reference's options in the four call styles behave as the same raw
/// options do on every rebuild.
///
/// The observer never sees a reference: it is handed options, and a
/// reference's `options()` returns the options an options function would
/// have built. So the claim is parity, and every case here asserts it the
/// same way: one script, run once per source of options in a fresh client,
/// produces one trace of what was fetched and what was shown, and every
/// reference's trace is the raw options' trace.
///
/// The sources are the ways an app hands a reference to a reader: a family
/// recreated on every build (a declaration inside `build`), one family
/// called again on every build, a zero-input definition recreated or held,
/// and the raw options built inline beside each.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'harness.dart';
import 'typed_support.dart';

typedef _Make<O> = O Function(int generation);

typedef _Source<O, P> = ({
  String name,
  _Make<O> Function(Api api, P policy) prepare
});

final _plainSources = <_Source<QueryObserverOptions<Device>, Policy>>[
  (
    name: 'raw options',
    prepare: (api, policy) => (_) => rawDetail(api, 'a', policy: policy),
  ),
  (
    name: 'a family recreated per build',
    prepare: (api, policy) =>
        (_) => detailFamily(api, policy: policy)('a').options(),
  ),
  (
    name: 'one family called per build',
    prepare: (api, policy) {
      final family = detailFamily(api, policy: policy);
      return (_) => family('a').options();
    },
  ),
  (
    name: 'raw options of the definition key',
    prepare: (api, policy) => (_) => rawCurrent(api, policy: policy),
  ),
  (
    name: 'a definition recreated per build',
    prepare: (api, policy) =>
        (_) => currentDefinition(api, policy: policy).options(),
  ),
  (
    name: 'one definition',
    prepare: (api, policy) {
      final definition = currentDefinition(api, policy: policy);
      return (_) => definition.options();
    },
  ),
  (
    name: 'one family, the policy per use',
    prepare: (api, policy) {
      final family = detailFamily(api);
      return (_) => policy(family('a').options());
    },
  ),
  (
    name: 'one definition, the policy per use',
    prepare: (api, policy) {
      final definition = currentDefinition(api);
      return (_) => policy(definition.options());
    },
  ),
];

final _infiniteSources =
    <_Source<InfiniteQueryObserverOptions<List<int>, int>, InfinitePolicy>>[
  (
    name: 'raw options',
    prepare: (api, policy) => (_) => rawFeed(api, 'a', policy: policy),
  ),
  (
    name: 'a family recreated per build',
    prepare: (api, policy) =>
        (_) => feedFamily(api, policy: policy)('a').options(),
  ),
  (
    name: 'one family called per build',
    prepare: (api, policy) {
      final family = feedFamily(api, policy: policy);
      return (_) => family('a').options();
    },
  ),
  (
    name: 'raw options of the definition key',
    prepare: (api, policy) => (_) => rawLog(api, policy: policy),
  ),
  (
    name: 'a definition recreated per build',
    prepare: (api, policy) =>
        (_) => logDefinition(api, policy: policy).options(),
  ),
  (
    name: 'one definition',
    prepare: (api, policy) {
      final definition = logDefinition(api, policy: policy);
      return (_) => definition.options();
    },
  ),
  (
    name: 'one family, the policy per use',
    prepare: (api, policy) {
      final family = feedFamily(api);
      return (_) => policy(family('a').options());
    },
  ),
  (
    name: 'one definition, the policy per use',
    prepare: (api, policy) {
      final definition = logDefinition(api);
      return (_) => policy(definition.options());
    },
  ),
];

typedef _Run = ({List<String> trace, int optionUpdates, QueryClient client});

/// Runs [script] over a reader of [style] fed by [source], in a client of
/// its own, and takes the tree down again.
Future<_Run> _runPlain(
  WidgetTester tester,
  Style style,
  _Source<QueryObserverOptions<Device>, Policy> source,
  Future<void> Function(Lab lab, QueryClient client) script, {
  Policy policy = noPolicy,
  Object? id,
}) async {
  final client = tester.adopt(QueryClient());
  final lab = Lab(tester);
  final make = source.prepare(Api(lab.trace), policy);
  final updates = countOptionsUpdates(client);
  await tester.pumpWidget(app(
      client,
      lab.host((generation) => readPlain(style, make(generation),
          id: id, seen: (result) => lab.trace.add(describe(result))))));
  await script(lab, client);
  updates.stop();
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  lab.dispose();
  return (trace: lab.trace, optionUpdates: updates.count(), client: client);
}

Future<_Run> _runInfinite(
  WidgetTester tester,
  Style style,
  _Source<InfiniteQueryObserverOptions<List<int>, int>, InfinitePolicy> source,
  Future<void> Function(Lab lab, QueryClient client) script, {
  InfinitePolicy policy = noInfinitePolicy,
  Object? id,
}) async {
  final client = tester.adopt(QueryClient());
  final lab = Lab(tester);
  final make = source.prepare(Api(lab.trace), policy);
  final updates = countOptionsUpdates(client);
  await tester.pumpWidget(app(
      client,
      lab.host((generation) => readInfinite(style, make(generation),
          id: id, seen: (feed) => lab.trace.add(describeFeed(feed.value))))));
  await script(lab, client);
  updates.stop();
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  lab.dispose();
  return (trace: lab.trace, optionUpdates: updates.count(), client: client);
}

/// Every source's trace, keyed by its name, and the check that each one
/// equals the raw options' trace.
void _expectParity(Map<String, _Run> runs) {
  final raw = runs['raw options']!.trace;
  for (final MapEntry(:key, :value) in runs.entries) {
    expect(value.trace, raw, reason: '$key against raw options');
  }
}

int _fetches(List<String> trace) => trace
    .where((line) => line.startsWith('fetch') || line.startsWith('page'))
    .length;

void main() {
  for (final style in Style.values) {
    group('${style.name}:', () {
      queryWidgetTest(
          'a rebuild with an equal reference starts no fetch, as raw '
          'options do', (tester, _) async {
        final runs = <String, _Run>{
          for (final source in _plainSources)
            source.name: await _runPlain(tester, style, source, (lab, _) async {
              await tester.pump();
              for (var i = 0; i < 3; i++) {
                await lab.rebuild();
              }
              await tester.pump(const Duration(seconds: 1));
            }),
        };
        _expectParity(runs);
        // Default stale time: the data is stale from the start, and still
        // no rebuild refetches it.
        expect(_fetches(runs['raw options']!.trace), 1);
        expect(runs['raw options']!.trace.last, 'show a@A1 success/idle stale');
      });

      queryWidgetTest(
          'setOptions still runs on every rebuild: one options update per '
          'build wherever the fetch function is a new closure',
          (tester, _) async {
        final runs = <String, _Run>{
          for (final source in _plainSources)
            source.name: await _runPlain(tester, style, source, (lab, _) async {
              await tester.pump();
              for (var i = 0; i < 3; i++) {
                await lab.rebuild();
              }
            }),
        };
        _expectParity(runs);
        expect({
          for (final MapEntry(:key, :value) in runs.entries)
            key: value.optionUpdates,
        }, {
          // A family binds its input into a new closure on every
          // `options()`, as an inline `queryFn:` literal is a new closure
          // on every build; a definition hands out the function it was
          // given, so only a recreated one differs.
          'raw options': 3,
          'a family recreated per build': 3,
          'one family called per build': 3,
          'raw options of the definition key': 3,
          'a definition recreated per build': 3,
          'one definition': 0,
          'one family, the policy per use': 3,
          'one definition, the policy per use': 0,
        });
      });

      queryWidgetTest(
          'a rebuild with an equal reference does not restart the polling '
          'timer', (tester, _) async {
        QueryObserverOptions<Device> poll(QueryObserverOptions<Device> base) =>
            base.copyWith(
              staleTime: StaleTime.infinite,
              refetchInterval:
                  const RefetchInterval.every(Duration(seconds: 1)),
            );
        final runs = <String, _Run>{
          for (final source in _plainSources)
            source.name: await _runPlain(
              tester,
              style,
              source,
              policy: poll,
              (lab, _) async {
                await tester.pump();
                // A rebuild every 400 ms: a timer restarted by each one
                // would never reach its second.
                for (var i = 0; i < 5; i++) {
                  await tester.pump(const Duration(milliseconds: 400));
                  await lab.rebuild();
                }
                await tester.pump(const Duration(milliseconds: 100));
              },
            ),
        };
        _expectParity(runs);
        expect(_fetches(runs['raw options']!.trace), 3);
      });

      queryWidgetTest(
          'a rebuild with an equal reference does not restart the stale '
          'timer', (tester, _) async {
        QueryObserverOptions<Device> stale(QueryObserverOptions<Device> base) =>
            base.copyWith(
              staleTime: const StaleTime.duration(Duration(seconds: 1)),
            );
        final runs = <String, _Run>{
          for (final source in _plainSources)
            source.name: await _runPlain(
              tester,
              style,
              source,
              policy: stale,
              (lab, _) async {
                await tester.pump();
                await tester.pump(const Duration(milliseconds: 600));
                await lab.rebuild();
                lab.trace.add('-- 1100 ms, no rebuild since 600 ms');
                await tester.pump(const Duration(milliseconds: 500));
              },
            ),
        };
        _expectParity(runs);
        // The timer armed at the fetch flipped the result at 1000 ms; one
        // re-armed by the rebuild would flip it at 1600 ms.
        expect(runs['raw options']!.trace.last, 'show a@A1 success/idle stale');
      });

      queryWidgetTest(
          'the gc timer starts at unmount and not before, as with raw '
          'options', (tester, _) async {
        QueryObserverOptions<Device> gc(QueryObserverOptions<Device> base) =>
            base.copyWith(gcTime: const GcTime.duration(Duration(seconds: 1)));
        final present = <String, List<bool>>{};
        for (final source in _plainSources) {
          final seen = present[source.name] = <bool>[];
          late QueryClient client;
          final run = await _runPlain(
            tester,
            style,
            source,
            policy: gc,
            (lab, _) async {
              await tester.pump();
              for (var i = 0; i < 4; i++) {
                await tester.pump(const Duration(milliseconds: 600));
                await lab.rebuild();
              }
            },
          );
          client = run.client;
          bool held() => client.queryCache.queries.isNotEmpty;
          seen.add(held());
          await tester.pump(const Duration(milliseconds: 900));
          seen.add(held());
          await tester.pump(const Duration(milliseconds: 200));
          seen.add(held());
        }
        for (final MapEntry(:key, :value) in present.entries) {
          expect(value, [true, true, false], reason: key);
        }
      });

      queryWidgetTest(
          'infinite: a rebuild with an equal reference starts no fetch and '
          'does not restart the polling timer', (tester, _) async {
        InfiniteQueryObserverOptions<List<int>, int> poll(
          InfiniteQueryObserverOptions<List<int>, int> base,
        ) =>
            base.copyWith(
              staleTime: StaleTime.infinite,
              refetchInterval:
                  const RefetchInterval.every(Duration(seconds: 1)),
            );
        final quiet = <String, _Run>{
          for (final source in _infiniteSources)
            source.name:
                await _runInfinite(tester, style, source, (lab, _) async {
              await tester.pump();
              for (var i = 0; i < 3; i++) {
                await lab.rebuild();
              }
            }),
        };
        _expectParity(quiet);
        expect(_fetches(quiet['raw options']!.trace), 1);
        expect({
          for (final MapEntry(:key, :value) in quiet.entries)
            key: value.optionUpdates,
        }, {
          'raw options': 3,
          'a family recreated per build': 3,
          'one family called per build': 3,
          'raw options of the definition key': 3,
          'a definition recreated per build': 3,
          'one definition': 0,
          'one family, the policy per use': 3,
          'one definition, the policy per use': 0,
        });

        final polling = <String, _Run>{
          for (final source in _infiniteSources)
            source.name: await _runInfinite(
              tester,
              style,
              source,
              policy: poll,
              (lab, _) async {
                await tester.pump();
                for (var i = 0; i < 5; i++) {
                  await tester.pump(const Duration(milliseconds: 400));
                  await lab.rebuild();
                }
                await tester.pump(const Duration(milliseconds: 100));
              },
            ),
        };
        _expectParity(polling);
        expect(_fetches(polling['raw options']!.trace), 3);
      });

      queryWidgetTest(
          'a rebuild with a new definition instance hands the observer the '
          'new fetcher: an invalidation before it runs the old one, after '
          'it the new one', (tester, _) async {
        final runs = <String, _Run>{
          for (final source in _switchSources)
            source.name: await _runPlain(tester, style, source, _switchScript),
        };
        _expectParity(runs);
        expect(_requestsAndMarks(runs['raw options']!.trace), [
          'fetch A1',
          '-- invalidate before the rebuild',
          'fetch A2',
          '-- rebuild with the second definition',
          '-- invalidate after it',
          'fetch B1',
        ]);
        expect(runs['raw options']!.trace.last, 'show a@B1 success/idle stale');
      });

      queryWidgetTest(
          'infinite: a rebuild with a new definition instance hands the '
          'observer the new page function', (tester, _) async {
        final runs = <String, _Run>{
          for (final source in _infiniteSwitchSources)
            source.name:
                await _runInfinite(tester, style, source, _switchScript),
        };
        _expectParity(runs);
        expect(_requestsAndMarks(runs['raw options']!.trace), [
          'page A0#1',
          '-- invalidate before the rebuild',
          'page A0#2',
          '-- rebuild with the second definition',
          '-- invalidate after it',
          'page B0#1',
        ]);
      });

      queryWidgetTest(
          'an Enabled.when over outside state is re-evaluated by a rebuild '
          'with an equal reference: set by configure and per use',
          (tester, _) async {
        var paused = false;
        QueryObserverOptions<Device> gated(QueryObserverOptions<Device> base) =>
            base.copyWith(
              enabled: Enabled.when((_) => !paused),
              staleTime: StaleTime.infinite,
              refetchInterval:
                  const RefetchInterval.every(Duration(seconds: 1)),
            );
        final runs = <String, _Run>{
          for (final source in _plainSources)
            source.name: await _runPlain(
              tester,
              style,
              source,
              policy: gated,
              (lab, _) {
                paused = false;
                return _pausePolling(lab, (value) => paused = value);
              },
            ),
        };
        _expectParity(runs);
        _expectPausedThenResumed(runs['raw options']!.trace);
      });

      queryWidgetTest(
          'infinite: an Enabled.when over outside state is re-evaluated by a '
          'rebuild with an equal reference', (tester, _) async {
        var paused = false;
        InfiniteQueryObserverOptions<List<int>, int> gated(
          InfiniteQueryObserverOptions<List<int>, int> base,
        ) =>
            base.copyWith(
              enabled: Enabled.when((_) => !paused),
              staleTime: StaleTime.infinite,
              refetchInterval:
                  const RefetchInterval.every(Duration(seconds: 1)),
            );
        final runs = <String, _Run>{
          for (final source in _infiniteSources)
            source.name: await _runInfinite(
              tester,
              style,
              source,
              policy: gated,
              (lab, _) {
                paused = false;
                return _pausePolling(lab, (value) => paused = value);
              },
            ),
        };
        _expectParity(runs);
        _expectPausedThenResumed(runs['raw options']!.trace);
      });

      for (final id in <Object?>[null, 'detail']) {
        // A builder and a controller hold one observer and move it; the
        // two reading styles move theirs only when an id says the reads
        // are one.
        final follows =
            id != null || style == Style.builder || style == Style.controller;

        queryWidgetTest(
            "a parameter change moves to the new input's entry, keeping the "
            'previous data as raw options do (id: $id)', (tester, _) async {
          final runs = <String, _Run>{
            for (final source in _paramSources)
              source.name: await _runPlain(
                tester,
                style,
                source,
                policy: _keepPrevious,
                id: id,
                _paramScript,
              ),
          };
          _expectParity(runs);
          final trace = runs['raw options']!.trace;
          final switched = trace.sublist(trace.indexOf('-- input b') + 1);
          expect(
            switched.firstWhere((line) => line.startsWith('show')),
            follows
                ? 'show a@A1 success/fetching placeholder stale'
                : 'show - pending/fetching stale',
          );
          expect(
            switched,
            containsAllInOrder(['fetch A1', 'show b@A1 success/idle stale']),
          );
        });

        queryWidgetTest(
            "infinite: a parameter change moves to the new input's entry, "
            'keeping the previous pages as raw options do (id: $id)',
            (tester, _) async {
          final runs = <String, _Run>{
            for (final source in _infiniteParamSources)
              source.name: await _runInfinite(
                tester,
                style,
                source,
                policy: _keepPreviousPages,
                id: id,
                _paramScript,
              ),
          };
          _expectParity(runs);
          final trace = runs['raw options']!.trace;
          final switched = trace.sublist(trace.indexOf('-- input b') + 1);
          expect(
            switched.firstWhere((line) => line.startsWith('show')),
            follows
                ? 'show 0,1 success/fetching placeholder stale'
                : 'show - pending/fetching stale',
          );
          expect(
            switched,
            containsAllInOrder(['page A0#1', 'show 0,1 success/idle stale']),
          );
        });
      }
    });
  }
}

/// The requests and the script's marks of a trace, in order.
List<String> _requestsAndMarks(List<String> trace) => [
      for (final line in trace)
        if (!line.startsWith('show')) line,
    ];

Future<void> _switchScript(Lab lab, QueryClient client) async {
  final tester = lab.tester;
  await tester.pump();
  lab.trace.add('-- invalidate before the rebuild');
  final before = devicesNamespace().invalidate(client);
  await tester.pump();
  await before;
  lab.trace.add('-- rebuild with the second definition');
  await lab.rebuild();
  await tester.pump();
  lab.trace.add('-- invalidate after it');
  final after = devicesNamespace().invalidate(client);
  await tester.pump();
  await after;
}

Future<void> _paramScript(Lab lab, QueryClient client) async {
  await lab.tester.pump();
  lab.trace.add('-- input b');
  await lab.rebuild();
  await lab.tester.pump();
}

Future<void> _pausePolling(
    Lab lab, void Function(bool paused) setPaused) async {
  final tester = lab.tester;
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  setPaused(true);
  lab.trace.add('-- paused');
  await lab.rebuild();
  await tester.pump(const Duration(seconds: 3));
  setPaused(false);
  lab.trace.add('-- resumed');
  await lab.rebuild();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

void _expectPausedThenResumed(List<String> trace) {
  final paused = trace.indexOf('-- paused');
  final resumed = trace.indexOf('-- resumed');
  expect(_fetches(trace.sublist(0, paused)), 2, reason: 'polling');
  expect(_fetches(trace.sublist(paused, resumed)), 0, reason: 'paused');
  expect(_fetches(trace.sublist(resumed)), greaterThan(0), reason: 'resumed');
}

QueryObserverOptions<Device> _keepPrevious(QueryObserverOptions<Device> base) =>
    base.copyWith(placeholderData: const PlaceholderData.keepPrevious());

InfiniteQueryObserverOptions<List<int>, int> _keepPreviousPages(
  InfiniteQueryObserverOptions<List<int>, int> base,
) =>
    base.copyWith(placeholderData: const PlaceholderData.keepPrevious());

String _input(int generation) => generation == 0 ? 'a' : 'b';

final _paramSources = <_Source<QueryObserverOptions<Device>, Policy>>[
  (
    name: 'raw options',
    prepare: (api, policy) => (g) => rawDetail(api, _input(g), policy: policy),
  ),
  (
    name: 'a family recreated per build',
    prepare: (api, policy) =>
        (g) => detailFamily(api, policy: policy)(_input(g)).options(),
  ),
  (
    name: 'one family called per build',
    prepare: (api, policy) {
      final family = detailFamily(api, policy: policy);
      return (g) => family(_input(g)).options();
    },
  ),
  (
    name: 'one family, the policy per use',
    prepare: (api, policy) {
      final family = detailFamily(api);
      return (g) => policy(family(_input(g)).options());
    },
  ),
];

final _infiniteParamSources =
    <_Source<InfiniteQueryObserverOptions<List<int>, int>, InfinitePolicy>>[
  (
    name: 'raw options',
    prepare: (api, policy) => (g) => rawFeed(api, _input(g), policy: policy),
  ),
  (
    name: 'a family recreated per build',
    prepare: (api, policy) =>
        (g) => feedFamily(api, policy: policy)(_input(g)).options(),
  ),
  (
    name: 'one family, the policy per use',
    prepare: (api, policy) {
      final family = feedFamily(api);
      return (g) => policy(family(_input(g)).options());
    },
  ),
];

/// Generation 0 reads through a definition over backend `A`, every later
/// one through another definition of the same query over backend `B`.
final _switchSources = <_Source<QueryObserverOptions<Device>, Policy>>[
  (
    name: 'raw options',
    prepare: (a, _) {
      final b = Api(a.trace, tag: 'B');
      return (g) => rawDetail(g == 0 ? a : b, 'a');
    },
  ),
  (
    name: 'a family recreated per build',
    prepare: (a, _) {
      final b = Api(a.trace, tag: 'B');
      return (g) => detailFamily(g == 0 ? a : b)('a').options();
    },
  ),
  (
    name: 'two families, each held',
    prepare: (a, _) {
      final first = detailFamily(a);
      final second = detailFamily(Api(a.trace, tag: 'B'));
      return (g) => (g == 0 ? first : second)('a').options();
    },
  ),
  (
    name: 'raw options of the definition key',
    prepare: (a, _) {
      final b = Api(a.trace, tag: 'B');
      return (g) => rawCurrent(g == 0 ? a : b);
    },
  ),
  (
    name: 'two definitions, each held',
    prepare: (a, _) {
      final first = currentDefinition(a);
      final second = currentDefinition(Api(a.trace, tag: 'B'));
      return (g) => (g == 0 ? first : second).options();
    },
  ),
];

final _infiniteSwitchSources =
    <_Source<InfiniteQueryObserverOptions<List<int>, int>, InfinitePolicy>>[
  (
    name: 'raw options',
    prepare: (a, _) {
      final b = Api(a.trace, tag: 'B');
      return (g) => rawFeed(g == 0 ? a : b, 'a');
    },
  ),
  (
    name: 'a family recreated per build',
    prepare: (a, _) {
      final b = Api(a.trace, tag: 'B');
      return (g) => feedFamily(g == 0 ? a : b)('a').options();
    },
  ),
  (
    name: 'two definitions, each held',
    prepare: (a, _) {
      final first = logDefinition(a);
      final second = logDefinition(Api(a.trace, tag: 'B'));
      return (g) => (g == 0 ? first : second).options();
    },
  ),
];
