/// A fetch or a mutation shared by callers in different error zones.
///
/// Dart hands a future's error only to listeners in the error zone the future
/// was created in; a listener in another one never hears it, and the error is
/// reported as uncaught in the future's own zone instead. A Flutter app meets
/// this whenever two error zones touch one client: a `runZonedGuarded` around
/// `runApp` beside platform callbacks registered outside it, a widget test's
/// zone beside the binding's — the native suite found it, a focus refetch
/// started by a lifecycle event and cleared by the test's teardown. Not an
/// upstream case: JavaScript has no zones. Every test here starts the shared
/// work in zone A and meets it from zone B, and both zones must stay quiet.
library;

import 'dart:async';

import 'package:query_kit/query_kit.dart';
// The bridge itself, which the package does not export.
import 'package:query_kit/src/zones.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// A fresh error zone, collecting what is reported in it as uncaught.
Zone errorZone(List<Object> uncaught) {
  late Zone zone;
  runZonedGuarded(() => zone = Zone.current, (error, _) => uncaught.add(error));
  return zone;
}

/// Runs [body] in [zone] and completes with its outcome, handed back to the
/// test's own zone by a listener in [zone] — the one its error reaches.
Future<T> inZone<T>(Zone zone, Future<T> Function() body) {
  final result = Completer<T>();
  zone.run(() async {
    try {
      result.complete(await body());
    } catch (error, stackTrace) {
      result.completeError(error, stackTrace);
    }
  });
  return result.future;
}

/// Lets every microtask and zero-length timer run.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

/// What a hang looks like here: the shared work never answering the second
/// zone. Long enough for anything that does answer, short enough to fail.
const Duration hang = Duration(seconds: 2);

void main() {
  late QueryClient client;
  late QueryKey key;
  late List<Object> uncaughtA;
  late List<Object> uncaughtB;
  late Zone zoneA;
  late Zone zoneB;

  setUp(() {
    client = testClient();
    key = queryKey();
    uncaughtA = <Object>[];
    uncaughtB = <Object>[];
    zoneA = errorZone(uncaughtA);
    zoneB = errorZone(uncaughtB);
  });

  /// A completer of [zone]'s: a query function hands back a future its own
  /// zone can hear fail, as a request made there does.
  Completer<T> completerIn<T>(Zone zone) => zone.run(Completer<T>.new);

  tearDown(() async {
    client.clear();
    await settle();
    expect(uncaughtA, isEmpty, reason: 'zone A, which started the work');
    expect(uncaughtB, isEmpty, reason: 'zone B, which met it');
  });

  /// A fetch started in zone A that answers only through [answer].
  Future<String> startInA(Completer<String> answer) => inZone(zoneA, () async {
        final fetch = client.query<String>(QueryOptions<String>(
          queryKey: key,
          queryFn: (_) => answer.future,
        ));
        // Caught here, in its own zone: what zone A's caller would do.
        return fetch.catchError((Object _) => 'failed');
      });

  for (final how in ['cancelQueries', 'clear', 'removeQueries']) {
    test('$how from another error zone cancels a fetch quietly', () async {
      final answer = completerIn<String>(zoneA);
      final inA = startInA(answer);
      await settle();

      await inZone(zoneB, () async {
        switch (how) {
          case 'cancelQueries':
            // It used to wait for the cancelled fetch's error, which never
            // crossed into this zone: it hung for good.
            await client
                .cancelQueries(filters: QueryFilters(queryKey: key))
                .timeout(hang);
          case 'clear':
            client.clear();
          default:
            client.removeQueries(filters: QueryFilters(queryKey: key));
        }
        await settle();
      });
      expect(await inA.timeout(hang), 'failed');
    });
  }

  test('resetQueries from another error zone cancels and refetches quietly',
      () async {
    final answer = completerIn<String>(zoneA);
    final inA = startInA(answer);
    await settle();

    await inZone(zoneB, () async {
      await client
          .resetQueries(filters: QueryFilters(queryKey: key))
          .timeout(hang);
    });
    expect(await inA.timeout(hang), 'failed');
  });

  test('a fetch joined from another error zone fails there with its error',
      () async {
    final answer = completerIn<String>(zoneA);
    final inA = startInA(answer);
    await settle();

    final joined = inZone(zoneB, () async {
      // Same key, no data: joins the fetch zone A started.
      return client.query<String>(QueryOptions<String>(
        queryKey: key,
        queryFn: (_) => throw StateError('never called'),
      ));
    });
    await settle();
    answer.completeError(StateError('refused'));

    await expectLater(
      joined.timeout(hang),
      throwsA(isA<StateError>()
          .having((error) => error.message, 'message', 'refused')),
    );
    expect(await inA.timeout(hang), 'failed');
  });

  test('a fetch joined from another error zone completes there with its data',
      () async {
    final answer = completerIn<String>(zoneA);
    final inA = startInA(answer);
    await settle();

    final joined = inZone(zoneB, () async {
      return client.query<String>(QueryOptions<String>(
        queryKey: key,
        queryFn: (_) => throw StateError('never called'),
      ));
    });
    await settle();
    answer.complete('data');

    expect(await joined.timeout(hang), 'data');
    expect(await inA.timeout(hang), 'data');
  });

  for (final cancel in [false, true]) {
    test(
        "a query's future read in another error zone "
        '${cancel ? 'is cancelled' : 'fails'} there', () async {
      final answer = completerIn<String>(zoneA);
      final inA = startInA(answer);
      await settle();
      final query =
          client.queryCache.find(filters: QueryFilters(queryKey: key))!;

      // Read in zone B, not handed over from A: Query.future is public.
      final read = inZone(zoneB, () => query.future!);
      await settle();
      if (cancel) {
        await inZone(zoneB, () => client.cancelQueries().timeout(hang));
      } else {
        answer.completeError(StateError('refused'));
      }

      await expectLater(
        read.timeout(hang),
        throwsA(cancel ? isA<CancelledError>() : isA<StateError>()),
      );
      expect(await inA.timeout(hang), 'failed');
    });
  }

  test(
      'a refetch from another error zone that cancels a running one hands its '
      'failure to the first caller', () async {
    client.setQueryData<String>(key, 'cached');
    final first = completerIn<String>(zoneA);
    final inA = inZone(zoneA, () async {
      final fetch = client.query<String>(QueryOptions<String>(
        queryKey: key,
        staleTime: StaleTime.zero,
        queryFn: (_) => first.future,
      ));
      return fetch.catchError((Object error) => 'failed: $error');
    });
    await settle();

    final second = completerIn<String>(zoneB);
    final inB = inZone(zoneB, () async {
      // An explicit refetch cancels over data: the first fetch is cancelled
      // silently and its caller rides along with this one.
      final observer =
          client.observe<String, String>(QueryObserverOptions<String>(
        queryKey: key,
        retry: RetryPolicy.never,
        queryFn: (_) => second.future,
      ));
      final result = await observer.refetch();
      return 'failed: ${result.errorOrNull}';
    });
    await settle();
    second.completeError(StateError('refused'));
    first.complete('too late');

    expect(await inB.timeout(hang), 'failed: Bad state: refused');
    expect(await inA.timeout(hang), 'failed: Bad state: refused');
  });

  test('a mutation run joined from another error zone fails there', () async {
    final run = completerIn<String>(zoneA);
    final mutation = client.mutationCache.build<String, String, void>(
      client,
      client.defaultMutationOptions(
          MutationOptions<String, String, void>(mutationFn: (_) => run.future)),
    );
    final first = inZone(
        zoneA,
        () => mutation
            .execute('a')
            .catchError((Object error) => 'failed: $error'));
    await settle();

    // A second execute of the same mutation joins the run zone A began.
    final joined = inZone(zoneB, () => mutation.execute('a'));
    await settle();
    run.completeError(StateError('refused'));

    await expectLater(
      joined.timeout(hang),
      throwsA(isA<StateError>()
          .having((error) => error.message, 'message', 'refused')),
    );
    expect(await first.timeout(hang), 'failed: Bad state: refused');
  });

  test(
      'resuming a paused mutation from another error zone settles when it '
      'fails', () async {
    client.onlineManager.setOnline(false);
    final run = completerIn<String>(zoneA);
    final mutated = inZone(zoneA, () async {
      final observer = MutationObserver<String, String, void>(
        client,
        MutationOptions<String, String, void>(mutationFn: (_) => run.future),
      );
      return observer.mutateAsync('a').catchError((Object _) => 'failed');
    });
    await settle();
    expect(client.mutationCache.mutations.single.state.isPaused, isTrue);

    final resumed = inZone(zoneB, () async {
      client.onlineManager.setOnline(true);
      // It used to wait on the run's error, which never crossed into this
      // zone: the resume, and every refetch queued behind it, hung for good.
      await client.resumePausedMutations().timeout(hang);
    });
    await settle();
    run.completeError(StateError('refused'));

    await resumed;
    expect(await mutated.timeout(hang), 'failed');
  });

  test(
      'an error crossing zones meets the error callback of the zone it was '
      'made in once, as a listener there does', () async {
    var interceptions = 0;
    final wrapping = zoneA.fork(
      specification: ZoneSpecification(
        errorCallback: (self, parent, zone, error, stackTrace) {
          interceptions++;
          return AsyncError(StateError('wrapped $error'), stackTrace);
        },
      ),
    );
    final source = completerIn<String>(wrapping);
    // Heard where each zone listens, as values: `inZone` would complete its
    // own completer in the wrapping zone and be wrapped there once more.
    Future<Object?> heard(Future<String> future) =>
        future.then<Object?>((_) => null, onError: (Object error) => error);
    final there = wrapping.run(() => heard(source.future));
    final crossed =
        zoneB.run(() => heard(inCurrentZone(source.future, wrapping)));
    wrapping.run(() => source.completeError('refused'));

    final inOrigin = await there;
    final inB = await crossed;
    // Completed in the zone it was made in, the crossing went through that
    // zone's callback a second time: wrapped twice.
    expect(interceptions, 1);
    expect(inB, same(inOrigin));
  });
}
