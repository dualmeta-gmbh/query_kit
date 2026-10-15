// The example's widget-test harness: the app against its in-memory backend,
// on the test's fake clock, and the documented teardown after every test.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_hooks/query_kit_hooks.dart';
import 'package:query_kit_hooks_example/src/api.dart';
import 'package:query_kit_hooks_example/src/app.dart';
import 'package:query_kit_hooks_example/src/in_memory_backend.dart';
import 'package:query_kit_hooks_example/src/queries.dart';

/// The app's seed, `assets/seed.json`, decoded afresh: every backend gets
/// rows of its own to write to.
Map<String, Object?> seed() =>
    jsonDecode(File('assets/seed.json').readAsStringSync())
        as Map<String, Object?>;

/// What one request costs, as in the app.
const Duration latency = Duration(milliseconds: 300);

/// The app running against [backend] through [client].
class ExampleRun {
  ExampleRun(this.tester, this.backend, this.client);

  final WidgetTester tester;
  final InMemoryBackend backend;
  final QueryClient client;

  /// Steps the fake clock by [duration], then one more frame for what the
  /// answers scheduled.
  Future<void> wait(Duration duration) async {
    await tester.pump(duration);
    await tester.pump();
  }

  /// Steps one request's latency.
  Future<void> answer() => wait(latency);

  Future<void> tapText(String text) async {
    await tester.tap(find.text(text));
    await tester.pump();
  }

  /// The texts inside the [Group] named [name], in tree order.
  List<String> textsIn(String name) => [
        for (final element in find
            .descendant(
                of: find.byKey(ValueKey(name)), matching: find.byType(Text))
            .evaluate())
          (element.widget as Text).data ?? '',
      ];
}

/// A widget test of the whole app: [body] gets it pumped, its first frame
/// built and nothing answered yet.
void exampleTest(
    String description, Future<void> Function(ExampleRun run) body) {
  testWidgets(description, (tester) async {
    final backend = InMemoryBackend(seed: seed(), latency: latency);
    final client = QueryClient(defaultOptions: exampleDefaults);
    await tester.pumpWidget(
      HooksExampleApp(api: ExampleApi.inMemory(backend), client: client),
    );
    try {
      await body(ExampleRun(tester, backend, client));
    } finally {
      // The documented teardown (ADR-0002): the tree down, the cache's
      // timers cleared, then once more for what a dropped mutation's
      // callbacks wrote. The backend's own latency timers go last.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      client.clear();
      await tester.pump();
      client.clear();
      backend.close();
    }
  });
}
