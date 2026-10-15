/// Every screen at a phone's size: the iPhone 17 Pro's 402 × 874 logical
/// pixels, and the narrowest common Android width, 360.
///
/// The scenario id is as long as the native end-to-end suite's
/// (`integration_test/native_harness.dart`), because the app bar shows it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showcase/routes.dart';

import 'harness.dart';

void main() {
  for (final width in [402.0, 360.0]) {
    for (final entry in featureEntries) {
      showcaseTest(
          '${entry.feature.route} fits a ${width.toInt()} pt wide phone',
          scenario:
              'native-the-simple-screen-loads-its-post-from-t-1a2b3c4d5e6f',
          (tester, h) async {
        tester.view.physicalSize = Size(width * 3, 874 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await h.open(tester, entry.feature.route, settle: false);
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        // The list builds what is near the viewport only: walk it to the end
        // so every section has been laid out at this width.
        final list = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        while (list.position.pixels < list.position.maxScrollExtent) {
          list.position.jumpTo(list.position.pixels + 400);
          await tester.pump(const Duration(milliseconds: 100));
        }
      });
    }
  }
}
