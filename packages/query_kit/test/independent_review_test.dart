/// Regressions of the independent reviews of 2026-10-15 (GPT-6-Astra and
/// Fable), core side. One test (or group) per finding, named after its ID;
/// PORTING_NOTES' "Independent reviews 2026-10-15" has a row for each.
library;

import 'package:query_kit/query_kit.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('ASTRA-C2 value equality is symmetric across type arguments', () {
    void symmetric(Object a, Object b) {
      expect(a == b, b == a, reason: '$a vs $b');
      expect(<Object>{a, b}.length, <Object>{b, a}.length);
      if (a == b) expect(a.hashCode, b.hashCode);
    }

    test('QueryState', () {
      symmetric(const QueryState<int>(), const QueryState<num>());
      symmetric(const QueryState<int?>(), const QueryState<Object?>());
      // Same type arguments stay equal.
      expect(const QueryState<int>(data: 1, hasData: true),
          const QueryState<int>(data: 1, hasData: true));
    });

    test('MutationState', () {
      symmetric(const MutationState<int, int, int>(),
          const MutationState<num, num, num>());
      // One type argument at a time.
      symmetric(const MutationState<int, String, void>(),
          const MutationState<Object?, String, void>());
      symmetric(const MutationState<int, String, void>(),
          const MutationState<int, Object?, void>());
      symmetric(const MutationState<int, String, int>(),
          const MutationState<int, String, Object?>());
      expect(const MutationState<int, String, void>(),
          const MutationState<int, String, void>());
    });

    test('DefaultedMutationOptions', () {
      final client = testClient();
      Object defaulted<A, B, C>() =>
          client.defaultMutationOptions(MutationOptions<A, B, C>());
      symmetric(defaulted<int, int, int>(), defaulted<num, num, num>());
      symmetric(
          defaulted<int, String, void>(), defaulted<Object?, String, void>());
      symmetric(
          defaulted<int, String, void>(), defaulted<int, Object?, void>());
      expect(defaulted<int, String, void>(), defaulted<int, String, void>());
      client.clear();
    });
  });

  // errors.md's fix for the `UnsupportedError` an `InfiniteQueryObserver`
  // throws said to hand `setInfiniteOptions` what
  // `client.infiniteObserverOptions` returns — a type it does not take. Both
  // spellings the page gives now are compiled here.
  testFakeAsync('ASTRA-D3 both remedies errors.md gives for plain options',
      (time) async {
    final client = testClient();
    final options = InfiniteQueryObserverOptions<int, int>(
      queryKey: queryKey(),
      initialPageParam: 0,
      pageFn: (context) => context.pageParam,
      getNextPageParam: (_, __, last, ___) => last + 1,
    );
    final observer = InfiniteQueryObserver<int, int, InfiniteData<int, int>>(
        client, options);
    final unsubscribe = observer.subscribe((_) {});
    await time.flushMicrotasks();

    observer.setInfiniteOptions(options.copyWith(meta: 'infinite'));
    expect(observer.options.meta, 'infinite');
    expect(
        observer.getOptimisticInfiniteResult(options).dataOrNull?.pages, [0]);
    observer.setOptions(
        client.infiniteObserverOptions(options.copyWith(meta: 'converted')));
    expect(observer.options.meta, 'converted');
    // And what the error is about.
    expect(
      () => observer.setOptions(QueryObserverOptions<InfiniteData<int, int>>(
          queryKey: options.queryKey)),
      throwsUnsupportedError,
    );

    unsubscribe();
    client.clear();
  });
}
