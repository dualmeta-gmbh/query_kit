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
      'its refetch cancels that read', (tester, api, client) async {
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
      'a tick made while a refetch is in flight cancels it: the read from '
      'before would take the tick back', (tester, api, client) async {
    api.reads.single.complete(seeded);
    await settle(tester);

    // A tick, alone, and the refetch it starts as it settles.
    await tester.tap(box(checklist));
    await settle(tester);
    api.ticks[1]!.complete(seeded.first.copyWith(done: true));
    await settle(tester);
    expect(api.reads, hasLength(2));

    // A second tick while that read is held, which then answers with the
    // list from before it.
    await tester.tap(box(token));
    await settle(tester);
    expect(ticked(tester, token), isTrue);
    api.reads[1].complete([seeded.first.copyWith(done: true), seeded.last]);
    await settle(tester);
    expect(ticked(tester, token), isTrue);

    api.ticks[3]!.complete(seeded.last.copyWith(done: true));
    await settle(tester);
    expect(api.reads, hasLength(3));
    api.reads[2].complete([
      seeded.first.copyWith(done: true),
      seeded.last.copyWith(done: true),
    ]);
    await settle(tester);
    expect(ticked(tester, checklist), isTrue);
    expect(ticked(tester, token), isTrue);
  });

  heldTest(
      'two ticks answered in one turn each put their answer in the list, '
      'over a read from before, and one of them refetches',
      (tester, api, client) async {
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
    // `isMutating` in each `onSettled` would count the other, and neither
    // would refetch. The writes' own count tells the second one it is last.
    expect(api.reads, hasLength(3));
    api.reads[2].complete([
      seeded.first.copyWith(done: true),
      seeded.last.copyWith(done: true),
    ]);
    await settle(tester);
    expect(ticked(tester, checklist), isTrue);
    expect(ticked(tester, token), isTrue);
  });

  heldTest(
      'an add answered while the first load is in flight: that load is '
      'replaced, it may not have the add', (tester, api, client) async {
    await tester.enterText(find.byType(TextField), added);
    await tester.tap(find.text('Add'));
    await settle(tester);
    api.adds[added]!.complete(const Todo(id: 4, text: added, done: false));
    await settle(tester);
    expect(writing(client), 0);
    expect(api.reads, hasLength(2));

    // Served before the add was stored.
    api.reads.first.complete(seeded);
    await settle(tester);
    expect(find.text('Loading todos…'), findsOneWidget);
    api.reads[1].complete([
      ...seeded,
      const Todo(id: 4, text: added, done: false),
    ]);
    await settle(tester);
    expect(find.text(added), findsOneWidget);
  });

  heldTest(
      'two adds made before the list has loaded, answered in one turn: the '
      'last one loads it', (tester, api, client) async {
    for (final text in ['A', 'B']) {
      await tester.enterText(find.byType(TextField), text);
      await tester.tap(find.text('Add'));
      await settle(tester);
    }
    expect(api.reads, hasLength(1));

    api.adds['A']!.complete(const Todo(id: 4, text: 'A', done: false));
    api.adds['B']!.complete(const Todo(id: 5, text: 'B', done: false));
    await settle(tester);
    expect(writing(client), 0);
    // The first load is cancelled, the second answers with both.
    expect(api.reads, hasLength(2));
    api.reads.first.complete(seeded);
    await settle(tester);
    expect(find.text('Loading todos…'), findsOneWidget);
    api.reads[1].complete([
      ...seeded,
      const Todo(id: 4, text: 'A', done: false),
      const Todo(id: 5, text: 'B', done: false),
    ]);
    await settle(tester);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
  });

  heldTest(
      'a first load answered after an add, while another is in flight, is '
      'dropped: it may not have the add', (tester, api, client) async {
    for (final text in ['A', 'B']) {
      await tester.enterText(find.byType(TextField), text);
      await tester.tap(find.text('Add'));
      await settle(tester);
    }
    api.adds['A']!.complete(const Todo(id: 4, text: 'A', done: false));
    await settle(tester);
    expect(writing(client), 1);

    // Served before A was stored: a list without it.
    api.reads.first.complete(seeded);
    await settle(tester);
    expect(client.getQueryData<List<Todo>>(Keys.todos), isNull);
    expect(find.text('Loading todos…'), findsOneWidget);
    expect(api.reads, hasLength(1));

    api.adds['B']!.complete(const Todo(id: 5, text: 'B', done: false));
    await settle(tester);
    expect(api.reads, hasLength(2));
    api.reads[1].complete([
      ...seeded,
      const Todo(id: 4, text: 'A', done: false),
      const Todo(id: 5, text: 'B', done: false),
    ]);
    await settle(tester);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
  });

  heldTest(
      'an add answered after a read that has its todo leaves that row as it '
      'is: ticked since', (tester, api, client) async {
    await tester.enterText(find.byType(TextField), added);
    await tester.tap(find.text('Add'));
    await settle(tester);

    // The first load, served after the add was stored.
    api.reads.single.complete([
      ...seeded,
      const Todo(id: 4, text: added, done: false),
    ]);
    await settle(tester);
    await tester.tap(box(added));
    await settle(tester);
    expect(ticked(tester, added), isTrue);

    // The add's own answer, from before the tick.
    api.adds[added]!.complete(const Todo(id: 4, text: added, done: false));
    await settle(tester);
    expect(writing(client), 1);
    expect(ticked(tester, added), isTrue);
    expect(find.text(added), findsOneWidget);

    api.ticks[4]!.complete(const Todo(id: 4, text: added, done: true));
    await settle(tester);
    expect(api.reads, hasLength(2));
    api.reads[1].complete([
      ...seeded,
      const Todo(id: 4, text: added, done: true),
    ]);
    await settle(tester);
    expect(ticked(tester, added), isTrue);
  });

  heldTest(
      'a remount while the list has no data loads it, writes or not, and an '
      'add answered late leaves its row ticked since',
      (tester, api, client) async {
    for (final text in ['A', 'B']) {
      await tester.enterText(find.byType(TextField), text);
      await tester.tap(find.text('Add'));
      await settle(tester);
    }
    api.adds['A']!.complete(const Todo(id: 4, text: 'A', done: false));
    await settle(tester);
    expect(find.text('Loading todos…'), findsOneWidget);

    // The tab built again: a list with no data loads on mount whatever
    // `refetchOnMount` says, so this read starts with B in flight.
    await tester.pumpWidget(
      QueryClientProvider(
        client: client,
        child: ApiScope(
          api: api,
          child: const MaterialApp(
            home: Scaffold(body: TodosTab(key: ValueKey('again'))),
          ),
        ),
      ),
    );
    await settle(tester);
    expect(api.reads, hasLength(2));
    api.reads[1].complete([
      ...seeded,
      const Todo(id: 4, text: 'A', done: false),
      const Todo(id: 5, text: 'B', done: false),
    ]);
    await settle(tester);
    await tester.tap(box('B'));
    await settle(tester);
    expect(ticked(tester, 'B'), isTrue);

    api.adds['B']!.complete(const Todo(id: 5, text: 'B', done: false));
    await settle(tester);
    expect(writing(client), 1);
    expect(ticked(tester, 'B'), isTrue);

    api.ticks[5]!.complete(const Todo(id: 5, text: 'B', done: true));
    await settle(tester);
    expect(api.reads, hasLength(3));
    api.reads[2].complete([
      ...seeded,
      const Todo(id: 4, text: 'A', done: false),
      const Todo(id: 5, text: 'B', done: true),
    ]);
    await settle(tester);
    expect(ticked(tester, 'A'), isFalse);
    expect(ticked(tester, 'B'), isTrue);
  });
}
