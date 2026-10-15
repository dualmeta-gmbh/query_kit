/// Every hook the app uses, on a device, against the real backend: one
/// group per hook, as the Playwright suite has one `describe` per hook.
/// What the browser suite proves by holding a request, this one proves
/// with real frames and the backend's own log.
///
/// The backend holds nothing back on request, so a state that lasts while a
/// request is in flight is read inside the backend's latency: [slow], long
/// enough that a slow device still reads it. An order the app must keep is
/// proven where it does not hang on a window: by a failure that stops a
/// waterfall here, and by a held request in the browser. One case is the
/// exception: a tick's write gets [slow] to reach the backend before every
/// later request turns fast, because the backend reads its latency when a
/// request arrives. A device slower than that fails it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'native_harness.dart';

const String first = 'Local development: setup guide';
const String second = 'Continuous integration: setup guide';
const String third = 'Code review: setup guide';
const String lastButOne = 'Data export: setup guide';
const String last = 'Analytics events: setup guide';
const String checklist = 'Update the deploy checklist';
const String token = 'Replace the expired API token';

/// The backend's latency while a test reads a state that lasts as long as a
/// request: not a clock in an assertion, a window to read it in.
const int slow = 3000;

/// A box that takes no tick: a write for its todo is in flight.
Finder lockedBox(String text) => find.descendant(
      of: find.widgetWithText(CheckboxListTile, text),
      matching: find.byWidgetPredicate(
        (widget) => widget is Checkbox && widget.onChanged == null,
      ),
    );

Future<void> openPost(WidgetTester tester, NativeHarness h) async {
  await h.open(tester);
  await waitFor(tester, find.text(first));
  await tapOn(tester, find.text(first));
  await waitForFact(tester, 'post', first);
}

Future<void> openTodos(WidgetTester tester, NativeHarness h) async {
  await h.open(tester);
  await tapOn(tester, find.text('Todos'));
  await waitForFact(tester, 'open todos', '2 open');
}

void main() {
  initNativeBinding();

  group('useIsFetching', () {
    nativeTest('counts the list and the prefetched page, then nothing',
        (tester, h) async {
      await h.configure(latencyMs: slow);
      await h.open(tester);
      await waitForFact(tester, 'activity', 'fetching 2');
      await waitForFact(tester, 'activity', 'fetching 0');
    });
  });

  group('useQuery', () {
    nativeTest('the list, then a post', (tester, h) async {
      await openPost(tester, h);
      expect(find.text('Post 1'), findsOneWidget);
      expect(await h.requests('GET', '/api/posts'), 1);
      expect(await h.requests('GET', '/api/posts/1'), 1);
    });

    nativeTest('a tab change while a tick is in flight reads no list over it',
        (tester, h) async {
      await openTodos(tester, h);
      // The write slow, and given a window to reach the backend, which
      // reads the latency when a request arrives. Then every other request
      // fast: a read of the list now would answer long before the write,
      // with the todo unticked.
      await h.configure(latencyMs: 4 * slow);
      await tapOn(tester, todoBox(token));
      await waitFor(tester, lockedBox(token));
      await settleFor(tester, const Duration(milliseconds: slow));
      await h.configure(latencyMs: 0);

      await tapOn(tester, find.text('Posts'));
      await waitForCount(tester, groupNamed('todos'), 0);
      await tapOn(tester, find.text('Todos'));
      await waitFor(tester, lockedBox(token));
      await waitForFact(tester, 'activity', 'fetching 0');
      expect(ticked(tester, token), isTrue);
      expect(await h.requests('GET', '/api/todos'), 1);

      // The write answers, and its refetch is the only read since the first.
      await waitForFact(tester, 'activity', 'saving 0');
      await h.waitForRequests(tester, 'GET', '/api/todos', 2);
      await waitForFact(tester, 'activity', 'fetching 0');
      expect(ticked(tester, token), isTrue);
      expect(await h.requests('PATCH', '/api/todos/3'), 1);
      expect(await h.requests('GET', '/api/todos'), 2);
    });
  });

  group('usePrefetchQuery', () {
    nativeTest('the comments come with the post, asked for once',
        (tester, h) async {
      await openPost(tester, h);
      await waitForFact(tester, 'comments', '3 comments');
      expect(await h.requests('GET', '/api/posts/1/comments'), 1);
    });

    nativeTest('the comments are asked for while the post is refused',
        (tester, h) async {
      // The first attempt and the client's one retry: the post never
      // arrives, so the widget that reads the comments never exists, and
      // only the prefetch can ask for them.
      await h.configure(failNext: [
        {'method': 'GET', 'path': '/api/posts/1', 'count': 2, 'status': 503},
      ]);
      await h.open(tester);
      await waitFor(tester, find.text(first));
      await tapOn(tester, find.text(first));
      await waitFor(tester, find.text('Scripted failure 503'));
      await h.waitForRequests(tester, 'GET', '/api/posts/1/comments', 1);
      expect(groupNamed('comments'), findsNothing);
      expect(await h.requests('GET', '/api/posts/1'), 2);
    });
  });

  group('useSelectQuery', () {
    nativeTest('the open count, from the todos', (tester, h) async {
      await openTodos(tester, h);
      expect(await h.requests('GET', '/api/todos'), 1);
    });
  });

  group('useCombinedQueries', () {
    nativeTest('up next, and the next post from the cache', (tester, h) async {
      await openPost(tester, h);
      await waitForFact(tester, 'up next', 'Up next: $second, then $third');
      await tapOn(tester, find.text('Next post'));
      await waitFor(tester, find.text('Post 2'));
      await waitForFact(tester, 'post', second);
      expect(await h.requests('GET', '/api/posts/2'), 1);
    });

    nativeTest('one post left is an answer of one, and none is no answer',
        (tester, h) async {
      await h.open(tester);
      await waitFor(tester, find.text(first));
      await tester.scrollUntilVisible(
        find.text(lastButOne),
        300,
        scrollable: find.descendant(
          of: groupNamed('posts'),
          matching: find.byType(Scrollable),
        ),
      );
      await tapOn(tester, find.text(lastButOne));
      await waitForFact(tester, 'up next', 'Up next: $last');
      await tapOn(tester, find.text('Next post'));
      await waitForFact(tester, 'post', last);
      // The replaced screen, and its up next, leave when the entrance ends.
      await waitForCount(tester, groupNamed('up next'), 0);
      expect(find.text('Post 30'), findsOneWidget);
    });
  });

  group('useQueries', () {
    nativeTest('the posts opened, newest first', (tester, h) async {
      await openPost(tester, h);
      await waitForFact(tester, 'up next', 'Up next: $second, then $third');
      await tapOn(tester, find.text('Next post'));
      await waitFor(tester, find.text('Post 2'));
      // The replaced screen leaves when the new one's entrance is over.
      await waitForCount(tester, find.byType(BackButton), 1);
      await tapOn(tester, find.byType(BackButton));
      await waitFor(tester, groupNamed('recently viewed'));
      final viewed = find.descendant(
        of: groupNamed('recently viewed'),
        matching: find.byType(OutlinedButton),
      );
      await waitForCount(tester, viewed, 2);
      expect(
        [
          for (final button in tester.widgetList<OutlinedButton>(viewed))
            (button.child! as Text).data,
        ],
        [second, first],
      );
      expect(await h.requests('GET', RegExp(r'^/api/posts/[12]$')), 2);
    });
  });

  group('useMutation', () {
    nativeTest('a tick reaches the backend', (tester, h) async {
      await openTodos(tester, h);
      await tapOn(tester, todoBox(checklist));
      expect(ticked(tester, checklist), isTrue);
      await waitForFact(tester, 'activity', 'saving 0');
      expect(ticked(tester, checklist), isTrue);
      final todos = await h.read('/todos') as List<Object?>;
      expect((todos.first! as Map<String, Object?>)['done'], isTrue);
    });

    nativeTest('a todo with a write in flight takes no second tick',
        (tester, h) async {
      await openTodos(tester, h);
      await h.configure(latencyMs: slow);
      await tapOn(tester, todoBox(checklist));
      await waitFor(tester, lockedBox(checklist));
      expect(lockedBox(token), findsNothing);
      await waitForFact(tester, 'activity', 'saving 0');
      await waitForCount(tester, lockedBox(checklist), 0);
      expect(ticked(tester, checklist), isTrue);
      expect(await h.requests('PATCH', '/api/todos/1'), 1);
    });
  });

  group('useQueryClient', () {
    nativeTest('the tick is written to the cache: the count moves with it',
        (tester, h) async {
      await openTodos(tester, h);
      await h.configure(latencyMs: slow);
      await tapOn(tester, todoBox(checklist));
      await waitForFact(tester, 'open todos', '1 open');
      expect(await h.requests('PATCH', '/api/todos/1'), 0);
      await waitForFact(tester, 'activity', 'saving 0');
      expect(await h.requests('PATCH', '/api/todos/1'), 1);
    });
  });

  group('useMutationState', () {
    nativeTest('a refused tick is taken back and counted', (tester, h) async {
      await openTodos(tester, h);
      await h.configure(failNext: [
        {
          'method': 'PATCH',
          'path': '/api/todos/1',
          'count': 1,
          'status': 409,
          'message': 'Taken',
        },
      ]);
      await tapOn(tester, todoBox(checklist));
      await waitForFact(tester, 'activity', 'failed 1');
      await waitForFact(tester, 'activity', 'last failure: Taken');
      expect(ticked(tester, checklist), isFalse);
      await waitForFact(tester, 'open todos', '2 open');
    });
  });

  group('useIsMutating', () {
    nativeTest('counts the writes in flight', (tester, h) async {
      await openTodos(tester, h);
      await h.configure(latencyMs: slow);
      await tapOn(tester, todoBox(checklist));
      await tapOn(tester, todoBox(token));
      await waitForFact(tester, 'activity', 'saving 2');
      await waitForFact(tester, 'activity', 'saving 0');
      await waitForFact(tester, 'open todos', '0 open');
    });
  });

  group('useTypedMutationState', () {
    nativeTest('an added todo is a pending row, then a todo',
        (tester, h) async {
      await openTodos(tester, h);
      await h.configure(latencyMs: slow);
      await typeInto(tester, find.byType(TextField), 'Write the README');
      await tapOn(tester, find.text('Add'));
      await waitForFact(tester, 'todos', 'Adding: Write the README');
      await waitFor(tester, todoBox('Write the README'));
      expect(factIn('todos', 'Adding: Write the README'), findsNothing);
      await waitForFact(tester, 'open todos', '3 open');
      expect(await h.requests('POST', '/api/todos'), 1);
    });

    nativeTest('two adds in flight outlive the tab that started them',
        (tester, h) async {
      await openTodos(tester, h);
      // Two adds and two tab changes inside one window: twice the usual.
      await h.configure(latencyMs: 2 * slow);
      for (final text in ['Write the README', 'Tag the release']) {
        await typeInto(tester, find.byType(TextField), text);
        await tapOn(tester, find.text('Add'));
        await waitForFact(tester, 'todos', 'Adding: $text');
      }
      await tapOn(tester, find.text('Posts'));
      await waitForCount(tester, groupNamed('todos'), 0);
      await tapOn(tester, find.text('Todos'));
      await waitForFact(tester, 'todos', 'Adding: Write the README');
      expect(factIn('todos', 'Adding: Tag the release'), findsOneWidget);
      expect(factIn('activity', 'saving 2'), findsOneWidget);
      expect(await h.requests('POST', '/api/todos'), 0);

      await waitForFact(tester, 'open todos', '4 open');
      await waitFor(tester, todoBox('Tag the release'));
      await waitForCount(tester, find.textContaining('Adding: '), 0);
      expect(await h.requests('POST', '/api/todos'), 2);
    });
  });

  group('usePrefetchInfiniteQuery', () {
    nativeTest('the first page is fetched before its tab exists',
        (tester, h) async {
      await h.open(tester);
      await waitFor(tester, find.text(first));
      await waitForFact(tester, 'activity', 'fetching 0');
      expect(await h.requests('GET', '/api/projects'), 1);
      await tapOn(tester, find.text('Projects'));
      await waitForFact(tester, 'projects', '10 projects loaded');
      expect(await h.requests('GET', '/api/projects'), 1);
    });
  });

  group('useInfiniteQuery', () {
    nativeTest('a page at a time', (tester, h) async {
      await h.open(tester);
      await tapOn(tester, find.text('Projects'));
      await waitForFact(tester, 'projects', '10 projects loaded');
      await tapOn(tester, find.text('Load more'));
      await waitForFact(tester, 'projects', '20 projects loaded');
      expect(await h.requests('GET', '/api/projects'), 2);
    });
  });
}
