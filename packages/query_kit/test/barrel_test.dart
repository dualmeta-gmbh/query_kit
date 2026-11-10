// What the barrel hides, asserted rather than assumed: the ninth review's
// API decisions (C21, C23, C24) changed the list
// (https://github.com/dualmeta-gmbh/query_kit/issues/43). Dart offers no
// runtime view of an export's combinators without `dart:mirrors`, which the
// Flutter-bundled SDK does not ship, so the source is read; the positive
// half — every name a consumer may write — is the import below compiling
// on every platform.
@TestOn('vm')
library;

import 'dart:io';

import 'package:query_kit/query_kit.dart';
import 'package:test/test.dart';

void main() {
  final barrel = File('lib/query_kit.dart').readAsStringSync();

  /// The `hide` list of the barrel's export of `src/<file>.dart`.
  Set<String> hidden(String file) {
    final export = RegExp("export 'src/$file.dart'(?:\\s+hide\\s+([^;]+))?;")
        .firstMatch(barrel);
    expect(export, isNotNull, reason: 'src/$file.dart is exported');
    final list = export!.group(1);
    return list == null
        ? const {}
        : list.split(',').map((name) => name.trim()).toSet();
  }

  test('C23.6 FetchBehavior and FetchContext are exported, the cache refs not',
      () {
    expect(hidden('query'), {'QueryCacheRef'});
    expect(hidden('mutation'), {'MutationCacheRef'});
    // Nameable through the barrel: the type of `QueryOptions.behavior`.
    expect(<Type>[FetchBehavior, FetchContext], hasLength(2));
  });

  test('C24 the observer-internal paging aliases are hidden', () {
    expect(hidden('infinite_query_observer'),
        {'hasNextPageOf', 'hasPreviousPageOf'});
  });

  test('the paging plumbing and the toString helper stay hidden', () {
    expect(hidden('infinite_query'), {
      'InfiniteQueryBehavior',
      'addToEnd',
      'addToStart',
      'hasNextPage',
      'hasPreviousPage',
      'nextPageParam',
      'previousPageParam',
    });
    expect(hidden('filters'), {'describeFilters'});
  });

  test('R3-1 the set walk\'s bucket function stays hidden', () {
    expect(hidden('structural_sharing'), {'sharingBucketOf'});
  });

  // The typed query definitions add ten types and nothing else: no typedef,
  // no top-level function, no extension (the plan's "Final surface").
  test('the typed query library exports ten types, and only types', () {
    expect(hidden('query_definition'), isEmpty);
    expect(
      <Type>[
        QueryTarget,
        QueryNamespace,
        TypedQueryKey,
        QueryEntryRef,
        QueryRef,
        InfiniteQueryRef,
        QueryDefinition,
        QueryFamily,
        InfiniteQueryDefinition,
        InfiniteQueryFamily,
      ],
      hasLength(10),
    );

    final lines = File('lib/src/query_definition.dart').readAsLinesSync();
    final classes = <String>{};
    final others = <String>[];
    final classPattern = RegExp(r'^(?:[a-z]+ )*class (\w+)');
    final namePattern = RegExp(r'(\w+)(?:<[\w, ]*>)?\(');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      // A declaration starts in the first column.
      if (!line.startsWith(RegExp('[A-Za-z]')) ||
          line.startsWith('import ') ||
          line.startsWith('library')) {
        continue;
      }
      final declared = classPattern.firstMatch(line);
      if (declared != null) {
        classes.add(declared.group(1)!);
        continue;
      }
      // A function, whose name may be on the line after its return type.
      final name = namePattern.firstMatch('$line ${lines[i + 1]}')?.group(1);
      others.add(name ?? line);
    }
    expect(classes.where((name) => !name.startsWith('_')), {
      'QueryTarget',
      'QueryNamespace',
      'TypedQueryKey',
      'QueryEntryRef',
      'QueryRef',
      'InfiniteQueryRef',
      'QueryDefinition',
      'QueryFamily',
      'InfiniteQueryDefinition',
      'InfiniteQueryFamily',
    });
    expect(others, isNotEmpty);
    expect(others.where((name) => !name.startsWith('_')), isEmpty);
  });
}
