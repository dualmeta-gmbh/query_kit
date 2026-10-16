/// The hooks guide's samples that have to run, not only compile: the widget
/// test with the testing guide's teardown, and the `unawaited` trap with
/// its typed spellings, each followed by what the guide says of it.
///
/// Their regions are compared with the page by `../docs_fences_test.dart`.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_hooks/query_kit_hooks.dart';

import '../harness.dart';
import 'fixtures.dart';
import 'guide.dart';

void main() {
  // >>> guides/hooks.md#testing
  testWidgets('the list loads', (tester) async {
    final client = QueryClient();
    await tester.pumpWidget(QueryClientProvider(
      client: client,
      child: const MaterialApp(home: TasksScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(ListView), findsOneWidget);

    // Let the widgets go, and the frame after them run.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    // Then the cache and its timers.
    client.clear();
    // A mutation the clear dropped fails a moment later and its callbacks
    // run then; let them, then clear what they wrote.
    await tester.pump();
    client.clear();
  });
  // <<<

  Widget reader() => HookBuilder(builder: (context) {
        final tasks = useQuery(tasksQuery());
        return Text('${tasks.dataOrNull?.length}');
      });

  hookTest('unawaited(client.query(…)) creates the entry for void',
      (tester, client) async {
    // >>> guides/hooks.md#trap
    // Creates the entry for `void`: the first typed reader throws.
    unawaited(client.query(tasksQuery()));
    // <<<
    await tester.pump();
    expect(() => client.getQueryData<List<Task>>(tasksKey),
        throwsA(isA<QueryDataTypeError>()));

    await tester.pumpApp(client, reader());
    expect(tester.takeException(), isA<QueryDataTypeError>());
  });

  hookTest('the typed spellings create the entry for the data type',
      (tester, client) async {
    // >>> guides/hooks.md#trap-typed
    // The type comes from the options:
    client.query(tasksQuery()).ignore();
    // or is written out:
    unawaited(client.query<List<Task>>(tasksQuery()));
    // <<<
    await tester.pump();
    expect(client.getQueryData<List<Task>>(tasksKey), isEmpty);

    await tester.pumpApp(client, reader());
    expect(tester.takeException(), isNull);
    expect(find.text('0'), findsOneWidget);
  });
}
