// Ported from query/packages/react-query/src/__tests__/useMutation.test.tsx
// at 50680b98c. Spike selection (AP0 of docs/plans/hooks-package.md).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_hooks/query_kit_hooks.dart';

import 'harness.dart';

void main() {
  // useMutation.test.tsx:34
  hookTest('should be able to reset `data`', (tester, client) async {
    await tester.pumpApp(
      client,
      HookProbe((context) {
        final mutation = useMutation(MutationOptions.simple<String, void>(
          mutationFn: (_) => Future.value('mutation'),
        ));
        return Column(children: [
          Text(mutation.value.dataOrNull ?? 'empty', key: const Key('heading')),
          TextButton(
            onPressed: mutation.reset,
            child: const Text('reset'),
          ),
          TextButton(
            onPressed: () => mutation.mutate(null),
            child: const Text('mutate'),
          ),
        ]);
      }),
    );

    String heading() =>
        tester.widget<Text>(find.byKey(const Key('heading'))).data!;

    expect(heading(), 'empty');

    await click(tester, 'mutate');

    await advance(tester, 0);
    expect(heading(), 'mutation');

    await click(tester, 'reset');

    await advance(tester, 0);
    expect(heading(), 'empty');
  });

  // useMutation.test.tsx:999
  hookTest('should be able to use mutation defaults', (tester, client) async {
    final key = queryKey();

    client.setMutationDefaults(
      key,
      MutationDefaults(
        mutationFn: (text) => sleep(10).then((_) => text),
      ),
    );

    final states = <MutationResult<String, String>>[];

    await tester.pumpApp(
      client,
      HookProbe((context) {
        final state = useMutation(
            MutationOptions<String, String, void>(mutationKey: key));

        states.add(state.value);

        useEffect(() {
          final timer = Timer(
            const Duration(milliseconds: 10),
            () => state.mutate('todo'),
          );
          return timer.cancel;
        }, [state]);

        return const SizedBox();
      }),
    );

    await advance(tester, 21);

    expect(states, hasLength(3));
    expect(states[0].dataOrNull, isNull);
    expect(states[0].isPending, isFalse);
    expect(states[1].dataOrNull, isNull);
    expect(states[1].isPending, isTrue);
    expect(states[2].dataOrNull, 'todo');
    expect(states[2].isPending, isFalse);
  });

  // useMutation.test.tsx:1578
  hookTest('should call cache callbacks when unmounted',
      (tester, client) async {
    var onSuccess = 0;
    var onSuccessMutate = 0;
    var onSettled = 0;
    var onSettledMutate = 0;
    final mutationKey = queryKey();
    var count = 0;

    final component = HookProbe((context) {
      final mutation = useMutation(MutationOptions.simple<int, String>(
        mutationFn: (_) async {
          count++;
          await sleep(10);
          return count;
        },
        mutationKey: mutationKey,
        gcTime: const GcTime.duration(Duration.zero),
        onSuccess: (_, __, ___) => onSuccess++,
        onSettled: (_, __, ___, ____, _____) => onSettled++,
      ));
      final result = mutation.value;
      return Column(children: [
        TextButton(
          onPressed: () => mutation.mutate(
            'todo',
            callbacks: MutateCallbacks(
              onSuccess: (_, __, ___) => onSuccessMutate++,
              onSettled: (_, __, ___, ____, _____) => onSettledMutate++,
            ),
          ),
          child: const Text('mutate'),
        ),
        Text('data: ${result.dataOrNull ?? 'null'}, '
            'status: ${result.status.name}, '
            'isPaused: ${result.isPaused}'),
      ]);
    });

    await tester.pumpApp(
      client,
      HookProbe((context) {
        final show = useState(true);
        return Column(children: [
          TextButton(
            onPressed: () => show.value = false,
            child: const Text('hide'),
          ),
          if (show.value) component,
        ]);
      }),
    );

    expect(
        find.text('data: null, status: idle, isPaused: false'), findsOneWidget);
    await click(tester, 'mutate');
    await click(tester, 'hide');

    await advance(tester, 10);
    expect(
      client.mutationCache
          .findAll(filters: MutationFilters(mutationKey: mutationKey)),
      isEmpty,
    );

    expect(count, 1);

    expect(onSuccess, 1);
    expect(onSettled, 1);
    expect(onSuccessMutate, 0);
    expect(onSettledMutate, 0);
  });
}
