// The example, run: its list loads, a task added through the mutation shows
// up after the invalidation refetches it, and the app comes down with the
// documented teardown.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';
import 'package:query_kit_flutter_example/main.dart' as example;

void main() {
  testWidgets('the tour loads its tasks and adds one', (tester) async {
    example.main();
    await tester.pump();
    final client = QueryClientProvider.of(
      tester.element(find.byType(example.TasksScreen)),
    );
    try {
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(find.byType(ListTile), findsNWidgets(3));
      expect(find.text('Kitchen'), findsOneWidget);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      // The write, then the refetch its `onSuccess` invalidation starts.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(find.byType(ListTile), findsNWidgets(4));
      expect(find.textContaining('Task '), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      client.clear();
      await tester.pump();
      client.clear();
    }
  });
}
