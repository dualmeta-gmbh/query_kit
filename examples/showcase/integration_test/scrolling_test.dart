/// An infinite list driven the way a thumb drives it: flings on the list
/// itself, with the platform's own scroll physics (iOS bounces past the end,
/// Android clamps), until the last page is in. The screen appends a page
/// when the list nears its end; a bounce reports the end more than once, and
/// none of that may ask for a page twice.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'native_harness.dart';

void main() {
  initNativeBinding();

  nativeTest('flinging through load-more fetches each page exactly once',
      (tester, h) async {
    await h.open(tester, '/load-more');
    await waitForFact(tester, 'projects facts', 'pages=1');
    final projects = find.byKey(const ValueKey<String>('projects-list'));
    await reveal(tester, projects);

    for (var fling = 0; fling < 60; fling++) {
      if (factIn('projects facts', 'hasNextPage=false').evaluate().isNotEmpty) {
        break;
      }
      await tester.fling(projects, const Offset(0, -500), 2500);
      await settleFor(tester, const Duration(milliseconds: 400));
    }

    await waitForFact(tester, 'projects facts', 'hasNextPage=false');
    await waitForFact(tester, 'projects facts', 'pages=10');
    await waitForFact(tester, 'projects facts', 'rows=100');
    // A fling more past the end, bounce included, asks for nothing.
    await tester.fling(projects, const Offset(0, -500), 2500);
    await settleFor(tester, const Duration(seconds: 1));
    expect(await h.requests('GET', '/api/projects'), 10);
  });
}
