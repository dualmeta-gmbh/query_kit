// Todo writes and reads answered in an order no latency gives reliably:
// every todo request is held until the case answers it. The Todos tab
// alone, so nothing else asks for anything.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_hooks/query_kit_hooks.dart';
import 'package:query_kit_hooks_example/src/api.dart';
import 'package:query_kit_hooks_example/src/app.dart';
import 'package:query_kit_hooks_example/src/models.dart';
import 'package:query_kit_hooks_example/src/queries.dart';
import 'package:query_kit_hooks_example/src/todos.dart';

const String checklist = 'Update the deploy checklist';
const String token = 'Replace the expired API token';
const String added = 'Added while the list reloads';

const List<Todo> seeded = [
  Todo(id: 1, text: checklist, done: false),
  Todo(id: 3, text: token, done: false),
];

/// The todo calls, each answered when the case completes it.
class HeldApi extends ExampleApi {
  HeldApi() : super(baseUrl: 'http://held.invalid');

  final List<Completer<List<Todo>>> reads = [];
  final Map<int, Completer<Todo>> ticks = {};
  final Map<String, Completer<Todo>> adds = {};

  @override
  Future<List<Todo>> todos({QueryCancelToken? signal}) {
    final read = Completer<List<Todo>>();
    reads.add(read);
    return read.future;
  }

  @override
  Future<Todo> setDone(int id, {required bool done}) =>
      (ticks[id] = Completer<Todo>()).future;

  @override
  Future<Todo> addTodo(String text) => (adds[text] = Completer<Todo>()).future;
}

void heldTest(
  String description,
  Future<void> Function(WidgetTester tester, HeldApi api, QueryClient client)
      body,
) {
  testWidgets(description, (tester) async {
    final api = HeldApi();
    final client = QueryClient(defaultOptions: exampleDefaults);
    await tester.pumpWidget(
      QueryClientProvider(
        client: client,
        child: ApiScope(
          api: api,
          child: const MaterialApp(home: Scaffold(body: TodosTab())),
        ),
      ),
    );
    try {
      await body(tester, api, client);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      client.clear();
      await tester.pump();
      client.clear();
    }
  });
}

Finder box(String text) => find.descendant(
      of: find.widgetWithText(CheckboxListTile, text),
      matching: find.byType(Checkbox),
    );

bool? ticked(WidgetTester tester, String text) =>
    tester.widget<Checkbox>(box(text)).value;

int writing(QueryClient client) =>
    client.isMutating(filters: MutationFilters(mutationKey: Keys.todoWrites));

/// Lets what was sent and what was answered run, without stepping the clock.
Future<void> settle(WidgetTester tester) => tester.pump(Duration.zero);

void main() {
  heldTest(
      'an add answered while a refetch is in flight stays on the screen: '
      'the add cancels the read', (tester, api, client) async {
    api.reads.single.complete(seeded);
    await settle(tester);

    // A tick, alone, and the refetch its `onSettled` starts.
    await tester.tap(box(checklist));
    await settle(tester);
    api.ticks[1]!.complete(seeded.first.copyWith(done: true));
    await settle(tester);
    expect(api.reads, hasLength(2));

    // An add, answered while that read is held.
    await tester.enterText(find.byType(TextField), added);
    await tester.tap(find.text('Add'));
    await settle(tester);
    api.adds[added]!.complete(const Todo(id: 4, text: added, done: false));
    await settle(tester);
    expect(find.text(added), findsOneWidget);

    // The read answers last, with the list from before the add.
    api.reads[1].complete([seeded.first.copyWith(done: true), seeded.last]);
    await settle(tester);
    expect(find.text(added), findsOneWidget);
    expect(writing(client), 0);

    // The add was the last write: its refetch is the third read.
    expect(api.reads, hasLength(3));
    api.reads[2].complete([
      seeded.first.copyWith(done: true),
      seeded.last,
      const Todo(id: 4, text: added, done: false),
    ]);
    await settle(tester);
    expect(find.text(added), findsOneWidget);
    expect(ticked(tester, checklist), isTrue);
  });

  heldTest(
      'two ticks answered in one turn each put their answer in the list, '
      'over a read from before', (tester, api, client) async {
    api.reads.single.complete(seeded);
    await settle(tester);
    await tester.tap(box(checklist));
    await settle(tester);
    await tester.tap(box(token));
    await settle(tester);

    // A read the screen did not start, answered with the list from before
    // both ticks.
    final refetch = client.refetchQueries(
      filters: QueryFilters(queryKey: Keys.todos, exact: true),
    );
    await settle(tester);
    api.reads[1].complete(seeded);
    await settle(tester);
    await refetch;
    expect(ticked(tester, checklist), isFalse);
    expect(ticked(tester, token), isFalse);

    api.ticks[1]!.complete(seeded.first.copyWith(done: true));
    api.ticks[3]!.complete(seeded.last.copyWith(done: true));
    await settle(tester);
    expect(ticked(tester, checklist), isTrue);
    expect(ticked(tester, token), isTrue);
    expect(writing(client), 0);
    // Each counted the other in its `onSettled`, so neither refetched: the
    // count's blind spot, which PORTING_NOTES records. Each write's own
    // answer is in the list all the same.
    expect(api.reads, hasLength(2));
  });
}
