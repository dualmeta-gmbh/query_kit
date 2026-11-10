/// The `typed-queries` screen against the fake backend.
///
/// Four strips, five readers and the two toolbars are more than the default
/// 800×600 view holds, and the scaffold builds its children lazily, so every
/// test starts by making the view taller.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';
import 'package:showcase/features/typed_queries/typed_queries_screen.dart';
import 'package:showcase/shared/models.dart';

import '../fake_backend.dart';
import '../harness.dart';

/// A view tall enough for every card and every strip.
void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

const String firstTitle = 'Local development: setup guide';
const String secondTitle = 'Continuous integration: setup guide';

Finder reader(String name, String text) => factIn('reader $name', text);

Future<void> press(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

/// Every strip's fetch count at once: `post 1`, `post 2`, `posts`, `time`.
void expectFetches(Harness h, int post1, int post2, int posts, int time) {
  expect(h.fact('post 1', 'fetches=$post1'), findsOneWidget);
  expect(h.fact('post 2', 'fetches=$post2'), findsOneWidget);
  expect(h.fact('posts', 'fetches=$posts'), findsOneWidget);
  expect(h.fact('time', 'fetches=$time'), findsOneWidget);
}

void main() {
  showcaseTest(
      'each entry is fetched once, and the raw reader of post 1 shares the '
      "typed reader's entry", (tester, h) async {
    tall(tester);
    await h.open(tester, '/typed-queries');

    expect(reader('post 1', 'title=$firstTitle'), findsOneWidget);
    expect(reader('raw post 1', 'title=$firstTitle'), findsOneWidget);
    expect(reader('post 2', 'title=$secondTitle'), findsOneWidget);
    expect(reader('posts', 'count=30'), findsOneWidget);
    expect(reader('posts', 'first=$firstTitle'), findsOneWidget);
    expect(reader('time', 'serial=1'), findsOneWidget);
    expectFetches(h, 1, 1, 1, 1);
    // Two observers, one entry, one request.
    expect(h.fact('post 1', 'observers=2'), findsOneWidget);
    expect(h.fact('post 2', 'observers=1'), findsOneWidget);
    expect(h.requests('GET', '/api/posts/1'), 1);
    expect(h.requests('GET', '/api/posts/2'), 1);
    expect(h.requests('GET', '/api/posts'), 1);
    expect(h.requests('GET', '/api/time'), 1);
    expect(factIn('typed facts', 'readAll=2'), findsOneWidget);
    expect(factIn('typed facts', 'equalRefs=true'), findsOneWidget);

    // The keys are the ones the declarations say, and the cache holds the
    // declared types: the raw client reads them with the type written out.
    expect(
      h.client
          .getQueryData<Post>(
              QueryKey(const <Object?>['typed-queries', 'posts', 'detail', 1]))
          ?.title,
      firstTitle,
    );
    expect(
      h.client
          .getQueryData<List<Post>>(
              QueryKey(const <Object?>['typed-queries', 'posts', 'list']))
          ?.length,
      30,
    );
    expect(TypedPostQueries(h.api).detail(1).read(h.client)?.title, firstTitle);
  });

  showcaseTest(
      'Write post 1 puts the value into the entry with no request, and the '
      'raw reader shows it too', (tester, h) async {
    tall(tester);
    await h.open(tester, '/typed-queries');
    expect(h.fact('post 1', 'updates=1'), findsOneWidget);

    await press(tester, 'Write post 1');

    expect(reader('post 1', 'title=$writtenTitle'), findsOneWidget);
    expect(reader('raw post 1', 'title=$writtenTitle'), findsOneWidget);
    expect(reader('post 2', 'title=$secondTitle'), findsOneWidget);
    expect(h.fact('post 1', 'updates=2'), findsOneWidget);
    expect(h.fact('post 1', 'fetchStatus=idle'), findsOneWidget);
    expectFetches(h, 1, 1, 1, 1);
    expect(h.requests('GET', '/api/posts/1'), 1);
    // Written as the declared type, so the typed read takes it back.
    expect(
        TypedPostQueries(h.api).detail(1).read(h.client)?.title, writtenTitle);
  });

  showcaseTest('Update post 2 derives the new title from the cached one',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/typed-queries');

    await press(tester, 'Update post 2');

    expect(reader('post 2', 'title=$secondTitle (updated)'), findsOneWidget);
    expect(reader('post 1', 'title=$firstTitle'), findsOneWidget);
    expect(h.fact('post 2', 'updates=2'), findsOneWidget);
    expect(h.fact('post 1', 'updates=1'), findsOneWidget);
    expectFetches(h, 1, 1, 1, 1);
    expect(h.requests('GET', '/api/posts/2'), 1);
  });

  showcaseTest(
      'Patch every detail runs over both cached details and not the list',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/typed-queries');

    await press(tester, 'Patch every detail');

    expect(reader('post 1', 'title=$firstTitle (patched)'), findsOneWidget);
    expect(reader('raw post 1', 'title=$firstTitle (patched)'), findsOneWidget);
    expect(reader('post 2', 'title=$secondTitle (patched)'), findsOneWidget);
    expect(h.fact('post 1', 'updates=2'), findsOneWidget);
    expect(h.fact('post 2', 'updates=2'), findsOneWidget);
    // The list is a sibling of the family, not a member of it.
    expect(reader('posts', 'first=$firstTitle'), findsOneWidget);
    expect(h.fact('posts', 'updates=1'), findsOneWidget);
    expectFetches(h, 1, 1, 1, 1);
    expect(h.backend.log.where((entry) => entry.method == 'GET'), hasLength(4));
  });

  showcaseTest('Invalidate post 1 refetches exactly that entry',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/typed-queries');

    await press(tester, 'Invalidate post 1');

    expectFetches(h, 2, 1, 1, 1);
    // One refetch for the entry, whichever of its two observers asked.
    expect(h.requests('GET', '/api/posts/1'), 2);
    expect(h.requests('GET', '/api/posts/2'), 1);
    expect(h.requests('GET', '/api/posts'), 1);
    expect(h.requests('GET', '/api/time'), 1);
    expect(h.fact('post 1', 'isStale=false'), findsOneWidget);
  });

  showcaseTest('Invalidate details refetches every detail and not the list',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/typed-queries');

    await press(tester, 'Invalidate details');

    expectFetches(h, 2, 2, 1, 1);
    expect(h.requests('GET', '/api/posts/1'), 2);
    expect(h.requests('GET', '/api/posts/2'), 2);
    expect(h.requests('GET', '/api/posts'), 1);
    expect(h.requests('GET', '/api/time'), 1);
  });

  showcaseTest(
      'Invalidate posts refetches everything under the namespace and not the '
      'time beside it', (tester, h) async {
    tall(tester);
    await h.open(tester, '/typed-queries');

    await press(tester, 'Invalidate posts');

    expectFetches(h, 2, 2, 2, 1);
    expect(h.requests('GET', '/api/posts/1'), 2);
    expect(h.requests('GET', '/api/posts/2'), 2);
    expect(h.requests('GET', '/api/posts'), 2);
    expect(h.requests('GET', '/api/time'), 1);
    expect(reader('time', 'serial=1'), findsOneWidget);
  });

  showcaseTest(
      'a write is replaced by the refetch an invalidation asks for, in both '
      'readers', (tester, h) async {
    tall(tester);
    await h.open(tester, '/typed-queries');
    await press(tester, 'Write post 1');
    expect(reader('raw post 1', 'title=$writtenTitle'), findsOneWidget);

    await press(tester, 'Invalidate post 1');

    expect(reader('post 1', 'title=$firstTitle'), findsOneWidget);
    expect(reader('raw post 1', 'title=$firstTitle'), findsOneWidget);
    expectFetches(h, 2, 1, 1, 1);
  });

  showcaseTest(
      'an api replaced under the open screen fetches every next refetch '
      'through the replacement', (tester, h) async {
    tall(tester);
    await h.open(tester, '/typed-queries');
    expect(h.backend.log, hasLength(4));

    final replacement = FakeBackend();
    addTearDown(replacement.close);
    await h.replaceApi(tester, '/typed-queries', replacement);
    final refetch = h.client.invalidateQueries();
    await tester.pumpAndSettle();
    await refetch;

    // Both definitions were made again over the new api: every entry was
    // refetched there — post 2, the list and the time have typed readers
    // only — and the old backend heard nothing more.
    expect(replacement.count('GET', '/api/posts/1'), 1);
    expect(replacement.count('GET', '/api/posts/2'), 1);
    expect(replacement.count('GET', '/api/posts'), 1);
    expect(replacement.count('GET', '/api/time'), 1);
    expect(h.backend.log, hasLength(4));
  });

  showcaseTest('leaving the screen releases every observer', (tester, h) async {
    tall(tester);
    await h.open(tester, '/typed-queries');
    expect(
      h.client.queryCache.queries.map((query) => query.observersCount),
      <int>[2, 1, 1, 1],
    );

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('query_kit showcase'), findsOneWidget);
    expect(
      h.client.queryCache.queries.map((query) => query.observersCount),
      everyElement(0),
    );
  });
}
