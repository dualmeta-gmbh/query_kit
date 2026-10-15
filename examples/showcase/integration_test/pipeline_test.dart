/// The pipeline itself: the app on the device reaches the real backend
/// through the proxy, in its own scenario.
library;

import 'package:flutter_test/flutter_test.dart';

import 'native_harness.dart';

void main() {
  initNativeBinding();

  nativeTest('the simple screen loads its post from the real backend',
      (tester, h) async {
    await h.open(tester, '/simple');
    await waitFor(tester, h.fact('post', 'status=success'));
    expect(find.text('Local development: setup guide'), findsOneWidget);
    expect(await h.requests('GET', '/api/posts/1'), 1);
  });
}
