/// Every screen once, on the device, against the real backend: opened,
/// given a moment to fetch, and walked to the end of its list, so every
/// section has been built and laid out at the device's own size, fonts and
/// pixel ratio. A layout overflow or an exception anywhere fails it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showcase/routes.dart';

import 'native_harness.dart';

void main() {
  initNativeBinding();

  for (final entry in featureEntries) {
    final route = entry.feature.route;
    nativeTest('$route opens and lays out on the device', (tester, h) async {
      await h.open(tester, route);
      await settleFor(tester, const Duration(milliseconds: 1500));
      final list = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      for (var step = 0;
          step < 40 && list.position.pixels < list.position.maxScrollExtent;
          step++) {
        list.position.jumpTo(list.position.pixels + 400);
        await settleFor(tester, const Duration(milliseconds: 150));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
