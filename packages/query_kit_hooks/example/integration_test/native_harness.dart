/// What every native end-to-end test shares: the showcase's backend in a
/// scenario of the test's own, reached through the host's network proxy;
/// the host's device control; the real app; and the teardown a `QueryClient`
/// needs.
///
/// These tests run on an iOS simulator, an Android emulator, a desktop or in
/// Chrome, started by `e2e-native/run.sh`, which also starts the backend and
/// the showcase's `e2e-native/device_control.ts` on the host, on ports of
/// this suite's own. Time is real and frames are real: the binding runs
/// fully live, and a wait is a wait. Shaped after the showcase's harness
/// (`examples/showcase/integration_test/native_harness.dart`), cut to what
/// this app needs.
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:query_kit_hooks/query_kit_hooks.dart';
import 'package:query_kit_hooks_example/src/api.dart';
import 'package:query_kit_hooks_example/src/app.dart';
import 'package:query_kit_hooks_example/src/queries.dart';

/// The host as the device sees it: an Android emulator reaches the host's
/// loopback as 10.0.2.2; an iOS simulator, a desktop and a browser share it.
final String host = const String.fromEnvironment('E2E_HOST').isNotEmpty
    ? const String.fromEnvironment('E2E_HOST')
    : (!kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? '10.0.2.2'
        : 'localhost');

/// Whether the host can send the app away ([Device.background]): not in a
/// browser, and not on Linux, whose virtual display has no window manager to
/// put another window in front.
final bool canLeave = !kIsWeb && defaultTargetPlatform != TargetPlatform.linux;

const int backendPort = 5178;
const int controlPort = 5179;
const int proxyPort = 5180;

/// Switches the binding to real frames. Call first in every test file's
/// `main`.
void initNativeBinding() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
}

/// The test's own line to the host, separate from the app's.
final Dio _http = Dio(BaseOptions(
  connectTimeout: const Duration(seconds: 5),
  receiveTimeout: const Duration(seconds: 60),
));

Future<Object?> _call(String method, Uri uri, [Object? body]) async {
  final response = await _http.requestUri<Object?>(
    uri,
    data: body,
    options: Options(method: method),
  );
  return response.data;
}

/// The host's device control.
class Device {
  const Device._();

  static Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.http('$host:$controlPort', path, query);

  /// Sends the app to the background for [duration] and brings it back, as
  /// the operating system does it: the app sees its platform's own
  /// lifecycle transitions.
  static Future<void> background(Duration duration) => _call(
        'POST',
        _uri('/background', {'ms': '${duration.inMilliseconds}'}),
      );

  /// What the network does: `up`, `refuse` or `blackhole`, for the backend
  /// as the app reaches it, through the proxy.
  static Future<void> network(String mode) =>
      _call('POST', _uri('/network/$mode'));
}

/// One test's world: a fresh scenario on the real backend, a fresh client,
/// and the app's api, pointed at the proxy.
class NativeHarness {
  NativeHarness(String description)
      : scenario = 'hooks-native-${_slug(description)}-'
            '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
        client = QueryClient(defaultOptions: exampleDefaults) {
    api =
        ExampleApi(baseUrl: 'http://$host:$proxyPort/api', scenario: scenario);
  }

  final String scenario;
  final QueryClient client;
  late final ExampleApi api;

  static String _slug(String text) {
    final slug = text
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return slug.length > 40 ? slug.substring(0, 40) : slug;
  }

  /// The scenario's control endpoints, straight to the backend.
  Uri _scenarioUri(String tail) =>
      Uri.http('$host:$backendPort', '/api/__scenario/$scenario/$tail');

  Future<void> reset() => _call('POST', _scenarioUri('reset'));

  Future<void> configure({
    int? latencyMs,
    List<Map<String, Object?>>? failNext,
  }) =>
      _call('POST', _scenarioUri('config'), {
        if (latencyMs != null) 'latency': latencyMs,
        if (failNext != null) 'failNext': failNext,
      });

  /// How many answered requests match [method] and [path], an exact full
  /// path or a `RegExp` on it.
  Future<int> requests(String method, Pattern path) async {
    final log = await _call('GET', _scenarioUri('requests')) as List<Object?>;
    return log.cast<Map<String, Object?>>().where((entry) {
      final full = entry['path']! as String;
      return entry['method'] == method &&
          (path is RegExp ? path.hasMatch(full) : full == path);
    }).length;
  }

  /// Waits until the backend has answered [count] requests matching
  /// [method] and [path], pumping as it goes: for a request the app makes
  /// on its own, which no frame shows.
  Future<void> waitForRequests(
    WidgetTester tester,
    String method,
    Pattern path,
    int count, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      await tester.pump();
      if (await requests(method, path) == count) return;
      if (DateTime.now().isAfter(deadline)) {
        fail('Timed out after $timeout waiting for $count of $method $path');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  /// What the backend holds for [path], read past the app.
  Future<Object?> read(String path) => _http
      .getUri<Object?>(
        Uri.http('$host:$backendPort', '/api$path'),
        options: Options(headers: {'x-scenario': scenario}),
      )
      .then((response) => response.data);

  /// Pumps the real app and waits for its first frame.
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(HooksExampleApp(api: api, client: client));
    await tester.pump();
  }
}

/// The semantics group named [name] (`lib/src/group.dart`), as the widget
/// tests and the Playwright suite address it.
Finder groupNamed(String name) => find.byKey(ValueKey<String>(name));

/// One text inside the group named [name], exactly.
Finder factIn(String name, String text) =>
    find.descendant(of: groupNamed(name), matching: find.text(text));

/// A todo's checkbox, by its text.
Finder todoBox(String text) => find.descendant(
      of: find.widgetWithText(CheckboxListTile, text),
      matching: find.byType(Checkbox),
    );

bool? ticked(WidgetTester tester, String text) =>
    tester.widget<Checkbox>(todoBox(text)).value;

/// Waits in real time until [finder] finds something, pumping as it goes.
Future<void> waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out after $timeout waiting for $finder');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

/// Waits until [finder] finds exactly [count] widgets. Not an index finder
/// with [waitFor]: `finder.at(1)` throws while there is only one.
Future<void> waitForCount(
  WidgetTester tester,
  Finder finder,
  int count, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    await tester.pump();
    if (finder.evaluate().length == count) return;
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out after $timeout waiting for $count of $finder');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

/// Waits until the group named [group] shows [text].
Future<void> waitForFact(WidgetTester tester, String group, String text) =>
    waitFor(tester, factIn(group, text));

/// Taps [finder], scrolled into view, as a finger does.
Future<void> tapOn(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

/// Focuses the text field [finder] finds and replaces its text with [text],
/// as the keyboard does: through the field's `EditableTextState`, because
/// `tester.enterText` is dropped in a profile build (the showcase's
/// `typeInto` says why).
Future<void> typeInto(WidgetTester tester, Finder finder, String text) async {
  await tester.showKeyboard(finder);
  tester
      .state<EditableTextState>(
          find.descendant(of: finder, matching: find.byType(EditableText)))
      .updateEditingValue(TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      ));
  await tester.pump();
}

/// Waits in real time while pumping frames.
Future<void> settleFor(WidgetTester tester, Duration duration) async {
  final deadline = DateTime.now().add(duration);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// `testWidgets` for a native run: a fresh scenario and client, the network
/// up, and the client's teardown.
void nativeTest(
  String description,
  Future<void> Function(WidgetTester tester, NativeHarness h) body, {
  bool? skip,
}) {
  testWidgets(description, skip: skip, (tester) async {
    final h = NativeHarness(description);
    await h.reset();
    await Device.network('up');
    // Low, so a run is quick, and not zero, so a loading state is a frame.
    await h.configure(latencyMs: 50);
    try {
      await body(tester, h);
    } finally {
      await Device.network('up');
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      h.client.clear();
      await tester.pump();
      h.client.clear();
    }
  });
}
