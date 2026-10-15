// What holds the example to the repository around it. Not in the package
// archive (`.pubignore`): it reads files the archive does not hold.
//
// The seed is a copy of the showcase server's, because the archive cannot
// reach that file and the in-memory backend must answer as the server does.
// And every hook the package exports is called by the app and has a test in
// both end-to-end suites, by name: a `test.describe('<hook>', …)` in
// `e2e/tests/` and a `group('<hook>', …)` in `integration_test/`, each with
// a test in it and nothing skipped. A hook added to the package fails here
// until the example uses it and both suites test it.
//
// This is a catalogue, not the proof: whether those tests pass is for the
// suites themselves, which CI runs.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// [source] with its comments blanked out and, unless [keepStrings], its
/// string literals too: Dart's, and a template literal's in TypeScript.
/// Every other character stays where it was, so a position in one is the
/// same position in the other.
String _code(String source, {bool keepStrings = false}) {
  final out = StringBuffer();
  var i = 0;
  void copy(int end, {required bool keep}) {
    for (; i < end && i < source.length; i++) {
      out.write(keep || source[i] == '\n' ? source[i] : ' ');
    }
  }

  final quote = RegExp("r?('''|\"\"\"|'|\"|`)");
  while (i < source.length) {
    if (source.startsWith('//', i)) {
      final end = source.indexOf('\n', i);
      copy(end < 0 ? source.length : end, keep: false);
    } else if (source.startsWith('/*', i)) {
      var depth = 0;
      var j = i;
      do {
        if (source.startsWith('/*', j)) {
          depth += 1;
          j += 2;
        } else if (source.startsWith('*/', j)) {
          depth -= 1;
          j += 2;
        } else {
          j += 1;
        }
      } while (depth > 0 && j < source.length);
      copy(j, keep: false);
    } else if (quote.matchAsPrefix(source, i) case final match?
        when i == 0 || !RegExp(r'\w').hasMatch(source[i - 1])) {
      final raw = match.group(0)!.startsWith('r');
      final delimiter = match.group(1)!;
      var j = match.end;
      while (j < source.length && !source.startsWith(delimiter, j)) {
        if (!raw && source[j] == r'\') {
          j += 2;
        } else if (!raw && source.startsWith(r'${', j)) {
          var depth = 0;
          do {
            if (source[j] == '{') depth += 1;
            if (source[j] == '}') depth -= 1;
            j += 1;
          } while (depth > 0 && j < source.length);
        } else {
          j += 1;
        }
      }
      copy(j + delimiter.length, keep: keepStrings);
    } else {
      out.write(source[i]);
      i += 1;
    }
  }
  return out.toString();
}

/// The hooks [source] declares at the top level: an identifier `use…`,
/// followed by its type parameters and a parameter list, outside every
/// bracket and outside every initializer and expression body. A call is
/// never there, so whatever the return type looks like, this finds the
/// declarations and only them.
Set<String> _declaredHooks(String source) {
  final code = _code(source);
  final name = RegExp(r'use[A-Z]\w*');
  final hooks = <String>{};
  var depth = 0;
  var inExpression = false;
  var i = 0;
  while (i < code.length) {
    final char = code[i];
    if ('([{'.contains(char)) {
      depth += 1;
    } else if (')]}'.contains(char)) {
      depth -= 1;
    } else if (depth == 0 && char == '=') {
      inExpression = true;
    } else if (depth == 0 && char == ';') {
      inExpression = false;
    } else if (depth == 0 && !inExpression) {
      final match = name.matchAsPrefix(code, i);
      if (match != null &&
          (i == 0 || !RegExp(r'[\w.$]').hasMatch(code[i - 1]))) {
        var j = match.end;
        while (j < code.length && code[j].trim().isEmpty) {
          j += 1;
        }
        if (j < code.length && code[j] == '<') {
          var angle = 0;
          do {
            if (code[j] == '<') angle += 1;
            if (code[j] == '>') angle -= 1;
            j += 1;
          } while (angle > 0 && j < code.length);
          while (j < code.length && code[j].trim().isEmpty) {
            j += 1;
          }
        }
        if (j < code.length && code[j] == '(') {
          hooks.add(match.group(0)!);
        }
        i = match.end;
        continue;
      }
    }
    i += 1;
  }
  return hooks;
}

/// The files `lib/query_kit_hooks.dart` exports from `src/`, whole: an
/// export with `show` or `hide` would make the declarations a wrong answer,
/// so it fails here.
List<File> _exportedSources() {
  final library = _code(
    File('../lib/query_kit_hooks.dart').readAsStringSync(),
    keepStrings: true,
  );
  final exports = RegExp(r"export\s+'(src/[^']+)'\s*([^;]*);");
  return [
    for (final match in exports.allMatches(library))
      if (match.group(2)!.trim().isNotEmpty)
        throw StateError('export ${match.group(1)} ${match.group(2)}: '
            'narrowed, which this test does not read')
      else
        File('../lib/${match.group(1)}'),
  ];
}

/// What each call of [opening] in [files] says about a hook, by the hook
/// it names in its first argument: the call whole, from its name to its
/// closing parenthesis, comments blanked and strings kept. [opening] ends at
/// the call's opening parenthesis.
Map<String, List<String>> _calls(Iterable<File> files, RegExp opening) {
  final calls = <String, List<String>>{};
  for (final file in files) {
    final source = file.readAsStringSync();
    // The name is a string, so it is read from the kept text; where the call
    // ends is read from the text without strings, where no bracket is quoted.
    final kept = _code(source, keepStrings: true);
    final bare = _code(source);
    for (final match in opening.allMatches(bare)) {
      var depth = 0;
      var j = match.end - 1;
      do {
        if ('([{'.contains(bare[j])) depth += 1;
        if (')]}'.contains(bare[j])) depth -= 1;
        j += 1;
      } while (depth > 0 && j < bare.length);
      final call = kept.substring(match.start, j);
      final name = RegExp(r"""^[^(]*\(\s*['"](use\w+)['"]""").firstMatch(call);
      if (name != null) {
        calls.putIfAbsent(name.group(1)!, () => []).add(call);
      }
    }
  }
  return calls;
}

Iterable<File> _files(String directory, String suffix) => Directory(directory)
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith(suffix));

String _read(Iterable<File> files) =>
    files.map((file) => _code(file.readAsStringSync())).join('\n');

void main() {
  test('the seed is the showcase server’s, byte for byte', () {
    expect(
      File('assets/seed.json').readAsStringSync(),
      File('../../../examples/showcase/server/seed.json').readAsStringSync(),
    );
  });

  test(
      'the declarations are found whatever their return type, and nothing '
      'else is', () {
    const source = r'''
/// A comment naming useInComment(…).
QueryResult<T> useA<T>(QueryObserverOptions<T> options) => useQuery(options);
({QueryResult<T> value}) useB<T>(
  QueryObserverOptions<T> options,
) =>
    (value: useQuery(options));
void Function() useC() {
  final inner = useD(); // a call, in a body
  return () => useE();
}
List<String>
    useF({String text = 'useInString()'}) => const [];
final useG = useH();
typedef UseI = int Function(int);
String get useJ => 'useK()';
/* useL() */ Map<String, int> useM(
    {int Function(int) map = _identity}) => {};
''';
    expect(_declaredHooks(source), {'useA', 'useB', 'useC', 'useF', 'useM'});
  });

  test(
      'a call is read to its closing parenthesis, past quoted brackets and '
      'comments', () {
    final file = File('${Directory.systemTemp.createTempSync().path}/a.ts')
      ..writeAsStringSync(r'''
test.describe('useA', () => {
  // test.skip('in a comment')
  const glob = '**/*.ts) {';
  test(`a ${'('} test`, async () => {});
});
test.describe.serial('useB', () => {});
test.describe('shell', () => { test('not a hook', () => {}); });
''');
    final calls = _calls([file], RegExp(r'\btest\.describe(\.\w+)?\s*\('));
    expect(calls.keys, ['useA', 'useB']);
    expect(calls['useA']!.single, endsWith('});\n})'));
    expect(calls['useA']!.single, isNot(contains('skip')));
    expect(calls['useB']!.single, "test.describe.serial('useB', () => {})");
  });

  group('every exported hook', () {
    final hooks = {
      for (final file in _exportedSources())
        ..._declaredHooks(file.readAsStringSync()),
    };

    test('is found where the package declares it', () {
      // A scan that finds nothing would pass everything below.
      expect(hooks, hasLength(greaterThanOrEqualTo(13)));
      expect(
          hooks, containsAll(['useQuery', 'useMutation', 'useInfiniteQuery']));
    });

    final app = _read(_files('lib', '.dart'));
    final browser = _calls(
      _files('e2e/tests', '.spec.ts'),
      RegExp(r'\btest\.describe(\.\w+)?\s*\('),
    );
    final native = _calls(
      _files('integration_test', '.dart'),
      RegExp(r'\bgroup\s*\('),
    );

    for (final hook in hooks) {
      test('$hook: called by the app, tested in the browser and natively', () {
        expect(app, matches(RegExp('\\b$hook\\s*[<(]')),
            reason: '$hook is not called in lib/');

        final describes = browser[hook] ?? const [];
        expect(describes, isNotEmpty,
            reason: 'e2e/tests/ has no test.describe for $hook');
        for (final describe in describes) {
          expect(describe, matches(RegExp(r'\btest\s*\(')),
              reason: 'a test.describe for $hook holds no test');
          expect(
            describe,
            isNot(matches(RegExp(r'\.(skip|fixme|fail|only)\b'))),
            reason: 'a test.describe for $hook skips, or narrows the run',
          );
        }

        final groups = native[hook] ?? const [];
        expect(groups, isNotEmpty,
            reason: 'integration_test/ has no group for $hook');
        for (final group in groups) {
          expect(group, matches(RegExp(r'\b(nativeTest|testWidgets)\s*\(')),
              reason: 'a group for $hook holds no test');
          expect(group, isNot(matches(RegExp(r'\bskip\s*:'))),
              reason: 'a group for $hook skips');
        }
      });
    }
  });
}
