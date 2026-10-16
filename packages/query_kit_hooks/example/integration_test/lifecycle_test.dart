/// The app leaving the foreground and coming back, for real: the operating
/// system puts another app on top, and `QueryClientProvider` turns the
/// engine's lifecycle into focus. What a return refetches is what the
/// queries on screen say about their freshness: the todos are never fresh,
/// the posts are for a minute.
library;

import 'package:flutter_test/flutter_test.dart';

import 'native_harness.dart';

const Duration away = Duration(seconds: 3);

void main() {
  initNativeBinding();

  nativeTest('a real return refetches the todos on screen', (tester, h) async {
    await h.open(tester);
    await tapOn(tester, find.text('Todos'));
    await waitForFact(tester, 'open todos', '2 open');
    expect(await h.requests('GET', '/api/todos'), 1);

    await Device.background(away);

    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (await h.requests('GET', '/api/todos') < 2) {
      if (DateTime.now().isAfter(deadline)) {
        fail('The return to the foreground refetched no todos');
      }
      await settleFor(tester, const Duration(milliseconds: 200));
    }
    await waitForFact(tester, 'open todos', '2 open');
  }, skip: !canLeave);

  nativeTest('a real return within the minute leaves the posts alone',
      (tester, h) async {
    await h.open(tester);
    await waitFor(tester, find.text('Local development: setup guide'));
    expect(await h.requests('GET', '/api/posts'), 1);

    await Device.background(away);

    await settleFor(tester, const Duration(seconds: 2));
    expect(await h.requests('GET', '/api/posts'), 1);
  }, skip: !canLeave);
}
