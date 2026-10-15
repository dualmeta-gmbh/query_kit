/// The hooks suite's harness: a client per case, the provider around the
/// widget under test, the ADR-0002 teardown, and a [Recorder] for what a case
/// observes. Upstream's `function Page() { … }` is `flutter_hooks`'
/// `HookBuilder`, not a copy of it (plan, D16).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meta/meta.dart';
import 'package:query_kit_hooks/query_kit_hooks.dart';

/// [testWidgets] for a tree with a [QueryClient] in it, torn down the way the
/// testing guide documents (ADR-0002).
@isTest
void hookTest(
  String description,
  Future<void> Function(WidgetTester tester, QueryClient client) body, {
  QueryClient Function()? createClient,
  bool? skip,
}) {
  testWidgets(
    description,
    (tester) async {
      final client = (createClient ?? QueryClient.new)();
      try {
        await body(tester, client);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        client.clear();
        await tester.pump();
        client.clear();
      }
    },
    skip: skip,
  );
}

/// Upstream's `renderWithClient(queryClient, <Page />)`.
Widget app(QueryClient client, Widget child) => QueryClientProvider(
      client: client,
      observeAppLifecycle: false,
      child: MaterialApp(home: Scaffold(body: child)),
    );

/// Upstream's `const states: Array<…> = []`, and beside it what the frame
/// hides (plan, D8).
///
/// React renders after every timer; Flutter builds once per frame for every
/// notification before it. [advance] steps one frame per millisecond, so the
/// two mostly agree, but a frame can still merge two results into one build.
/// [builds] is what upstream's `states.push(state)` records; [delivered] is
/// every result the observer handed the hook that differed from the one on
/// screen — a state the frame merged away is still in it.
///
/// ```dart
/// final state = rec.build(useQuery(options, buildWhen: rec.buildWhen));
/// ```
final class Recorder<T> {
  /// One entry per build: upstream's `states`.
  final List<T> builds = <T>[];

  /// One entry per delivered result that differed from the one built last.
  /// An equal one never reaches a `buildWhen`: the rebuild rule drops it
  /// first, as it does for every call style.
  final List<T> delivered = <T>[];

  /// Records [value] as built and returns it.
  T build(T value) {
    builds.add(value);
    return value;
  }

  /// A `buildWhen` that records what it is asked about and rebuilds, which
  /// is what no `buildWhen` at all does — passing it changes no build.
  BuildWhen<T> get buildWhen => (previous, current) {
        delivered.add(current);
        return true;
      };

  /// [buildWhen] in front of a case's own predicate [inner].
  BuildWhen<T> around(BuildWhen<T> inner) => (previous, current) {
        delivered.add(current);
        return inner(previous, current);
      };
}

int _keyCounter = 0;

/// A key no other case uses — upstream's `queryKey()`.
QueryKey queryKey() => QueryKey(<Object?>['query_${++_keyCounter}']);

/// How many observers the entry under [key] has; 0 without an entry.
int observersOf(QueryClient client, QueryKey key) =>
    client.queryCache
        .find(filters: QueryFilters(queryKey: key))
        ?.observersCount ??
    0;

/// Upstream's `sleep(ms)`.
Future<void> sleep(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

/// Upstream's `vi.advanceTimersByTimeAsync(ms)`, stepped (plan, D8): React
/// renders after each macrotask, while `tester.pump(d)` would elapse all of
/// [ms] first and build once.
///
/// - A frame before any time passes, for what microtasks already raised, as
///   `act` renders it before the first timer. Without it, a failure delivered
///   in a microtask and a 1 ms retry's failure share one frame (case 159).
/// - Then one frame per millisecond, so every timer that fires gets a frame
///   of its own.
Future<void> advance(WidgetTester tester, int ms) async {
  await tester.pump(Duration.zero);
  for (var i = 0; i < ms; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

/// `act(() => window.dispatchEvent(new Event('visibilitychange')))`: a focus
/// event, and the frame `act` renders. The refetch it starts runs after an
/// await in the client's focus handler, so the frame is needed.
Future<void> focusWindow(WidgetTester tester, QueryClient client) async {
  client.focusManager.onFocus();
  await tester.pump();
}

/// Upstream's `queryClient.prefetchQuery(…)`, or `query(…).catch(noop)`.
Future<void> prefetch<T>(QueryClient client, QueryOptions<T> options) =>
    client.query(options).then<void>((_) {}, onError: (Object _) {});

/// Upstream's `setState` inside a `useEffect`. `flutter_hooks` runs an
/// effect inside `build`, where a state change to the element being built is
/// dropped, so it lands after the frame instead, and costs a pump.
void afterFrame(VoidCallback callback) =>
    WidgetsBinding.instance.addPostFrameCallback((_) => callback());

/// Upstream's `vi.spyOn(window, 'setTimeout')` around [body]: the duration
/// of every timer [body] creates, in order.
Future<List<Duration>> timersCreatedBy(Future<void> Function() body) async {
  final created = <Duration>[];
  await runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, f) {
        created.add(duration);
        return parent.createTimer(zone, duration, f);
      },
    ),
  );
  return created;
}

/// A tap, and the frame it asks for — `fireEvent.click`, which React
/// renders synchronously inside `act`.
Future<void> click(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pump();
}

extension HarnessTester on WidgetTester {
  /// Pumps [child] under [app] for [client].
  Future<void> pumpApp(QueryClient client, Widget child) =>
      pumpWidget(app(client, child));
}

/// Upstream's `Blink`: shows [child] for [duration] milliseconds, then
/// `off`.
class Blink extends HookWidget {
  /// Shows [child] for [duration] milliseconds.
  const Blink({super.key, required this.duration, required this.child});

  /// How long [child] stays, in milliseconds.
  final int duration;

  /// What is shown until then.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shouldShow = useState(true);
    useEffect(() {
      shouldShow.value = true;
      final timer = Timer(
        Duration(milliseconds: duration),
        () => shouldShow.value = false,
      );
      return timer.cancel;
    }, [duration, child]);
    return shouldShow.value ? child : const Text('off');
  }
}
