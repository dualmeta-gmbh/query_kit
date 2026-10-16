// Ported from query/packages/react-query/src/__tests__/mutationOptions.test.tsx
// at 50680b98c. Each case keeps upstream's name, and its upstream line is in
// the comment above it. What was adapted or omitted, and why, is in
// PORTING_NOTES.md.
//
// `mutationOptions(…)` is TypeScript's identity function for inference; in
// Dart the options are a value already, so each case builds a
// `MutationOptions` and hands it to `useMutation` as upstream does. The two
// cases that only check the identity (lines 20 and 29) are not ported.
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_hooks/query_kit_hooks.dart';

import 'harness.dart';

void main() {
  // mutationOptions.test.tsx:37
  hookTest(
      'should return the number of fetching mutations when used with useIsMutating (with mutationKey in mutationOptions)',
      (tester, client) async {
    final isMutatingArray = <int>[];
    final mutationOpts = MutationOptions.simple<String, void>(
      mutationKey: queryKey(),
      mutationFn: (_) => sleep(50).then((_) => 'data'),
    );

    await tester.pumpApp(
      client,
      Column(children: [
        HookBuilder(builder: (context) {
          final isMutating = useIsMutating();

          isMutatingArray.add(isMutating);

          return const SizedBox();
        }),
        HookBuilder(builder: (context) {
          final mutate = useMutation(mutationOpts).mutate;

          return TextButton(
            onPressed: () => mutate(null),
            child: const Text('mutate'),
          );
        }),
      ]),
    );

    await click(tester, 'mutate');
    expect(isMutatingArray[0], 0);
    await advance(tester, 0);
    expect(isMutatingArray[1], 1);
    await advance(tester, 51);
    expect(isMutatingArray[2], 0);
    expect(isMutatingArray.last, 0);
  });

  // mutationOptions.test.tsx:83
  hookTest(
      'should return the number of fetching mutations when used with useIsMutating (without mutationKey in mutationOptions)',
      (tester, client) async {
    final isMutatingArray = <int>[];
    final mutationOpts = MutationOptions.simple<String, void>(
      mutationFn: (_) => sleep(50).then((_) => 'data'),
    );

    await tester.pumpApp(
      client,
      Column(children: [
        HookBuilder(builder: (context) {
          final isMutating = useIsMutating();

          isMutatingArray.add(isMutating);

          return const SizedBox();
        }),
        HookBuilder(builder: (context) {
          final mutate = useMutation(mutationOpts).mutate;

          return TextButton(
            onPressed: () => mutate(null),
            child: const Text('mutate'),
          );
        }),
      ]),
    );

    await click(tester, 'mutate');
    expect(isMutatingArray[0], 0);
    await advance(tester, 0);
    expect(isMutatingArray[1], 1);
    await advance(tester, 51);
    expect(isMutatingArray[2], 0);
    expect(isMutatingArray.last, 0);
  });

  // mutationOptions.test.tsx:128
  hookTest(
      'should return the number of fetching mutations when used with useIsMutating',
      (tester, client) async {
    final isMutatingArray = <int>[];
    final mutationOpts1 = MutationOptions.simple<String, void>(
      mutationKey: queryKey(),
      mutationFn: (_) => sleep(50).then((_) => 'data1'),
    );
    final mutationOpts2 = MutationOptions.simple<String, void>(
      mutationFn: (_) => sleep(50).then((_) => 'data2'),
    );

    await tester.pumpApp(
      client,
      Column(children: [
        HookBuilder(builder: (context) {
          final isMutating = useIsMutating();

          isMutatingArray.add(isMutating);

          return const SizedBox();
        }),
        HookBuilder(builder: (context) {
          final mutate1 = useMutation(mutationOpts1).mutate;
          final mutate2 = useMutation(mutationOpts2).mutate;

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
        }),
      ]),
    );

    await _clickTogether(tester, ['mutate1', 'mutate2']);
    expect(isMutatingArray[0], 0);
    await advance(tester, 0);
    expect(isMutatingArray[1], 2);
    await advance(tester, 51);
    expect(isMutatingArray[2], 0);
    expect(isMutatingArray.last, 0);
  });

  // mutationOptions.test.tsx:180
  hookTest(
      'should return the number of fetching mutations when used with useIsMutating (filter mutationOpts1.mutationKey)',
      (tester, client) async {
    final isMutatingArray = <int>[];
    final mutationOpts1 = MutationOptions.simple<String, void>(
      mutationKey: queryKey(),
      mutationFn: (_) => sleep(50).then((_) => 'data1'),
    );
    final mutationOpts2 = MutationOptions.simple<String, void>(
      mutationFn: (_) => sleep(50).then((_) => 'data2'),
    );

    await tester.pumpApp(
      client,
      Column(children: [
        HookBuilder(builder: (context) {
          final isMutating = useIsMutating(
            filters: MutationFilters(mutationKey: mutationOpts1.mutationKey),
          );

          isMutatingArray.add(isMutating);

          return const SizedBox();
        }),
        HookBuilder(builder: (context) {
          final mutate1 = useMutation(mutationOpts1).mutate;
          final mutate2 = useMutation(mutationOpts2).mutate;

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
        }),
      ]),
    );

    await _clickTogether(tester, ['mutate1', 'mutate2']);
    expect(isMutatingArray[0], 0);
    await advance(tester, 0);
    expect(isMutatingArray[1], 1);
    await advance(tester, 51);
    expect(isMutatingArray[2], 0);
    expect(isMutatingArray.last, 0);
  });

  // mutationOptions.test.tsx:234
  hookTest(
      'should return the number of fetching mutations when used with queryClient.isMutating (with mutationKey in mutationOptions)',
      (tester, client) async {
    final isMutatingArray = <int>[];
    final mutationOpts = MutationOptions.simple<String, void>(
      mutationKey: queryKey(),
      mutationFn: (_) => sleep(500).then((_) => 'data'),
    );

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final isMutating = client.isMutating(
          filters: MutationFilters(mutationKey: mutationOpts.mutationKey),
        );
        final mutate = useMutation(mutationOpts).mutate;

        isMutatingArray.add(isMutating);

        return TextButton(
          onPressed: () => mutate(null),
          child: const Text('mutate'),
        );
      }),
    );

    await click(tester, 'mutate');
    expect(isMutatingArray[0], 0);
    await advance(tester, 0);
    expect(isMutatingArray[1], 1);
    await advance(tester, 501);
    expect(isMutatingArray[2], 0);
    expect(isMutatingArray.last, 0);
  });

  // mutationOptions.test.tsx:266
  hookTest(
      'should return the number of fetching mutations when used with queryClient.isMutating (without mutationKey in mutationOptions)',
      (tester, client) async {
    final isMutatingArray = <int>[];
    final mutationOpts = MutationOptions.simple<String, void>(
      mutationFn: (_) => sleep(500).then((_) => 'data'),
    );

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final isMutating = client.isMutating();
        final mutate = useMutation(mutationOpts).mutate;

        isMutatingArray.add(isMutating);

        return TextButton(
          onPressed: () => mutate(null),
          child: const Text('mutate'),
        );
      }),
    );

    await click(tester, 'mutate');
    expect(isMutatingArray[0], 0);
    await advance(tester, 0);
    expect(isMutatingArray[1], 1);
    await advance(tester, 501);
    expect(isMutatingArray[2], 0);
    expect(isMutatingArray.last, 0);
  });

  // mutationOptions.test.tsx:297
  hookTest(
      'should return the number of fetching mutations when used with queryClient.isMutating',
      (tester, client) async {
    final isMutatingArray = <int>[];
    final mutationOpts1 = MutationOptions.simple<String, void>(
      mutationKey: queryKey(),
      mutationFn: (_) => sleep(500).then((_) => 'data1'),
    );
    final mutationOpts2 = MutationOptions.simple<String, void>(
      mutationFn: (_) => sleep(500).then((_) => 'data2'),
    );

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final isMutating = client.isMutating();
        final mutate1 = useMutation(mutationOpts1).mutate;
        final mutate2 = useMutation(mutationOpts2).mutate;

        isMutatingArray.add(isMutating);

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
      }),
    );

    await _clickTogether(tester, ['mutate1', 'mutate2']);
    expect(isMutatingArray[0], 0);
    await advance(tester, 0);
    expect(isMutatingArray[1], 2);
    await advance(tester, 501);
    expect(isMutatingArray[2], 0);
    expect(isMutatingArray.last, 0);
  });

  // mutationOptions.test.tsx:335
  hookTest(
      'should return the number of fetching mutations when used with queryClient.isMutating (filter mutationOpt1.mutationKey)',
      (tester, client) async {
    final isMutatingArray = <int>[];
    final mutationOpts1 = MutationOptions.simple<String, void>(
      mutationKey: queryKey(),
      mutationFn: (_) => sleep(500).then((_) => 'data1'),
    );
    final mutationOpts2 = MutationOptions.simple<String, void>(
      mutationFn: (_) => sleep(500).then((_) => 'data2'),
    );

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final isMutating = client.isMutating(
          filters: MutationFilters(mutationKey: mutationOpts1.mutationKey),
        );
        final mutate1 = useMutation(mutationOpts1).mutate;
        final mutate2 = useMutation(mutationOpts2).mutate;

        isMutatingArray.add(isMutating);

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
      }),
    );

    await _clickTogether(tester, ['mutate1', 'mutate2']);
    expect(isMutatingArray[0], 0);
    await advance(tester, 0);
    expect(isMutatingArray[1], 1);
    await advance(tester, 501);
    expect(isMutatingArray[2], 0);
    expect(isMutatingArray.last, 0);
  });

  // mutationOptions.test.tsx:375
  hookTest(
      'should return the number of fetching mutations when used with useMutationState (with mutationKey in mutationOptions)',
      (tester, client) async {
    final mutationStateArray = <MutationState<Object?, Object?, Object?>>[];
    final mutationOpts = MutationOptions.simple<String, void>(
      mutationKey: queryKey(),
      mutationFn: (_) => sleep(10).then((_) => 'data'),
    );

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutate = useMutation(mutationOpts).mutate;
        final data = useMutationState(
          filters: MutationFilters(
            mutationKey: mutationOpts.mutationKey,
            status: MutationStatus.success,
          ),
          select: _state,
        );

        mutationStateArray.addAll(data);

        return TextButton(
          onPressed: () => mutate(null),
          child: const Text('mutate'),
        );
      }),
    );

    expect(mutationStateArray.length, 0);

    await click(tester, 'mutate');
    await advance(tester, 11);
    expect(mutationStateArray.length, 1);
    expect(mutationStateArray[0].data, 'data');
  });

  // mutationOptions.test.tsx:410
  hookTest(
      'should return the number of fetching mutations when used with useMutationState (without mutationKey in mutationOptions)',
      (tester, client) async {
    final mutationStateArray = <MutationState<Object?, Object?, Object?>>[];
    final mutationOpts = MutationOptions.simple<String, void>(
      mutationFn: (_) => sleep(10).then((_) => 'data'),
    );

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutate = useMutation(mutationOpts).mutate;
        final data = useMutationState(
          filters: const MutationFilters(status: MutationStatus.success),
          select: _state,
        );

        mutationStateArray.addAll(data);

        return TextButton(
          onPressed: () => mutate(null),
          child: const Text('mutate'),
        );
      }),
    );

    expect(mutationStateArray.length, 0);

    await click(tester, 'mutate');
    await advance(tester, 11);
    expect(mutationStateArray.length, 1);
    expect(mutationStateArray[0].data, 'data');
  });

  // mutationOptions.test.tsx:444
  hookTest(
      'should return the number of fetching mutations when used with useMutationState',
      (tester, client) async {
    final mutationStateArray = <MutationState<Object?, Object?, Object?>>[];
    final mutationOpts1 = MutationOptions.simple<String, void>(
      mutationKey: queryKey(),
      mutationFn: (_) => sleep(10).then((_) => 'data1'),
    );
    final mutationOpts2 = MutationOptions.simple<String, void>(
      mutationFn: (_) => sleep(10).then((_) => 'data2'),
    );

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutate1 = useMutation(mutationOpts1).mutate;
        final mutate2 = useMutation(mutationOpts2).mutate;
        final data = useMutationState(
          filters: const MutationFilters(status: MutationStatus.success),
          select: _state,
        );

        mutationStateArray.addAll(data);

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
      }),
    );

    expect(mutationStateArray.length, 0);

    await _clickTogether(tester, ['mutate1', 'mutate2']);
    await advance(tester, 11);
    expect(mutationStateArray.length, 2);
    expect(mutationStateArray[0].data, 'data1');
    expect(mutationStateArray[1].data, 'data2');
  });

  // mutationOptions.test.tsx:486
  hookTest(
      'should return the number of fetching mutations when used with useMutationState (filter mutationOpt1.mutationKey)',
      (tester, client) async {
    final mutationStateArray = <MutationState<Object?, Object?, Object?>>[];
    final mutationOpts1 = MutationOptions.simple<String, void>(
      mutationKey: queryKey(),
      mutationFn: (_) => sleep(10).then((_) => 'data1'),
    );
    final mutationOpts2 = MutationOptions.simple<String, void>(
      mutationFn: (_) => sleep(10).then((_) => 'data2'),
    );

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutate1 = useMutation(mutationOpts1).mutate;
        final mutate2 = useMutation(mutationOpts2).mutate;
        final data = useMutationState(
          filters: MutationFilters(
            mutationKey: mutationOpts1.mutationKey,
            status: MutationStatus.success,
          ),
          select: _state,
        );

        mutationStateArray.addAll(data);

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
      }),
    );

    expect(mutationStateArray.length, 0);

    await _clickTogether(tester, ['mutate1', 'mutate2']);
    await advance(tester, 11);
    expect(mutationStateArray.length, 1);
    expect(mutationStateArray[0].data, 'data1');
  });
}

/// `useMutationState`'s default `select`: the mutation's state.
MutationState<Object?, Object?, Object?> _state(
  Mutation<Object?, Object?, Object?> mutation,
) =>
    mutation.state;

/// Upstream's `fireEvent.click`s one after another with no time between.
/// React renders a notification only when the notify manager's zero-delay
/// timer runs, so nothing is built between them; here every tap goes in
/// before the one frame they share.
Future<void> _clickTogether(WidgetTester tester, List<String> labels) async {
  for (final label in labels) {
    await tester.tap(find.text(label));
  }
  await tester.pump();
}
