/// The `combine` screen against the fake backend.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showcase/features/combine/combine_screen.dart';
import 'package:showcase/shared/models.dart';

import '../fake_backend.dart';
import '../harness.dart';

/// The backend's latency in the cases that look at the screen between a
/// request and its answer.
const Duration latency = Duration(milliseconds: 300);

const String postPath = '/api/posts/1';
const String commentsPath = '/api/posts/1/comments';
const String counterPath = '/api/counter';

/// Opens the screen on a view tall enough for the controls, the three strips
/// and the combined card: the scaffold's list builds only what is in view.
Future<void> open(WidgetTester tester, Harness h, {bool settle = true}) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await h.open(tester, '/combine', settle: settle);
}

/// The seed's rows, parsed: what the backend answers for post 1, without a
/// request — a test body runs on the binding's fake clock, where awaiting dio
/// would wait for a timer nobody steps.
List<T> seeded<T>(String name, T Function(Map<String, Object?> json) parse) =>
    (FakeBackend.seed()[name]! as List<Object?>)
        .map((row) => parse(row! as Map<String, Object?>))
        .toList();

final Post seedPost = seeded('posts', Post.fromJson).first;

final List<Comment> seedComments = seeded('comments', Comment.fromJson)
    .where((comment) => comment.postId == seedPost.id)
    .toList();

Finder combined(String text) => factIn('combined', text);

Finder overview(String text) => factIn('overview', text);

Finder details(String text) => factIn('details', text);

Finder pinned(String text) => factIn('pinned', text);

/// The list, every detail, and the third detail alone.
const String listPath = '/api/posts';
final RegExp detailPaths = RegExp(r'^/api/posts/[234]$');
const String thirdDetailPath = '/api/posts/4';

/// The post behind each pinned choice.
const String pinnedPath = '/api/posts/5';
const String deletedPath = '/api/posts/999';

/// Brings the list section into view and lets its reads land.
Future<void> showList(WidgetTester tester) async {
  await tester.scrollUntilVisible(groupNamed('pinned'), 300,
      scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

Future<void> press(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

/// The number behind `key=` in the `combined` group.
int combinedNumber(WidgetTester tester, String key) {
  final text = tester
      .widgetList<Text>(find.descendant(
        of: groupNamed('combined'),
        matching: find.byType(Text),
      ))
      .map((widget) => widget.data!)
      .singleWhere((data) => data.startsWith('$key='));
  return int.parse(text.substring(key.length + 1));
}

Future<void> refusePost(WidgetTester tester) async {
  await tester.tap(find.text('is refused'));
  await tester.pumpAndSettle();
}

Future<void> answerPost(WidgetTester tester) async {
  await tester.tap(find.text('answers'));
  await tester.pumpAndSettle();
}

void main() {
  showcaseTest('pending until every source has data, then the combination',
      (tester, h) async {
    // Two of the three are in the cache before the screen is. Stale, so all
    // three fetch on mount — but only the counter has nothing to show.
    h.client.setQueryData<Post>(combinePostKey, seedPost);
    h.client.setQueryData<List<Comment>>(combineCommentsKey, seedComments);
    h.backend.latency = latency;

    await open(tester, h, settle: false);
    await tester.pump();

    expect(h.fact('post', 'status=success'), findsOneWidget);
    expect(h.fact('comments', 'status=success'), findsOneWidget);
    expect(h.fact('counter', 'status=pending'), findsOneWidget);
    expect(combined('state=pending'), findsOneWidget);
    expect(combined('isFetching=true'), findsOneWidget);
    // The combiner has nothing to run on yet.
    expect(combined('combines=0'), findsOneWidget);
    expect(groupNamed('overview'), findsNothing);

    await tester.pump(latency);
    await tester.pumpAndSettle();

    expect(combined('state=data'), findsOneWidget);
    expect(combined('isFetching=false'), findsOneWidget);
    expect(combined('combines=1'), findsOneWidget);
    expect(find.text(seedPost.title), findsOneWidget);
    expect(overview('comments=3'), findsOneWidget);
    expect(overview('counter=0'), findsOneWidget);
    expect(overview('refetchError=none'), findsOneWidget);
  });

  showcaseTest(
      'a source that failed with nothing to show is the error, and retry '
      'refetches only it', (tester, h) async {
    h.backend.failNext('GET', postPath);

    await open(tester, h);

    expect(h.fact('post', 'status=error'), findsOneWidget);
    expect(h.fact('comments', 'status=success'), findsOneWidget);
    expect(h.fact('counter', 'status=success'), findsOneWidget);
    expect(combined('state=error'), findsOneWidget);
    expect(combined('combines=0'), findsOneWidget);
    expect(find.text('Scripted failure 500'), findsOneWidget);
    expect(groupNamed('overview'), findsNothing);
    // `RetryPolicy.never`: refused once, asked once.
    expect(h.requests('GET', postPath), 1);
    expect(h.requests('GET', commentsPath), 1);
    expect(h.requests('GET', counterPath), 1);

    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(combined('state=data'), findsOneWidget);
    expect(combined('combines=1'), findsOneWidget);
    expect(overview('comments=3'), findsOneWidget);
    expect(find.text('Scripted failure 500'), findsNothing);
    // `retry()` went to the failed source and left the other two alone.
    expect(h.requests('GET', postPath), 2);
    expect(h.requests('GET', commentsPath), 1);
    expect(h.requests('GET', counterPath), 1);
  });

  showcaseTest('a failed background refetch keeps the data as refetchError',
      (tester, h) async {
    await open(tester, h);
    expect(combined('state=data'), findsOneWidget);
    final title = seedPost.title;
    h.backend.log.clear();

    await refusePost(tester);
    h.backend.latency = latency;
    await tester.tap(find.text('Refetch all'));
    await tester.pump();

    // `isFetching` is "any source is", and the content stays where it is.
    expect(combined('isFetching=true'), findsOneWidget);
    expect(combined('state=data'), findsOneWidget);
    expect(find.text(title), findsOneWidget);

    await tester.pump(latency);
    await tester.pumpAndSettle();

    // `refetch()` went to all three; the post's was refused.
    expect(h.requests('GET', postPath), 1);
    expect(h.requests('GET', commentsPath), 1);
    expect(h.requests('GET', counterPath), 1);
    expect(h.fact('post', 'status=error'), findsOneWidget);
    expect(combined('isFetching=false'), findsOneWidget);
    // Not an error state: the stale post is still part of the combination.
    expect(combined('state=data'), findsOneWidget);
    expect(find.text(title), findsOneWidget);
    expect(overview('comments=3'), findsOneWidget);
    expect(overview('refetchError=Requested: 500'), findsOneWidget);
    expect(find.text('Could not refresh: Requested: 500'), findsOneWidget);

    // Answered again, the next refetch clears it.
    await answerPost(tester);
    await tester.tap(find.text('Refetch all'));
    await tester.pump(latency);
    await tester.pumpAndSettle();
    expect(overview('refetchError=none'), findsOneWidget);
    expect(find.text('Could not refresh: Requested: 500'), findsNothing);
  });

  showcaseTest('reset with the post refused is the error state, until a retry',
      (tester, h) async {
    await open(tester, h);
    await refusePost(tester);

    // Reset drops the data, so this refusal has nothing to fall back on.
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(combined('state=error'), findsOneWidget);
    expect(find.text('Requested: 500'), findsOneWidget);

    // Still refused: the retry fails the same way.
    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pumpAndSettle();
    expect(combined('state=error'), findsOneWidget);

    await answerPost(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pumpAndSettle();
    expect(combined('state=data'), findsOneWidget);
    expect(overview('refetchError=none'), findsOneWidget);
  });

  showcaseTest(
      'the memo skips the combiner while every source holds the same data',
      (tester, h) async {
    await open(tester, h);
    expect(combined('combines=1'), findsOneWidget);
    final builds = combinedNumber(tester, 'builds');

    // Nothing changed at the backend: structural sharing hands every source
    // the instance it had, the screen rebuilt for `isFetching`, and the
    // combiner was not asked again.
    await tester.tap(find.text('Refetch all'));
    await tester.pumpAndSettle();
    expect(h.requests('GET', counterPath), 2);
    expect(combinedNumber(tester, 'builds'), greaterThan(builds));
    expect(combined('combines=1'), findsOneWidget);

    // A source with new data is a new combination.
    await tester.tap(find.text('Increment counter'));
    await tester.pumpAndSettle();
    expect(overview('counter=1'), findsOneWidget);
    expect(combined('combines=2'), findsOneWidget);
  });

  showcaseTest('combineWith: the list and a read per item, one combination',
      (tester, h) async {
    await open(tester, h);
    await showList(tester);

    final posts = seeded('posts', Post.fromJson);
    expect(details('state=data'), findsOneWidget);
    expect(details('items=3'), findsOneWidget);
    expect(details('refetchError=none'), findsOneWidget);
    // The three posts after the screen's own, read one by one.
    expect(find.text(posts.skip(1).take(3).map((p) => p.title).join(' · ')),
        findsOneWidget);
    expect(h.requests('GET', listPath), 1);
    expect(h.requests('GET', detailPaths), 3);
  });

  showcaseTest(
      'a refused detail keeps the titles as refetchError, and retry reads '
      'only that detail', (tester, h) async {
    await open(tester, h);
    await showList(tester);
    h.backend.log.clear();

    await press(tester, 'the third is refused');
    await press(tester, 'Refetch details');

    // `refetch()` went to the list and every detail; the third was refused.
    expect(h.requests('GET', listPath), 1);
    expect(h.requests('GET', detailPaths), 3);
    expect(details('state=data'), findsOneWidget);
    expect(details('items=3'), findsOneWidget);
    expect(details('refetchError=Requested: 500'), findsOneWidget);

    await press(tester, 'all answer');
    h.backend.log.clear();
    await press(tester, 'Retry details');

    expect(h.requests('GET', thirdDetailPath), 1);
    expect(h.requests('GET', detailPaths), 1);
    expect(h.requests('GET', listPath), 0);
    expect(details('refetchError=none'), findsOneWidget);
  });

  showcaseTest(
      'optional: a deleted pinned post leaves the combination data, and retry '
      'still reads it', (tester, h) async {
    await open(tester, h);
    await showList(tester);

    final title = seeded('posts', Post.fromJson)[4].title;
    expect(pinned('state=data'), findsOneWidget);
    expect(pinned('pinned=$title'), findsOneWidget);

    await press(tester, 'a deleted post');

    // A 404 with nothing to fall back on — and the whole is still data.
    expect(h.requests('GET', deletedPath), 1);
    expect(pinned('state=data'), findsOneWidget);
    expect(pinned('pinned=none'), findsOneWidget);
    expect(pinned('isFetching=false'), findsOneWidget);

    h.backend.log.clear();
    await press(tester, 'Retry pinned');
    // The stand-in carries its origin: retry reached the refused read, and
    // left the list alone.
    expect(h.requests('GET', deletedPath), 1);
    expect(h.requests('GET', listPath), 0);
    expect(pinned('pinned=none'), findsOneWidget);

    // Back to a post that is there: its entry shows at once, and refetches
    // behind the title because it is stale.
    h.backend.latency = latency;
    await tester.tap(find.text('post 5'));
    await tester.pump();
    expect(pinned('pinned=$title'), findsOneWidget);
    expect(pinned('isFetching=true'), findsOneWidget);
    await tester.pump(latency);
    await tester.pumpAndSettle();
    expect(pinned('isFetching=false'), findsOneWidget);
    expect(h.requests('GET', pinnedPath), 1);
  });
}
