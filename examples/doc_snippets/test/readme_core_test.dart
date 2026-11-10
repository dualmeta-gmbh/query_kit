/// The core README's quick start, run top to bottom.
///
/// `site_fences_test.dart` holds the README's fences to `lib/readme_core.dart`;
/// this runs that code. The page says the raw-key form reaches the same
/// entries as the typed one: a raw read or write of another type than the
/// definition's would throw a `QueryDataTypeError` here, so a run that
/// completes, printing what the observer saw, is what backs the sentence.
library;

import 'dart:async';

import 'package:doc_snippets/readme_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the quick start runs, typed and raw on the same entries', () async {
    final List<String> printed = <String>[];
    await runZoned(
      () => readmeQuickStart('1'),
      zoneSpecification: ZoneSpecification(
        print: (_, __, ___, String line) => printed.add(line),
      ),
    );

    expect(printed.first, 'loading');
    // What the observer of `tasks.detail('1')` saw, among the other lines:
    // the typed update, the refetch the invalidations started, then the raw
    // update of the same entry.
    expect(
      printed,
      containsAllInOrder(<String>[
        'Renamed',
        'Draft the changelog',
        'Renamed',
      ]),
    );
    // The raw read found the entry the typed definition had filled.
    expect(printed, contains('0 Draft the changelog'));
  });
}
