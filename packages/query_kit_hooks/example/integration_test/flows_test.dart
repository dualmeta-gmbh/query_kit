/// Every hook the app uses, on a device, against the real backend: one
/// group per hook, as the Playwright suite has one `describe` per hook.
/// What the browser suite proves by holding a request, this one proves
/// with real frames and the backend's own log.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'native_harness.dart';

const String first = 'Local development: setup guide';
const String second = 'Continuous integration: setup guide';
const String third = 'Code review: setup guide';
const String checklist = 'Update the deploy checklist';

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
      await h.configure(latencyMs: 1500);
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
  });

  group('usePrefetchQuery', () {
    nativeTest('the comments come with the post, asked for once',
        (tester, h) async {
      await openPost(tester, h);
      await waitForFact(tester, 'comments', '3 comments');
      expect(await h.requests('GET', '/api/posts/1/comments'), 1);
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
  });

  group('useQueryClient', () {
    nativeTest('the tick is written to the cache: the count moves with it',
        (tester, h) async {
      await openTodos(tester, h);
      await h.configure(latencyMs: 1500);
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
      await h.configure(latencyMs: 1500);
      await tapOn(tester, todoBox(checklist));
      await tapOn(tester, todoBox('Replace the expired API token'));
      await waitForFact(tester, 'activity', 'saving 2');
      await waitForFact(tester, 'activity', 'saving 0');
      await waitForFact(tester, 'open todos', '0 open');
    });
  });

  group('useTypedMutationState', () {
    nativeTest('an added todo is a pending row, then a todo',
        (tester, h) async {
      await openTodos(tester, h);
      await h.configure(latencyMs: 1500);
      await typeInto(tester, find.byType(TextField), 'Write the README');
      await tapOn(tester, find.text('Add'));
      await waitForFact(tester, 'todos', 'Adding: Write the README');
      await waitFor(tester, todoBox('Write the README'));
      expect(factIn('todos', 'Adding: Write the README'), findsNothing);
      await waitForFact(tester, 'open todos', '3 open');
      expect(await h.requests('POST', '/api/todos'), 1);
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
