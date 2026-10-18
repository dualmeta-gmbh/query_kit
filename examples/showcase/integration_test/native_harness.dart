/// What every native end-to-end test shares: the real backend in a scenario
/// of the test's own, reached through the host's network proxy; the host's
/// device control; the real app opened on one route; and the teardown a
/// `QueryClient` needs.
///
/// These tests run on an iOS simulator or an Android emulator, started by
/// `e2e-native/run.sh`, which also starts the backend and
/// `e2e-native/device_control.ts` on the host. Unlike the widget tests, time
/// is real and frames are real: the binding runs fully live, so the app
/// renders on vsync as it does for a user, and a wait is a wait.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';
import 'package:showcase/main.dart';
import 'package:showcase/shared/api.dart';

/// The host as the device sees it: an Android emulator reaches the host's
/// loopback as 10.0.2.2; an iOS simulator and a browser share it.
final String host = const String.fromEnvironment('E2E_HOST').isNotEmpty
    ? const String.fromEnvironment('E2E_HOST')
    : (isAndroid ? '10.0.2.2' : 'localhost');

/// Where this run happens. The suite also runs in a browser
/// (`flutter drive -d chrome`), where there is no device to control.
final bool isAndroid =
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
final bool isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
final bool isMacOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
const bool isWeb = kIsWeb;

/// A desktop window, where another app in front is `inactive` — which counts
/// as unfocused there — and nothing reports `paused`.
final bool isDesktop = !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows);

/// Whether the host can send the app away ([Device.background]): not in a
/// browser, not on Linux, whose virtual display has no window manager to put
/// another window in front, and not on a Mac whose session sits at the login
/// window, where no app can come to the front (#109). Settled by
/// `await probeDevice()`, which a file with cases that leave calls first in
/// `main`; reading it before is a bug, and asserts.
bool get canLeave {
  assert(_canLeave != null, 'call `await probeDevice()` in main first');
  return _canLeave!;
}

bool? _canLeave;
String? _leaveBlock;

/// What `skip:` takes for a case that leaves the app: `false`, or the reason
/// it cannot run, which [nativeTest] puts in the case's name.
Object get leaveSkip => canLeave ? false : _leaveBlock!;

/// The platform's name, for what a test prints.
final String platformName = kIsWeb ? 'web' : defaultTargetPlatform.name;

const int backendPort = 5175;
const int controlPort = 5176;
const int proxyPort = 5177;

/// Switches the binding to real frames. Call first in every test file's
/// `main`.
void initNativeBinding() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
}

/// Settles [canLeave]: asks the host whether the app can be sent away. A
/// macOS session at the login window (a locked CI runner) has nothing in
/// front and lets no app come there, so a trip away would test nothing; the
/// cases that leave then skip, and this says why, on a CI run as a warning
/// annotation. Call after [initNativeBinding], before the cases are declared.
Future<void> probeDevice() async {
  if (kIsWeb) {
    _canLeave = false;
    _leaveBlock = 'a browser has no other app to leave to';
    return;
  }
  if (defaultTargetPlatform == TargetPlatform.linux) {
    _canLeave = false;
    _leaveBlock = 'the Linux run has no window manager';
    return;
  }
  final info =
      await _call('GET', Device._uri('/platform')) as Map<String, Object?>;
  _canLeave = info['loginWindow'] != true;
  if (_canLeave!) return;
  _leaveBlock = 'macOS session at the login window; no app can come to the '
      'front';
  // ignore: avoid_print
  print('SKIPPED: $_leaveBlock; the cases that send the app away do not run.');
  if (info['ci'] == true) {
    // ignore: avoid_print
    print('::warning title=macOS trip-away cases skipped::$_leaveBlock');
  }
}

/// The test's own line to the host, separate from the app's: dio, because it
/// works on every platform the suite runs on.
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

/// The host refused a trip because the session is at the login window.
Never _refused(DioException error) => throw StateError(
    'The host cannot send the app away: its macOS session is at the login '
    'window and no app can come to the front. A case that leaves the app '
    'should have skipped (`skip: leaveSkip`, after `await probeDevice()`).');

/// When the app was in the background, as [Device.background] reports it.
typedef Absence = ({DateTime left, DateTime back});

/// The host's device control (`e2e-native/device_control.ts`).
class Device {
  const Device._();

  static Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.http('$host:$controlPort', path, query);

  /// Sends the app to the background for [duration] and brings it back, as
  /// the operating system does it: the app sees the real lifecycle
  /// transitions of its platform. Answers with when it had left and when
  /// its return was asked for, by the host's clock, which is the clock the
  /// backend logs by: between the two the app was away.
  static Future<Absence> background(Duration duration) async {
    final Map<String, Object?> window;
    try {
      window = await _call(
        'POST',
        _uri('/background', {'ms': '${duration.inMilliseconds}'}),
      ) as Map<String, Object?>;
    } on DioException catch (error) {
      if (error.response?.statusCode == 409) _refused(error);
      rethrow;
    }
    return (
      left: DateTime.parse(window['left']! as String),
      back: DateTime.parse(window['back']! as String),
    );
  }

  /// The same trip as [background], booked to start [after] from now and
  /// answered at once: for a moment the app has no line to the host, as in
  /// airplane mode. The app's own lifecycle tells a test when it happened.
  static Future<void> backgroundLater(Duration after, Duration duration) =>
      _call(
          'POST',
          _uri('/background', {
            'ms': '${duration.inMilliseconds}',
            'after': '${after.inMilliseconds}',
          }));

  /// What the network does: `up`, `refuse` (connections closed at once) or
  /// `blackhole` (accepted, never answered). Applies to the backend as the
  /// app reaches it, through the proxy.
  static Future<void> network(String mode) =>
      _call('POST', _uri('/network/$mode'));

  /// The requests the app hung up on before they were answered, as
  /// `METHOD /path`: a cancel that reached the transport, seen on the wire.
  static Future<List<String>> aborts() async =>
      ((await _call('GET', _uri('/aborts'))) as List<Object?>).cast<String>();

  static Future<void> clearAborts() => _call('DELETE', _uri('/aborts'));

  /// Android only: the emulator's airplane mode, on from a moment after this
  /// returns until [duration] has passed. The host ends it, because this
  /// line to the host goes down with the radio; [reachable] waits for it.
  static Future<void> airplane(Duration duration) =>
      _call('POST', _uri('/airplane/on', {'ms': '${duration.inMilliseconds}'}));

  /// Waits until the host answers again.
  static Future<void> reachable({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      try {
        await _call('GET', _uri('/platform'));
        return;
      } on DioException {
        if (DateTime.now().isAfter(deadline)) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  /// Android only: the screen's orientation.
  static Future<void> rotate(String orientation) =>
      _call('POST', _uri('/rotate/$orientation'));
}

/// One test's world: a fresh scenario on the real backend, a fresh client,
/// and the api the app uses, pointed at the proxy.
class NativeHarness {
  NativeHarness(String description)
      : scenario = 'native-${_slug(description)}-'
            '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
        client = QueryClient(notifyManager: NotifyManager.shared) {
    api =
        ShowcaseApi(baseUrl: 'http://$host:$proxyPort/api', scenario: scenario);
  }

  final String scenario;
  final QueryClient client;
  late final ShowcaseApi api;

  static String _slug(String text) {
    final slug = text
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return slug.length > 40 ? slug.substring(0, 40) : slug;
  }

  /// The scenario's control endpoints, straight to the backend: they keep
  /// working while the proxy cuts the app off.
  Uri _scenarioUri(String tail) =>
      Uri.http('$host:$backendPort', '/api/__scenario/$scenario/$tail');

  Future<void> reset() => _call('POST', _scenarioUri('reset'));

  /// The scenario's latency, error rate and scripted failures, as the
  /// backend takes them (`server/scenarios.ts`).
  Future<void> configure({
    int? latencyMs,
    double? errorRate,
    List<Map<String, Object?>>? failNext,
  }) =>
      _call('POST', _scenarioUri('config'), {
        if (latencyMs != null) 'latency': latencyMs,
        if (errorRate != null) 'errorRate': errorRate,
        if (failNext != null) 'failNext': failNext,
      });

  /// When the backend answered each request for [method] and [path]: an
  /// exact `/api/time`, or a `RegExp` on the full path. With [after] and
  /// [before], only those answered in between.
  Future<List<DateTime>> answered(
    String method,
    Pattern path, {
    DateTime? after,
    DateTime? before,
  }) async {
    final log = await _call('GET', _scenarioUri('requests')) as List<Object?>;
    bool matches(String full) =>
        path is RegExp ? path.hasMatch(full) : full == path;
    bool within(DateTime at) =>
        (after == null || at.isAfter(after)) &&
        (before == null || at.isBefore(before));
    return <DateTime>[
      for (final entry in log.cast<Map<String, Object?>>())
        if (entry['method'] == method && matches(entry['path']! as String))
          DateTime.parse(entry['at']! as String),
    ].where(within).toList();
  }

  /// How many requests [answered] counts.
  Future<int> requests(
    String method,
    Pattern path, {
    DateTime? after,
    DateTime? before,
  }) async =>
      (await answered(method, path, after: after, before: before)).length;

  /// Pumps the real app on [route] and waits until its first frame is up.
  /// [onlineStatus] is the app's connectivity source, none by default.
  Future<void> open(
    WidgetTester tester,
    String route, {
    OnlineStatus? onlineStatus,
  }) async {
    await tester.pumpWidget(
      ShowcaseApp(
        api: api,
        client: client,
        onlineStatus: onlineStatus,
        initialRoute: route,
      ),
    );
    await tester.pump();
  }

  /// A connectivity source as the cookbook's "A link is not reachability"
  /// builds one: every [every], ask the backend — through the proxy, the
  /// app's own line — and say whenever the answer changes. Stops asking
  /// once nobody listens.
  Stream<bool> reachability({Duration every = const Duration(seconds: 1)}) {
    // A connection per question: one kept alive from before the radio went
    // could answer for a network that is no longer there.
    final probe = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 1),
      receiveTimeout: const Duration(seconds: 1),
      persistentConnection: false,
    ));
    final uri =
        Uri.http('$host:$proxyPort', '/api/__scenario/$scenario/requests');
    Timer? timer;
    bool? last;
    var asking = false;
    late final StreamController<bool> changes;
    Future<void> ask() async {
      if (asking) return;
      asking = true;
      bool reachable;
      try {
        await probe.getUri<Object?>(uri);
        reachable = true;
      } on Object {
        reachable = false;
      }
      asking = false;
      if (reachable != last && !changes.isClosed) changes.add(last = reachable);
    }

    changes = StreamController<bool>.broadcast(
      onListen: () {
        unawaited(ask());
        timer = Timer.periodic(every, (_) => unawaited(ask()));
      },
      onCancel: () {
        timer?.cancel();
        probe.close(force: true);
      },
    );
    return changes.stream;
  }

  /// The debug strip labelled [label]: the group named `debug <label>`.
  Finder strip(String label) => groupNamed('debug $label');

  /// One fact inside the strip, by its exact text: `fetchStatus=idle`.
  Finder fact(String label, String text) => factIn('debug $label', text);
}

/// The semantics group named [name] (`lib/shared/fact_group.dart`), as the
/// widget tests and the Playwright suite address it.
Finder groupNamed(String name) => find.byKey(ValueKey<String>(name));

/// One fact inside the group named [name], by its exact text.
Finder factIn(String name, String text) =>
    find.descendant(of: groupNamed(name), matching: find.text(text));

/// Waits in real time until [finder] finds something, pumping as it goes.
/// Fails with what the screen showed if [timeout] passes first.
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

/// Scrolls the screen's list until [finder] is built and in view. A phone
/// shows a fraction of most screens, and a `ListView` builds only what is
/// near the viewport, so a fact further down does not exist until then.
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.pump();
  final list = find.byType(Scrollable).first;
  if (finder.evaluate().isEmpty) {
    // Back to the top first: what is wanted may be above.
    final position = tester.state<ScrollableState>(list).position;
    position.jumpTo(position.minScrollExtent);
    await tester.pump();
  }
  await tester.scrollUntilVisible(finder, 200, scrollable: list);
  await tester.pump();
}

/// Waits until the group named [group] shows [text], keeping the group in
/// view: a screen whose content grows above it pushes it out of the range
/// the list builds, and then it is scrolled back.
Future<void> waitForFact(
  WidgetTester tester,
  String group,
  String text, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  final fact = factIn(group, text);
  while (true) {
    await tester.pump();
    if (fact.evaluate().isNotEmpty) return;
    if (groupNamed(group).evaluate().isEmpty) {
      await reveal(tester, groupNamed(group));
      continue;
    }
    if (DateTime.now().isAfter(deadline)) {
      final shown = find
          .descendant(of: groupNamed(group), matching: find.byType(Text))
          .evaluate()
          .map((element) => (element.widget as Text).data)
          .join(', ');
      fail('Timed out after $timeout waiting for "$text" in $group, '
          'which shows: $shown');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

/// Brings [finder] into view and taps it, as a finger does.
Future<void> tapOn(WidgetTester tester, Finder finder) async {
  await reveal(tester, finder);
  await tester.tap(finder);
  await tester.pump();
}

/// Focuses the text field [finder] finds and replaces its text with [text],
/// as the keyboard does.
///
/// Not `tester.enterText`: it sends the edit as text input client `-1`, an
/// id `TextInput` accepts inside an `assert` only, so in a profile build the
/// edit is dropped and the field stays empty. This hands the value to the
/// field's `EditableTextState`, where the keyboard's own edits arrive.
Future<void> typeInto(WidgetTester tester, Finder finder, String text) async {
  await reveal(tester, finder);
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
/// back up whatever the test did to it, and the client's teardown.
void nativeTest(
  String description,
  Future<void> Function(WidgetTester tester, NativeHarness h) body, {
  Object? skip,
  Timeout? timeout,
}) {
  testWidgets(skip is String ? '$description (skipped: $skip)' : description,
      skip: skip is String || skip == true, timeout: timeout, (tester) async {
    final h = NativeHarness(description);
    await h.reset();
    await Device.network('up');
    await Device.clearAborts();
    // Tests lower the latency where they need speed; the default keeps the
    // loading states the screens are about visible for a frame or two.
    await h.configure(latencyMs: 50);
    try {
      await body(tester, h);
    } finally {
      // A test that failed in airplane mode has no line to the host until the
      // radio is back; without the wait this call's error would hide its own.
      await Device.reachable();
      await Device.network('up');
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      h.client.clear();
      await tester.pump();
      h.client.clear();
    }
  });
}
