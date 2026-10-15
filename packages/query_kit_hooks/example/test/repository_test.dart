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
// at the top of `main` are the shapes it is known to read. Where a scanner
// cannot tell, it fails rather than guess: a `/` that only a parser could
// call a division or a regular expression, and a test a helper registers,
// which is not seen, so its hook fails here rather than passing unproven.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

/// [source], Dart, with its comments blanked out and, unless [keepStrings],
/// the text of its string literals too. The code in an interpolation is code,
/// and stays. Every other character stays where it was, so a position in one
/// is the same position in the other.
String _code(String source, {bool keepStrings = false}) {
  final out = StringBuffer();
  var i = 0;
  void copy(int end, {required bool keep}) {
    for (; i < end && i < source.length; i++) {
      out.write(keep || source[i] == '\n' ? source[i] : ' ');
    }
  }

  // For each open brace, the closing quote of the string whose
  // interpolation it opened, or null.
  final braces = <String?>[];
  // A string's text from [i]: to and past its closing [quote], or to and
  // past the next `${`.
  void text(String quote, {required bool raw}) {
    var j = i;
    while (j < source.length && !source.startsWith(quote, j)) {
      if (!raw && source[j] == r'\') {
        j += 2;
      } else if (!raw && source.startsWith(r'${', j)) {
        copy(j + 2, keep: keepStrings);
        braces.add(quote);
        return;
      } else {
        j += 1;
      }
    }
    copy(j + quote.length, keep: keepStrings);
  }

  while (i < source.length) {
    final quote = _dartQuote.matchAsPrefix(source, i);
    if (_commentEnd(source, i, typescript: false) case final end?) {
      copy(end, keep: false);
    } else if (quote != null &&
        (i == 0 || !RegExp(r'[\w$]').hasMatch(source[i - 1]))) {
      copy(quote.end, keep: keepStrings);
      text(quote.group(1)!, raw: quote.group(0)!.startsWith('r'));
    } else if (source[i] == '}' && braces.isNotEmpty && braces.last != null) {
      copy(i + 1, keep: keepStrings);
      text(braces.removeLast()!, raw: false);
    } else {
      if (source[i] == '{') braces.add(null);
      if (source[i] == '}' && braces.isNotEmpty) braces.removeLast();
      copy(i + 1, keep: true);
    }
  }
  return out.toString();
}

final RegExp _dartQuote = RegExp("r?('''|\"\"\"|'|\")");

/// What a `/` is after the TypeScript read so far.
enum _Slash { regExp, division, unknown }

/// [source], TypeScript, as [_code] has it for Dart: comments blanked out
/// and, unless [keepStrings], the text of strings, templates and regular
/// expressions too.
///
/// It reads the code token by token, because the token before a `/` is what
/// tells a regular expression from a division. After a name, a literal, `]`,
/// `)` or a non-null `!` it divides; after an operator, an opening bracket,
/// a keyword that an expression follows or the `)` of a condition, a regular
/// expression starts. After `}`, `.`, `++`, `--`, `>` or `of` only a parser
/// could tell, and it throws: the catalogue fails rather than misread.
String _typeScriptCode(String source, {bool keepStrings = false}) {
  final out = StringBuffer();
  var i = 0;
  void copy(int end, {required bool keep}) {
    for (; i < end && i < source.length; i++) {
      out.write(keep || source[i] == '\n' ? source[i] : ' ');
    }
  }

  Never unreadable(String what) {
    final line = '\n'.allMatches(source.substring(0, i)).length + 1;
    throw StateError('line $line: $what, which this test does not read');
  }

  var slash = _Slash.regExp;
  // The last two tokens, a member's name with its dot; and whether a line
  // ended since the last.
  var last = '';
  var beforeLast = '';
  var lineBreak = false;
  // For each open parenthesis, whether it holds a condition; for each open
  // brace, whether it opened a template's interpolation.
  final parens = <bool>[];
  final braces = <bool>[];
  // A template's text from [i]: to and past its closing backtick, or to and
  // past the next `${`.
  void template() {
    var j = i;
    while (j < source.length && source[j] != '`') {
      if (source[j] == r'\') {
        j += 2;
      } else if (source.startsWith(r'${', j)) {
        copy(j + 2, keep: keepStrings);
        braces.add(true);
        slash = _Slash.regExp;
        return;
      } else {
        j += 1;
      }
    }
    if (j >= source.length) unreadable('a template that does not end');
    copy(j + 1, keep: keepStrings);
    slash = _Slash.division;
  }

  while (i < source.length) {
    final char = source[i];
    if (_commentEnd(source, i, typescript: true) case final end?) {
      lineBreak = lineBreak || source.substring(i, end).contains('\n');
      copy(end, keep: false);
      continue;
    }
    if (char.trim().isEmpty) {
      lineBreak = lineBreak || char == '\n';
      copy(i + 1, keep: true);
      continue;
    }
    final start = i;
    final member = last == '.' || last == '?.';
    final postfix = slash == _Slash.division && !lineBreak;
    lineBreak = false;
    if (char == '/') {
      switch (slash) {
        case _Slash.regExp:
          final end = _regExpEnd(source, i) ??
              unreadable('a regular expression that does not end');
          copy(end, keep: keepStrings);
          slash = _Slash.division;
        case _Slash.division:
          copy(i + (source.startsWith('/=', i) ? 2 : 1), keep: true);
          slash = _Slash.regExp;
        case _Slash.unknown:
          unreadable('a / after `$last`, a division or a regular expression');
      }
    } else if (char == "'" || char == '"') {
      var j = i + 1;
      while (j < source.length && source[j] != char && source[j] != '\n') {
        j += source[j] == r'\' ? 2 : 1;
      }
      if (j >= source.length || source[j] != char) {
        unreadable('a string that does not end');
      }
      copy(j + 1, keep: keepStrings);
      slash = _Slash.division;
    } else if (char == '`') {
      copy(i + 1, keep: keepStrings);
      template();
    } else if (char == '}' && braces.isNotEmpty && braces.last) {
      braces.removeLast();
      copy(i + 1, keep: keepStrings);
      template();
    } else if (_word.matchAsPrefix(source, i) case final word?) {
      copy(word.end, keep: true);
      slash = member
          ? _Slash.division
          : _expressionKeywords.contains(word[0])
              ? _Slash.regExp
              : word[0] == 'of'
                  ? _Slash.unknown
                  : _Slash.division;
    } else if (_punctuator.matchAsPrefix(source, i) case final punctuator?) {
      copy(punctuator.end, keep: true);
      switch (punctuator[0]!) {
        case '(':
          parens.add(_conditions.contains(last) ||
              (last == 'await' && beforeLast == 'for'));
          slash = _Slash.regExp;
        case ')':
          slash = parens.isNotEmpty && parens.removeLast()
              ? _Slash.regExp
              : _Slash.division;
        case ']':
          slash = _Slash.division;
        case '{':
          braces.add(false);
          slash = _Slash.regExp;
        case '}':
          if (braces.isNotEmpty) braces.removeLast();
          slash = _Slash.unknown;
        case '!':
          slash = postfix ? _Slash.division : _Slash.regExp;
        case '.' || '?.' || '++' || '--' || '>' || '>>' || '>>>':
          slash = _Slash.unknown;
        default:
          slash = _Slash.regExp;
      }
    } else {
      copy(i + 1, keep: true);
      slash = _Slash.unknown;
    }
    beforeLast = last;
    last = (member && _word.hasMatch(source[start]) ? '.' : '') +
        source.substring(start, i);
  }
  return out.toString();
}

/// A name, a keyword or a number, as far as telling a `/` needs: a number's
/// fraction is a member, and divides the same.
final RegExp _word = RegExp(r'[\w$#\u0080-￿]+');

/// TypeScript's operators and brackets, the longest first. A `/` is not
/// one: what it is depends on what precedes it.
final RegExp _punctuator = RegExp(
  r'>>>=|\.\.\.|===|!==|\*\*=|<<=|>>=|>>>|&&=|\|\|=|\?\?=|=>|==|!=|<=|>=|'
  r'&&|\|\||\?\?|\?\.(?!\d)|\+\+|--|\+=|-=|\*=|%=|&=|\|=|\^=|\*\*|<<|>>|'
  r'[{}()\[\];,<>+\-*%&|^!~?:=.@]',
);

/// The keywords that an expression follows, so a `/` after them starts a
/// regular expression.
const Set<String> _expressionKeywords = {
  'await', 'case', 'default', 'delete', 'do', 'else', 'in', //
  'instanceof', 'new', 'return', 'throw', 'typeof', 'void', 'yield',
};

/// The keywords whose `(` holds a condition, so a `/` after its `)` starts a
/// regular expression.
const Set<String> _conditions = {'if', 'while', 'for', 'with'};

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

/// Where the regular-expression literal that starts at [i] ends, past its
/// flags; null if the line ends first.
int? _regExpEnd(String source, int i) {
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
      while (j < source.length && RegExp(r'[\w$]').hasMatch(source[j])) {
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

/// The files of [library], in [package], whose declarations it exports:
/// itself, the files it exports from its own package, whole, by a relative
/// URI or a `package:` one, the files those export in turn, and every file's
/// parts.
/// An export with `show`, `hide` or a condition would make the declarations
/// a wrong answer, so it fails here, whatever URI it names. An export of
/// another package (the binding) is not read: it declares no hook.
List<File> _librarySources(File library, {required String package}) {
  final directive = RegExp(
    r"""\b(export|part)\s+(['"])([^'"]+)\2\s*([^;]*);""",
  );
  final own = 'package:$package/';
  final files = <String, File>{};
  void visit(File file) {
    final code = _code(file.readAsStringSync(), keepStrings: true);
    for (final match in directive.allMatches(code)) {
      final uri = match.group(3)!;
      if (match.group(4)!.trim().isNotEmpty) {
        throw StateError('${match.group(1)} $uri ${match.group(4)}: not a '
            'whole file, which this test does not read');
      }
      if (!uri.startsWith(own) &&
          (uri.startsWith('package:') || uri.startsWith('dart:'))) {
        continue;
      }
      final target = File.fromUri(
        uri.startsWith(own)
            ? library.parent.uri.resolve(uri.substring(own.length))
            : file.uri.resolve(uri),
      );
      if (files.putIfAbsent(target.absolute.path, () => target) == target) {
        visit(target);
      }
    }
  }

  files[library.absolute.path] = library;
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
    final read = typescript ? _typeScriptCode : _code;
    final String kept;
    final String bare;
    try {
      kept = read(source, keepStrings: true);
      bare = read(source);
    } on StateError catch (error) {
      throw StateError('${file.path}, ${error.message}');
    }
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

/// A test call in a `test.describe`'s bare text: `test(`, not a member
/// such as a regular expression's `.test(`, whatever space is before it.
final RegExp _browserTest = RegExp(r'(?<![\w$#])(?<!\.\s*)test\s*\(');

/// A run narrowed or skipped in a `test.describe`'s bare text: a modifier's
/// name, however it is reached; or `test` neither called nor followed by a
/// member's name, which is how one would reach a modifier without it.
final RegExp _browserSkip = RegExp(
  r'(?<![\w$#])(skip|fixme|fail|only)(?![\w$])|'
  r'(?<![\w$#])(?<!\.\s*)test(?![\w$])(?!\s*(\(|\.\s*[\w$]))',
);

/// A test call in a `group`'s bare text, and a skip: the argument, or
/// the call that skips from inside a test.
final RegExp _nativeTest =
    RegExp(r'(?<![\w$])(?<!\.\s*)(nativeTest|testWidgets)\s*\(');
final RegExp _nativeSkip =
    RegExp(r'(?<![\w$])(skip\s*:|markTestSkipped(?![\w$]))');

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
    File('${root.path}/src/d.dart').writeAsStringSync('void useD() {}\n');
    final library = File('${root.path}/library.dart')
      ..writeAsStringSync(
        "export 'package:other/other.dart';\nexport 'src/a.dart';\n"
        "export 'package:self/src/d.dart';\nvoid useRoot() {}\n",
      );
    expect(
      {
        for (final file in _librarySources(library, package: 'self'))
          ..._declaredHooks(file.readAsStringSync()),
      },
      {'useA', 'useB', 'useC', 'useD', 'useRoot'},
    );

    for (final directive in [
      "export 'src/c.dart' show useC;",
      "export 'package:other/other.dart' if (dart.library.io) 'src/c.dart';",
      "export 'package:other/other.dart' hide useOther;",
    ]) {
      final narrowed = File('${root.path}/narrowed.dart')
        ..writeAsStringSync('$directive\n');
      expect(
        () => _librarySources(narrowed, package: 'self'),
        throwsStateError,
        reason: directive,
      );
    }
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

  test('a slash starts a regular expression or divides, by what precedes it',
      () {
    final file = _scratch('b.spec.ts', r'''
test.describe('useA', () => {
  if (ready) /["(]/.test('x');
  if /* a comment */ (ready) /["]/.test('x');
  for await (const line of lines) /["]/.test(line);
  test('after a condition', () => {});
});
test.describe('useB', () => {
  test('after a name, a member, a bracket or a non-null', () => {
    const ratio = myreturn / items[0] / (count) / total! / page.size / 2;
    test.skip(); /abc/.test('abc');
  });
});
test.describe('useC', () => { /a/.test('a'); /b/. test('b'); c?.test(1); });
function proof() { test('in a helper', () => {}); }
test.describe('useD', () => { proof(); });
test.describe('useE', () => {
  const label = `${ /}/.test(x) ? '`' : `${'}'}` }`;
  test('after a template', () => {});
});
''');
    final calls = _calls([file], RegExp(r'\btest\.describe(\.\w+)?\s*\('));
    expect(calls.keys, ['useA', 'useB', 'useC', 'useD', 'useE']);
    expect(calls['useA']!.single.bare, matches(_browserTest));
    expect(calls['useA']!.single.bare, isNot(matches(_browserSkip)));
    expect(calls['useB']!.single.bare, matches(_browserSkip));
    // A member called `test` is not a test.
    expect(calls['useC']!.single.bare, isNot(matches(_browserTest)));
    // Nor is a helper's: the hook fails here rather than pass unproven.
    expect(calls['useD']!.single.bare, isNot(matches(_browserTest)));
    expect(calls['useE']!.single.bare, matches(_browserTest));

    // Where the tokens before a `/` cannot tell, nothing is read.
    for (final source in [
      'const block = () => {}\n/["]/.test(x);',
      'const ratio = <any>{valueOf: () => 4} / 2;',
      'i++ / 2;',
      'const n = x as Array<number> / 2;',
      'for (const x of /re/.exec(y)) {}',
      'const half = 1./2;',
      'const open = /abc',
      "const text = 'abc",
      'const text = `abc',
    ]) {
      expect(() => _typeScriptCode(source), throwsStateError, reason: source);
    }
  });

  test('a skip is seen however it is spelled', () {
    final file = _scratch('c.spec.ts', r'''
test.describe('useA', () => { test(`${test.skip()}`, () => {}); });
test.describe('useB', () => { const { skip } = test; skip(); });
test.describe('useC', () => { const t = test; t('aliased', () => {}); });
test.describe('useD', () => { test('d', (_, info) => { info.fixme(); }); });
test.describe('useE', () => { test('e', () => {}); test.step; });
''');
    final calls = _calls([file], RegExp(r'\btest\.describe(\.\w+)?\s*\('));
    for (final hook in ['useA', 'useB', 'useC', 'useD']) {
      expect(calls[hook]!.single.bare, matches(_browserSkip), reason: hook);
    }
    expect(calls['useE']!.single.bare, isNot(matches(_browserSkip)));
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
group('useE', () {
  nativeTest('${markTestSkipped('e')}', (tester, h) async {});
});
group('useF', () { h. nativeTest('f', (tester, h) async {}); });
''');
    final calls = _calls([file], RegExp(r'\bgroup\s*\('));
    expect(calls.keys, ['useA', 'useB', 'useC', 'useD', 'useE', 'useF']);
    expect(calls['useA']!.single.bare, matches(_nativeTest));
    expect(calls['useB']!.single.bare, isNot(matches(_nativeTest)));
    expect(calls['useC']!.single.bare, matches(_nativeSkip));
    expect(calls['useD']!.single.kept, endsWith('});\n})'));
    expect(calls['useD']!.single.bare, matches(_nativeTest));
    // The code in an interpolation is code.
    expect(calls['useE']!.single.bare, matches(_nativeSkip));
    expect(calls['useF']!.single.bare, isNot(matches(_nativeTest)));
  });

  group('every exported hook', () {
    final hooks = {
      for (final file in _librarySources(
        File('../lib/query_kit_hooks.dart'),
        package: 'query_kit_hooks',
      ))
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
