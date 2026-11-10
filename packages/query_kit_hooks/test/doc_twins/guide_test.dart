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

  hookTest('a generic helper keeps the reference\'s data type',
      (tester, client) async {
    await tester.pumpApp(client, title);
    await tester.pumpAndSettle();
    expect(find.text('Draft the changelog'), findsOneWidget);
    expect(
      client.queryCache.find(filters: tasks.detail('1').filters())!.dataType,
      Task,
    );
    expect(tasks.detail('1').read(client)?.name, 'Draft the changelog');
  });

  hookTest('a helper over QueryObserverOptions<Object> makes an Object entry',
      (tester, client) async {
    await tester.pumpApp(
      client,
      Loaded<Object>(tasks.detail('2').options(),
          builder: (data) => Text('$data')),
    );
    await tester.pumpAndSettle();
    expect(
      client.queryCache.find(filters: tasks.detail('2').filters())!.dataType,
      Object,
    );
    // The reference refuses the entry the widened helper made.
    expect(() => tasks.detail('2').read(client),
        throwsA(isA<QueryDataTypeError>()));
  });

  hookTest(
      'the rename writes through the reference and settles with a '
      'refetch', (tester, client) async {
    await tester.pumpApp(
      client,
      Column(children: [const RenameTask('1'), title]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Draft the changelog'), findsOneWidget);

    await tester.tap(find.text('Rename'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // The server's answer, refetched by the invalidation in `onSettled`.
    expect(find.text('Draft the changelog'), findsOneWidget);
    expect(
      client.queryCache.find(filters: tasks.detail('1').filters())!.dataType,
      Task,
    );
  });
}
