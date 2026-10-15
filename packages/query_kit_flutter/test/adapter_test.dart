/// `adapter.dart` on its own (map #92, AP1): [RebuildRule] is usable with
/// nothing but that import, and its branches are the ones the four call
/// styles rely on. Their behaviour through a widget is the rest of the
/// suite's; here the rule meets plain values, the way an adapter package
/// drives it.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/adapter.dart';

/// A controller stand-in: a value, and a flag that lives beside it the way an
/// infinite query's paging flags do.
class _Source {
  int value = 0;
  bool flag = false;

  RebuildRule<int> rule() => RebuildRule(
        value: () => value,
        observedState: () => (value, flag),
      );

  /// The same, saying which half is beside the value.
  RebuildRule<int> ruleWithBeside() => RebuildRule(
        value: () => value,
        observedState: () => (value, flag),
        beside: () => flag,
      );
}

void main() {
  test('anything is news before the first read', () {
    final source = _Source();
    final rule = source.rule();

    expect(rule.shouldRebuild(null), isTrue);
    expect(rule.shouldRebuild((_, __) => false), isTrue);
  });

  test('read returns the current value', () {
    final source = _Source()..value = 7;

    expect(source.rule().read(), 7);
  });

  test('an equal observed state never rebuilds, buildWhen or not', () {
    final source = _Source();
    final rule = source.rule()..read();
    var asked = false;

    expect(rule.shouldRebuild(null), isFalse);
    expect(
      rule.shouldRebuild((_, __) => asked = true),
      isFalse,
    );
    expect(asked, isFalse);
  });

  test('a value moved and back is equal again', () {
    final source = _Source();
    final rule = source.rule()..read();

    source.value = 1;
    source.value = 0;

    expect(rule.shouldRebuild(null), isFalse);
  });

  test('only the half beside the value moved: rebuilds, buildWhen unasked', () {
    final source = _Source();
    final rule = source.rule()..read();
    var asked = false;

    source.flag = true;

    expect(
      rule.shouldRebuild((_, __) {
        asked = true;
        return false;
      }),
      isTrue,
    );
    expect(asked, isFalse);
  });

  test('a moved value rebuilds with no buildWhen', () {
    final source = _Source();
    final rule = source.rule()..read();

    source.value = 1;

    expect(rule.shouldRebuild(null), isTrue);
  });

  test('a moved value asks buildWhen with what was built and what is now', () {
    final source = _Source()..value = 1;
    final rule = source.rule()..read();
    final asked = <(int, int)>[];

    source.value = 2;

    expect(
      rule.shouldRebuild((previous, current) {
        asked.add((previous, current));
        return false;
      }),
      isFalse,
    );
    expect(
      rule.shouldRebuild((previous, current) {
        asked.add((previous, current));
        return true;
      }),
      isTrue,
    );
    expect(asked, [(1, 2), (1, 2)]);
  });

  test('a declined change is compared against what is still shown', () {
    final source = _Source()..value = 1;
    final rule = source.rule()..read();
    final asked = <(int, int)>[];
    bool record(int previous, int current) {
      asked.add((previous, current));
      return false;
    }

    source.value = 2;
    rule.shouldRebuild(record);
    source.value = 3;
    rule.shouldRebuild(record);

    expect(asked, [(1, 2), (1, 3)]);
  });

  test('a read records both halves anew', () {
    final source = _Source();
    final rule = source.rule()..read();

    source
      ..value = 1
      ..flag = true;
    expect(rule.shouldRebuild(null), isTrue);

    expect(rule.read(), 1);
    expect(rule.shouldRebuild(null), isFalse);
  });

  test('beside moved with the value: rebuilds, buildWhen unasked', () {
    final source = _Source();
    final rule = source.ruleWithBeside()..read();
    var asked = false;

    source
      ..value = 1
      ..flag = true;

    expect(
      rule.shouldRebuild((_, __) {
        asked = true;
        return false;
      }),
      isTrue,
    );
    expect(asked, isFalse);
  });

  test('beside moved alone: rebuilds, buildWhen unasked', () {
    final source = _Source();
    final rule = source.ruleWithBeside()..read();
    var asked = false;

    source.flag = true;

    expect(
      rule.shouldRebuild((_, __) {
        asked = true;
        return false;
      }),
      isTrue,
    );
    expect(asked, isFalse);
  });

  test('beside where it was: a moved value is buildWhen\'s', () {
    final source = _Source();
    final rule = source.ruleWithBeside()..read();

    source.value = 1;

    expect(rule.shouldRebuild((_, __) => false), isFalse);
    expect(rule.shouldRebuild((_, __) => true), isTrue);
  });

  test('beside moved and back is equal again', () {
    final source = _Source();
    final rule = source.ruleWithBeside()..read();

    source
      ..flag = true
      ..flag = false;

    expect(rule.shouldRebuild((_, __) => true), isFalse);
  });

  test('without beside, buildWhen decides when both halves moved', () {
    final source = _Source();
    final rule = source.rule()..read();

    source
      ..value = 1
      ..flag = true;

    expect(rule.shouldRebuild((_, __) => false), isFalse);
  });

  test('a read records beside anew', () {
    final source = _Source();
    final rule = source.ruleWithBeside()..read();

    source.flag = true;
    expect(rule.shouldRebuild((_, __) => false), isTrue);

    rule.read();
    source.value = 1;
    expect(rule.shouldRebuild((_, __) => false), isFalse);
  });
}
