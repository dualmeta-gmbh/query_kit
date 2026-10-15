/// The hooks suite's harness: a client per case, the provider around the
/// widget under test, the ADR-0002 teardown, and [HookProbe] — upstream's
/// `function Page() { … }` as a widget.
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

/// A hook widget whose `build` is [builder] — upstream's `function Page()`.
class HookProbe extends HookWidget {
  /// Builds with [builder].
  const HookProbe(this.builder, {super.key});

  /// The body of upstream's component.
  final Widget Function(BuildContext context) builder;

  @override
  Widget build(BuildContext context) => builder(context);
}

int _keyCounter = 0;

/// A key no other case uses — upstream's `queryKey()`.
QueryKey queryKey() => QueryKey(<Object?>['query_${++_keyCounter}']);

/// Upstream's `sleep(ms)`.
Future<void> sleep(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

/// Upstream's `vi.advanceTimersByTimeAsync(ms)`, stepped: one frame per
/// millisecond of fake time, so every timer that fires gets a frame of its
/// own — React renders after each macrotask; `tester.pump(d)` would elapse
/// all of [ms] first and build once (plan, D8).
Future<void> advance(WidgetTester tester, int ms) async {
  if (ms == 0) {
    await tester.pump(Duration.zero);
    return;
  }
  for (var i = 0; i < ms; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
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
