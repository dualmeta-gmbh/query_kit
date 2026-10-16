// query_kit is an entirely AI-coded project: all code, tests and
// documentation were written by AI coding agents (Anthropic's Claude). A
// human maintainer set the goals and reviews releases, but did not write the
// code.

/// Posts, todos and projects on `query_kit_hooks`: every hook the package
/// exports, each in the place an app would use it.
///
/// ```bash
/// flutter create . --platforms=web    # once: the archive holds no platform folders
/// flutter run -d chrome
/// ```
///
/// Without a server the app runs against `lib/src/in_memory_backend.dart`,
/// in the same process, as slow as a server (300 ms a request). In the
/// repository it also runs against the showcase's backend:
///
/// ```bash
/// cd examples/showcase/server && npm install && PORT=5178 npm run dev
/// flutter run -d chrome --dart-define=BACKEND=http://localhost:5178/api
/// ```
///
/// On the web, `?scenario=<id>` before the `#` puts every request in that
/// backend world, which is how the end-to-end suites keep their tests apart.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'src/api.dart';
import 'src/app.dart';
import 'src/in_memory_backend.dart';

/// `--dart-define=BACKEND=<url>`: the backend to talk to. Empty, the app
/// talks to the in-memory one.
const String _backend = String.fromEnvironment('BACKEND');

/// Built with `--dart-define=E2E=true`, the app switches its semantics tree
/// on from the start. Flutter web paints to a canvas, so that tree is the
/// only thing a browser-driving test can see.
const bool _e2e = bool.fromEnvironment('E2E');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_e2e) {
    SemanticsBinding.instance.ensureSemantics();
  }
  runApp(HooksExampleApp(api: await _connect()));
}

Future<ExampleApi> _connect() async {
  if (_backend.isNotEmpty) {
    return ExampleApi(
      baseUrl: _backend,
      scenario: Uri.base.queryParameters['scenario'],
    );
  }
  final seed = jsonDecode(await rootBundle.loadString('assets/seed.json'))
      as Map<String, Object?>;
  return ExampleApi.inMemory(
    InMemoryBackend(seed: seed, latency: const Duration(milliseconds: 300)),
  );
}
