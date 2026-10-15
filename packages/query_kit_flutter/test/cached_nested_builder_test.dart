// A nested builder kept in a field, reading for the `State` around it.
//
// Fable's F-1 (2026-10-15): the docs promised that nothing shown in a
// reader's own subtree loses its subscription. It does here — the `State`'s
// own build keeps only what it reads, and a nested builder handed the same
// widget instance is not re-run, so its key is released while it still shows
// it. The rule is V3's and stays (keeping such keys is the leak V3 removed);
// what changed is the documentation, which now states this bound and its fix.
// This file pins both: the bound, and that the fix — a widget of its own,
// kept in a field just the same — holds. The verifiers added the second
// shape: a `build` that reads nothing, handed a new widget, takes the next
// read through its context for that own build, a nested builder's included.
// PORTING_NOTES, "Independent reviews 2026-10-15".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'harness.dart';

QueryObserverOptions<String> _options(String key) => QueryObserverOptions(
      queryKey: QueryKey(<Object?>[key]),
      staleTime: StaleTime.infinite,
      queryFn: (_) async => '$key-fetched',
    );

enum _Nested {
  /// A `ValueListenableBuilder` built once and kept: its callback reads
  /// through the `State`.
  cachedBuilder,

  /// The same builder built anew in every `build`: re-run, it reads again.
  rebuiltBuilder,

  /// The fix: a widget of its own, kept the same way, reading in its own
  /// `build`.
  cachedReader,
}

class _Outer extends StatefulWidget {
  const _Outer(this.tick,
      {super.key, required this.mixin, required this.nested});
  final ValueNotifier<int> tick;
  final bool mixin;
  final _Nested nested;

  @override
  State<_Outer> createState() => _OuterState();
}

class _OuterState extends State<_Outer> with QueryMixin {
  int counter = 0;

  QueryResult<String> _read(String key) =>
      widget.mixin ? watchQuery(_options(key)) : context.query(_options(key));

  Widget _builder() => ValueListenableBuilder<int>(
        valueListenable: widget.tick,
        builder: (_, __, ___) => Text('inner=${_read('inner').dataOrNull}'),
      );

  late final Widget _cached = switch (widget.nested) {
    _Nested.cachedReader => _InnerReader(mixin: widget.mixin),
    _ => _builder(),
  };

  void bump() => setState(() => counter++);

  @override
  Widget build(BuildContext context) => Column(children: [
        Text('outer=${_read('outer').dataOrNull}'),
        Text('counter=$counter'),
        if (widget.nested == _Nested.rebuiltBuilder) _builder() else _cached,
      ]);
}

class _InnerReader extends StatefulWidget {
  const _InnerReader({required this.mixin});
  final bool mixin;

  @override
  State<_InnerReader> createState() => _InnerReaderState();
}

class _InnerReaderState extends State<_InnerReader> with QueryMixin {
  @override
  Widget build(BuildContext context) {
    final options = _options('inner');
    final result = widget.mixin ? watchQuery(options) : context.query(options);
    return Text('inner=${result.dataOrNull}');
  }
}

/// Hands [_TwoBuilders] a new widget instance on every `bump`.
class _Parent extends StatefulWidget {
  const _Parent(
      {super.key, required this.mixin, required this.a, required this.b});
  final bool mixin;
  final ValueNotifier<int> a;
  final ValueNotifier<int> b;

  @override
  State<_Parent> createState() => _ParentState();
}

class _ParentState extends State<_Parent> {
  int version = 0;
  void bump() => setState(() => version++);

  @override
  Widget build(BuildContext context) =>
      _TwoBuilders(version, mixin: widget.mixin, a: widget.a, b: widget.b);
}

/// Reads nothing in its own `build`; two nested builders kept in fields
/// read through it.
class _TwoBuilders extends StatefulWidget {
  const _TwoBuilders(this.version,
      {required this.mixin, required this.a, required this.b});
  final int version;
  final bool mixin;
  final ValueNotifier<int> a;
  final ValueNotifier<int> b;

  @override
  State<_TwoBuilders> createState() => _TwoBuildersState();
}

class _TwoBuildersState extends State<_TwoBuilders> with QueryMixin {
  QueryResult<String> _read(String key) =>
      widget.mixin ? watchQuery(_options(key)) : context.query(_options(key));

  late final Widget _a = ValueListenableBuilder<int>(
    valueListenable: widget.a,
    builder: (_, __, ___) => Text('a=${_read('a').dataOrNull}'),
  );
  late final Widget _b = ValueListenableBuilder<int>(
    valueListenable: widget.b,
    builder: (_, __, ___) => Text('b=${_read('b').dataOrNull}'),
  );

  @override
  Widget build(BuildContext context) =>
      Column(children: [Text('v=${widget.version}'), _a, _b]);
}

int _observersOf(QueryClient client, String key) =>
    client.queryCache
        .find(filters: QueryFilters(queryKey: QueryKey(<Object?>[key])))
        ?.observersCount ??
    0;

void main() {
  for (final mixin in [true, false]) {
    for (final nested in _Nested.values) {
      final style = mixin ? 'watchQuery' : 'context.query';
      final kept = nested != _Nested.cachedBuilder;
      queryWidgetTest(
          '$style, ${nested.name}: after the State\'s own build the inner '
          'key is ${kept ? 'kept and updates' : 'released while shown'}',
          (tester, client) async {
        client.setQueryData<String>(QueryKey(<Object?>['outer']), 'outer-0');
        client.setQueryData<String>(QueryKey(<Object?>['inner']), 'inner-0');
        final tick = ValueNotifier<int>(0);
        addTearDown(tick.dispose);
        final key = GlobalKey<_OuterState>();
        await tester.pumpApp(
            client, _Outer(tick, key: key, mixin: mixin, nested: nested));
        await tester.pump();
        expect(find.text('inner=inner-0'), findsOneWidget);
        expect(_observersOf(client, 'inner'), 1);

        // The State's own build, for nothing either query did.
        key.currentState!.bump();
        await tester.pump();
        await tester.pump();
        expect(find.text('counter=1'), findsOneWidget);
        expect(find.text('inner=inner-0'), findsOneWidget);
        expect(_observersOf(client, 'inner'), kept ? 1 : 0);

        client.setQueryData<String>(QueryKey(<Object?>['inner']), 'inner-1');
        await tester.pump();
        await tester.pump();
        expect(find.text(kept ? 'inner=inner-1' : 'inner=inner-0'),
            findsOneWidget);

        // A tick re-runs the cached builder: it reads again, is subscribed
        // again, and shows the cache.
        tick.value++;
        await tester.pump();
        await tester.pump();
        expect(find.text('inner=inner-1'), findsOneWidget);
        expect(_observersOf(client, 'inner'), 1);
      });
    }
  }

  for (final mixin in [true, false]) {
    final style = mixin ? 'watchQuery' : 'context.query';
    queryWidgetTest(
        '$style: a build that reads nothing, handed a new widget, takes the '
        'next nested read for its own build', (tester, client) async {
      client.setQueryData<String>(QueryKey(<Object?>['a']), 'a-0');
      client.setQueryData<String>(QueryKey(<Object?>['b']), 'b-0');
      final a = ValueNotifier<int>(0);
      final b = ValueNotifier<int>(0);
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      final parent = GlobalKey<_ParentState>();
      await tester.pumpApp(
          client, _Parent(key: parent, mixin: mixin, a: a, b: b));
      await tester.pump();
      expect((_observersOf(client, 'a'), _observersOf(client, 'b')), (1, 1));

      // A new widget and no read: nothing is released yet.
      parent.currentState!.bump();
      await tester.pump();
      await tester.pump();
      expect(find.text('v=1'), findsOneWidget);
      expect((_observersOf(client, 'a'), _observersOf(client, 'b')), (1, 1));

      // `a`'s tick is the first read since: it counts as the own build and
      // keeps only `a`, while `b` still shows its key.
      a.value++;
      await tester.pump();
      await tester.pump();
      expect(find.text('b=b-0'), findsOneWidget);
      expect((_observersOf(client, 'a'), _observersOf(client, 'b')), (1, 0));

      // `b`'s own tick reads again and shows the cache.
      client.setQueryData<String>(QueryKey(<Object?>['b']), 'b-1');
      b.value++;
      await tester.pump();
      await tester.pump();
      expect(find.text('b=b-1'), findsOneWidget);
      expect(_observersOf(client, 'b'), 1);
    });
  }
}
