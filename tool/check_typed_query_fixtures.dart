// Proves the typed query definition API with the analyzer and at runtime.
//
//   dart run tool/check_typed_query_fixtures.dart [--no-runtime] [--keep]
//                                                 [--record]
//   dart run tool/check_typed_query_fixtures.dart --self-test
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
// What keeps a green run from meaning nothing. Every check above compares
// what is there with what is there: a deleted fixture, a deleted misuse with
// its marker, a deleted recorded line together with the observation that
// printed it, all leave a smaller tree that agrees with itself. So the tree
// is pinned from outside it:
//
//   inventory.txt   every fixture file with the number of markers of each
//                   kind it holds, and every recorded file with its number
//                   of observations. The run fails unless the tree matches
//                   it exactly: a file gone, a file nobody recorded, a count
//                   that moved.
//   the floors      what no inventory may record away: a fixture in every
//                   directory, a language error expected somewhere, the
//                   observation program, a recorded file with observations
//                   for every runtime, and an inventory.
//   the output      a runtime that prints nothing fails, whatever the
//                   recorded file holds; so does a missing or empty recorded
//                   file, a printed line that is not an observation, and an
//                   id printed twice.
//
// These are checked first, before anything is analyzed.
//
// `--record` is the one way to move a pin. It rewrites each recorded file
// from the first runtime that names it (the others are still compared with
// it), and then, when the whole run is green, inventory.txt, printing what
// changed in it; with `--no-runtime` it rewrites the inventory alone. The
// floors hold while recording. Read the diff before committing it.
//
// `--no-runtime` stops after the analysis, `--keep` leaves the temporary
// consumer packages for a look.
//
// `--self-test` proves that each of those failures is one: it breaks a copy
// of the real tree in each of the ways above (and in the way a review of
// this runner did, down to one file and no recorded output) and requires
// the failure, with the untouched copy as the control. It needs no node and
// resolves no package.
//
// CI runs both in `gates` (the CI SDK) and in `floors` (the declared floor).
import 'dart:convert';
import 'dart:io';

const _fixtures = 'tool/typed_query_fixtures';
const _inventory = 'inventory.txt';
const _program = 'runtime/observations.dart';

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

/// The recorded files, each once.
final _expectFiles = {for (final runtime in _runtimes) runtime.expect};

const _flags = ['--no-runtime', '--keep', '--record'];

final _marker = RegExp(r'^\s*// EXPECT (error|strict) ([a-z0-9_]+)\s*$');
final _markerLike = RegExp(r'//\s*EXPECT\b');

/// `id | what was done | what happened`.
final _observation = RegExp(r'^([A-Za-z0-9]+(?:-[A-Za-z0-9]+)*) \| .+ \| .+$');

void main(List<String> args) {
  final selfTest = args.length == 1 && args.single == '--self-test';
  if (!selfTest && args.any((a) => !_flags.contains(a))) {
    stderr.writeln(
      'usage: dart run tool/check_typed_query_fixtures.dart '
      '[--no-runtime] [--keep] [--record]\n'
      '       dart run tool/check_typed_query_fixtures.dart --self-test',
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
  if (selfTest) {
    exit(_selfTest(fixtures) ? 0 : 1);
  }
  final record = args.contains('--record');
  final runtime = !args.contains('--no-runtime');

  // What a smaller tree would still agree with, before anything else.
  final structure = _structureFailures(
    fixtures,
    record: record,
    runtime: runtime,
  );
  if (structure.isNotEmpty) {
    _fail(structure);
  }

  final sdk = _minor(Platform.version);
  final floor = _floorOf(core);
  final languages = [floor, if (_compare(sdk, floor) > 0) sdk];
  stdout.writeln(
    'Dart ${Platform.version.split(' ').first}; '
    'language ${languages.join(' and ')}; fixtures in $_fixtures',
  );

  final files = _fixtureFiles(fixtures);
  final expectations = _expectationsOfAll(files);
  final failures = <String>[];

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

  if (runtime) {
    failures.addAll(_runtime(runtimeHome!, fixtures, record: record));
  }

  if (args.contains('--keep')) {
    stdout.writeln('Kept: ${temps.map((d) => d.path).join(', ')}');
  } else {
    for (final temp in temps) {
      temp.deleteSync(recursive: true);
    }
  }

  if (record) {
    if (failures.isEmpty) {
      // The recorded files may be new: the floors once more, with them.
      failures.addAll(_structureFailures(fixtures, record: true));
    }
    if (failures.isEmpty) {
      _recordInventory(fixtures, files, expectations);
    } else {
      stdout.writeln('  $_inventory is left as it was: the run failed');
    }
  }

  if (failures.isNotEmpty) {
    _fail(failures);
  }
  final negatives = expectations.values
      .expand((list) => list)
      .where((e) => !e.strictOnly)
      .length;
  stdout.writeln(
    'OK: ${files.length} fixture files, $negatives misuses refused at their '
    'line with their code, every control clean; the tree is the one '
    '$_inventory records.',
  );
}

Never _fail(List<String> failures) {
  stderr.writeln('\n${failures.length} failure(s):');
  failures.forEach(stderr.writeln);
  exit(1);
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

Map<String, List<_Expectation>> _expectationsOfAll(
  Map<String, List<String>> files,
) =>
    {
      for (final entry in files.entries)
        entry.key: _expectationsOf(entry.key, entry.value),
    };

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
    if (lines.every((line) => line.trim().isEmpty)) {
      failures.add('$file: an empty fixture');
      continue;
    }
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

// ------------------------------------------- the tree, pinned from outside

/// Everything that is wrong with the tree before a line of it is analyzed:
/// the floors, the layout and the inventory.
///
/// While recording, the inventory is about to be rewritten and is not
/// compared; with the runtime as well, so are the recorded files, which
/// are not required yet. The floors hold either way.
List<String> _structureFailures(
  Directory fixtures, {
  bool record = false,
  bool runtime = false,
}) {
  final files = _fixtureFiles(fixtures);
  final expectations = _expectationsOfAll(files);
  final failures = [
    ..._floorFailures(
      fixtures,
      files,
      expectations,
      recordedFiles: !(record && runtime),
    ),
    ..._layoutFailures(files, expectations),
  ];
  if (record) {
    return failures;
  }
  final recorded = _readInventory(fixtures);
  if (recorded == null) {
    return [
      ...failures,
      '$_inventory is missing: nothing says what this tree has to hold. '
          'Restore it, or record it with --record.',
    ];
  }
  return [
    ...failures,
    ..._inventoryFailures(
      recorded,
      _inventoryOf(fixtures, files, expectations),
    ),
  ];
}

/// What no inventory can record away.
List<String> _floorFailures(
  Directory fixtures,
  Map<String, List<String>> files,
  Map<String, List<_Expectation>> expectations, {
  required bool recordedFiles,
}) {
  final failures = <String>[];
  for (final directory in _kinds.keys) {
    if (!files.keys.any((file) => file.startsWith('$directory/'))) {
      failures.add('$directory/ holds no fixture');
    }
  }
  if (!files.containsKey(_program)) {
    failures.add('$_program is missing: nothing is observed at runtime');
  }
  if (!expectations.values.expand((list) => list).any((e) => !e.strictOnly)) {
    failures.add('no fixture expects a language error: nothing is refused');
  }
  if (recordedFiles) {
    for (final expect in _expectFiles) {
      final lines = _recordedLines(fixtures, expect);
      if (lines == null) {
        failures.add('runtime/$expect is missing');
      } else if (lines.isEmpty) {
        failures.add('runtime/$expect holds no observation');
      }
    }
  }
  return failures;
}

/// The lines of a text that hold something.
List<String> _lines(String text) => [
      for (final line in const LineSplitter().convert(text))
        if (line.trim().isNotEmpty) line.trimRight(),
    ];

/// The observations a recorded file holds, or `null` when there is no file.
List<String>? _recordedLines(Directory fixtures, String expect) {
  final file = File('${fixtures.path}/runtime/$expect');
  return file.existsSync() ? _lines(file.readAsStringSync()) : null;
}

/// What the tree holds, as the inventory writes it: a row per fixture file
/// with its markers, a row per recorded file with its observations.
Map<String, String> _inventoryOf(
  Directory fixtures,
  Map<String, List<String>> files,
  Map<String, List<_Expectation>> expectations,
) =>
    {
      for (final file in files.keys)
        'fixture $file':
            'errors=${expectations[file]!.where((e) => !e.strictOnly).length} '
                'strict=${expectations[file]!.where((e) => e.strictOnly).length}',
      for (final expect in _expectFiles)
        if (_recordedLines(fixtures, expect) case final lines?)
          'observations runtime/$expect': 'lines=${lines.length}',
    };

/// The committed inventory, or `null` when there is none.
Map<String, String>? _readInventory(Directory fixtures) {
  final file = File('${fixtures.path}/$_inventory');
  if (!file.existsSync()) {
    return null;
  }
  final rows = <String, String>{};
  for (final line in _lines(file.readAsStringSync())) {
    if (line.startsWith('#')) {
      continue;
    }
    final parts = line.split(' ');
    rows[parts.take(2).join(' ')] = parts.skip(2).join(' ');
  }
  return rows;
}

/// Where the tree and the inventory disagree. Exact, in both directions: a
/// count that was only a minimum would stop meaning anything the first time
/// the tree grew without it.
List<String> _inventoryFailures(
  Map<String, String> recorded,
  Map<String, String> found,
) {
  final failures = <String>[
    for (final row in recorded.entries)
      if (!found.containsKey(row.key))
        'recorded in $_inventory and gone: ${row.key} (${row.value})'
      else if (found[row.key] != row.value)
        '${row.key}: $_inventory records ${row.value}, the tree holds '
            '${found[row.key]}',
    for (final row in found.entries)
      if (!recorded.containsKey(row.key))
        'not in $_inventory: ${row.key} (${row.value})',
  ];
  return [
    ...failures,
    if (failures.isNotEmpty)
      'If the tree is meant to be this way, run with --record and commit '
          '$_inventory with the change.',
  ];
}

/// Rewrites the inventory from the tree and says what moved.
void _recordInventory(
  Directory fixtures,
  Map<String, List<String>> files,
  Map<String, List<_Expectation>> expectations,
) {
  final before = _readInventory(fixtures) ?? const <String, String>{};
  final after = _inventoryOf(fixtures, files, expectations);
  File('${fixtures.path}/$_inventory').writeAsStringSync(
    [
      '# What tool/check_typed_query_fixtures.dart has to find in this tree:',
      '# every fixture file with the markers it holds, every recorded file',
      '# with its observations. The run fails on any difference. Written by',
      '# --record, never by hand: a row that changes here is a fixture, a',
      '# refused misuse or an observation that came or went.',
      for (final row in after.entries) '${row.key} ${row.value}',
      '',
    ].join('\n'),
  );
  final moved = <String>[
    for (final row in before.entries)
      if (!after.containsKey(row.key))
        '    gone: ${row.key} (${row.value})'
      else if (after[row.key] != row.value)
        '    ${row.key}: ${row.value} -> ${after[row.key]}',
    for (final row in after.entries)
      if (!before.containsKey(row.key)) '    new: ${row.key} (${row.value})',
  ];
  stdout.writeln(
    moved.isEmpty
        ? '  recorded $_inventory: nothing moved'
        : '  recorded $_inventory:\n${moved.join('\n')}',
  );
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
  _copyTree(fixtures, Directory(home));
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

void _copyTree(Directory from, Directory to) {
  for (final entity in from.listSync(recursive: true)) {
    if (entity is File) {
      final relative = entity.path.substring(from.path.length + 1);
      File('${to.path}/$relative')
        ..createSync(recursive: true)
        ..writeAsBytesSync(entity.readAsBytesSync());
    }
  }
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
  final recorded = <String>{};
  for (final runtime in _runtimes) {
    final String output;
    if (runtime.vm) {
      output = _run(home, Platform.resolvedExecutable, [
        'run',
        ...runtime.flags,
        _program,
      ]);
    } else {
      _run(home, Platform.resolvedExecutable, [
        'compile',
        'js',
        ...runtime.flags,
        '-o',
        'observations.js',
        _program,
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
      // Never an output that is itself wrong: it would become the record.
      if (_outputFailures(output).isEmpty) {
        expected.writeAsStringSync('${output.trim()}\n');
        stdout.writeln(
          '  recorded runtime/${runtime.expect} from ${runtime.name}',
        );
      } else {
        stdout.writeln(
          '  runtime/${runtime.expect} is left as it was: what '
          '${runtime.name} printed cannot be a record',
        );
      }
    }
    final found = _observationFailures(
      output: output,
      wanted: expected.existsSync() ? expected.readAsStringSync() : null,
      expect: runtime.expect,
    );
    if (found.isEmpty) {
      stdout.writeln(
        '  runtime ${runtime.name}: ${_lines(output).length} observations '
        'as recorded',
      );
    } else {
      failures.addAll(found.map((f) => '[runtime ${runtime.name}] $f'));
    }
  }
  return failures;
}

/// What is wrong with what a runtime printed, whatever was recorded:
/// nothing at all, a line that is not an observation, an id twice.
List<String> _outputFailures(String output) {
  final lines = _lines(output);
  if (lines.isEmpty) {
    return ['printed no observation'];
  }
  final failures = <String>[];
  final ids = <String>{};
  for (var i = 0; i < lines.length; i++) {
    final match = _observation.firstMatch(lines[i]);
    if (match == null) {
      failures.add('line ${i + 1} is not an observation: ${lines[i]}');
    } else if (!ids.add(match.group(1)!)) {
      failures.add('the id ${match.group(1)} is printed twice');
    }
  }
  return failures;
}

/// What is wrong with a runtime's [output] against the recorded [wanted],
/// which is `null` when there is no recorded file. Equal texts are not
/// enough: two empty ones are equal.
List<String> _observationFailures({
  required String output,
  required String? wanted,
  required String expect,
}) =>
    [
      ..._outputFailures(output),
      if (wanted == null)
        'runtime/$expect is missing: nothing to compare the output with'
      else if (_lines(wanted).isEmpty)
        'runtime/$expect holds no observation'
      else if (output.trim() != wanted.trim())
        'the output differs from runtime/$expect:\n${_diff(wanted, output)}',
    ];

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

// --------------------------------------------------------------- self-test

/// Breaks a copy of the tree in each way a run must not survive, and
/// requires the failure. `true` when every one was reported and every
/// control was clean.
bool _selfTest(Directory fixtures) {
  final problems = <String>[];
  var cases = 0;

  void fails(String name, List<String> failures, String needle) {
    cases++;
    if (!failures.any((failure) => failure.contains(needle))) {
      problems.add(
        '$name: no failure that says "$needle"; '
        '${failures.isEmpty ? 'the run would be green' : 'got:\n    '
            '${failures.join('\n    ')}'}',
      );
    }
  }

  void clean(String name, List<String> failures) {
    cases++;
    if (failures.isNotEmpty) {
      problems.add('$name: a control failed:\n    ${failures.join('\n    ')}');
    }
  }

  /// [check] over a copy of the tree that [breaking] has changed.
  void on(
      void Function(Directory tree) breaking, void Function(Directory) check) {
    final tree = Directory(
      Directory.systemTemp
          .createTempSync('typed_query_self_test_')
          .resolveSymbolicLinksSync(),
    );
    try {
      _copyTree(fixtures, tree);
      breaking(tree);
      check(tree);
    } finally {
      tree.deleteSync(recursive: true);
    }
  }

  File at(Directory tree, String path) => File('${tree.path}/$path');

  final files = _fixtureFiles(fixtures);
  // A refused misuse to take away: a marker, and the line it names.
  final negative =
      files.keys.firstWhere((file) => file.startsWith('negative/'));
  final marked = [
    for (var i = 0; i + 1 < files[negative]!.length; i++)
      if (_marker.hasMatch(files[negative]![i]) &&
          !_marker.hasMatch(files[negative]![i + 1]))
        i,
  ].first;
  final positive =
      files.keys.firstWhere((file) => file.startsWith('positive/'));
  final expect = _expectFiles.first;

  // ------------------------------------------------------------ the tree
  on((tree) {}, (tree) {
    clean('the tree as it is committed', _structureFailures(tree));
  });
  on((tree) => at(tree, negative).deleteSync(), (tree) {
    fails(
      'a fixture file deleted',
      _structureFailures(tree),
      'recorded in $_inventory and gone: fixture $negative',
    );
  });
  on((tree) {
    final lines = [...files[negative]!]..removeRange(marked, marked + 2);
    at(tree, negative).writeAsStringSync('${lines.join('\n')}\n');
  }, (tree) {
    fails(
      'a misuse deleted together with its marker',
      _structureFailures(tree),
      'fixture $negative: $_inventory records',
    );
  });
  on((tree) {
    final lines = [...files[negative]!]..removeAt(marked);
    at(tree, negative).writeAsStringSync('${lines.join('\n')}\n');
  }, (tree) {
    fails(
      'a marker deleted, the misuse left',
      _structureFailures(tree),
      'fixture $negative: $_inventory records',
    );
  });
  on(
    (tree) => at(tree, 'positive/unrecorded.dart')
        .writeAsStringSync('library;\n\nvoid unrecorded() {}\n'),
    (tree) {
      fails(
        'a fixture file nobody recorded',
        _structureFailures(tree),
        'not in $_inventory: fixture positive/unrecorded.dart',
      );
    },
  );
  on((tree) => at(tree, positive).writeAsStringSync('\n'), (tree) {
    fails(
      'a fixture file emptied',
      _structureFailures(tree),
      '$positive: an empty fixture',
    );
  });
  on((tree) {
    final file = at(tree, 'runtime/$expect');
    final lines = _lines(file.readAsStringSync())..removeLast();
    file.writeAsStringSync('${lines.join('\n')}\n');
  }, (tree) {
    fails(
      'a recorded observation deleted',
      _structureFailures(tree),
      'observations runtime/$expect: $_inventory records',
    );
  });
  on((tree) => at(tree, 'runtime/$expect').deleteSync(), (tree) {
    fails(
      'a recorded file deleted',
      _structureFailures(tree),
      'runtime/$expect is missing',
    );
  });
  on((tree) => at(tree, 'runtime/$expect').writeAsStringSync(''), (tree) {
    fails(
      'a recorded file emptied',
      _structureFailures(tree),
      'runtime/$expect holds no observation',
    );
  });
  on((tree) => at(tree, _inventory).deleteSync(), (tree) {
    fails(
      'the inventory deleted',
      _structureFailures(tree),
      '$_inventory is missing',
    );
  });
  on((tree) {
    final file = at(tree, _inventory);
    file.writeAsStringSync(
      file.readAsStringSync().replaceFirst(
            RegExp('^observations runtime/$expect lines=\\d+\$',
                multiLine: true),
            'observations runtime/$expect lines=1',
          ),
    );
  }, (tree) {
    fails(
      'the inventory lowered by hand',
      _structureFailures(tree),
      'observations runtime/$expect: $_inventory records lines=1',
    );
  });

  // The tree a review reduced this one to, which the runner then passed:
  // one fixture, a program that prints nothing, no recorded file.
  void emptied(Directory tree) {
    for (final file in files.keys) {
      if (file != positive &&
          !file.startsWith('support/') &&
          file != _program) {
        at(tree, file).deleteSync();
      }
    }
    for (final directory in ['negative', 'boundary']) {
      Directory('${tree.path}/$directory').deleteSync(recursive: true);
    }
    at(tree, _program).writeAsStringSync('void main() {}\n');
    for (final recorded in _expectFiles) {
      at(tree, 'runtime/$recorded').deleteSync();
    }
  }

  on(emptied, (tree) {
    final failures = _structureFailures(tree);
    fails('the emptied tree', failures, 'negative/ holds no fixture');
    fails('the emptied tree', failures, 'no fixture expects a language error');
    fails('the emptied tree', failures, 'runtime/$expect is missing');
    fails('the emptied tree', failures, 'recorded in $_inventory and gone');
  });
  on((tree) {
    emptied(tree);
    at(tree, _inventory).deleteSync();
  }, (tree) {
    fails(
      'the emptied tree, its inventory deleted with it',
      _structureFailures(tree),
      '$_inventory is missing',
    );
    // What --record would be asked to pin: the floors refuse it, with and
    // without the runtime.
    fails(
      'the emptied tree, recorded again without the runtime',
      _structureFailures(tree, record: true),
      'negative/ holds no fixture',
    );
    fails(
      'the emptied tree, recorded again with the runtime',
      _structureFailures(tree, record: true, runtime: true),
      'no fixture expects a language error',
    );
  });
  // The control for recording: a whole tree whose recorded files and
  // inventory are yet to be written may be recorded.
  on((tree) {
    for (final recorded in _expectFiles) {
      at(tree, 'runtime/$recorded').deleteSync();
    }
    at(tree, _inventory).deleteSync();
  }, (tree) {
    clean(
      'a whole tree recorded from nothing',
      _structureFailures(tree, record: true, runtime: true),
    );
    fails(
      'the same without the runtime that would write the recorded files',
      _structureFailures(tree, record: true),
      'runtime/$expect is missing',
    );
  });

  // ----------------------------------------------------- what a runtime prints
  const two = 'A-1 | something done | what happened\n'
      'A-2 | something else | what happened then\n';
  List<String> compared(String output, String? wanted) =>
      _observationFailures(output: output, wanted: wanted, expect: expect);

  clean('the output that was recorded', compared(two, two));
  fails(
    'nothing printed and nothing recorded',
    compared('', ''),
    'printed no observation',
  );
  fails('nothing printed', compared('\n', two), 'printed no observation');
  fails(
    'no recorded file',
    compared(two, null),
    'runtime/$expect is missing',
  );
  fails(
    'an empty recorded file',
    compared(two, '\n'),
    'runtime/$expect holds no observation',
  );
  fails(
    'an outcome that differs',
    compared(two.replaceFirst('what happened then', 'something new'), two),
    'the output differs from runtime/$expect',
  );
  fails(
    'an observation fewer than recorded',
    compared(two.split('\n').first, two),
    'the output differs from runtime/$expect',
  );
  fails(
    'an observation more than recorded',
    compared('${two}A-3 | a third | unrecorded\n', two),
    'the output differs from runtime/$expect',
  );
  const crashed = '${two}Unhandled exception:\n';
  fails(
    'a line that is not an observation, recorded as one',
    compared(crashed, crashed),
    'line 3 is not an observation',
  );
  const twice = '${two}A-2 | something else | once more\n';
  fails(
    'an id printed twice, recorded so',
    compared(twice, twice),
    'the id A-2 is printed twice',
  );

  // ------------------------------------------------------- the whole program
  // One break through the program itself, for the exit code: the functions
  // above report a failure, and this is what the run does with one.
  on((tree) => at(tree, negative).deleteSync(), (tree) {
    final root = Directory(
      Directory.systemTemp
          .createTempSync('typed_query_self_test_root_')
          .resolveSymbolicLinksSync(),
    );
    try {
      _copyTree(tree, Directory('${root.path}/$_fixtures'));
      Directory('${root.path}/packages/query_kit').createSync(recursive: true);
      final result = Process.runSync(
        Platform.resolvedExecutable,
        [Platform.script.toFilePath(), '--no-runtime'],
        workingDirectory: root.path,
      );
      fails(
        'the program over a tree with a fixture deleted',
        [
          if (result.exitCode == 1) result.stderr as String,
        ],
        'recorded in $_inventory and gone: fixture $negative',
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  if (problems.isNotEmpty) {
    stderr.writeln('self-test: ${problems.length} of $cases cases failed:');
    problems.forEach(stderr.writeln);
    return false;
  }
  stdout.writeln(
    'self-test: $cases cases; every break of the tree and of the output is '
    'reported, every control is clean.',
  );
  return true;
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
