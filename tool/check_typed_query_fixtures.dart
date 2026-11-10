// Proves the typed query definition API with the analyzer and at runtime.
//
//   dart run tool/check_typed_query_fixtures.dart [--no-runtime] [--keep]
//                                                 [--record]
//
// The fixtures are in tool/typed_query_fixtures/, which the repository's own
// analysis excludes: half of them are code that must not compile. This runner
// is what analyzes them. It builds a consumer package of its own in a
// temporary directory — the fixtures, a path dependency on packages/query_kit
// and nothing of the workspace — and analyzes it with the SDK that runs this
// script, once per configuration:
//
//   language version   the declared floor, and this SDK's own when newer
//   analysis options   `minimal` (none: the analyzer's defaults) and `strict`
//                      (the repository's root analysis_options.yaml)
//
// What a fixture expects is written in it, on the line before:
//
//   // EXPECT error <code>    an error with this code on the next line, in
//                             every configuration. A language error: no
//                             consumer setting turns it off.
//   // EXPECT strict <code>   a diagnostic with this code on the next line
//                             under `strict` only; under `minimal` the line
//                             is clean. An optional lint or strict mode.
//
// A diagnostic no marker expects fails the run, and so does a marker nothing
// matches, so a fixture cannot fail for the wrong reason (a missing import)
// or at the wrong place. The directory says what a file may hold:
//
//   positive/ support/ runtime/              no marker: clean everywhere
//   boundary/                                compiles; `strict` markers only
//   negative/                                at least one `error` marker
//
// Then runtime/observations.dart runs on the VM with and without assertions,
// and under node compiled with dart2js at its default level, at -O3 and at
// -O4 (Flutter's web release level). What each prints is compared with a
// recorded file, and those three files are the record of what each kind of
// runtime does with a widened receiver:
//
//   observations.debug.expect       the VM with assertions
//   observations.release.expect     the VM without, and dart2js by default
//   observations.unchecked.expect   dart2js -O3 and -O4
//
// `--record` rewrites each file from the first runtime that names it (the
// others are still compared with it); read the diff before committing it.
// `--no-runtime` stops after the analysis, `--keep` leaves the temporary
// consumer packages for a look.
//
// CI runs this in `gates` (the CI SDK) and in `floors` (the declared floor).
import 'dart:convert';
import 'dart:io';

const _fixtures = 'tool/typed_query_fixtures';

/// The directories of the fixture tree and what a file in each may expect.
enum _Kind {
  clean, // no marker at all
  boundary, // compiles; `strict` markers only
  negative, // at least one `error` marker
}

const _kinds = {
  'positive': _Kind.clean,
  'support': _Kind.clean,
  'runtime': _Kind.clean,
  'boundary': _Kind.boundary,
  'negative': _Kind.negative,
};

/// The runtimes `runtime/observations.dart` is run on, and the file that
/// holds what each must print.
const _runtimes = [
  (
    name: 'vm, assertions on',
    vm: true,
    flags: ['--enable-asserts'],
    expect: 'observations.debug.expect',
  ),
  (
    name: 'vm',
    vm: true,
    flags: <String>[],
    expect: 'observations.release.expect',
  ),
  (
    name: 'dart2js',
    vm: false,
    flags: <String>[],
    expect: 'observations.release.expect',
  ),
  (
    name: 'dart2js -O3',
    vm: false,
    flags: ['-O3'],
    expect: 'observations.unchecked.expect',
  ),
  (
    name: 'dart2js -O4',
    vm: false,
    flags: ['-O4'],
    expect: 'observations.unchecked.expect',
  ),
];

const _flags = ['--no-runtime', '--keep', '--record'];

final _marker = RegExp(r'^\s*// EXPECT (error|strict) ([a-z0-9_]+)\s*$');
final _markerLike = RegExp(r'//\s*EXPECT\b');

void main(List<String> args) {
  if (args.any((a) => !_flags.contains(a))) {
    stderr.writeln(
      'usage: dart run tool/check_typed_query_fixtures.dart '
      '[--no-runtime] [--keep] [--record]',
    );
    exit(64);
  }
  final root = Directory.current.absolute;
  final fixtures = Directory('${root.path}/$_fixtures');
  final core = Directory('${root.path}/packages/query_kit');
  if (!fixtures.existsSync() || !core.existsSync()) {
    stderr.writeln('Run from the repository root: no $_fixtures here.');
    exit(64);
  }

  final sdk = _minor(Platform.version);
  final floor = _floorOf(core);
  final languages = [floor, if (_compare(sdk, floor) > 0) sdk];
  stdout.writeln(
    'Dart ${Platform.version.split(' ').first}; '
    'language ${languages.join(' and ')}; fixtures in $_fixtures',
  );

  final files = _fixtureFiles(fixtures);
  final expectations = <String, List<_Expectation>>{
    for (final entry in files.entries)
      entry.key: _expectationsOf(entry.key, entry.value),
  };
  final failures = <String>[..._layoutFailures(files, expectations)];

  final temps = <Directory>[];
  Directory? runtimeHome;
  for (final language in languages) {
    final home = _consumer(fixtures, core, language);
    temps.add(home);
    runtimeHome ??= home;
    for (final strict in [false, true]) {
      final label = 'language $language, ${strict ? 'strict' : 'minimal'}';
      final options = File('${home.path}/analysis_options.yaml');
      if (strict) {
        options.writeAsStringSync(
          File('${root.path}/analysis_options.yaml').readAsStringSync(),
        );
      } else if (options.existsSync()) {
        options.deleteSync();
      }
      final found = _analyze(home);
      final result = _judge(expectations, found, strict: strict);
      failures.addAll(result.failures.map((f) => '[$label] $f'));
      stdout.writeln(
        '  $label: ${result.errors} language errors where expected, '
        '${result.optional} optional diagnostics where expected, '
        '${result.failures.length} failures',
      );
    }
  }

  if (!args.contains('--no-runtime')) {
    failures.addAll(
      _runtime(runtimeHome!, fixtures, record: args.contains('--record')),
    );
  }

  if (args.contains('--keep')) {
    stdout.writeln('Kept: ${temps.map((d) => d.path).join(', ')}');
  } else {
    for (final temp in temps) {
      temp.deleteSync(recursive: true);
    }
  }

  if (failures.isNotEmpty) {
    stderr.writeln('\n${failures.length} failure(s):');
    failures.forEach(stderr.writeln);
    exit(1);
  }
  final negatives = expectations.values
      .expand((list) => list)
      .where((e) => !e.strictOnly)
      .length;
  stdout.writeln(
    'OK: ${files.length} fixture files, $negatives misuses refused at their '
    'line with their code, every control clean.',
  );
}

// ------------------------------------------------------------ expectations

final class _Expectation {
  _Expectation(this.file, this.line, this.code, {required this.strictOnly});

  final String file;

  /// The line the diagnostic must be reported on, 1-based.
  final int line;
  final String code;
  final bool strictOnly;

  @override
  String toString() => '$file:$line ${strictOnly ? 'strict' : 'error'} $code';
}

/// Every `.dart` file of the fixture tree by its path relative to it.
Map<String, List<String>> _fixtureFiles(Directory fixtures) {
  final files = <String, List<String>>{};
  for (final entity in fixtures.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      final relative = entity.path.substring(fixtures.path.length + 1);
      files[relative] = entity.readAsLinesSync();
    }
  }
  return Map.fromEntries(
    files.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
}

List<_Expectation> _expectationsOf(String file, List<String> lines) {
  final expectations = <_Expectation>[];
  final pending = <RegExpMatch>[];
  for (var i = 0; i < lines.length; i++) {
    final match = _marker.firstMatch(lines[i]);
    if (match != null) {
      pending.add(match);
      continue;
    }
    // Stacked markers all name the first line after them.
    for (final marker in pending) {
      expectations.add(
        _Expectation(
          file,
          i + 1,
          marker.group(2)!,
          strictOnly: marker.group(1) == 'strict',
        ),
      );
    }
    pending.clear();
  }
  return expectations;
}

/// What the directories promise, checked without the analyzer.
List<String> _layoutFailures(
  Map<String, List<String>> files,
  Map<String, List<_Expectation>> expectations,
) {
  final failures = <String>[];
  for (final entry in files.entries) {
    final file = entry.key;
    final lines = entry.value;
    for (var i = 0; i < lines.length; i++) {
      if (_markerLike.hasMatch(lines[i]) && !_marker.hasMatch(lines[i])) {
        failures.add('$file:${i + 1} a marker the runner cannot read');
      }
    }
    if (_marker.hasMatch(lines.last)) {
      failures.add('$file: a marker on the last line names no line');
    }
    final directory = file.contains('/') ? file.split('/').first : '';
    final kind = directory.isEmpty ? _Kind.clean : _kinds[directory];
    final expected = expectations[file]!;
    final errors = expected.where((e) => !e.strictOnly).length;
    switch (kind) {
      case null:
        failures.add('$file: a directory the runner does not know');
      case _Kind.clean:
        if (expected.isNotEmpty) {
          failures.add('$file: a control may not expect a diagnostic');
        }
      case _Kind.boundary:
        if (errors > 0) {
          failures.add('$file: a boundary fixture compiles; it expects none');
        }
      case _Kind.negative:
        if (errors == 0) {
          failures.add('$file: a negative fixture expects no error');
        }
    }
  }
  return failures;
}

// ---------------------------------------------------------------- analysis

final class _Diagnostic {
  _Diagnostic(this.file, this.line, this.code, this.severity, this.message);

  final String file;
  final int line;
  final String code;

  /// `ERROR`, `WARNING` or `INFO`.
  final String severity;
  final String message;

  @override
  String toString() => '$file:$line $severity $code — $message';
}

/// A consumer package in a temporary directory: the fixtures, and a path
/// dependency on the core. Resolved by itself, so nothing of the workspace's
/// resolution is borrowed.
Directory _consumer(Directory fixtures, Directory core, String language) {
  final home = Directory.systemTemp
      .createTempSync('typed_query_fixtures_')
      .resolveSymbolicLinksSync();
  for (final entity in fixtures.listSync(recursive: true)) {
    if (entity is File) {
      final relative = entity.path.substring(fixtures.path.length + 1);
      File('$home/$relative')
        ..createSync(recursive: true)
        ..writeAsBytesSync(entity.readAsBytesSync());
    }
  }
  File('$home/pubspec.yaml').writeAsStringSync('''
name: typed_query_fixtures
publish_to: none
environment:
  sdk: ^$language.0
dependencies:
  query_kit:
    path: ${core.path}
dev_dependencies:
  lints: '>=5.1.1 <7.0.0'
''');
  // Offline first: after the workspace's own `pub get` everything is cached.
  for (final arguments in [
    ['pub', 'get', '--offline'],
    ['pub', 'get'],
  ]) {
    final result = Process.runSync(
      Platform.resolvedExecutable,
      arguments,
      workingDirectory: home,
    );
    if (result.exitCode == 0) {
      return Directory(home);
    }
    if (arguments.length == 2) {
      stderr.writeln('pub get failed in $home:\n${result.stderr}');
      exit(1);
    }
  }
  throw StateError('unreachable');
}

List<_Diagnostic> _analyze(Directory home) {
  final result = Process.runSync(
    Platform.resolvedExecutable,
    ['analyze', '--format=json', '.'],
    workingDirectory: home.path,
  );
  final json = (result.stdout as String)
      .split('\n')
      .lastWhere((line) => line.startsWith('{'), orElse: () => '');
  if (json.isEmpty) {
    stderr.writeln(
      'dart analyze printed no JSON:\n${result.stdout}\n${result.stderr}',
    );
    exit(1);
  }
  final decoded = jsonDecode(json) as Map<String, Object?>;
  final diagnostics = decoded['diagnostics']! as List<Object?>;
  return [
    for (final diagnostic in diagnostics.cast<Map<String, Object?>>())
      _diagnosticOf(home, diagnostic),
  ];
}

_Diagnostic _diagnosticOf(Directory home, Map<String, Object?> diagnostic) {
  final location = diagnostic['location']! as Map<String, Object?>;
  final range = location['range']! as Map<String, Object?>;
  final start = range['start']! as Map<String, Object?>;
  final path = location['file']! as String;
  return _Diagnostic(
    path.startsWith('${home.path}/')
        ? path.substring(home.path.length + 1)
        : path,
    start['line']! as int,
    diagnostic['code']! as String,
    diagnostic['severity']! as String,
    diagnostic['problemMessage']! as String,
  );
}

typedef _Judgement = ({int errors, int optional, List<String> failures});

_Judgement _judge(
  Map<String, List<_Expectation>> expectations,
  List<_Diagnostic> found, {
  required bool strict,
}) {
  final failures = <String>[];
  final unmatched = [...found];
  var errors = 0;
  var optional = 0;
  for (final expectation in expectations.values.expand((list) => list)) {
    if (expectation.strictOnly && !strict) {
      continue;
    }
    // One marker answers for one diagnostic, so the number of diagnostics a
    // line draws is pinned too: three missing arguments are three markers.
    final index = unmatched.indexWhere(
      (d) =>
          d.file == expectation.file &&
          d.line == expectation.line &&
          d.code == expectation.code,
    );
    if (index < 0) {
      failures.add('expected and not reported: $expectation');
      continue;
    }
    final match = unmatched.removeAt(index);
    if (expectation.strictOnly) {
      optional++;
    } else if (match.severity == 'ERROR') {
      errors++;
    } else {
      failures.add(
        'expected a language error, reported as '
        '${match.severity}: $expectation',
      );
    }
  }
  failures.addAll(unmatched.map((d) => 'not expected: $d'));
  return (errors: errors, optional: optional, failures: failures);
}

// ----------------------------------------------------------------- runtime

List<String> _runtime(
  Directory home,
  Directory fixtures, {
  required bool record,
}) {
  final failures = <String>[];
  const program = 'runtime/observations.dart';
  final recorded = <String>{};
  for (final runtime in _runtimes) {
    final String output;
    if (runtime.vm) {
      output = _run(home, Platform.resolvedExecutable, [
        'run',
        ...runtime.flags,
        program,
      ]);
    } else {
      _run(home, Platform.resolvedExecutable, [
        'compile',
        'js',
        ...runtime.flags,
        '-o',
        'observations.js',
        program,
      ]);
      // dart2js compiles for a browser: its timers go through `self`,
      // which node does not define, and without it the first `gcTime` timer
      // ends the program silently.
      output = _run(home, 'node', [
        '-e',
        "globalThis.self = globalThis; require('./observations.js');",
      ]);
    }
    final expected = File('${fixtures.path}/runtime/${runtime.expect}');
    if (record && recorded.add(runtime.expect)) {
      expected.writeAsStringSync('${output.trim()}\n');
      stdout
          .writeln('  recorded runtime/${runtime.expect} from ${runtime.name}');
    }
    final wanted = expected.existsSync() ? expected.readAsStringSync() : '';
    if (output.trim() == wanted.trim()) {
      final cases = output.trim().split('\n').length;
      stdout.writeln(
          '  runtime ${runtime.name}: $cases observations as recorded');
    } else {
      failures.add(
        '[runtime ${runtime.name}] the output differs from '
        'runtime/${runtime.expect}:\n${_diff(wanted, output)}',
      );
    }
  }
  return failures;
}

String _run(Directory home, String executable, List<String> arguments) {
  final ProcessResult result;
  try {
    result = Process.runSync(
      executable,
      arguments,
      workingDirectory: home.path,
    );
  } on ProcessException catch (error) {
    stderr.writeln(
      'Cannot run $executable (${error.message}). The runtime observations '
      'need node on the PATH; --no-runtime skips them.',
    );
    exit(1);
  }
  if (result.exitCode != 0) {
    stderr.writeln(
      '$executable ${arguments.join(' ')} exited ${result.exitCode}:\n'
      '${result.stdout}\n${result.stderr}',
    );
    exit(1);
  }
  return result.stdout as String;
}

String _diff(String wanted, String actual) {
  final want = wanted.trim().split('\n');
  final got = actual.trim().split('\n');
  final lines = <String>[];
  for (var i = 0; i < want.length || i < got.length; i++) {
    final w = i < want.length ? want[i] : '<nothing>';
    final g = i < got.length ? got[i] : '<nothing>';
    if (w != g) {
      lines.add('  line ${i + 1}\n    recorded: $w\n    printed:  $g');
    }
  }
  return lines.join('\n');
}

// ------------------------------------------------------------------ versions

/// `3.6` of `3.6.2 (stable) …`.
String _minor(String version) {
  final parts = version.split(' ').first.split('.');
  return '${parts[0]}.${parts[1]}';
}

/// The language version the core declares as its floor.
String _floorOf(Directory core) {
  final pubspec = File('${core.path}/pubspec.yaml').readAsStringSync();
  final match = RegExp(r'sdk:\s*\^(\d+\.\d+)\.').firstMatch(pubspec);
  if (match == null) {
    stderr.writeln('No `sdk: ^x.y.z` in ${core.path}/pubspec.yaml.');
    exit(1);
  }
  return match.group(1)!;
}

int _compare(String a, String b) {
  final x = a.split('.').map(int.parse).toList();
  final y = b.split('.').map(int.parse).toList();
  return x[0] != y[0] ? x[0].compareTo(y[0]) : x[1].compareTo(y[1]);
}
