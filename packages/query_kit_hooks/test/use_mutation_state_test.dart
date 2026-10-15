// Ported from
// query/packages/react-query/src/__tests__/useMutationState.test.tsx at
// 50680b98c. Spike selection (AP0 of docs/plans/hooks-package.md).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_hooks/query_kit_hooks.dart';

import 'harness.dart';

void main() {
  // useMutationState.test.tsx:17
  hookTest('should return the number of fetching mutations',
      (tester, client) async {
    final isMutatingArray = <int>[];
    final key1 = queryKey();
    final key2 = queryKey();

    final isMutating = HookProbe((context) {
      isMutatingArray.add(useIsMutating());
      return const SizedBox();
    });
    final mutations = HookProbe((context) {
      final mutate1 = useMutation(MutationOptions.simple<String, void>(
        mutationKey: key1,
        mutationFn: (_) => sleep(50).then((_) => 'data'),
      ));
      final mutate2 = useMutation(MutationOptions.simple<String, void>(
        mutationKey: key2,
        mutationFn: (_) => sleep(10).then((_) => 'data'),
      ));
      return Column(children: [
        TextButton(
          onPressed: () => mutate1.mutate(null),
          child: const Text('mutate1'),
        ),
        TextButton(
          onPressed: () => mutate2.mutate(null),
          child: const Text('mutate2'),
        ),
      ]);
    });

    await tester.pumpApp(client, Column(children: [isMutating, mutations]));

    await click(tester, 'mutate1');
    await advance(tester, 10);
    await click(tester, 'mutate2');

    await advance(tester, 41);
    expect(isMutatingArray, [0, 1, 2, 1, 0]);
  });
}
