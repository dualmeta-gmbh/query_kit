/// The check that the hooks guide's and this README's Dart samples are code
/// that compiles — the twin of `examples/doc_snippets/test/site_fences_test.dart`.
///
/// Every other Dart sample on the site has a twin in `examples/doc_snippets`,
/// compiled and analyzed in CI, and that test holds each fence equal to its
/// twin. The hooks samples cannot live there: they need `flutter_hooks`, and
/// no example may depend on a third-party package. So their twins live in
/// this package, under `test/doc_twins/`, where `dart analyze` and
/// `flutter test` see them, and this file holds the fences equal to them.
///
/// A twin marks the region a page shows, as in `doc_snippets`:
///
/// ```dart
/// // >>> guides/hooks.md#use-query
/// final tasks = useQuery(tasksQuery());
/// // <<<
/// ```
///
/// and the fence names it on its metastring with `twin=`:
///
///     ```dart snippet="prose-only: its twin is in query_kit_hooks …" twin="guides/hooks.md#use-query"
///
/// On a site page the fence carries both attributes. `snippet=` is the site
/// check's, and to it the sample is prose-only, because its twin is not in
/// `doc_snippets`; `twin=` is this check's. In the README, which the site
/// check does not read, `twin=` alone.
///
/// The three forms are the site check's, under the new name:
///
/// * `twin="<id> [<id> …]"` — **exact**, character for character once the
///   block's own indentation is out of the way, with one allowance: the
///   twin's last line may carry the `;` or `,` that makes it a statement
///   where the page shows an expression. Several ids are compared as one
///   sample with a blank line between.
/// * `twin="excerpt: <id>"` — the page elides. The id must resolve, and the
///   fence must show a `…`.
/// * `twin="prose-only: <reason>"` — no twin, with the reason recorded.
///
/// What is read: every `dart` fence of `website/docs/guides/hooks.md` and of
/// this package's `README.md`, and any `dart` fence elsewhere on the site
/// that carries `twin=`. An id is `<page>#<slug>`, its page part one of
/// those pages: `guides/hooks.md`, or `packages/query_kit_hooks/README.md`
/// for a sample only the README shows. A fence is found indented as well, in
/// a list item say, where the site check reads only fences at the margin.
///
/// One check more than the site's: every hook this package exports appears
/// in a compiled sample on the guide.
///
/// The files are read through `dart:io`, which a browser does not have, so
/// the cases are skipped when the suite runs compiled to JavaScript.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// The guide, by its path under `website/docs`.
const String _guide = 'guides/hooks.md';

/// This package's README, by its repository path — which is also its page
/// name.
const String _readme = 'packages/query_kit_hooks/README.md';

void main() {
  group('the hooks guide and the README', () {
    late List<_Fence> fences;
    late Map<String, _Region> regions;
    late List<String> duplicateRegionIds;
    late Set<String> hooks;
    late List<String> unread;

    setUpAll(() {
      final repo = _repoRoot();
      fences = _fencesOf(repo);
      unread = _unreadSpellings(repo);
      final (found, duplicates) = _regionsOf(repo);
      regions = found;
      duplicateRegionIds = duplicates;
      hooks = _exportedHooks(repo);
    });

    // A guard on the guard: if a path stops resolving, every other case
    // passes vacuously.
    test('the pages, the twins and the hooks are where this test expects', () {
      expect(fences.where((f) => f.page == _guide), isNotEmpty,
          reason: 'no dart fences found in website/docs/$_guide');
      expect(fences.where((f) => f.page == _readme), isNotEmpty,
          reason: 'no dart fences found in $_readme');
      expect(regions, isNotEmpty,
          reason: 'no regions found under test/doc_twins/');
      expect(hooks, contains('useQuery'),
          reason: 'no exported hooks found under lib/src/');
    });

    // The parser reads a fence opened with three backticks and `dart`, and
    // attributes in double quotes. Markdown takes more spellings than that,
    // and a sample written in one of them would not be read at all, so the
    // others are refused rather than skipped.
    test('no fence or attribute is spelled in a way this check cannot read',
        () {
      expect(
        unread,
        isEmpty,
        reason: 'Write these fences as ```dart at the start of the line, and '
            'their attributes in double quotes:\n  ${unread.join('\n  ')}',
      );
    });

    test('every dart fence names a twin region, or says why it has none', () {
      final unnamed = [
        for (final f in fences)
          if (f.regionIds.isEmpty && f.proseOnlyReason == null) f.where,
      ];
      expect(
        unnamed,
        isEmpty,
        reason: 'These dart fences carry no `twin=`. Add a region under '
            'test/doc_twins/ and name it, or declare '
            'twin="prose-only: <reason>":\n  ${unnamed.join('\n  ')}',
      );
      final reasonless = [
        for (final f in fences)
          if (f.proseOnlyReason != null && f.proseOnlyReason!.trim().isEmpty)
            f.where,
      ];
      expect(reasonless, isEmpty,
          reason: 'prose-only needs a reason after the colon:\n  '
              '${reasonless.join('\n  ')}');
    });

    test("every fence on a site page is prose-only to the site's own check",
        () {
      // Without it the site check asks for a twin in doc_snippets, which
      // cannot import flutter_hooks; with a doc_snippets id, the fence would
      // be held to two twins.
      final unmarked = [
        for (final f in fences)
          if (f.page != _readme && !f.siteProseOnly) f.where,
      ];
      expect(
        unmarked,
        isEmpty,
        reason: 'These fences are on a site page and need '
            'snippet="prose-only: <reason>" beside twin=, for '
            'site_fences_test.dart:\n  ${unmarked.join('\n  ')}',
      );
    });

    test('every fence matches its region, character for character', () {
      for (final f in fences) {
        if (f.regionIds.isEmpty || f.isExcerpt) continue;
        if (f.regionIds.any((id) => !regions.containsKey(id))) {
          continue; // reported by the resolution case below.
        }
        final parts = [for (final id in f.regionIds) regions[id]!];

        final want = <String>[];
        for (final part in parts) {
          if (want.isNotEmpty) want.add('');
          want.addAll(_normalise(part.lines));
        }
        final got = _normalise(f.lines);
        if (_same(want, got)) continue;

        final at = _firstDifference(want, got);
        final from = parts.map((r) => r.where).join(' + ');
        fail(
          '${f.where} has drifted from $from.\n'
          'First difference at line ${at + 1} of the sample:\n'
          '  twin:  ${at < want.length ? want[at] : '(nothing: twin is shorter)'}\n'
          '  fence: ${at < got.length ? got[at] : '(nothing: fence is shorter)'}\n'
          '\n--- the twin (${want.length} lines) ---\n${want.join('\n')}\n'
          '\n--- the fence (${got.length} lines) ---\n${got.join('\n')}\n'
          '\nOne of the two is wrong. Neither is authoritative: the twin is '
          'what compiles, the fence is what a reader copies.',
        );
      }
    });

    test('every region is on the page it names, exactly once', () {
      final byId = <String, List<_Fence>>{};
      for (final f in fences) {
        for (final id in f.regionIds) {
          (byId[id] ??= []).add(f);
        }
      }

      // A twin for a sample somebody deleted still compiles, so nothing
      // else would notice it.
      final orphans = [
        for (final r in regions.values)
          if (!byId.containsKey(r.id)) '${r.id} (${r.where})',
      ];
      expect(orphans, isEmpty,
          reason: 'These regions are marked in a twin and shown on no page. '
              'Delete the markers, or add the fence:\n  '
              '${orphans.join('\n  ')}');

      // One sample on two pages is fine — the README shows the guide's
      // first one. Twice on one page is a mistake.
      final twice = [
        for (final e in byId.entries)
          for (final page in e.value.map((f) => f.page).toSet())
            if (e.value.where((f) => f.page == page).length > 1)
              '${e.key} appears twice on $page',
      ];
      expect(twice, isEmpty,
          reason: 'One region, two fences on one page. Give the second its '
              'own region:\n  ${twice.join('\n  ')}');

      final unknown = [
        for (final f in fences)
          for (final id in f.regionIds)
            if (!id.contains('#'))
              '${f.where} names $id: ids are "<page>#<slug>"'
            else if (id.split('#').first != _guide &&
                id.split('#').first != _readme)
              '${f.where} names $id, whose page part is neither $_guide nor '
                  '$_readme',
      ];
      expect(unknown, isEmpty, reason: unknown.join('\n  '));
    });

    test('every excerpt says so, with an ellipsis a reader can see', () {
      final silent = [
        for (final f in fences)
          if (f.isExcerpt && !f.lines.any((l) => l.contains('…')))
            '${f.where} is marked an excerpt and elides nothing visible: '
                'drop the "excerpt: " prefix and make it match, or show the '
                '… it leaves out',
      ];
      expect(silent, isEmpty, reason: silent.join('\n  '));
    });

    test('every region id is unique and every fence id resolves', () {
      final unresolved = [
        for (final f in fences)
          for (final id in f.regionIds)
            if (!regions.containsKey(id))
              '${f.where} names $id, which no twin marks',
      ];
      expect(unresolved, isEmpty,
          reason: 'A typo here would otherwise skip the comparison '
              'silently:\n  ${unresolved.join('\n  ')}');
      expect(duplicateRegionIds, isEmpty,
          reason: 'The same region id is marked twice in the twins:\n  '
              '${duplicateRegionIds.join('\n  ')}');
    });

    test('every exported hook has a compiled sample on the guide', () {
      final compiled = [
        for (final f in fences)
          if (f.page == _guide && f.regionIds.isNotEmpty) f.lines.join('\n'),
      ].join('\n');
      final missing = [
        for (final hook in hooks)
          if (!RegExp('\\b$hook\\s*[<(]').hasMatch(compiled)) hook,
      ];
      expect(missing, isEmpty,
          reason: 'These hooks are exported and called in no compiled '
              'sample on $_guide:\n  ${missing.join('\n  ')}');
    });
  },
      skip: kIsWeb
          ? 'reads the site, the README and the sources through dart:io, '
              'which a browser does not have'
          : null);
}

// ---------------------------------------------------------------------------
// Comparison — the site check's rules, unchanged
// ---------------------------------------------------------------------------

/// The same lines, once the block's own indentation and trailing whitespace
/// are out of the way, and blank lines at either end dropped.
List<String> _normalise(List<String> lines) {
  final trimmed = [for (final l in lines) l.trimRight()];
  final content = trimmed.where((l) => l.isNotEmpty);
  final indent = content.isEmpty
      ? 0
      : content
          .map((l) => l.length - l.trimLeft().length)
          .reduce((a, b) => a < b ? a : b);
  final dedented = [
    for (final l in trimmed) l.isEmpty ? l : l.substring(indent),
  ];
  var start = 0;
  var end = dedented.length;
  while (start < end && dedented[start].isEmpty) {
    start++;
  }
  while (end > start && dedented[end - 1].isEmpty) {
    end--;
  }
  return dedented.sublist(start, end);
}

/// Identical, except that the twin's last line may carry a trailing `;` or
/// `,` the page does not.
bool _same(List<String> want, List<String> got) {
  if (want.join('\n') == got.join('\n')) return true;
  if (want.isEmpty || got.isEmpty) return false;
  final last = want.last;
  if (last.endsWith(';') || last.endsWith(',')) {
    final withoutSeparator = [
      ...want.sublist(0, want.length - 1),
      last.substring(0, last.length - 1),
    ];
    return withoutSeparator.join('\n') == got.join('\n');
  }
  return false;
}

int _firstDifference(List<String> a, List<String> b) {
  final shorter = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < shorter; i++) {
    if (a[i] != b[i]) return i;
  }
  return shorter;
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

/// A `dart` fence this test is responsible for.
class _Fence {
  _Fence({
    required this.page,
    required this.line,
    required this.lines,
    required this.regionIds,
    required this.isExcerpt,
    required this.proseOnlyReason,
    required this.siteProseOnly,
    required this.hasTwin,
  });

  /// `guides/hooks.md` for a site page, the repository path for the README.
  final String page;
  final int line;
  final List<String> lines;

  /// The regions this fence shows, in order; empty when it is prose-only.
  final List<String> regionIds;
  final bool isExcerpt;
  final String? proseOnlyReason;

  /// Whether the fence declares `snippet="prose-only: …"`, the site check's
  /// exemption.
  final bool siteProseOnly;

  /// Whether the fence carries `twin=` in any form.
  final bool hasTwin;

  String get where => '$page:$line';
}

/// A marked region of a twin file.
class _Region {
  _Region({required this.id, required this.where, required this.lines});

  final String id;
  final String where;
  final List<String> lines;
}

final RegExp _twinAttribute = RegExp(r'twin="([^"]*)"');
final RegExp _snippetAttribute = RegExp(r'snippet="([^"]*)"');

/// The guide's and the README's `dart` fences, and every other site fence
/// that names a twin.
List<_Fence> _fencesOf(Directory repo) {
  final docs = Directory('${repo.path}/website/docs');
  final pages = docs
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.md') || f.path.endsWith('.mdx'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final page in pages)
      for (final fence in _fencesOfPage(
          page,
          page.path
              .substring(docs.path.length + 1)
              .replaceAll(Platform.pathSeparator, '/')))
        if (fence.page == _guide || fence.hasTwin) fence,
    ..._fencesOfPage(File('${repo.path}/$_readme'), _readme),
  ];
}

/// A fence opening this check does not read: tildes, four or more
/// backticks, or an info string after a space.
final RegExp _unreadFence = RegExp(r'^(~{3,}|`{4,}|```[ \t]+\S)');

/// A `twin=` or `snippet=` whose value is not in double quotes.
final RegExp _unreadAttribute = RegExp(r'\b(twin|snippet)=(?!")');

/// Where the guide or the README opens a fence this check would not read,
/// and where any site page spells `twin=` or `snippet=` without double
/// quotes, as `<page>:<line>`.
List<String> _unreadSpellings(Directory repo) {
  final docs = Directory('${repo.path}/website/docs');
  final pages = <(File, String)>[
    for (final page in docs.listSync(recursive: true).whereType<File>())
      if (page.path.endsWith('.md') || page.path.endsWith('.mdx'))
        (
          page,
          page.path
              .substring(docs.path.length + 1)
              .replaceAll(Platform.pathSeparator, '/'),
        ),
    (File('${repo.path}/$_readme'), _readme),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  return [
    for (final (page, rel) in pages)
      for (final (i, line) in page.readAsLinesSync().indexed)
        if (_unreadAttribute.hasMatch(line) ||
            ((rel == _guide || rel == _readme) &&
                _unreadFence.hasMatch(line.trimLeft())))
          '$rel:${i + 1}',
  ];
}

/// The `dart` fences of one page, named [rel].
List<_Fence> _fencesOfPage(File page, String rel) {
  final found = <_Fence>[];
  final lines = page.readAsLinesSync();
  for (var i = 0; i < lines.length; i++) {
    // Indented too: a fence in a list item is still one a reader copies.
    final open = lines[i].trimLeft();
    if (!open.startsWith('```dart')) continue;
    final meta = open.substring('```dart'.length);
    var j = i + 1;
    while (j < lines.length && !lines[j].trimLeft().startsWith('```')) {
      j++;
    }
    final attribute = _twinAttribute.firstMatch(meta)?.group(1);
    final proseOnly = attribute?.startsWith('prose-only:') ?? false;
    final excerpt = attribute?.startsWith('excerpt:') ?? false;
    final value = excerpt ? attribute!.substring('excerpt:'.length) : attribute;
    final snippet = _snippetAttribute.firstMatch(meta)?.group(1);
    found.add(_Fence(
      page: rel,
      line: i + 1,
      lines: lines.sublist(i + 1, j),
      regionIds: proseOnly || value == null
          ? const []
          : value.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList(),
      isExcerpt: excerpt,
      proseOnlyReason:
          proseOnly ? attribute!.substring('prose-only:'.length) : null,
      siteProseOnly: snippet?.startsWith('prose-only:') ?? false,
      hasTwin: attribute != null,
    ));
    i = j;
  }
  return found;
}

/// Every marked region under `test/doc_twins/`, and the ids marked twice.
/// Discovered rather than listed, so adding a twin is adding a file.
(Map<String, _Region>, List<String>) _regionsOf(Directory repo) {
  final dir = Directory('${repo.path}/packages/query_kit_hooks/test/doc_twins');
  final twins = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final regions = <String, _Region>{};
  final duplicates = <String>[];
  for (final file in twins) {
    final twin = file.path
        .substring(repo.path.length + 1)
        .replaceAll(Platform.pathSeparator, '/');
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final open = lines[i].trim();
      if (!open.startsWith('// >>> ')) continue;
      final id = open.substring('// >>> '.length).trim();
      var j = i + 1;
      while (j < lines.length && lines[j].trim() != '// <<<') {
        j++;
      }
      if (j == lines.length) {
        fail('$twin:${i + 1} opens region "$id" and never closes it '
            '(expected a `// <<<` line).');
      }
      final region = _Region(
          id: id, where: '$twin:${i + 1}', lines: lines.sublist(i + 1, j));
      if (regions.containsKey(id)) {
        duplicates.add('$id (${regions[id]!.where} and ${region.where})');
      }
      regions[id] = region;
      i = j;
    }
  }
  return (regions, duplicates);
}

/// The hooks `lib/src/` declares at the top level: a function whose name is
/// `use` and a capital letter, its return type on the same line or on the
/// line above.
Set<String> _exportedHooks(Directory repo) {
  final src = Directory('${repo.path}/packages/query_kit_hooks/lib/src');
  final sameLine =
      RegExp(r'^[A-Za-z_][\w<>, ?]*\s+(use[A-Z]\w*)\s*(?:<[^()]*>)?\(');
  final nextLine = RegExp(r'^\s+(use[A-Z]\w*)\s*(?:<[^()]*>)?\(');
  final bareType = RegExp(r'^[A-Z][\w<>, ?]*$');
  final hooks = <String>{};
  for (final file in src.listSync().whereType<File>()) {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final same = sameLine.firstMatch(line);
      if (same != null) {
        hooks.add(same.group(1)!);
        continue;
      }
      final next = nextLine.firstMatch(line);
      if (next != null && i > 0 && bareType.hasMatch(lines[i - 1])) {
        hooks.add(next.group(1)!);
      }
    }
  }
  return hooks;
}

/// Walks up from where `flutter test` runs until the repository root is in
/// sight.
Directory _repoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    if (Directory('${dir.path}/website/docs').existsSync() &&
        File('${dir.path}/packages/query_kit_hooks/pubspec.yaml')
            .existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('Could not find the repository root from ${Directory.current.path}. '
      'This test reads website/docs, this package\'s README and its '
      'test/doc_twins/.');
}
