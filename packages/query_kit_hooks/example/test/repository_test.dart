// What holds the example to the repository around it. Not in the package
// archive (`.pubignore`): it reads files the archive does not hold.
//
// The seed is a copy of the showcase server's, because the archive cannot
// reach that file and the in-memory backend must answer as the server does.
// And every hook the package exports is used by the app and has a test in
// both end-to-end suites, by name: a `test.describe('<hook>', …)` in
// `e2e/tests/` and a `group('<hook>', …)` in `integration_test/`, each with
// a test in it and nothing skipped. A hook added to the package fails here
// until the example uses it and both suites test it.
//
// This is a catalogue, not the proof: whether those tests pass is for the
// suites themselves, which CI runs. And it reads the source with a scanner,
// not a parser: comments, strings with their interpolations, and
// TypeScript's regular expressions are told apart from code, and the cases
// at the top of `main` are the shapes it is known to read.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

/// [source] with its comments blanked out and, unless [keepStrings], its
/// string literals too: Dart's, or TypeScript's when [typescript], where a
/// regular-expression literal counts as a string. Every other character
/// stays where it was, so a position in one is the same position in the
/// other.
String _code(
  String source, {
  bool keepStrings = false,
  bool typescript = false,
}) {
  final out = StringBuffer();
  var i = 0;
  void copy(int end, {required bool keep}) {
    for (; i < end && i < source.length; i++) {
      out.write(keep || source[i] == '\n' ? source[i] : ' ');
    }
  }

  while (i < source.length) {
    if (_commentEnd(source, i, typescript: typescript) case final end?) {
      copy(end, keep: false);
    } else if (_stringEnd(source, i, typescript: typescript) case final end?) {
      copy(end, keep: keepStrings);
    } else if ((typescript ? _regExpEnd(source, i) : null) case final end?) {
      copy(end, keep: keepStrings);
    } else {
      out.write(source[i]);
      i += 1;
    }
  }
  return out.toString();
}

/// Where the comment that starts at [i] ends, if one does. Dart's block
/// comments nest; TypeScript's do not.
int? _commentEnd(String source, int i, {required bool typescript}) {
  if (source.startsWith('//', i)) {
    final end = source.indexOf('\n', i);
    return end < 0 ? source.length : end;
  }
  if (!source.startsWith('/*', i)) {
    return null;
  }
  if (typescript) {
    final end = source.indexOf('*/', i + 2);
    return end < 0 ? source.length : end + 2;
  }
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
  return j;
}

final RegExp _dartQuote = RegExp("r?('''|\"\"\"|'|\")");
final RegExp _typeScriptQuote = RegExp("['\"`]");

/// Where the string literal that starts at [i] ends, if one does: past its
/// closing quote, and past every interpolation in it on the way, the
/// strings and comments in those included. Every Dart string but a raw one
/// interpolates; in TypeScript only a template literal does.
int? _stringEnd(String source, int i, {required bool typescript}) {
  final match =
      (typescript ? _typeScriptQuote : _dartQuote).matchAsPrefix(source, i);
  if (match == null || (i > 0 && RegExp(r'[\w$]').hasMatch(source[i - 1]))) {
    return null;
  }
  final raw = match.group(0)!.startsWith('r');
  final delimiter = typescript ? match.group(0)! : match.group(1)!;
  final interpolates = typescript ? delimiter == '`' : !raw;
  var j = match.end;
  while (j < source.length && !source.startsWith(delimiter, j)) {
    if (!raw && source[j] == r'\') {
      j += 2;
    } else if (interpolates && source.startsWith(r'${', j)) {
      j = _interpolationEnd(source, j + 2, typescript: typescript);
    } else {
      j += 1;
    }
  }
  return min(j + delimiter.length, source.length);
}

/// Where the code of an interpolation, from [i] just after its `${`, ends:
/// past the `}` that closes it.
int _interpolationEnd(String source, int i, {required bool typescript}) {
  var depth = 1;
  var j = i;
  while (j < source.length) {
    if (_commentEnd(source, j, typescript: typescript) case final end?) {
      j = end;
    } else if (_stringEnd(source, j, typescript: typescript) case final end?) {
      j = end;
    } else {
      if (source[j] == '{') depth += 1;
      if (source[j] == '}') depth -= 1;
      j += 1;
      if (depth == 0) {
        return j;
      }
    }
  }
  return j;
}

/// Where the TypeScript regular-expression literal that starts at [i]
/// ends, if one does. A `/` starts one where an expression can start:
/// first in the file, after an opening bracket, a comma, an operator or
/// `return`; anywhere else it divides.
int? _regExpEnd(String source, int i) {
  if (source[i] != '/' ||
      source.startsWith('//', i) ||
      source.startsWith('/*', i)) {
    return null;
  }
  var k = i - 1;
  while (k >= 0 && source[k].trim().isEmpty) {
    k -= 1;
  }
  if (k >= 0 &&
      !'([{,;:=!&|?+-*%<>~^'.contains(source[k]) &&
      !source.substring(0, k + 1).endsWith('return')) {
    return null;
  }
  var j = i + 1;
  var inClass = false;
  while (j < source.length && source[j] != '\n') {
    final char = source[j];
    if (char == r'\') {
      j += 2;
      continue;
    }
    if (char == '[') {
      inClass = true;
    } else if (char == ']') {
      inClass = false;
    } else if (char == '/' && !inClass) {
      j += 1;
      while (j < source.length && RegExp(r'\w').hasMatch(source[j])) {
        j += 1;
      }
      return j;
    }
    j += 1;
  }
  return null;
}

/// The hooks [source] declares at the top level: an identifier `use…`,
/// followed by its type parameters and a parameter list, or after `get`;
/// outside every bracket and outside every initializer and expression body,
/// and not an annotation. A call is never there, so whatever the return
/// type looks like, this finds the declarations and only them.
Set<String> _declaredHooks(String source) {
  final code = _code(source);
  final name = RegExp(r'use[A-Z]\w*');
  final getter = RegExp(r'\bget\s+$');
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
          (i == 0 || !RegExp(r'[\w$]').hasMatch(code[i - 1]))) {
        var before = i - 1;
        while (before >= 0 && code[before].trim().isEmpty) {
          before -= 1;
        }
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
        final member = before >= 0 && '.@'.contains(code[before]);
        final isGetter = getter.hasMatch(code.substring(max(0, i - 16), i));
        if (!member && (isGetter || (j < code.length && code[j] == '('))) {
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

/// The files of [library] whose declarations it exports: the files it
/// exports from its own package, whole, the files those export in turn, and
/// every file's parts. An export with `show`, `hide` or a condition would
/// make the declarations a wrong answer, so it fails here. An export of
/// another package (the binding) is not read: it declares no hook.
List<File> _librarySources(File library) {
  final directive = RegExp(
    r"""\b(export|part)\s+(['"])([^'"]+)\2\s*([^;]*);""",
  );
  final files = <String, File>{};
  void visit(File file) {
    final code = _code(file.readAsStringSync(), keepStrings: true);
    for (final match in directive.allMatches(code)) {
      final uri = match.group(3)!;
      if (uri.startsWith('package:') || uri.startsWith('dart:')) {
        continue;
      }
      if (match.group(4)!.trim().isNotEmpty) {
        throw StateError('${match.group(1)} $uri ${match.group(4)}: not a '
            'whole file, which this test does not read');
      }
      final target = File.fromUri(file.uri.resolve(uri));
      if (files.putIfAbsent(target.absolute.path, () => target) == target) {
        visit(target);
      }
    }
  }

  visit(library);
  return files.values.toList();
}

/// One call, from its name to its closing parenthesis: [kept] with its
/// strings, [bare] without, comments blanked in both.
typedef _Call = ({String kept, String bare});

/// What each call of [opening] in [files] says about a hook, by the hook
/// it names in its first argument. [opening] ends at the call's opening
/// parenthesis and is matched where no string is.
Map<String, List<_Call>> _calls(Iterable<File> files, RegExp opening) {
  final calls = <String, List<_Call>>{};
  for (final file in files) {
    final source = file.readAsStringSync();
    final typescript = file.path.endsWith('.ts');
    // The name is a string, so it is read from the kept text; where the call
    // ends is read from the bare text, where no bracket is quoted.
    final kept = _code(source, keepStrings: true, typescript: typescript);
    final bare = _code(source, typescript: typescript);
    for (final match in opening.allMatches(bare)) {
      var depth = 0;
      var j = match.end - 1;
      do {
        if ('([{'.contains(bare[j])) depth += 1;
        if (')]}'.contains(bare[j])) depth -= 1;
        j += 1;
      } while (depth > 0 && j < bare.length);
      final call = (
        kept: kept.substring(match.start, j),
        bare: bare.substring(match.start, j),
      );
      final name =
          RegExp(r"""^[^(]*\(\s*['"`](use\w+)['"`]""").firstMatch(call.kept);
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

/// A test call in a `test.describe`'s bare text.
final RegExp _browserTest = RegExp(r'\btest\s*\(');

/// A run narrowed or skipped in a `test.describe`'s bare text: a modifier
/// by name, or any member of `test` reached by index, which is how one
/// would hide a modifier from the name.
final RegExp _browserSkip =
    RegExp(r'\.\s*(skip|fixme|fail|only)\b|\btest(\s*\.\s*\w+)*\s*\[');

/// A test call in a `group`'s bare text, and a skip.
final RegExp _nativeTest = RegExp(r'\b(nativeTest|testWidgets)\s*\(');
final RegExp _nativeSkip = RegExp(r'\bskip\s*:');

/// [contents] as a file of its own, named [name].
File _scratch(String name, String contents) =>
    File('${Directory.systemTemp.createTempSync().path}/$name')
      ..writeAsStringSync(contents);

void main() {
  test('the seed is the showcase server’s, byte for byte', () {
    expect(
      File('assets/seed.json').readAsStringSync(),
      File('../../../examples/showcase/server/seed.json').readAsStringSync(),
    );
  });

  test(
      'the declarations are found whatever their shape, and nothing else '
      'is', () {
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
/* useL() /* nested */ useL2() */ Map<String, int> useM(
    {int Function(int) map = _identity}) => {};
@useN()
external QueryResult<int> useO();
final text = '${identity('x')} and ${'}'}';
void useP() {}
final raw = r'${';
void useQ() {}
final lines = """
useInLines()
""";
T useS<T extends Map<String, List<int>>>(T value) => value;
void useT(void Function(int) callback, {int count = 1}) {}
''';
    expect(_declaredHooks(source), {
      'useA', 'useB', 'useC', 'useF', 'useJ', 'useM', //
      'useO', 'useP', 'useQ', 'useS', 'useT',
    });
  });

  test('a library is read with its exports and their parts, whole', () {
    final root = Directory.systemTemp.createTempSync();
    File('${root.path}/src/a.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        "part 'b.dart';\nexport 'c.dart';\nvoid useA() {}\n",
      );
    File('${root.path}/src/b.dart')
        .writeAsStringSync("part of 'a.dart';\nint get useB => 1;\n");
    File('${root.path}/src/c.dart').writeAsStringSync('void useC() {}\n');
    final library = File('${root.path}/library.dart')
      ..writeAsStringSync(
        "export 'package:other/other.dart';\nexport 'src/a.dart';\n",
      );
    expect(
      {
        for (final file in _librarySources(library))
          ..._declaredHooks(file.readAsStringSync()),
      },
      {'useA', 'useB', 'useC'},
    );

    final narrowed = File('${root.path}/narrowed.dart')
      ..writeAsStringSync("export 'src/c.dart' show useC;\n");
    expect(() => _librarySources(narrowed), throwsStateError);
  });

  test(
      'a describe is read to its closing parenthesis, past strings, '
      'templates, regular expressions and comments', () {
    final file = _scratch('a.spec.ts', r'''
test.describe('useA', () => {
  // test.skip('in a comment')
  const glob = '**/*.ts) {';
  const quote = /["(]/g;
  const ratio = 4 / 2;
  test(`a ${`(`} test`, async () => {});
});
test.describe.serial('useB', () => {});
test.describe('useC', () => { const label = 'test('; });
test.describe('useD', () => { test('skipped', () => { test['skip'](); }); });
test.describe('shell', () => { test('not a hook', () => {}); });
''');
    final calls = _calls([file], RegExp(r'\btest\.describe(\.\w+)?\s*\('));
    expect(calls.keys, ['useA', 'useB', 'useC', 'useD']);
    final a = calls['useA']!.single;
    expect(a.kept, endsWith('});\n})'));
    expect(a.bare, matches(_browserTest));
    expect(a.bare, isNot(matches(_browserSkip)));
    expect(
        calls['useB']!.single.kept, "test.describe.serial('useB', () => {})");
    expect(calls['useC']!.single.bare, isNot(matches(_browserTest)));
    expect(calls['useD']!.single.bare, matches(_browserSkip));
  });

  test('a group is read to its closing parenthesis, past interpolations', () {
    final file = _scratch('a_test.dart', r'''
group('useA', () {
  nativeTest('a', (tester, h) async {});
});
group('useB', () { const label = 'nativeTest('; });
group('useC', () { nativeTest('c', (tester, h) async {}, skip: true); });
group('useD', () {
  final text = '${identity(')')}';
  nativeTest('d', (tester, h) async {});
});
''');
    final calls = _calls([file], RegExp(r'\bgroup\s*\('));
    expect(calls.keys, ['useA', 'useB', 'useC', 'useD']);
    expect(calls['useA']!.single.bare, matches(_nativeTest));
    expect(calls['useB']!.single.bare, isNot(matches(_nativeTest)));
    expect(calls['useC']!.single.bare, matches(_nativeSkip));
    expect(calls['useD']!.single.kept, endsWith('});\n})'));
    expect(calls['useD']!.single.bare, matches(_nativeTest));
  });

  group('every exported hook', () {
    final hooks = {
      for (final file in _librarySources(File('../lib/query_kit_hooks.dart')))
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
      test('$hook: used by the app, tested in the browser and natively', () {
        expect(app, matches(RegExp('(?<![\\w.\$])$hook\\b')),
            reason: '$hook is not used in lib/');

        final describes = browser[hook] ?? const [];
        expect(describes, isNotEmpty,
            reason: 'e2e/tests/ has no test.describe for $hook');
        for (final describe in describes) {
          expect(describe.bare, matches(_browserTest),
              reason: 'a test.describe for $hook holds no test');
          expect(describe.bare, isNot(matches(_browserSkip)),
              reason: 'a test.describe for $hook skips, or narrows the run');
        }

        final groups = native[hook] ?? const [];
        expect(groups, isNotEmpty,
            reason: 'integration_test/ has no group for $hook');
        for (final group in groups) {
          expect(group.bare, matches(_nativeTest),
              reason: 'a group for $hook holds no test');
          expect(group.bare, isNot(matches(_nativeSkip)),
              reason: 'a group for $hook skips');
        }
      });
    }
  });
}
