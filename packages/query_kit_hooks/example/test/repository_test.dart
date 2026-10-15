// What holds the example to the repository around it. Not in the package
// archive (`.pubignore`): it reads files the archive does not hold.
//
// The seed is a copy of the showcase server's, because the archive cannot
// reach that file and the in-memory backend must answer as the server does.
// And every hook the package exports is called by the app and proven in both
// end-to-end suites, by name: one `test.describe('<hook>', …)` in
// `e2e/tests/` and one `group('<hook>', …)` in `integration_test/`. A hook
// added to the package fails here until the example uses it and both suites
// prove it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The hooks `../lib/src/` declares at the top level: a declaration starts
/// at the first column with its return type, and the name follows on that
/// line or, indented, on the next.
Set<String> _exportedHooks() {
  final declaration = RegExp(
    r'^[A-Za-z][\w<>?, ]*[\w>?](?:\s+|\n\s+)(use[A-Z]\w*)\s*[<(]',
    multiLine: true,
  );
  return {
    for (final file in _dartFiles('../lib/src'))
      for (final match in declaration.allMatches(file.readAsStringSync()))
        match.group(1)!,
  };
}

Iterable<File> _dartFiles(String directory) => Directory(directory)
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'));

String _read(Iterable<File> files) =>
    files.map((file) => file.readAsStringSync()).join('\n');

void main() {
  test('the seed is the showcase server’s, byte for byte', () {
    expect(
      File('assets/seed.json').readAsStringSync(),
      File('../../../examples/showcase/server/seed.json').readAsStringSync(),
    );
  });

  group('every exported hook', () {
    final hooks = _exportedHooks();

    test('is found where the package declares it', () {
      // A pattern that finds nothing would pass everything below.
      expect(hooks, hasLength(greaterThanOrEqualTo(13)));
      expect(
          hooks, containsAll(['useQuery', 'useMutation', 'useInfiniteQuery']));
    });

    final app = _read(_dartFiles('lib'));
    final browser = _read(Directory('e2e/tests')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.spec.ts')));
    final native = _read(_dartFiles('integration_test'));

    for (final hook in hooks) {
      test('$hook: called by the app, proven in the browser and natively', () {
        expect(app, matches(RegExp('\\b$hook\\s*[<(]')),
            reason: '$hook is not called in lib/');
        expect(browser, contains("test.describe('$hook'"),
            reason: 'e2e/tests/ has no describe for $hook');
        expect(native, contains("group('$hook'"),
            reason: 'integration_test/ has no group for $hook');
      });
    }
  });
}
