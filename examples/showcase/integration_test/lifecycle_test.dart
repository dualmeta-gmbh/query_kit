/// The app leaving the foreground and coming back, for real: the operating
/// system moves another app on top, the engine reports its own lifecycle
/// transitions, and `QueryClientProvider`'s `AppLifecycleListener` turns
/// them into focus. The widget tests and the browser suite can only call
/// `setFocused` themselves, or raise the states by hand; this is the one
/// place the mapping meets a platform.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'native_harness.dart';

const Duration away = Duration(seconds: 3);

/// A segment of one knob, by its label.
Future<void> pick(WidgetTester tester, String knob, String label) =>
    tapOn(tester, factIn(knob, label));

void main() {
  initNativeBinding();

  group('focus-refetch', () {
    Future<void> openFresh(WidgetTester tester, NativeHarness h) async {
      await h.open(tester, '/focus-refetch');
      await waitForFact(tester, 'debug focus-a', 'fetches=1');
      await waitForFact(tester, 'debug focus-b', 'fetches=1');
    }

    nativeTest('a real return to the foreground refetches what always asks',
        (tester, h) async {
      await openFresh(tester, h);
      await pick(tester, 'on-focus-a', 'always');

      await Device.background(away);

      await waitForFact(tester, 'debug focus-a', 'fetches=2');
      // Entry B kept `ifStale` and its thirty seconds of stale time are not
      // up: the same return left it alone.
      await settleFor(tester, const Duration(seconds: 1));
      await waitForFact(tester, 'debug focus-b', 'fetches=1');
      expect(await h.requests('GET', '/api/time'), 3);
    }, skip: !canLeave);

    nativeTest('never: a real return refetches nothing, stale data included',
        (tester, h) async {
      await openFresh(tester, h);
      await pick(tester, 'on-focus-a', 'never');
      await pick(tester, 'on-focus-b', 'never');
      await pick(tester, 'stale-time', '0');
      await waitForFact(tester, 'reader-a', 'isStale=true');

      await Device.background(away);

      await settleFor(tester, const Duration(seconds: 2));
      await waitForFact(tester, 'debug focus-a', 'fetches=1');
      await waitForFact(tester, 'debug focus-b', 'fetches=1');
      expect(await h.requests('GET', '/api/time'), 2);
    }, skip: !canLeave);

    nativeTest(
        'entry C, threshold long: a real absence under the hour refetches '
        'nothing', (tester, h) async {
      await h.open(tester, '/focus-refetch');
      await pick(tester, 'min-background', 'long');
      await waitForFact(tester, 'reader-c', 'fetches=1');

      await Device.background(away);

      await waitForFact(tester, 'reader-c', 'shouldRefetchOnFocus=false');
      await settleFor(tester, const Duration(seconds: 1));
      await waitForFact(tester, 'reader-c', 'fetches=1');
    }, skip: !canLeave);

    nativeTest('entry C, threshold none: the same absence does refetch',
        (tester, h) async {
      await h.open(tester, '/focus-refetch');
      await waitForFact(tester, 'reader-c', 'fetches=1');

      await Device.background(away);

      await waitForFact(tester, 'reader-c', 'shouldRefetchOnFocus=true');
      await waitForFact(tester, 'reader-c', 'fetches=2');
    }, skip: !canLeave);
  });

  group('auto-refetching', () {
    const ticks = '/api/ticks';

    Future<void> poll(WidgetTester tester, NativeHarness h,
        {required bool inBackground}) async {
      await h.open(tester, '/auto-refetching');
      await waitForFact(tester, 'debug ticks', 'status=success');
      if (inBackground) {
        await tapOn(tester, find.text('Poll in the background'));
      }
      await pick(tester, 'interval', '500 ms');
      await waitForFact(tester, 'debug ticks', 'fetches=3');
    }

    nativeTest('an interval stops while the app is away', (tester, h) async {
      await poll(tester, h, inBackground: false);
      // What the engine reported, and when. On a phone the interval stops at
      // `paused`, not at the moment the host sent the app away: Android
      // reports `inactive` first, which counts as focused there (an
      // interruption, not an absence), and `paused` a second or so later.
      // A desktop window is never `paused`; another app in front makes it
      // `inactive`, which counts as unfocused there, and that is the stop.
      final stop =
          isDesktop ? AppLifecycleState.inactive : AppLifecycleState.paused;
      final states = <(DateTime, AppLifecycleState)>[];
      final listener = AppLifecycleListener(
        onStateChange: (state) => states.add((DateTime.now().toUtc(), state)),
      );
      addTearDown(listener.dispose);

      final absence = await Device.background(away);

      final stopped = states.firstWhere((entry) => entry.$2 == stop).$1;
      // The window ends where the app is focused again: when its return was
      // asked for, or earlier if the platform brought it back by itself — an
      // emulator under load showed it again (`inactive`, focused on a phone)
      // two seconds into a ten-second trip, and the interval rightly ran.
      final focusedAgain = isDesktop
          ? {AppLifecycleState.resumed}
          : {AppLifecycleState.inactive, AppLifecycleState.resumed};
      final returned = states
          .where((entry) =>
              entry.$1.isAfter(stopped) && focusedAgain.contains(entry.$2))
          .map((entry) => entry.$1)
          .fold(absence.back, (end, at) => at.isBefore(end) ? at : end);
      // A poll already in flight at the stop may still be answered.
      final during = await h.answered(
        'GET',
        ticks,
        after: stopped.add(const Duration(milliseconds: 600)),
        before: returned,
      );
      expect(during, isEmpty,
          reason: 'stopped at $stopped, back at $returned (asked for at '
              '${absence.back}); lifecycle: $states');
      expect(
          returned.difference(stopped), greaterThan(const Duration(seconds: 1)),
          reason: 'the window must be long enough to hold polls');
      // And it starts again once the app is back.
      await settleFor(tester, const Duration(seconds: 2));
      expect(await h.requests('GET', ticks, after: absence.back),
          greaterThanOrEqualTo(2));
    }, skip: !canLeave);

    nativeTest('refetchIntervalInBackground: what the platform allows',
        (tester, h) async {
      await poll(tester, h, inBackground: true);

      final absence = await Device.background(away);

      final during = await h.requests(
        'GET',
        ticks,
        after: absence.left.add(const Duration(seconds: 1)),
        before: absence.back,
      );
      // ignore: avoid_print
      print('refetchIntervalInBackground on $platformName: '
          '$during polls in ${absence.back.difference(absence.left)}');
      // An app the system has not suspended yet keeps its timers: Android
      // keeps a backgrounded process running, iOS gives it a few seconds
      // before it suspends it, and a desktop app behind another window is
      // not suspended at all.
      expect(during, greaterThanOrEqualTo(2));
    }, skip: !canLeave);
  });
}
