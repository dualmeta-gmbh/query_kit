/// What only a device's own settings can do to the app, on Android: the
/// radio switched off, and the screen turned. iOS simulators expose neither
/// to a script, so these run on the emulator alone.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'native_harness.dart';

void main() {
  initNativeBinding();

  nativeTest(
      'airplane mode: the retries run out, and the return after it is off '
      'recovers', (tester, h) async {
    // Long enough for the default policy's three retries, one, two and four
    // seconds apart, to run out inside it.
    await Device.airplane(const Duration(seconds: 14));
    await settleFor(tester, const Duration(seconds: 2));
    await h.open(tester, '/simple');
    await waitForFact(tester, 'debug post', 'status=error',
        timeout: const Duration(seconds: 12));
    await waitForFact(tester, 'debug post', 'failures=4');

    await Device.reachable();
    expect(await h.requests('GET', '/api/posts/1'), 0);
    await Device.background(const Duration(seconds: 1));
    await waitForFact(tester, 'debug post', 'status=success',
        timeout: const Duration(seconds: 20));
    expect(await h.requests('GET', '/api/posts/1'), 1);
  }, skip: !isAndroid);

  nativeTest(
      'airplane mode: a mutation made offline waits, survives a trip to the '
      'background, and is sent exactly once when the radio is back',
      (tester, h) async {
    // The app is told about the network by a reachability probe — the
    // cookbook's recipe — since it has no connectivity source of its own.
    await h.open(
      tester,
      '/offline',
      onlineStatus: OnlineStatus.stream(h.reachability(), initial: true),
    );
    await waitForFact(tester, 'debug todos', 'status=success');

    // What the engine reports while the radio is off: the trip below.
    final states = <AppLifecycleState>[];
    final listener = AppLifecycleListener(onStateChange: states.add);
    addTearDown(listener.dispose);

    // Both booked now, because once the radio is off this test has no line to
    // the host: off for eighteen seconds, and away for two of them, from the
    // ninth — after the mutation below is parked, before the radio is back.
    await Device.backgroundLater(
        const Duration(seconds: 9), const Duration(seconds: 2));
    await Device.airplane(const Duration(seconds: 18));
    await waitForFact(tester, 'facts offline', 'online=false');

    await typeInto(tester, find.widgetWithText(TextField, 'New todo'),
        'Written in airplane mode');
    await tapOn(tester, find.byTooltip('Add todo'));
    await waitForFact(tester, 'facts offline', 'mutation isPaused=true');
    expect(states, isEmpty, reason: 'the trip came before the mutation waited');

    // Away and back while the radio is still off: the mutation stays parked.
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (!(states.contains(AppLifecycleState.paused) &&
        states.last == AppLifecycleState.resumed)) {
      if (DateTime.now().isAfter(deadline)) fail('no trip away: $states');
      await settleFor(tester, const Duration(milliseconds: 200));
    }
    await waitForFact(tester, 'facts offline', 'online=false');
    await waitForFact(tester, 'facts offline', 'mutation isPaused=true');

    // The radio comes back by itself; the probe notices, and the mutation
    // goes out on its own.
    await waitForFact(tester, 'facts offline', 'online=true',
        timeout: const Duration(seconds: 25));
    await waitForFact(tester, 'facts offline', 'mutation isPaused=false');
    await waitForFact(tester, 'facts offline', 'mutation status=success',
        timeout: const Duration(seconds: 10));
    await settleFor(tester, const Duration(seconds: 3));
    expect(await h.requests('POST', '/api/todos'), 1);
  }, skip: !isAndroid);

  group('rotation', () {
    Future<void> turn(WidgetTester tester, String orientation) async {
      await Device.rotate(orientation);
      final wantWide = orientation == 'landscape';
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (true) {
        await tester.pump();
        final size = tester.view.physicalSize;
        if ((size.width > size.height) == wantWide) break;
        if (DateTime.now().isAfter(deadline)) {
          fail('the screen did not turn $orientation: $size');
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await settleFor(tester, const Duration(milliseconds: 800));
    }

    nativeTest('a turned screen keeps its data and fetches nothing',
        (tester, h) async {
      try {
        await h.open(tester, '/parallel-queries');
        for (final id in <int>[1, 2, 3]) {
          await waitForFact(tester, 'debug post-$id', 'status=success');
        }

        // Wide enough for the side-by-side layout: the cards move into a
        // row, their readers stay the same observers.
        await turn(tester, 'landscape');
        await turn(tester, 'portrait');

        for (final id in <int>[1, 2, 3]) {
          await waitForFact(tester, 'debug post-$id', 'status=success');
          await waitForFact(tester, 'debug post-$id', 'fetches=1');
        }
        expect(await h.requests('GET', RegExp(r'^/api/posts/\d+$')), 3);
        expect(tester.takeException(), isNull);
      } finally {
        await Device.rotate('portrait');
      }
    }, skip: !isAndroid);

    nativeTest('a turned infinite list keeps its pages', (tester, h) async {
      try {
        await h.open(tester, '/load-more');
        await waitForFact(tester, 'projects facts', 'pages=1');
        await tapOn(tester, find.text('Load more'));
        await waitForFact(tester, 'projects facts', 'pages=2');

        await turn(tester, 'landscape');
        await waitForFact(tester, 'projects facts', 'pages=2');
        await waitForFact(tester, 'projects facts', 'rows=20');
        await turn(tester, 'portrait');

        await waitForFact(tester, 'projects facts', 'pages=2');
        expect(await h.requests('GET', '/api/projects'), 2);
        expect(tester.takeException(), isNull);
      } finally {
        await Device.rotate('portrait');
      }
    }, skip: !isAndroid);
  });
}
