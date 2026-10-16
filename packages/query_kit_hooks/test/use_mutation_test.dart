// Ported from query/packages/react-query/src/__tests__/useMutation.test.tsx
// at 50680b98c. Each case keeps upstream's name, and its upstream line is in
// the comment above it. What was adapted or omitted, and why, is in
// PORTING_NOTES.md.
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
      HookBuilder(builder: (context) {
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

    expect(_heading(tester), 'empty');

    await click(tester, 'mutate');

    await advance(tester, 0);
    expect(_heading(tester), 'mutation');

    await click(tester, 'reset');

    await advance(tester, 0);
    expect(_heading(tester), 'empty');
  });

  // useMutation.test.tsx:66
  hookTest('should be able to reset `error`', (tester, client) async {
    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutation = useMutation(MutationOptions.simple<String, void>(
          mutationFn: (_) => Future<String>.error(
              StateError('Expected mock error. All is well!')),
        ));
        final error = mutation.value.errorOrNull;
        return Column(children: [
          if (error != null) Text(_message(error), key: const Key('heading')),
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

    expect(find.byKey(const Key('heading')), findsNothing);

    await click(tester, 'mutate');

    await advance(tester, 0);
    expect(_heading(tester), 'Expected mock error. All is well!');

    await click(tester, 'reset');

    await advance(tester, 0);
    expect(find.byKey(const Key('heading')), findsNothing);
  });

  // useMutation.test.tsx:102
  hookTest('should call mutate callbacks when useMutation has no callbacks',
      (tester, client) async {
    final callbacks = <String>[];

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutate = useMutation(MutationOptions.simple<String, String>(
          mutationFn: (text) => sleep(10).then((_) => text),
        )).mutate;

        return TextButton(
          onPressed: () => mutate(
            'todo',
            callbacks: MutateCallbacks(
              onSuccess: (_, __, ___) => callbacks.add('mutate.onSuccess'),
              onSettled: (_, __, ___, ____, _____) =>
                  callbacks.add('mutate.onSettled'),
            ),
          ),
          child: const Text('mutate'),
        );
      }),
    );

    await click(tester, 'mutate');
    await advance(tester, 10);

    expect(callbacks, ['mutate.onSuccess', 'mutate.onSettled']);
  });

  // useMutation.test.tsx:136
  hookTest(
      'should call mutateAsync callbacks when useMutation has no callbacks',
      (tester, client) async {
    final callbacks = <String>[];

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutateAsync = useMutation(MutationOptions.simple<String, String>(
          mutationFn: (text) => sleep(10).then((_) => text),
        )).mutateAsync;

        useEffect(() {
          Timer(Duration.zero, () async {
            await mutateAsync(
              'todo',
              callbacks: MutateCallbacks(
                onSuccess: (_, __, ___) =>
                    callbacks.add('mutateAsync.onSuccess'),
                onSettled: (_, __, ___, ____, _____) =>
                    callbacks.add('mutateAsync.onSettled'),
              ),
            );
          });
          return null;
        }, [mutateAsync]);

        return const SizedBox();
      }),
    );

    await advance(tester, 10);

    expect(callbacks, [
      'mutateAsync.onSuccess',
      'mutateAsync.onSettled',
    ]);
  });

  // useMutation.test.tsx:170
  hookTest(
      'should call mutate error callbacks when useMutation has no callbacks',
      (tester, client) async {
    final callbacks = <String>[];

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutate = useMutation(MutationOptions.simple<String, String>(
          mutationFn: (_) => sleep(10).then((_) => throw StateError('oops')),
        )).mutate;

        return TextButton(
          onPressed: () => mutate(
            'todo',
            callbacks: MutateCallbacks(
              onError: (_, __, ___, ____) => callbacks.add('mutate.onError'),
              onSettled: (_, __, ___, ____, _____) =>
                  callbacks.add('mutate.onSettled'),
            ),
          ),
          child: const Text('mutate'),
        );
      }),
    );

    await click(tester, 'mutate');
    await advance(tester, 10);

    expect(callbacks, ['mutate.onError', 'mutate.onSettled']);
  });

  // useMutation.test.tsx:207
  hookTest(
      'should call mutateAsync error callbacks when useMutation has no callbacks',
      (tester, client) async {
    final callbacks = <String>[];

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutateAsync = useMutation(MutationOptions.simple<String, String>(
          mutationFn: (_) => sleep(10).then((_) => throw StateError('oops')),
        )).mutateAsync;

        useEffect(() {
          Timer(Duration.zero, () async {
            try {
              await mutateAsync(
                'todo',
                callbacks: MutateCallbacks(
                  onError: (_, __, ___, ____) =>
                      callbacks.add('mutateAsync.onError'),
                  onSettled: (_, __, ___, ____, _____) =>
                      callbacks.add('mutateAsync.onSettled'),
                ),
              );
            } catch (_) {
              // Upstream's empty `catch {}`.
            }
          });
          return null;
        }, [mutateAsync]);

        return const SizedBox();
      }),
    );

    await advance(tester, 10);

    expect(callbacks, ['mutateAsync.onError', 'mutateAsync.onSettled']);
  });

  // useMutation.test.tsx:243
  hookTest(
      'should call only mutate onSuccess when useMutation has no callbacks',
      (tester, client) async {
    final callbacks = <String>[];

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutate = useMutation(MutationOptions.simple<String, String>(
          mutationFn: (text) => sleep(10).then((_) => text),
        )).mutate;

        return TextButton(
          onPressed: () => mutate(
            'todo',
            callbacks: MutateCallbacks(
              onSuccess: (_, __, ___) => callbacks.add('mutate.onSuccess'),
            ),
          ),
          child: const Text('mutate'),
        );
      }),
    );

    await click(tester, 'mutate');
    await advance(tester, 10);

    expect(callbacks, ['mutate.onSuccess']);
  });

  // useMutation.test.tsx:274
  hookTest('should call only mutate onError when useMutation has no callbacks',
      (tester, client) async {
    final callbacks = <String>[];

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutate = useMutation(MutationOptions.simple<String, String>(
          mutationFn: (_) => sleep(10).then((_) => throw StateError('oops')),
        )).mutate;

        return TextButton(
          onPressed: () => mutate(
            'todo',
            callbacks: MutateCallbacks(
              onError: (_, __, ___, ____) => callbacks.add('mutate.onError'),
            ),
          ),
          child: const Text('mutate'),
        );
      }),
    );

    await click(tester, 'mutate');
    await advance(tester, 10);

    expect(callbacks, ['mutate.onError']);
  });

  // useMutation.test.tsx:308
  hookTest(
      'should call only mutate onSettled when useMutation has no callbacks',
      (tester, client) async {
    final callbacks = <String>[];

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutate = useMutation(MutationOptions.simple<String, String>(
          mutationFn: (text) => sleep(10).then((_) => text),
        )).mutate;

        return TextButton(
          onPressed: () => mutate(
            'todo',
            callbacks: MutateCallbacks(
              onSettled: (_, __, ___, ____, _____) =>
                  callbacks.add('mutate.onSettled'),
            ),
          ),
          child: const Text('mutate'),
        );
      }),
    );

    await click(tester, 'mutate');
    await advance(tester, 10);

    expect(callbacks, ['mutate.onSettled']);
  });

  // useMutation.test.tsx:339
  hookTest(
      'should call only mutateAsync onSuccess when useMutation has no callbacks',
      (tester, client) async {
    final callbacks = <String>[];

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutateAsync = useMutation(MutationOptions.simple<String, String>(
          mutationFn: (text) => sleep(10).then((_) => text),
        )).mutateAsync;

        useEffect(() {
          Timer(Duration.zero, () async {
            await mutateAsync(
              'todo',
              callbacks: MutateCallbacks(
                onSuccess: (_, __, ___) =>
                    callbacks.add('mutateAsync.onSuccess'),
              ),
            );
          });
          return null;
        }, [mutateAsync]);

        return const SizedBox();
      }),
    );

    await advance(tester, 10);

    expect(callbacks, ['mutateAsync.onSuccess']);
  });

  // useMutation.test.tsx:367
  hookTest(
      'should call only mutateAsync onError when useMutation has no callbacks',
      (tester, client) async {
    final callbacks = <String>[];

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutateAsync = useMutation(MutationOptions.simple<String, String>(
          mutationFn: (_) => sleep(10).then((_) => throw StateError('oops')),
        )).mutateAsync;

        useEffect(() {
          Timer(Duration.zero, () async {
            try {
              await mutateAsync(
                'todo',
                callbacks: MutateCallbacks(
                  onError: (_, __, ___, ____) =>
                      callbacks.add('mutateAsync.onError'),
                ),
              );
            } catch (_) {
              // Upstream's empty `catch {}`.
            }
          });
          return null;
        }, [mutateAsync]);

        return const SizedBox();
      }),
    );

    await advance(tester, 10);

    expect(callbacks, ['mutateAsync.onError']);
  });

  // useMutation.test.tsx:400
  hookTest(
      'should call only mutateAsync onSettled when useMutation has no callbacks',
      (tester, client) async {
    final callbacks = <String>[];

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutateAsync = useMutation(MutationOptions.simple<String, String>(
          mutationFn: (text) => sleep(10).then((_) => text),
        )).mutateAsync;

        useEffect(() {
          Timer(Duration.zero, () async {
            await mutateAsync(
              'todo',
              callbacks: MutateCallbacks(
                onSettled: (_, __, ___, ____, _____) =>
                    callbacks.add('mutateAsync.onSettled'),
              ),
            );
          });
          return null;
        }, [mutateAsync]);

        return const SizedBox();
      }),
    );

    await advance(tester, 10);

    expect(callbacks, ['mutateAsync.onSettled']);
  });

  // useMutation.test.tsx:428
  hookTest(
      'should be able to call `onSuccess` and `onSettled` after each successful mutate',
      (tester, client) async {
    var count = 0;
    final onSuccessMock = <int>[];
    final onSettledMock = <int?>[];

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutate = useMutation(MutationOptions.simple<int, ({int count})>(
          mutationFn: (vars) => Future.value(vars.count),
          onSuccess: (data, _, __) => onSuccessMock.add(data),
          onSettled: (data, _, __, ___, ____) => onSettledMock.add(data),
        )).mutate;

        return Column(children: [
          Text('$count', key: const Key('heading')),
          TextButton(
            onPressed: () => mutate((count: ++count)),
            child: const Text('mutate'),
          ),
        ]);
      }),
    );

    expect(_heading(tester), '0');

    await _clickTogether(tester, ['mutate', 'mutate', 'mutate']);

    await advance(tester, 0);
    expect(_heading(tester), '3');
    expect(onSuccessMock, hasLength(3));

    expect(onSuccessMock, [1, 2, 3]);

    expect(onSettledMock, hasLength(3));

    expect(onSettledMock, [1, 2, 3]);
  });

  // useMutation.test.tsx:476
  hookTest(
      'should set correct values for `failureReason` and `failureCount` on multiple mutate calls',
      (tester, client) async {
    var count = 0;
    var calls = 0;

    // `mockImplementationOnce` a rejection, then `mockImplementation`.
    Future<({int count})> mutateFn(({int count}) value) {
      if (++calls == 1) {
        return Future.error(StateError('Error test Jonas'));
      }
      return sleep(10).then((_) => value);
    }

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutation = useMutation(
          MutationOptions.simple<({int count}), ({int count})>(
            mutationFn: mutateFn,
          ),
        );
        final result = mutation.value;

        return Column(children: [
          Text([
            'Data',
            if (result.dataOrNull case final data?) '${data.count}',
          ].join(' ')),
          Text('Status ${result.status.name}'),
          Text('Failed ${result.failureCount} times'),
          Text('Failed because ${_message(result.failureReason)}'),
          TextButton(
            onPressed: () => mutation.mutate((count: ++count)),
            child: const Text('mutate'),
          ),
        ]);
      }),
    );

    expect(find.text('Data'), findsOneWidget);

    await click(tester, 'mutate');

    await advance(tester, 0);
    expect(find.text('Status error'), findsOneWidget);
    expect(find.text('Failed 1 times'), findsOneWidget);
    expect(find.text('Failed because Error test Jonas'), findsOneWidget);

    await click(tester, 'mutate');
    await advance(tester, 0);
    expect(find.text('Status pending'), findsOneWidget);
    await advance(tester, 11);
    expect(find.text('Status success'), findsOneWidget);
    expect(find.text('Data 2'), findsOneWidget);
    expect(find.text('Failed 0 times'), findsOneWidget);
    expect(find.text('Failed because null'), findsOneWidget);
  });

  // useMutation.test.tsx:529
  hookTest(
      'should be able to call `onError` and `onSettled` after each failed mutate',
      (tester, client) async {
    final onErrorMock = <String>[];
    final onSettledMock = <String?>[];
    var count = 0;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutate = useMutation(MutationOptions.simple<void, ({int count})>(
          mutationFn: (vars) => Future.error(
              StateError('Expected mock error. All is well! ${vars.count}')),
          onError: (error, _, __, ___) => onErrorMock.add(_message(error)),
          onSettled: (_, error, __, ___, ____) =>
              onSettledMock.add((error as StateError?)?.message),
        )).mutate;

        return Column(children: [
          Text('$count', key: const Key('heading')),
          TextButton(
            onPressed: () => mutate((count: ++count)),
            child: const Text('mutate'),
          ),
        ]);
      }),
    );

    expect(_heading(tester), '0');

    await _clickTogether(tester, ['mutate', 'mutate', 'mutate']);

    await advance(tester, 0);
    expect(_heading(tester), '3');
    expect(onErrorMock, hasLength(3));
    expect(onErrorMock, [
      'Expected mock error. All is well! 1',
      'Expected mock error. All is well! 2',
      'Expected mock error. All is well! 3',
    ]);

    expect(onSettledMock, hasLength(3));
    expect(onSettledMock, [
      'Expected mock error. All is well! 1',
      'Expected mock error. All is well! 2',
      'Expected mock error. All is well! 3',
    ]);
  });

  // useMutation.test.tsx:598
  hookTest(
      'should be able to call `onSuccess` callback after successful mutate',
      (tester, client) async {
    final callbacks = <String>[];

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutate = useMutation(MutationOptions.simple<String, String>(
          mutationFn: (text) => sleep(10).then((_) => text),
          onSuccess: (_, __, ___) => callbacks.add('useMutation.onSuccess'),
        )).mutate;

        return TextButton(
          onPressed: () => mutate(
            'todo',
            callbacks: MutateCallbacks(
              onSuccess: (_, __, ___) => callbacks.add('mutate.onSuccess'),
            ),
          ),
          child: const Text('mutate'),
        );
      }),
    );

    await click(tester, 'mutate');
    await advance(tester, 10);

    expect(callbacks, ['useMutation.onSuccess', 'mutate.onSuccess']);
  });

  // useMutation.test.tsx:632
  hookTest('should be able to call `onError` callback after failed mutate',
      (tester, client) async {
    final callbacks = <String>[];

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutate = useMutation(MutationOptions.simple<String, String>(
          mutationFn: (_) => sleep(10).then((_) => throw StateError('oops')),
          onError: (_, __, ___, ____) => callbacks.add('useMutation.onError'),
        )).mutate;

        return TextButton(
          onPressed: () => mutate(
            'todo',
            callbacks: MutateCallbacks(
              onError: (_, __, ___, ____) => callbacks.add('mutate.onError'),
            ),
          ),
          child: const Text('mutate'),
        );
      }),
    );

    await click(tester, 'mutate');
    await advance(tester, 10);

    expect(callbacks, ['useMutation.onError', 'mutate.onError']);
  });

  // useMutation.test.tsx:669
  hookTest('should be able to call `onSettled` callback after mutate',
      (tester, client) async {
    final callbacks = <String>[];

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutate = useMutation(MutationOptions.simple<String, String>(
          mutationFn: (text) => sleep(10).then((_) => text),
          onSettled: (_, __, ___, ____, _____) =>
              callbacks.add('useMutation.onSettled'),
        )).mutate;

        return TextButton(
          onPressed: () => mutate(
            'todo',
            callbacks: MutateCallbacks(
              onSettled: (_, __, ___, ____, _____) =>
                  callbacks.add('mutate.onSettled'),
            ),
          ),
          child: const Text('mutate'),
        );
      }),
    );

    await click(tester, 'mutate');
    await advance(tester, 10);

    expect(callbacks, ['useMutation.onSettled', 'mutate.onSettled']);
  });

  // useMutation.test.tsx:703
  hookTest(
      'should be able to call `onSuccess` callback after successful mutateAsync',
      (tester, client) async {
    final callbacks = <String>[];

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutateAsync = useMutation(MutationOptions.simple<String, String>(
          mutationFn: (text) => sleep(10).then((_) => text),
          onSuccess: (_, __, ___) => callbacks.add('useMutation.onSuccess'),
        )).mutateAsync;

        useEffect(() {
          Timer(Duration.zero, () async {
            await mutateAsync(
              'todo',
              callbacks: MutateCallbacks(
                onSuccess: (_, __, ___) =>
                    callbacks.add('mutateAsync.onSuccess'),
              ),
            );
          });
          return null;
        }, [mutateAsync]);

        return const SizedBox();
      }),
    );

    await advance(tester, 10);

    expect(callbacks, [
      'useMutation.onSuccess',
      'mutateAsync.onSuccess',
    ]);
  });

  // useMutation.test.tsx:737
  hookTest('should be able to call `onError` callback after failed mutateAsync',
      (tester, client) async {
    final callbacks = <String>[];

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutateAsync = useMutation(MutationOptions.simple<String, String>(
          mutationFn: (_) => sleep(10).then((_) => throw StateError('oops')),
          onError: (_, __, ___, ____) => callbacks.add('useMutation.onError'),
        )).mutateAsync;

        useEffect(() {
          Timer(Duration.zero, () async {
            try {
              await mutateAsync(
                'todo',
                callbacks: MutateCallbacks(
                  onError: (_, __, ___, ____) =>
                      callbacks.add('mutateAsync.onError'),
                ),
              );
            } catch (_) {
              // Upstream's empty `catch {}`.
            }
          });
          return null;
        }, [mutateAsync]);

        return const SizedBox();
      }),
    );

    await advance(tester, 10);

    expect(callbacks, ['useMutation.onError', 'mutateAsync.onError']);
  });

  // useMutation.test.tsx:773
  hookTest('should be able to call `onSettled` callback after mutateAsync',
      (tester, client) async {
    final callbacks = <String>[];

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutateAsync = useMutation(MutationOptions.simple<String, String>(
          mutationFn: (text) => sleep(10).then((_) => text),
          onSettled: (_, __, ___, ____, _____) =>
              callbacks.add('useMutation.onSettled'),
        )).mutateAsync;

        useEffect(() {
          Timer(Duration.zero, () async {
            await mutateAsync(
              'todo',
              callbacks: MutateCallbacks(
                onSettled: (_, __, ___, ____, _____) =>
                    callbacks.add('mutateAsync.onSettled'),
              ),
            );
          });
          return null;
        }, [mutateAsync]);

        return const SizedBox();
      }),
    );

    await advance(tester, 10);

    expect(callbacks, [
      'useMutation.onSettled',
      'mutateAsync.onSettled',
    ]);
  });

  // useMutation.test.tsx:807
  hookTest('should be able to override the useMutation success callbacks',
      (tester, client) async {
    final callbacks = <String>[];

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutateAsync = useMutation(MutationOptions.simple<String, String>(
          mutationFn: Future<String>.value,
          onSuccess: (_, __, ___) {
            callbacks.add('useMutation.onSuccess');
            return Future<void>.value();
          },
          onSettled: (_, __, ___, ____, _____) {
            callbacks.add('useMutation.onSettled');
            return Future<void>.value();
          },
        )).mutateAsync;

        useEffect(() {
          Timer(const Duration(milliseconds: 10), () async {
            try {
              final result = await mutateAsync(
                'todo',
                callbacks: MutateCallbacks(
                  onSuccess: (_, __, ___) {
                    callbacks.add('mutateAsync.onSuccess');
                    return Future<void>.value();
                  },
                  onSettled: (_, __, ___, ____, _____) {
                    callbacks.add('mutateAsync.onSettled');
                    return Future<void>.value();
                  },
                ),
              );
              callbacks.add('mutateAsync.result:$result');
            } catch (_) {
              // Upstream's empty `catch {}`.
            }
          });
          return null;
        }, [mutateAsync]);

        return const SizedBox();
      }),
    );

    await advance(tester, 10);

    expect(callbacks, [
      'useMutation.onSuccess',
      'useMutation.onSettled',
      'mutateAsync.onSuccess',
      'mutateAsync.onSettled',
      'mutateAsync.result:todo',
    ]);
  });

  // useMutation.test.tsx:857
  hookTest(
      'should be able to override the error callbacks when using mutateAsync',
      (tester, client) async {
    final callbacks = <String>[];

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutateAsync = useMutation(MutationOptions.simple<String, String>(
          mutationFn: (_) => Future.error(StateError('oops')),
          onError: (_, __, ___, ____) {
            callbacks.add('useMutation.onError');
            return Future<void>.value();
          },
          onSettled: (_, __, ___, ____, _____) {
            callbacks.add('useMutation.onSettled');
            return Future<void>.value();
          },
        )).mutateAsync;

        useEffect(() {
          Timer(const Duration(milliseconds: 10), () async {
            try {
              await mutateAsync(
                'todo',
                callbacks: MutateCallbacks(
                  onError: (_, __, ___, ____) {
                    callbacks.add('mutateAsync.onError');
                    return Future<void>.value();
                  },
                  onSettled: (_, __, ___, ____, _____) {
                    callbacks.add('mutateAsync.onSettled');
                    return Future<void>.value();
                  },
                ),
              );
            } catch (error) {
              callbacks.add('mutateAsync.error:${_message(error)}');
            }
          });
          return null;
        }, [mutateAsync]);

        return const SizedBox();
      }),
    );

    await advance(tester, 10);

    expect(callbacks, [
      'useMutation.onError',
      'useMutation.onSettled',
      'mutateAsync.onError',
      'mutateAsync.onSettled',
      'mutateAsync.error:oops',
    ]);
  });

  // useMutation.test.tsx:908
  hookTest('should be able to override the error callbacks when using mutate',
      (tester, client) async {
    final callbacks = <String>[];

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutate = useMutation(MutationOptions.simple<String, String>(
          mutationFn: (_) =>
              sleep(10).then((_) => Future.error(StateError('oops'))),
          onError: (_, __, ___, ____) => callbacks.add('useMutation.onError'),
          onSettled: (_, __, ___, ____, _____) =>
              callbacks.add('useMutation.onSettled'),
        )).mutate;

        return TextButton(
          onPressed: () => mutate(
            'todo',
            callbacks: MutateCallbacks(
              onError: (_, __, ___, ____) => callbacks.add('mutate.onError'),
              onSettled: (_, __, ___, ____, _____) =>
                  callbacks.add('mutate.onSettled'),
            ),
          ),
          child: const Text('mutate'),
        );
      }),
    );

    await click(tester, 'mutate');
    await advance(tester, 10);

    expect(callbacks, [
      'useMutation.onError',
      'useMutation.onSettled',
      'mutate.onError',
      'mutate.onSettled',
    ]);
  });

  // useMutation.test.tsx:954
  hookTest('should be able to override the settled callbacks when using mutate',
      (tester, client) async {
    final callbacks = <String>[];

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutate = useMutation(MutationOptions.simple<String, String>(
          mutationFn: (text) => sleep(10).then((_) => text),
          onSuccess: (_, __, ___) => callbacks.add('useMutation.onSuccess'),
          onSettled: (_, __, ___, ____, _____) =>
              callbacks.add('useMutation.onSettled'),
        )).mutate;

        return TextButton(
          onPressed: () => mutate(
            'todo',
            callbacks: MutateCallbacks(
              onSuccess: (_, __, ___) => callbacks.add('mutate.onSuccess'),
              onSettled: (_, __, ___, ____, _____) =>
                  callbacks.add('mutate.onSettled'),
            ),
          ),
          child: const Text('mutate'),
        );
      }),
    );

    await click(tester, 'mutate');
    await advance(tester, 10);

    expect(callbacks, [
      'useMutation.onSuccess',
      'useMutation.onSettled',
      'mutate.onSuccess',
      'mutate.onSettled',
    ]);
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
      HookBuilder(builder: (context) {
        final state = useMutation(
            MutationOptions<String, String, void>(mutationKey: key));

        states.add(state.value);

        final mutate = state.mutate;

        useEffect(() {
          Timer(const Duration(milliseconds: 10), () => mutate('todo'));
          return null;
        }, [mutate]);

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

  // useMutation.test.tsx:1034
  hookTest('should be able to retry a failed mutation', (tester, client) async {
    var count = 0;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutate = useMutation(MutationOptions.simple<void, String>(
          mutationFn: (_) {
            count++;
            return Future.error(StateError('oops'));
          },
          retry: const RetryPolicy.times(1),
          retryDelay: const RetryDelay.fixed(Duration(milliseconds: 5)),
        )).mutate;

        useEffect(() {
          Timer(const Duration(milliseconds: 10), () => mutate('todo'));
          return null;
        }, [mutate]);

        return const SizedBox();
      }),
    );

    await advance(tester, 15);

    expect(count, 2);
  });

  // useMutation.test.tsx:1063
  hookTest('should not retry mutations while offline', (tester, client) async {
    final onlineMock = _mockOnlineManagerIsOnline(client, false);

    var count = 0;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutation = useMutation(MutationOptions.simple<void, String>(
          mutationFn: (_) {
            count++;
            return Future.error(StateError('oops'));
          },
          retry: const RetryPolicy.times(1),
          retryDelay: const RetryDelay.fixed(Duration(milliseconds: 5)),
        ));
        final result = mutation.value;

        return Column(children: [
          TextButton(
            onPressed: () => mutation.mutate('todo'),
            child: const Text('mutate'),
          ),
          Text('error: ${_message(result.errorOrNull)}, '
              'status: ${result.status.name}, isPaused: ${result.isPaused}'),
        ]);
      }),
    );

    expect(find.text('error: null, status: idle, isPaused: false'),
        findsOneWidget);

    await click(tester, 'mutate');

    await advance(tester, 0);
    expect(find.text('error: null, status: pending, isPaused: true'),
        findsOneWidget);

    expect(count, 0);

    onlineMock.mockReturnValue = true;
    unawaited(client.mutationCache.resumePaused());

    await advance(tester, 6);
    expect(find.text('error: oops, status: error, isPaused: false'),
        findsOneWidget);

    expect(count, 2);
    onlineMock.mockRestore();
  }, createClient: _clientWithOnlineSpy);

  // useMutation.test.tsx:1117 — D14: onMutate is told the variables only;
  // the mutation callback context it gets upstream is not asserted.
  hookTest('should call onMutate even if paused', (tester, client) async {
    final onlineMock = _mockOnlineManagerIsOnline(client, false);
    final onMutate = <String>[];
    var count = 0;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutation = useMutation(MutationOptions<int, String, void>(
          mutationFn: (_) async {
            count++;
            await sleep(10);
            return count;
          },
          onMutate: onMutate.add,
        ));
        final result = mutation.value;

        return Column(children: [
          TextButton(
            onPressed: () => mutation.mutate('todo'),
            child: const Text('mutate'),
          ),
          Text('data: ${result.dataOrNull ?? 'null'}, '
              'status: ${result.status.name}, isPaused: ${result.isPaused}'),
        ]);
      }),
    );

    expect(
        find.text('data: null, status: idle, isPaused: false'), findsOneWidget);

    await click(tester, 'mutate');

    await advance(tester, 0);
    expect(find.text('data: null, status: pending, isPaused: true'),
        findsOneWidget);

    expect(onMutate, hasLength(1));
    expect(onMutate, ['todo']);

    onlineMock.mockReturnValue = true;
    unawaited(client.mutationCache.resumePaused());
    await advance(tester, 11);
    expect(
        find.text('data: 1, status: success, isPaused: false'), findsOneWidget);

    expect(onMutate, hasLength(1));
    expect(count, 1);

    onlineMock.mockRestore();
  }, createClient: _clientWithOnlineSpy);

  // useMutation.test.tsx:1176 — strengthened (D8): a frame can merge an
  // intermediate state into the next build, so the observer's first
  // delivery after the tap is asserted beside upstream's two builds.
  hookTest('should optimistically go to paused state if offline',
      (tester, client) async {
    final onlineMock = _mockOnlineManagerIsOnline(client, false);
    var count = 0;
    final rec = Recorder<MutationResult<int, String>>();
    String describe(MutationResult<int, String> state) =>
        '${state.status.name}, ${state.isPaused}';

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutation = useMutation(
          MutationOptions.simple<int, String>(
            mutationFn: (_) async {
              count++;
              await sleep(10);
              return count;
            },
          ),
          buildWhen: rec.buildWhen,
        );
        final result = rec.build(mutation.value);

        return Column(children: [
          TextButton(
            onPressed: () => mutation.mutate('todo'),
            child: const Text('mutate'),
          ),
          Text('data: ${result.dataOrNull ?? 'null'}, '
              'status: ${result.status.name}, isPaused: ${result.isPaused}'),
        ]);
      }),
    );

    expect(
        find.text('data: null, status: idle, isPaused: false'), findsOneWidget);

    await click(tester, 'mutate');

    await advance(tester, 0);
    expect(find.text('data: null, status: pending, isPaused: true'),
        findsOneWidget);

    // no intermediate 'pending, false' state is expected because we don't
    // start mutating!
    expect(describe(rec.builds[0]), 'idle, false');
    expect(describe(rec.builds[1]), 'pending, true');
    // A frame could merge an intermediate state into the next build; the
    // observer's deliveries cannot (D8).
    expect(describe(rec.delivered.first), 'pending, true');

    onlineMock.mockReturnValue = true;
    unawaited(client.mutationCache.resumePaused());

    await advance(tester, 11);
    expect(
        find.text('data: 1, status: success, isPaused: false'), findsOneWidget);

    onlineMock.mockRestore();
  }, createClient: _clientWithOnlineSpy);

  // useMutation.test.tsx:1231
  hookTest('should be able to retry a mutation when online',
      (tester, client) async {
    final onlineMock = _mockOnlineManagerIsOnline(client, false);
    final key = queryKey();

    var count = 0;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final state = useMutation(MutationOptions.simple<String, String>(
          mutationKey: key,
          mutationFn: (_) => sleep(10).then((_) {
            count++;
            return count > 1
                ? Future.value('data$count')
                : Future<String>.error(StateError('oops'));
          }),
          retry: const RetryPolicy.times(1),
          retryDelay: const RetryDelay.fixed(Duration(milliseconds: 5)),
          networkMode: NetworkMode.offlineFirst,
        ));
        final result = state.value;

        return Column(children: [
          TextButton(
            onPressed: () => state.mutate('todo'),
            child: const Text('mutate'),
          ),
          Text('status: ${result.status.name}'),
          Text('isPaused: ${result.isPaused}'),
          Text('data: ${result.dataOrNull ?? 'null'}'),
        ]);
      }),
    );

    expect(find.text('status: idle'), findsOneWidget);
    await click(tester, 'mutate');
    await advance(tester, 16);
    expect(find.text('isPaused: true'), findsOneWidget);

    List<Mutation<Object?, Object?, Object?>> findAll() => client.mutationCache
        .findAll(filters: MutationFilters(mutationKey: key));

    expect(findAll().length, 1);
    final paused = findAll()[0].state;
    expect(paused.status, MutationStatus.pending);
    expect(paused.isPaused, isTrue);
    expect(paused.failureCount, 1);
    expect(_message(paused.failureReason), 'oops');

    onlineMock.mockReturnValue = true;
    unawaited(client.mutationCache.resumePaused());

    await advance(tester, 11);
    expect(find.text('data: data2'), findsOneWidget);

    final settled = findAll()[0].state;
    expect(settled.status, MutationStatus.success);
    expect(settled.isPaused, isFalse);
    expect(settled.failureCount, 0);
    expect(settled.failureReason, isNull);
    expect(settled.data, 'data2');

    onlineMock.mockRestore();
  }, createClient: _clientWithOnlineSpy);

  // useMutation.test.tsx:1301 — upstream asserts nothing: the case fails on
  // a throw. So does a widget test. The final advance drains the `sleep`.
  hookTest('should not change state if unmounted', (tester, client) async {
    final mutates = HookBuilder(builder: (context) {
      final mutate = useMutation(MutationOptions.simple<void, void>(
        mutationFn: (_) => sleep(10),
      )).mutate;
      return TextButton(
        onPressed: () => mutate(null),
        child: const Text('mutate'),
      );
    });

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mounted = useState(true);
        return Column(children: [
          TextButton(
            onPressed: () => mounted.value = false,
            child: const Text('unmount'),
          ),
          if (mounted.value) mutates,
        ]);
      }),
    );
    await _clickTogether(tester, ['mutate', 'unmount']);

    await advance(tester, 10);
  });

  // useMutation.test.tsx:1469
  hookTest('should not throw an error when throwOnError is not set',
      (tester, client) async {
    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutation = useMutation(MutationOptions.simple<String, void>(
          mutationFn: (_) =>
              sleep(10).then((_) => throw StateError('Expected mock error')),
        ));

        return Column(children: [
          TextButton(
            onPressed: () => mutation.mutate(null),
            child: const Text('mutate'),
          ),
          Text('error: ${_message(mutation.value.errorOrNull)}'),
        ]);
      }),
    );

    await click(tester, 'mutate');
    await advance(tester, 11);

    expect(find.text('error: Expected mock error'), findsOneWidget);
  });

  // useMutation.test.tsx:1494
  final successMock = <Object?>[];
  hookTest('should pass meta to mutation on success', (tester, client) async {
    const metaSuccessMessage = 'mutation succeeded';

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutation = useMutation(MutationOptions.simple<String, void>(
          mutationFn: (_) => Future.value(''),
          meta: const {'metaSuccessMessage': metaSuccessMessage},
        ));
        final succeed = mutation.mutate;

        return Column(children: [
          TextButton(
            onPressed: () => succeed(null),
            child: const Text('succeed'),
          ),
          if (mutation.value.isSuccess) const Text('successTest'),
        ]);
      }),
    );

    await click(tester, 'succeed');

    await advance(tester, 0);
    expect(find.text('successTest'), findsOneWidget);

    expect(successMock, hasLength(1));
    expect(successMock, [metaSuccessMessage]);
  },
      createClient: () => QueryClient(
            mutationCache: MutationCache(
              onSuccess: (_, __, ___, mutation) => successMock.add((mutation
                  .meta as Map<String, String>?)?['metaSuccessMessage']),
            ),
          ));

  // useMutation.test.tsx:1535
  final errorMock = <Object?>[];
  hookTest('should pass meta to mutation on error', (tester, client) async {
    const metaErrorMessage = 'mutation failed';

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutation = useMutation(MutationOptions.simple<String, void>(
          mutationFn: (_) => Future.error(StateError('')),
          meta: const {'metaErrorMessage': metaErrorMessage},
        ));
        final error = mutation.mutate;

        return Column(children: [
          TextButton(
            onPressed: () => error(null),
            child: const Text('error'),
          ),
          if (mutation.value.isError) const Text('errorTest'),
        ]);
      }),
    );

    await click(tester, 'error');

    await advance(tester, 0);
    expect(find.text('errorTest'), findsOneWidget);

    expect(errorMock, hasLength(1));
    expect(errorMock, [metaErrorMessage]);
  },
      createClient: () => QueryClient(
            mutationCache: MutationCache(
              onError: (_, __, ___, ____, mutation) => errorMock.add(
                  (mutation.meta as Map<String, String>?)?['metaErrorMessage']),
            ),
          ));

  // useMutation.test.tsx:1578
  hookTest('should call cache callbacks when unmounted',
      (tester, client) async {
    var onSuccess = 0;
    var onSuccessMutate = 0;
    var onSettled = 0;
    var onSettledMutate = 0;
    final mutationKey = queryKey();
    var count = 0;

    final component = HookBuilder(builder: (context) {
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
      HookBuilder(builder: (context) {
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
    await _clickTogether(tester, ['mutate', 'hide']);

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

  // useMutation.test.tsx:1650 — D14: the callbacks' fourth argument, the
  // mutation callback context, is not asserted.
  hookTest('should call mutate callbacks only for the last observer',
      (tester, client) async {
    final onSuccess = <(String, String, Object?)>[];
    final onSuccessMutate = <(String, String, Object?)>[];
    final onSettled = <(String?, Object?, String, Object?)>[];
    final onSettledMutate = <(String?, Object?, String, Object?)>[];
    var count = 0;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutation = useMutation(MutationOptions<String, String, Object?>(
          mutationFn: (text) async {
            count++;
            final result = 'result-$text';
            await sleep(10);
            return result;
          },
          onSuccess: (data, variables, onMutateResult) =>
              onSuccess.add((data, variables, onMutateResult)),
          onSettled: (data, error, _, variables, onMutateResult) =>
              onSettled.add((data, error, variables, onMutateResult)),
        ));
        final result = mutation.value;

        final callbacks = MutateCallbacks<String, String, Object?>(
          onSuccess: (data, variables, onMutateResult) =>
              onSuccessMutate.add((data, variables, onMutateResult)),
          onSettled: (data, error, _, variables, onMutateResult) =>
              onSettledMutate.add((data, error, variables, onMutateResult)),
        );

        return Column(children: [
          TextButton(
            onPressed: () => mutation.mutate('todo1', callbacks: callbacks),
            child: const Text('mutate1'),
          ),
          TextButton(
            onPressed: () => mutation.mutate('todo2', callbacks: callbacks),
            child: const Text('mutate2'),
          ),
          Text('data: ${result.dataOrNull ?? 'null'}, '
              'status: ${result.status.name}'),
        ]);
      }),
    );

    expect(find.text('data: null, status: idle'), findsOneWidget);

    await _clickTogether(tester, ['mutate1', 'mutate2']);

    await advance(tester, 11);
    expect(find.text('data: result-todo2, status: success'), findsOneWidget);

    expect(count, 2);

    expect(onSuccess, hasLength(2));
    expect(onSuccess[0], ('result-todo1', 'todo1', null));
    expect(onSuccess[1], ('result-todo2', 'todo2', null));
    expect(onSettled, hasLength(2));
    expect(onSuccessMutate, hasLength(1));
    expect(onSuccessMutate, [('result-todo2', 'todo2', null)]);
    expect(onSettledMutate, hasLength(1));
    expect(onSettledMutate, [('result-todo2', null, 'todo2', null)]);
  });

  // useMutation.test.tsx:1761 — D14: the mutation callback context, the
  // fourth argument upstream's `onError` is called with, is not asserted.
  hookTest('should go to error state if onSuccess callback errors',
      (tester, client) async {
    final error = StateError('error from onSuccess');
    final onError = <(Object, String, Object?)>[];

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutation = useMutation(MutationOptions<String, String, Object?>(
          mutationFn: (_) => sleep(10).then((_) => 'result'),
          onSuccess: (_, __, ___) => Future.error(error),
          onError: (error, _, variables, onMutateResult) =>
              onError.add((error, variables, onMutateResult)),
        ));

        return Column(children: [
          TextButton(
            onPressed: () => mutation.mutate('todo'),
            child: const Text('mutate'),
          ),
          Text('status: ${mutation.value.status.name}'),
        ]);
      }),
    );

    expect(find.text('status: idle'), findsOneWidget);

    await click(tester, 'mutate');

    await advance(tester, 11);
    expect(find.text('status: error'), findsOneWidget);

    expect(onError, contains((error, 'todo', null)));
  });

  // useMutation.test.tsx:1796 — `process.on('unhandledRejection')` is a zone
  // around the tap that starts the mutation; the rejected `onError` is
  // reported there. Upstream asserts nothing about it, nor does the port.
  hookTest('should go to error state if onError callback errors',
      (tester, client) async {
    final unhandledRejectionFn = <Object>[];

    final error = StateError('error from onError');
    final mutateFnError = StateError('mutateFnError');

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutation = useMutation(MutationOptions.simple<String, String>(
          mutationFn: (_) => sleep(10).then((_) => throw mutateFnError),
          onError: (_, __, ___, ____) => Future.error(error),
        ));
        final result = mutation.value;

        return Column(children: [
          TextButton(
            onPressed: () => mutation.mutate('todo'),
            child: const Text('mutate'),
          ),
          Text('error: ${_message(result.errorOrNull)}, '
              'status: ${result.status.name}'),
        ]);
      }),
    );

    expect(find.text('error: null, status: idle'), findsOneWidget);

    await _guarded(
      () => click(tester, 'mutate'),
      error,
      unhandledRejectionFn.add,
    );

    await advance(tester, 11);
    expect(find.text('error: mutateFnError, status: error'), findsOneWidget);
  });

  // useMutation.test.tsx:1841 — the zone as in 1796. D14: the mutation
  // callback context, the fourth argument upstream's `onError` is called
  // with, is not asserted.
  hookTest('should go to error state if onSettled callback errors',
      (tester, client) async {
    final unhandledRejectionFn = <Object>[];

    final error = StateError('error from onSettled');
    final mutateFnError = StateError('mutateFnError');
    final onError = <(Object, String, Object?)>[];

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutation = useMutation(MutationOptions<String, String, Object?>(
          mutationFn: (_) => sleep(10).then((_) => throw mutateFnError),
          onSettled: (_, __, ___, ____, _____) => Future.error(error),
          onError: (error, _, variables, onMutateResult) =>
              onError.add((error, variables, onMutateResult)),
        ));
        final result = mutation.value;

        return Column(children: [
          TextButton(
            onPressed: () => mutation.mutate('todo'),
            child: const Text('mutate'),
          ),
          Text('error: ${_message(result.errorOrNull)}, '
              'status: ${result.status.name}'),
        ]);
      }),
    );

    expect(find.text('error: null, status: idle'), findsOneWidget);

    await _guarded(
      () => click(tester, 'mutate'),
      error,
      unhandledRejectionFn.add,
    );

    await advance(tester, 11);
    expect(find.text('error: mutateFnError, status: error'), findsOneWidget);
    expect(onError, contains((mutateFnError, 'todo', null)));
  });

  // useMutation.test.tsx:1893
  hookTest('should use provided custom queryClient', (tester, client) async {
    // `render(<Page></Page>)`: no provider above the hook.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HookBuilder(builder: (context) {
          final mutation = useMutation(
            MutationOptions.simple<String, String>(
              mutationFn: Future<String>.value,
            ),
            client: client,
          );
          final result = mutation.value;

          return Column(children: [
            TextButton(
              onPressed: () => mutation.mutate('custom client'),
              child: const Text('mutate'),
            ),
            Text('data: ${result.dataOrNull ?? 'null'}, '
                'status: ${result.status.name}'),
          ]);
        }),
      ),
    ));

    expect(find.text('data: null, status: idle'), findsOneWidget);

    await click(tester, 'mutate');

    await advance(tester, 0);
    expect(find.text('data: custom client, status: success'), findsOneWidget);
  });

  // useMutation.test.tsx:1928
  hookTest('should be able to chain mutateAsync calls sequentially',
      (tester, client) async {
    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final result = useState('idle');

        final createUserAsync = useMutation(
            MutationOptions.simple<({String id, String name}), String>(
          mutationFn: (name) => sleep(10).then((_) => (id: '1', name: name)),
        )).mutateAsync;

        final updateProfileAsync =
            useMutation(MutationOptions.simple<String, String>(
          mutationFn: (userId) =>
              sleep(10).then((_) => 'profile updated for $userId'),
        )).mutateAsync;

        return Column(children: [
          TextButton(
            onPressed: () async {
              final user = await createUserAsync('John');
              final profile = await updateProfileAsync(user.id);
              result.value = profile;
            },
            child: const Text('chain'),
          ),
          Text('result: ${result.value}'),
        ]);
      }),
    );

    await click(tester, 'chain');
    await advance(tester, 10);
    await advance(tester, 11);

    expect(find.text('result: profile updated for 1'), findsOneWidget);
  });

  // useMutation.test.tsx:1968
  hookTest('should handle error in chained mutateAsync calls',
      (tester, client) async {
    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final result = useState('idle');

        final createUserAsync =
            useMutation(MutationOptions.simple<({String id}), String>(
          mutationFn: (_) =>
              sleep(10).then((_) => throw StateError('create failed')),
        )).mutateAsync;

        final updateProfileAsync =
            useMutation(MutationOptions.simple<String, String>(
          mutationFn: (userId) =>
              sleep(10).then((_) => 'profile updated for $userId'),
        )).mutateAsync;

        return Column(children: [
          TextButton(
            onPressed: () async {
              try {
                final user = await createUserAsync('John');
                final profile = await updateProfileAsync(user.id);
                result.value = profile;
              } catch (error) {
                result.value = 'error: ${_message(error)}';
              }
            },
            child: const Text('chain'),
          ),
          Text('result: ${result.value}'),
        ]);
      }),
    );

    await click(tester, 'chain');
    await advance(tester, 11);

    expect(find.text('result: error: create failed'), findsOneWidget);
  });

  // useMutation.test.tsx:2014
  hookTest(
      'should set success message from mutate callbacks when mutation succeeds',
      (tester, client) async {
    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final message = useState('idle');

        final mutate = useMutation(MutationOptions.simple<String, bool>(
          mutationFn: (shouldFail) => sleep(10).then((_) {
            if (shouldFail) {
              throw StateError('submission failed');
            }
            return 'submitted successfully';
          }),
          retry: RetryPolicy.never,
        )).mutate;

        return Column(children: [
          TextButton(
            onPressed: () => mutate(
              false,
              callbacks: MutateCallbacks(
                onSuccess: (result, _, __) =>
                    message.value = 'success: $result',
                onError: (error, _, __, ___) =>
                    message.value = 'error: ${_message(error)}',
              ),
            ),
            child: const Text('submit'),
          ),
          Text('message: ${message.value}'),
        ]);
      }),
    );

    await click(tester, 'submit');
    await advance(tester, 11);

    expect(
        find.text('message: success: submitted successfully'), findsOneWidget);
  });

  // useMutation.test.tsx:2056
  hookTest('should set error message from mutate callbacks when mutation fails',
      (tester, client) async {
    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final message = useState('idle');

        final mutate = useMutation(MutationOptions.simple<String, bool>(
          mutationFn: (shouldFail) => sleep(10).then((_) {
            if (shouldFail) {
              throw StateError('submission failed');
            }
            return 'submitted successfully';
          }),
          retry: RetryPolicy.never,
        )).mutate;

        return Column(children: [
          TextButton(
            onPressed: () => mutate(
              true,
              callbacks: MutateCallbacks(
                onSuccess: (result, _, __) =>
                    message.value = 'success: $result',
                onError: (error, _, __, ___) =>
                    message.value = 'error: ${_message(error)}',
              ),
            ),
            child: const Text('submit fail'),
          ),
          Text('message: ${message.value}'),
        ]);
      }),
    );

    await click(tester, 'submit fail');
    await advance(tester, 11);

    expect(find.text('message: error: submission failed'), findsOneWidget);
  });

  // useMutation.test.tsx:2098
  hookTest('should handle conditional error with retry using mutate',
      (tester, client) async {
    var attempt = 0;

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final message = useState('idle');

        final mutate = useMutation(MutationOptions.simple<String, void>(
          mutationFn: (_) => sleep(10).then((_) {
            attempt++;
            if (attempt < 2) {
              throw StateError('temporary failure');
            }
            return 'success';
          }),
          retry: RetryPolicy.never,
        )).mutate;

        return Column(children: [
          TextButton(
            onPressed: () => mutate(
              null,
              callbacks: MutateCallbacks(
                onSuccess: (result, _, __) => message.value = 'result: $result',
                onError: (_, __, ___, ____) =>
                    message.value = 'failed, retrying...',
              ),
            ),
            child: const Text('submit'),
          ),
          Text('message: ${message.value}'),
        ]);
      }),
    );

    await click(tester, 'submit');
    await advance(tester, 11);

    expect(find.text('message: failed, retrying...'), findsOneWidget);

    await click(tester, 'submit');
    await advance(tester, 11);

    expect(find.text('message: result: success'), findsOneWidget);
  });

  // useMutation.test.tsx:2148
  hookTest('should support optimistic update on success',
      (tester, client) async {
    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final itemsState = useState(const ['item1', 'item2', 'item3']);
        final items = itemsState.value;

        final successMessage = useState('');

        final mutate = useMutation(
            MutationOptions<String, String, ({List<String> previousItems})>(
          mutationFn: (item) => sleep(10).then((_) => item),
          onMutate: (item) {
            final previousItems = [...items];
            itemsState.value =
                itemsState.value.where((i) => i != item).toList();
            return (previousItems: previousItems);
          },
          onSuccess: (deletedItem, _, __) =>
              successMessage.value = 'deleted: $deletedItem',
          onError: (_, __, ___, context) {
            if (context?.previousItems case final previousItems?) {
              itemsState.value = previousItems;
            }
          },
        )).mutate;

        return Column(children: [
          for (final item in items)
            TextButton(
              key: ValueKey(item),
              onPressed: () => mutate(item),
              child: Text('delete $item'),
            ),
          Text('items: ${items.join(', ')}'),
          Text(
              'success: ${successMessage.value.isEmpty ? 'none' : successMessage.value}'),
        ]);
      }),
    );

    expect(find.text('items: item1, item2, item3'), findsOneWidget);
    expect(find.text('success: none'), findsOneWidget);

    await click(tester, 'delete item2');

    // optimistic update: item2 removed immediately
    expect(find.text('items: item1, item3'), findsOneWidget);

    await advance(tester, 11);

    // success: item2 stays removed and onSuccess called
    expect(find.text('items: item1, item3'), findsOneWidget);
    expect(find.text('success: deleted: item2'), findsOneWidget);
  });

  // useMutation.test.tsx:2205
  hookTest('should support optimistic update and rollback on error',
      (tester, client) async {
    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final itemsState = useState(const ['item1', 'item2', 'item3']);
        final items = itemsState.value;

        final message = useState('');

        final mutate = useMutation(
            MutationOptions<String, String, ({List<String> previousItems})>(
          mutationFn: (item) =>
              sleep(10).then((_) => throw StateError('Failed to delete $item')),
          onMutate: (item) {
            final previousItems = [...items];
            itemsState.value =
                itemsState.value.where((i) => i != item).toList();
            return (previousItems: previousItems);
          },
          onSuccess: (deletedItem, _, __) =>
              message.value = 'deleted: $deletedItem',
          onError: (_, __, ___, context) {
            message.value = 'rollback';
            if (context?.previousItems case final previousItems?) {
              itemsState.value = previousItems;
            }
          },
          retry: RetryPolicy.never,
        )).mutate;

        return Column(children: [
          for (final item in items)
            TextButton(
              key: ValueKey(item),
              onPressed: () => mutate(item),
              child: Text('delete $item'),
            ),
          Text('items: ${items.join(', ')}'),
          Text('message: ${message.value.isEmpty ? 'none' : message.value}'),
        ]);
      }),
    );

    expect(find.text('items: item1, item2, item3'), findsOneWidget);
    expect(find.text('message: none'), findsOneWidget);

    await click(tester, 'delete item2');

    // optimistic update: item2 removed immediately
    expect(find.text('items: item1, item3'), findsOneWidget);

    await advance(tester, 11);

    // rollback: item2 restored after error, onSuccess not called
    expect(find.text('items: item1, item2, item3'), findsOneWidget);
    expect(find.text('message: rollback'), findsOneWidget);
  });

  // useMutation.test.tsx:2267
  hookTest(
      'should update the cache in onMutate and roll back via onMutateResult in onError',
      (tester, client) async {
    final key = queryKey();
    client.setQueryData<List<String>>(key, ['Todo 1']);

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutate = useMutation(
            MutationOptions<void, String, ({List<String>? previousTodos})>(
          mutationFn: (_) => sleep(10)
              .then((_) => Future<void>.error(StateError('Some error'))),
          onMutate: (newTodo) async {
            await client.cancelQueries(filters: QueryFilters(queryKey: key));
            final previousTodos = client.getQueryData<List<String>>(key);

            client.updateQueryData<List<String>>(
              key,
              (old) => [...?old, newTodo],
            );

            return (previousTodos: previousTodos);
          },
          onError: (_, __, ___, onMutateResult) {
            if (onMutateResult?.previousTodos case final previousTodos?) {
              client.setQueryData(key, previousTodos);
            }
          },
        )).mutate;

        return TextButton(
          onPressed: () => mutate('Todo 2'),
          child: const Text('add'),
        );
      }),
    );

    await click(tester, 'add');
    // The optimistic value lands after onMutate's first await, so flush
    // microtasks before asserting.
    await advance(tester, 0);

    expect(client.getQueryData<List<String>>(key), ['Todo 1', 'Todo 2']);

    await advance(tester, 11);

    expect(client.getQueryData<List<String>>(key), ['Todo 1']);
  });

  // useMutation.test.tsx:2308
  hookTest(
      'should keep the optimistic update in place when the mutation succeeds',
      (tester, client) async {
    final key = queryKey();
    client.setQueryData<List<String>>(key, ['Todo 1']);

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutate = useMutation(
            MutationOptions<String, String, ({List<String>? previousTodos})>(
          mutationFn: (newTodo) => sleep(10).then((_) => newTodo),
          onMutate: (newTodo) async {
            await client.cancelQueries(filters: QueryFilters(queryKey: key));
            final previousTodos = client.getQueryData<List<String>>(key);

            client.updateQueryData<List<String>>(
              key,
              (old) => [...?old, newTodo],
            );

            return (previousTodos: previousTodos);
          },
        )).mutate;

        return TextButton(
          onPressed: () => mutate('Todo 2'),
          child: const Text('add'),
        );
      }),
    );

    await click(tester, 'add');
    await advance(tester, 11);

    expect(client.getQueryData<List<String>>(key), ['Todo 1', 'Todo 2']);
  });

  // useMutation.test.tsx:2339 — `Promise.all` is `Future.wait` with
  // `eagerError`, which rejects as soon as one future does.
  hookTest(
      'should be able to run multiple mutateAsync calls in parallel with Promise.all',
      (tester, client) async {
    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final result = useState('idle');

        final mutateAsync = useMutation(MutationOptions.simple<String, String>(
          mutationFn: (file) => sleep(10).then((_) => 'uploaded: $file'),
        )).mutateAsync;

        return Column(children: [
          TextButton(
            onPressed: () async {
              final results = await Future.wait([
                mutateAsync('file1'),
                mutateAsync('file2'),
                mutateAsync('file3'),
              ], eagerError: true);
              result.value = results.join(', ');
            },
            child: const Text('upload all'),
          ),
          Text('result: ${result.value}'),
        ]);
      }),
    );

    await click(tester, 'upload all');
    await advance(tester, 11);

    expect(
      find.text('result: uploaded: file1, uploaded: file2, uploaded: file3'),
      findsOneWidget,
    );
  });

  // useMutation.test.tsx:2378 — `Promise.all` as in 2339.
  hookTest(
      'should handle Promise.all rejection when one parallel mutateAsync call fails',
      (tester, client) async {
    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final result = useState('idle');

        final mutateAsync = useMutation(MutationOptions.simple<String, String>(
          mutationFn: (file) => sleep(10).then((_) {
            if (file == 'file2') {
              throw StateError('upload failed');
            }
            return 'uploaded: $file';
          }),
          retry: RetryPolicy.never,
        )).mutateAsync;

        return Column(children: [
          TextButton(
            onPressed: () async {
              try {
                final results = await Future.wait([
                  mutateAsync('file1'),
                  mutateAsync('file2'),
                  mutateAsync('file3'),
                ], eagerError: true);
                result.value = results.join(', ');
              } catch (error) {
                result.value = 'error: ${_message(error)}';
              }
            },
            child: const Text('upload all'),
          ),
          Text('result: ${result.value}'),
        ]);
      }),
    );

    await click(tester, 'upload all');
    await advance(tester, 11);

    expect(find.text('result: error: upload failed'), findsOneWidget);
  });

  // useMutation.test.tsx:2426 — `Promise.allSettled` is each future mapped
  // to its outcome, then `Future.wait`.
  hookTest(
      'should handle partial failure in parallel mutateAsync calls with Promise.allSettled',
      (tester, client) async {
    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final result = useState('idle');

        final mutateAsync = useMutation(MutationOptions.simple<String, String>(
          mutationFn: (file) => sleep(10).then((_) {
            if (file == 'file2') {
              throw StateError('upload failed');
            }
            return 'uploaded: $file';
          }),
          retry: RetryPolicy.never,
        )).mutateAsync;

        return Column(children: [
          TextButton(
            onPressed: () async {
              final results = await _allSettled([
                mutateAsync('file1'),
                mutateAsync('file2'),
                mutateAsync('file3'),
              ]);
              final summary = results
                  .map((r) => switch (r) {
                        (value: final value?, reason: _) => value,
                        (value: _, reason: final reason) =>
                          'error: ${_message(reason)}',
                      })
                  .join(', ');
              result.value = summary;
            },
            child: const Text('upload all'),
          ),
          Text('result: ${result.value}'),
        ]);
      }),
    );

    await click(tester, 'upload all');
    await advance(tester, 11);

    expect(
      find.text(
          'result: uploaded: file1, error: upload failed, uploaded: file3'),
      findsOneWidget,
    );
  });

  // useMutation.test.tsx:2479 — D14: the mutation callback context, the
  // fourth argument, is not asserted; data, variables and onMutateResult
  // are.
  hookTest(
      'should pass a non-undefined onMutateResult alongside context to onSuccess',
      (tester, client) async {
    final onSuccess = <(String, String, ({String startedWith})?)>[];

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutate =
            useMutation(MutationOptions<String, String, ({String startedWith})>(
          mutationFn: (text) => sleep(10).then((_) => text.toUpperCase()),
          onMutate: (text) => (startedWith: text),
          onSuccess: (data, variables, onMutateResult) =>
              onSuccess.add((data, variables, onMutateResult)),
        )).mutate;

        return TextButton(
          onPressed: () => mutate('todo'),
          child: const Text('mutate'),
        );
      }),
    );

    await click(tester, 'mutate');
    await advance(tester, 10);

    expect(onSuccess, hasLength(1));
    final (data, variables, onMutateResult) = onSuccess[0];
    expect(data, 'TODO');
    expect(variables, 'todo');
    expect(onMutateResult, (startedWith: 'todo'));
  });

  // useMutation.test.tsx:2507
  hookTest('should give mutationFn the same QueryClient instance via context',
      (tester, client) async {
    final key = queryKey();
    client.setQueryData<String>(key, 'tag-from-this-client');

    await tester.pumpApp(
      client,
      HookBuilder(builder: (context) {
        final mutation = useMutation(MutationOptions.simple<String?, String>(
          mutationFnWithContext: (_, context) =>
              sleep(10).then((_) => context.client.getQueryData<String>(key)),
        ));

        return Column(children: [
          Text('data: ${mutation.value.dataOrNull}'),
          TextButton(
            onPressed: () => mutation.mutate('todo'),
            child: const Text('mutate'),
          ),
        ]);
      }),
    );

    await click(tester, 'mutate');
    await advance(tester, 11);

    expect(find.text('data: tag-from-this-client'), findsOneWidget);
  });
}

String _heading(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('heading'))).data!;

/// `error instanceof Error ? error.message : 'null'`.
String _message(Object? error) => error is StateError ? error.message : 'null';

/// Upstream's `mockOnlineManagerIsOnline`: a spy on `isOnline` that answers
/// without telling anyone. Going "online" through it is no event, so nothing
/// resumes until the case calls `resumePaused`, as upstream's does.
final class _OnlineSpy extends OnlineManager {
  bool? mockReturnValue;

  void mockRestore() => mockReturnValue = null;

  @override
  bool isOnline() => mockReturnValue ?? super.isOnline();
}

QueryClient _clientWithOnlineSpy() => QueryClient(onlineManager: _OnlineSpy());

_OnlineSpy _mockOnlineManagerIsOnline(QueryClient client, bool value) =>
    (client.onlineManager as _OnlineSpy)..mockReturnValue = value;

/// Upstream's `process.on('unhandledRejection', …)` around [body]: the
/// callback's own rejection, [expected], goes to [onError] instead of
/// failing the case. Anything else still fails it: a zone also sees a timer
/// that throws, which upstream's handler for rejections would not catch.
Future<void> _guarded(
  Future<void> Function() body,
  Object expected,
  void Function(Object error) onError,
) async =>
    runZonedGuarded(body, (error, stack) {
      if (identical(error, expected)) {
        onError(error);
      } else {
        // The handler runs in the zone around the case, which fails it.
        Zone.current.handleUncaughtError(error, stack);
      }
    });

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

/// `Promise.allSettled`.
Future<List<({String? value, Object? reason})>> _allSettled(
  List<Future<String>> futures,
) =>
    Future.wait([
      for (final future in futures)
        future.then(
          (value) => (value: value, reason: null),
          onError: (Object reason) => (value: null, reason: reason),
        ),
    ]);
