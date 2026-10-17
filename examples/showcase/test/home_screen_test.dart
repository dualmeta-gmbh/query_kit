/// The catalogue screen against the fake backend: the list a human opens the
/// app on.
///
/// `catalogue_test.dart` builds each screen and never mounts one, and every
/// feature's own test opens its route directly, so nothing mounted
/// [HomeScreen] — its tiles, their texts, the order, and the
/// `Navigator.pushNamed` behind a tap. Its browser twin is
/// `e2e/tests/app/catalogue.spec.ts` (#79).
///
/// The file is not `test/features/<id>_test.dart`: the home screen is not a
/// feature, and the catalogue's five-sets test would count it as one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showcase/home_screen.dart';
import 'package:showcase/routes.dart';

import 'harness.dart';

/// Thirty tiles of two lines each are taller than the default window, and the
/// lazy list builds only what is in view. The size is a fact about this
/// screen and stays here (see the README's "Writing a screen").
void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

String _text(Widget? widget) => (widget! as Text).data!;

void main() {
  showcaseTest('every entry is one list tile with its title and its summary',
      (tester, h) async {
    tall(tester);
    await h.open(tester, '/');

    expect(find.byType(ListTile), findsNWidgets(featureEntries.length));
    for (final entry in featureEntries) {
      final feature = entry.feature;
      expect(
        find.byWidgetPredicate((widget) =>
            widget is ListTile &&
            _text(widget.title) == feature.title &&
            _text(widget.subtitle) == feature.summary),
        findsOneWidget,
        reason: '${feature.id} is not exactly one tile',
      );
    }
  });

  showcaseTest('the entries are in featureEntries order', (tester, h) async {
    tall(tester);
    await h.open(tester, '/');

    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => _text(tile.title))
        .toList();
    expect(titles, [for (final entry in featureEntries) entry.feature.title]);
  });

  showcaseTest('a tap pushes that feature\'s route', (tester, h) async {
    tall(tester);
    await h.open(tester, '/');

    for (final entry in featureEntries) {
      await tester.tap(find.text(entry.feature.title));
      await tester.pumpAndSettle();

      // The route on top is the one the entry names, and it built the
      // entry's own screen — not the catalogue's fallback.
      final BuildContext screen = tester.element(
          find.byType(entry.builder(_rootContext(tester)).runtimeType));
      expect(ModalRoute.of(screen)!.settings.name, entry.feature.route,
          reason: '${entry.feature.id} pushed another route');
      expect(find.byType(HomeScreen), findsNothing,
          reason: '${entry.feature.id} left the catalogue on top');

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
    }
  });

  showcaseTest('the app bar shows the scenario the app was given',
      (tester, h) async {
    await h.open(tester, '/');

    expect(find.text(showcaseTitle), findsOneWidget);
    expect(find.text('scenario widget-test'), findsOneWidget);
  });

  showcaseTest('the scenario in the app bar is the one handed in',
      (tester, h) async {
    await h.open(tester, '/');

    expect(find.text('scenario another-world'), findsOneWidget);
  }, scenario: 'another-world');

  showcaseTest('an entry past the fold is reachable by scrolling',
      (tester, h) async {
    // The default 800 x 600 window: the last tile is not built until the
    // list has been turned far enough.
    await h.open(tester, '/');
    final last = featureEntries.last.feature;
    expect(find.text(last.title), findsNothing);

    await tester.scrollUntilVisible(find.text(last.title), 200);
    await tester.tap(find.text(last.title));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsNothing);
    expect(
        find.byType(
            featureEntries.last.builder(_rootContext(tester)).runtimeType),
        findsOneWidget);
  });
}

/// A context to ask an entry's builder with: every builder is
/// `(_) => const XScreen()` and ignores it, which is what lets a test learn
/// the screen's type without mounting a second one.
BuildContext _rootContext(WidgetTester tester) =>
    tester.element(find.byType(Navigator).first);
