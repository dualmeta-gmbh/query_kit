// Ported from
// query/packages/react-query/src/__tests__/useMutationState.test.tsx at
// 50680b98c. Each case keeps upstream's name, and its upstream line is in
// the comment above it. What was adapted or omitted, and why, is in
// PORTING_NOTES.md. The file has two top-level describes, one per hook, and
// each is a group here.
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_hooks/query_kit_hooks.dart';

import 'harness.dart';

void main() {
  group('useIsMutating', () {
    // useMutationState.test.tsx:17
    hookTest('should return the number of fetching mutations',
        (tester, client) async {
      final isMutatingArray = <int>[];
      final key1 = queryKey();
      final key2 = queryKey();

      final isMutating = HookBuilder(builder: (context) {
        final isMutating = useIsMutating();

        isMutatingArray.add(isMutating);

        return const SizedBox();
      });

      final mutations = HookBuilder(builder: (context) {
        final mutate1 = useMutation(MutationOptions.simple<String, void>(
          mutationKey: key1,
          mutationFn: (_) => sleep(50).then((_) => 'data'),
        )).mutate;
        final mutate2 = useMutation(MutationOptions.simple<String, void>(
          mutationKey: key2,
          mutationFn: (_) => sleep(10).then((_) => 'data'),
        )).mutate;

        return Column(children: [
          TextButton(
            onPressed: () => mutate1(null),
            child: const Text('mutate1'),
          ),
          TextButton(
            onPressed: () => mutate2(null),
            child: const Text('mutate2'),
          ),
        ]);
      });

      await tester.pumpApp(client, Column(children: [isMutating, mutations]));

      await click(tester, 'mutate1');
      await advance(tester, 10);
      await click(tester, 'mutate2');

      // we don't really care if this yields
      // [ +0, 1, 2, +0 ]
      // or
      // [ +0, 1, 2, 1, +0 ]
      // our batching strategy might yield different results

      await advance(tester, 41);
      expect(isMutatingArray[0], 0);
      expect(isMutatingArray[1], 1);
      expect(isMutatingArray[2], 2);
      expect(isMutatingArray[3], 1);
      expect(isMutatingArray[4], 0);

      expect(isMutatingArray, [0, 1, 2, 1, 0]);
    });

    // useMutationState.test.tsx:80
    hookTest('should filter correctly by mutationKey', (tester, client) async {
      final isMutatingArray = <int>[];
      final key1 = queryKey();
      final key2 = queryKey();

      // A function, not an instance: React re-renders `<IsMutating />` with
      // its parent, and Flutter rebuilds a new widget.
      Widget isMutating() => HookBuilder(builder: (context) {
            final isMutating =
                useIsMutating(filters: MutationFilters(mutationKey: key1));
            isMutatingArray.add(isMutating);
            return const SizedBox();
          });

      await tester.pumpApp(
        client,
        HookBuilder(builder: (context) {
          final mutate1 = useMutation(MutationOptions.simple<String, void>(
            mutationKey: key1,
            mutationFn: (_) => sleep(100).then((_) => 'data'),
          )).mutate;
          final mutate2 = useMutation(MutationOptions.simple<String, void>(
            mutationKey: key2,
            mutationFn: (_) => sleep(100).then((_) => 'data'),
          )).mutate;

          // React runs an effect after the commit; flutter_hooks runs it in
          // the build, before `isMutating` builds, so the calls go after the
          // frame.
          useEffect(() {
            afterFrame(() {
              mutate1(null);
              mutate2(null);
            });
            return null;
          }, [mutate1, mutate2]);

          return isMutating();
        }),
      );

      await advance(tester, 101);
      expect(isMutatingArray, [0, 1, 0]);
    });

    // useMutationState.test.tsx:116
    hookTest('should filter correctly by predicate', (tester, client) async {
      final isMutatingArray = <int>[];
      final key1 = queryKey();
      final key2 = queryKey();

      Widget isMutating() => HookBuilder(builder: (context) {
            final isMutating = useIsMutating(
              filters: MutationFilters(
                predicate: (mutation) =>
                    mutation.options.mutationKey?.parts.first ==
                    key1.parts.first,
              ),
            );
            isMutatingArray.add(isMutating);
            return const SizedBox();
          });

      await tester.pumpApp(
        client,
        HookBuilder(builder: (context) {
          final mutate1 = useMutation(MutationOptions.simple<String, void>(
            mutationKey: key1,
            mutationFn: (_) => sleep(100).then((_) => 'data'),
          )).mutate;
          final mutate2 = useMutation(MutationOptions.simple<String, void>(
            mutationKey: key2,
            mutationFn: (_) => sleep(100).then((_) => 'data'),
          )).mutate;

          useEffect(() {
            afterFrame(() {
              mutate1(null);
              mutate2(null);
            });
            return null;
          }, [mutate1, mutate2]);

          return isMutating();
        }),
      );

      await advance(tester, 101);
      expect(isMutatingArray, [0, 1, 0]);
    });

    // useMutationState.test.tsx:154
    hookTest('should use provided custom queryClient', (tester, client) async {
      final key = queryKey();

      // No provider: upstream's `render(<Page />)`.
      await tester.pumpWidget(MaterialApp(
        home: HookBuilder(builder: (context) {
          final isMutating =
              useIsMutating(filters: const MutationFilters(), client: client);
          final mutate = useMutation(
            MutationOptions.simple<String, void>(
              mutationKey: key,
              mutationFn: (_) => sleep(10).then((_) => 'data'),
            ),
            client: client,
          ).mutate;

          useEffect(() {
            afterFrame(() => mutate(null));
            return null;
          }, [mutate]);

          return Column(children: [Text('mutating: $isMutating')]);
        }),
      ));

      await advance(tester, 0);
      expect(find.text('mutating: 1'), findsOneWidget);

      await advance(tester, 10); // the mutation's sleep
    });
  });

  group('useMutationState', () {
    // useMutationState.test.tsx:195
    hookTest('should return variables after calling mutate',
        (tester, client) async {
      final variables = <List<Object?>>[];
      final mutationKey = QueryKey(<Object?>['mutation']);

      final variablesWidget = HookBuilder(builder: (context) {
        variables.add(useMutationState(
          filters: MutationFilters(
            mutationKey: mutationKey,
            status: MutationStatus.pending,
          ),
          select: (mutation) => mutation.state.variables,
        ));

        return const SizedBox();
      });

      final mutate = HookBuilder(builder: (context) {
        final mutation = useMutation(MutationOptions.simple<String, int>(
          mutationKey: mutationKey,
          mutationFn: (input) => sleep(150).then((_) => 'data$input'),
        ));

        return Column(children: [
          Text('data: ${mutation.value.dataOrNull ?? 'null'}'),
          TextButton(
            onPressed: () => mutation.mutate(1),
            child: const Text('mutate'),
          ),
        ]);
      });

      await tester.pumpApp(client, Column(children: [variablesWidget, mutate]));

      expect(find.text('data: null'), findsOneWidget);

      await click(tester, 'mutate');
      await advance(tester, 151);
      expect(find.text('data: data1'), findsOneWidget);

      expect(variables, [
        <Object?>[],
        <Object?>[1],
        <Object?>[],
      ]);
    });
  });
}
