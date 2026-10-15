// The app, tab by tab, against its in-memory backend: every hook it uses,
// read where a user would see it. No clock in an assertion: time is stepped
// a request's latency at a time, and what was asked of the backend is read
// from its log.
//
// The name is not an accident. `flutter create .`, which the README asks
// for to run the app from the package archive, writes a template
// `test/widget_test.dart` for a counter app that does not exist here, unless
// the file is already there.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_hooks/query_kit_hooks.dart';
import 'package:query_kit_hooks_example/src/queries.dart';
import 'package:query_kit_hooks_example/src/todos.dart';

import 'harness.dart';

const String firstPost = 'Local development: setup guide';
const String secondPost = 'Continuous integration: setup guide';
const String thirdPost = 'Code review: setup guide';
const String lastButOnePost = 'Data export: setup guide';
const String lastPost = 'Analytics events: setup guide';
const String checklist = 'Update the deploy checklist';
const String token = 'Replace the expired API token';

void main() {
  group('the shell', () {
    exampleTest(
        'useIsFetching counts the list and the prefetched projects, '
        'then nothing', (run) async {
      expect(run.textsIn('activity'), contains('fetching 2'));
      expect(find.text('Loading posts…'), findsOneWidget);

      await run.answer();
      expect(run.textsIn('activity'), contains('fetching 0'));
      expect(find.text(firstPost), findsOneWidget);
    });

    exampleTest(
        'usePrefetchInfiniteQuery: the projects tab opens on the page '
        'fetched before it was built', (run) async {
      await run.answer();
      expect(run.backend.count('GET', '/api/projects'), 1);

      await run.tapText('Projects');
      expect(find.text('Loading projects…'), findsNothing);
      expect(run.textsIn('projects'), contains('10 projects loaded'));
      expect(run.backend.count('GET', '/api/projects'), 1);
    });
  });

  group('posts', () {
    exampleTest(
        'usePrefetchQuery: a post and its comments arrive together, not one '
        'after the other', (run) async {
      await run.answer();
      await run.tapText(firstPost);
      await run.wait(const Duration(milliseconds: 400));
      // One latency after the tap, both answers are in: the comments did not
      // wait for the post's widget to be built before they were asked for.
      expect(run.textsIn('post'), contains(firstPost));
      expect(run.textsIn('comments'), contains('3 comments'));
      expect(run.backend.count('GET', '/api/posts/1/comments'), 1);
    });

    exampleTest(
        'useCombinedQueries and useSelectQuery: up next names the two '
        'following posts, and the next post opens from the cache', (run) async {
      await run.answer();
      await run.tapText(firstPost);
      await run.wait(const Duration(milliseconds: 400));
      expect(run.textsIn('up next'), ['Up next: loading…']);

      await run.answer();
      expect(
        run.textsIn('up next'),
        ['Up next: $secondPost, then $thirdPost', 'Next post'],
      );

      await run.tapText('Next post');
      await run.wait(const Duration(milliseconds: 400));
      expect(find.text('Post 2'), findsOneWidget);
      expect(run.textsIn('post'), contains(secondPost));
      expect(run.backend.count('GET', '/api/posts/2'), 1);
    });

    exampleTest(
        'useCombinedQueries: one post left is an answer of one, and none is '
        'no answer', (run) async {
      await run.answer();
      await run.tester.scrollUntilVisible(
        find.text(lastButOnePost),
        300,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('posts')),
          matching: find.byType(Scrollable),
        ),
      );
      await run.tapText(lastButOnePost);
      await run.wait(const Duration(milliseconds: 400));
      await run.answer();
      expect(run.textsIn('up next'), ['Up next: $lastPost', 'Next post']);

      await run.tapText('Next post');
      await run.wait(const Duration(seconds: 1));
      expect(find.text('Post 30'), findsOneWidget);
      expect(run.textsIn('post'), contains(lastPost));
      expect(find.byKey(const ValueKey('up next')), findsNothing);
    });

    exampleTest(
        'useCombinedQueries: one failure fails the answer, and retry asks '
        'again', (run) async {
      // The first attempt and the client's one retry.
      run.backend.failNext('GET', '/api/posts/3', count: 2);
      await run.answer();
      await run.tapText(firstPost);
      await run.wait(const Duration(milliseconds: 400));
      await run.answer();
      await run.wait(const Duration(seconds: 1));
      await run.answer();
      expect(
        run.textsIn('up next'),
        ['Up next failed: Scripted failure 500. Try again'],
      );

      await run.tapText('Up next failed: Scripted failure 500. Try again');
      expect(run.textsIn('up next'), ['Up next: loading…']);
      await run.answer();
      expect(
        run.textsIn('up next'),
        ['Up next: $secondPost, then $thirdPost', 'Next post'],
      );
      expect(run.backend.count('GET', '/api/posts/2'), 1);
    });

    exampleTest(
        'useQueries: recently viewed lists the posts opened, newest first, '
        'from the cache', (run) async {
      await run.answer();
      expect(find.text('Recently viewed'), findsNothing);

      await run.tapText(firstPost);
      await run.wait(const Duration(milliseconds: 400));
      await run.answer();
      await run.tapText('Next post');
      // The replaced screen leaves when the new one's entrance is over, and
      // only then is there one back button.
      await run.wait(const Duration(seconds: 1));
      await run.tester.tap(find.byType(BackButton));
      await run.wait(const Duration(seconds: 1));

      expect(
        run.textsIn('recently viewed'),
        ['Recently viewed', secondPost, firstPost],
      );
      expect(run.backend.count('GET', '/api/posts/1'), 1);
      expect(run.backend.count('GET', '/api/posts/2'), 1);
    });
  });

  group('todos', () {
    Future<void> openTodos(ExampleRun run) async {
      await run.answer();
      await run.tapText('Todos');
      expect(run.textsIn('open todos'), ['… open']);
      await run.answer();
      expect(run.textsIn('open todos'), ['2 open']);
    }

    Finder checkbox(String text) => find.descendant(
          of: find.widgetWithText(CheckboxListTile, text),
          matching: find.byType(Checkbox),
        );

    bool? ticked(ExampleRun run, String text) =>
        run.tester.widget<Checkbox>(checkbox(text)).value;

    exampleTest(
        'useMutation: a tick shows before the backend has it, and stays',
        (run) async {
      await openTodos(run);
      await run.tester.tap(checkbox(checklist));
      await run.tester.pump();
      expect(ticked(run, checklist), isTrue);
      expect(run.textsIn('open todos'), ['1 open']);
      expect(run.textsIn('activity'), contains('saving 1'));

      // The write, then the refetch its invalidation starts.
      await run.answer();
      await run.answer();
      expect(ticked(run, checklist), isTrue);
      expect(run.textsIn('activity'), contains('saving 0'));
      expect(run.backend.todos.first['done'], isTrue);
    });

    exampleTest(
        'useMutation and useMutationState: a refused tick is taken back, '
        'and the failure counted', (run) async {
      run.backend.failNext('PATCH', '/api/todos/1');
      await openTodos(run);
      await run.tester.tap(checkbox(checklist));
      await run.tester.pump();
      expect(ticked(run, checklist), isTrue);

      // The refusal: `onError` puts the list back at once.
      await run.answer();
      expect(ticked(run, checklist), isFalse);
      expect(run.textsIn('open todos'), ['2 open']);
      // `onSettled` returns the refetch it starts, so the mutation is pending
      // until the list is reloaded, and counts as failed after.
      expect(run.textsIn('activity'), containsAll(['saving 1', 'failed 0']));
      await run.answer();
      expect(
        run.textsIn('activity'),
        containsAll([
          'saving 0',
          'failed 1',
          'last failure: Scripted failure 500',
        ]),
      );
      expect(ticked(run, checklist), isFalse);
      expect(run.backend.todos.first['done'], isFalse);
    });

    exampleTest(
        'useTypedMutationState and useIsMutating: an added todo shows as '
        'pending until the backend has it, then as a todo', (run) async {
      await openTodos(run);
      await run.tester.enterText(find.byType(TextField), 'Write the README');
      await run.tapText('Add');
      expect(run.textsIn('todos'), contains('Adding: Write the README'));
      expect(run.textsIn('activity'), contains('saving 1'));

      // The answer goes into the list in the frame the pending row leaves.
      await run.answer();
      expect(run.textsIn('todos'), isNot(contains('Adding: Write the README')));
      expect(run.textsIn('todos'), contains('Write the README'));
      expect(run.textsIn('open todos'), ['3 open']);
      expect(run.textsIn('activity'), contains('saving 0'));

      // The refetch it starts finds the same todo, once.
      await run.answer();
      expect(
        run.textsIn('todos').where((text) => text == 'Write the README'),
        hasLength(1),
      );
      expect(run.backend.count('GET', '/api/todos'), 2);
    });

    exampleTest(
        'useTypedMutationState: every add in flight is a row, and the rows '
        'outlive the screen that started them', (run) async {
      await openTodos(run);
      for (final text in ['Write the README', 'Tag the release']) {
        await run.tester.enterText(find.byType(TextField), text);
        await run.tapText('Add');
      }
      expect(
        run.textsIn('todos'),
        containsAll(['Adding: Write the README', 'Adding: Tag the release']),
      );

      // Away and back: the tab is built anew, and the adds are in the
      // mutation cache, not in the screen.
      await run.tapText('Posts');
      await run.tapText('Todos');
      expect(
        run.textsIn('todos'),
        containsAll(['Adding: Write the README', 'Adding: Tag the release']),
      );
      expect(run.textsIn('activity'), contains('saving 2'));

      await run.answer();
      await run.answer();
      expect(
        run.textsIn('todos'),
        containsAll(['Write the README', 'Tag the release']),
      );
      expect(run.textsIn('todos'), everyElement(isNot(startsWith('Adding: '))));
      expect(run.textsIn('open todos'), ['4 open']);
    });

    exampleTest(
        'useSelectQuery: the open count rebuilds when the number moves, not '
        'for a refetch', (run) async {
      await openTodos(run);
      var builds = 0;
      debugOnRebuildDirtyWidget = (element, _) {
        if (element.widget is OpenCount) {
          builds += 1;
        }
      };
      addTearDown(() => debugOnRebuildDirtyWidget = null);

      // A refetch the list shows running, and that changes no number.
      run.client
          .refetchQueries(filters: QueryFilters(queryKey: Keys.todos))
          .ignore();
      await run.tester.pump();
      expect(run.textsIn('activity'), contains('fetching 1'));
      await run.answer();
      expect(run.textsIn('activity'), contains('fetching 0'));
      expect(run.backend.count('GET', '/api/todos'), 2);
      expect(builds, 0);

      // A tick moves it.
      await run.tester.tap(checkbox(checklist));
      await run.tester.pump();
      expect(run.textsIn('open todos'), ['1 open']);
      expect(builds, 1);
      await run.answer();
      await run.answer();
    });

    exampleTest(
        "useMutation: a tick answered first leaves another todo's tick in "
        'flight alone', (run) async {
      await openTodos(run);
      await run.tester.tap(checkbox(checklist));
      await run.tester.pump();
      // The second write is slower than the first.
      run.backend.latency = const Duration(milliseconds: 900);
      await run.tester.tap(checkbox(token));
      await run.tester.pump();
      run.backend.latency = latency;

      // The first answers. Had it refetched the list, the second tick would
      // be gone by the time that refetch answered.
      await run.answer();
      expect(run.textsIn('activity'), contains('saving 1'));
      await run.answer();
      expect(ticked(run, token), isTrue);
      expect(run.textsIn('open todos'), ['0 open']);

      // The second answers last, and its refetch agrees.
      await run.answer();
      await run.answer();
      expect(run.textsIn('activity'), contains('saving 0'));
      expect(ticked(run, checklist), isTrue);
      expect(ticked(run, token), isTrue);
      expect(run.backend.count('GET', '/api/todos'), 2);
      expect(
        [for (final todo in run.backend.todos) todo['done']],
        everyElement(isTrue),
      );
    });

    exampleTest(
        'useMutation: a todo whose tick is in flight takes no second one',
        (run) async {
      await openTodos(run);
      Checkbox box() => run.tester.widget<Checkbox>(checkbox(checklist));
      await run.tester.tap(checkbox(checklist));
      await run.tester.pump();
      expect(box().onChanged, isNull);
      await run.tester.tap(checkbox(checklist), warnIfMissed: false);
      await run.tester.pump();
      expect(ticked(run, checklist), isTrue);
      expect(run.textsIn('activity'), contains('saving 1'));

      // The write, then the refetch it starts: the box takes ticks again.
      await run.answer();
      await run.answer();
      expect(box().onChanged, isNotNull);
      expect(run.backend.count('PATCH', '/api/todos/1'), 1);
      expect(run.backend.todos.first['done'], isTrue);
    });

    exampleTest(
        'useMutation: a refused tick takes back its own todo, and only it',
        (run) async {
      run.backend.failNext('PATCH', '/api/todos/1');
      await openTodos(run);
      // The refused write starts first, so the list it saw had neither tick.
      await run.tester.tap(checkbox(checklist));
      await run.tester.pump();
      await run.tester.tap(checkbox(token));
      await run.tester.pump();
      expect(run.textsIn('open todos'), ['0 open']);

      await run.answer();
      expect(ticked(run, checklist), isFalse);
      expect(ticked(run, token), isTrue);
      expect(run.textsIn('open todos'), ['1 open']);
      await run.answer();
      expect(run.textsIn('activity'), containsAll(['saving 0', 'failed 1']));
      expect(ticked(run, token), isTrue);
      expect(run.backend.todos.last['done'], isTrue);
    });

    exampleTest(
        'useMutation: an add answered while a tick is in flight keeps the '
        'tick, and shows the todo', (run) async {
      await openTodos(run);
      run.backend.latency = const Duration(milliseconds: 900);
      await run.tester.tap(checkbox(token));
      await run.tester.pump();
      run.backend.latency = latency;
      await run.tester.enterText(find.byType(TextField), 'Write the README');
      await run.tapText('Add');

      await run.answer();
      expect(run.textsIn('todos'), contains('Write the README'));
      expect(run.textsIn('todos'), isNot(contains('Adding: Write the README')));
      await run.answer();
      expect(ticked(run, token), isTrue);
      expect(run.textsIn('open todos'), ['2 open']);

      await run.answer();
      await run.answer();
      expect(run.textsIn('activity'), contains('saving 0'));
      expect(ticked(run, token), isTrue);
      expect(run.textsIn('todos'), contains('Write the README'));
      expect(run.backend.todos.last['text'], 'Write the README');
    });
  });

  group('projects', () {
    exampleTest('useInfiniteQuery: a page at a time, to the last', (run) async {
      await run.answer();
      await run.tapText('Projects');
      expect(run.textsIn('projects'), contains('Load more'));

      await run.tapText('Load more');
      expect(run.textsIn('projects'), contains('Loading more…'));
      await run.answer();
      expect(run.textsIn('projects'), contains('20 projects loaded'));

      for (var page = 3; page <= 10; page++) {
        await run.tapText('Load more');
        await run.answer();
      }
      expect(
        run.textsIn('projects'),
        containsAll(['100 projects loaded', 'All loaded']),
      );
      expect(run.backend.count('GET', '/api/projects'), 10);
    });
  });
}
