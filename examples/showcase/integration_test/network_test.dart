/// The network as a device has it: a real socket to a real backend, through
/// the host's proxy (`e2e-native/device_control.ts`), which a test can cut.
/// What the widget tests fake with an adapter and the browser suite holds in
/// the page, this checks on the wire: a cancel closes the connection, and an
/// unreachable host is an error the retries run out on.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'native_harness.dart';

Future<void> main() async {
  initNativeBinding();
  await probeDevice();

  nativeTest('cancelling the slow fetch hangs up on the backend',
      (tester, h) async {
    await h.open(tester, '/cancellation');
    await waitForFact(tester, 'slow facts', 'fetchStatus=fetching');

    await tapOn(tester, find.text('Cancel'));

    await waitForFact(tester, 'slow facts', 'cancels=1');
    await waitForFact(tester, 'slow facts', 'status=pending');
    await waitForFact(tester, 'slow facts', 'fetchStatus=idle');
    // The signal reached the socket: the app closed the connection while
    // the backend was still sleeping out its three seconds…
    expect(await Device.aborts(), <String>['GET /api/posts']);
    // …and the backend, once awake, had no one left to answer.
    await settleFor(tester, const Duration(seconds: 4));
    expect(await h.requests('GET', '/api/posts'), 0);
  });

  nativeTest('a cancelled rename hangs up, rolls back and refetches',
      (tester, h) async {
    const before = 'Update the deploy checklist';
    const after = 'Rewrite the deploy checklist';
    await h.open(tester, '/mutation-cancel');
    await waitForFact(tester, 'debug todos', 'fetchStatus=idle');
    await waitForFact(tester, 'rename facts', 'text=$before');

    await typeInto(tester, find.byType(TextField), after);
    await tapOn(tester, find.text('Rename'));
    await waitForFact(tester, 'rename facts', 'status=pending');
    await waitForFact(tester, 'rename facts', 'text=$after');

    await tapOn(tester, find.text('Cancel'));

    await waitForFact(tester, 'rename facts', 'error=cancelled');
    await waitForFact(tester, 'rename facts', 'signalCancels=1');
    await waitForFact(tester, 'rename facts', 'rollbacks=1');
    await waitForFact(tester, 'rename facts', 'text=$before');
    await waitForFact(tester, 'rename facts', 'settles=1');
    await waitForFact(tester, 'debug todos', 'fetches=2');
    expect(await Device.aborts(), <String>['PATCH /api/todos/1']);
  });

  nativeTest(
      'an unreachable host: the retries run out, and a return to the app '
      'after the network is back recovers', (tester, h) async {
    await Device.network('refuse');
    await h.open(tester, '/simple');

    // The default policy: three retries, one, two and four seconds apart.
    await waitForFact(tester, 'debug post', 'status=error',
        timeout: const Duration(seconds: 20));
    await waitForFact(tester, 'debug post', 'failures=4');
    expect(await h.requests('GET', '/api/posts/1'), 0);

    await Device.network('up');
    // No connectivity source: the binding requires none, so nothing tells
    // the client the network is back. The user returning to the app does:
    // an errored entry is stale, and `refetchOnWindowFocus` refetches it.
    if (!canLeave) {
      h.client.focusManager.setFocused(false);
      h.client.focusManager.setFocused(true);
    } else {
      await Device.background(const Duration(seconds: 1));
    }
    await waitForFact(tester, 'debug post', 'status=success');
    await waitFor(tester, find.text('Local development: setup guide'));
    expect(await h.requests('GET', '/api/posts/1'), 1);
  });
}
