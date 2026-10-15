/// Shared futures across error zones.
///
/// Dart hands a future's error only to listeners in the error zone the future
/// was created in. A listener in another one never hears it — the error is
/// reported as uncaught in the future's own zone instead, and the listener's
/// future never completes. A query's fetch and a mutation's run are shared by
/// whoever calls in, and a Flutter app has more than one error zone as soon
/// as a `runZonedGuarded` wraps `runApp` beside platform callbacks registered
/// outside it, or a widget test's zone meets the binding's: a focus refetch
/// started by a lifecycle event, then cancelled by code in another zone,
/// reported its `CancelledError` as uncaught, and an `await cancelQueries`
/// waiting on it hung for good. TanStack Query has nothing to match: a
/// JavaScript promise has no zone.
library;

import 'dart:async';

/// [future], created in [origin], as a future the current zone can listen to.
///
/// The same future when both share an error zone. Otherwise a new one of the
/// current zone, completed by a listener registered in [origin], which is the
/// one zone the error is delivered to. The error is passed on in the current
/// zone: completed in [origin], it went through [origin]'s `errorCallback` a
/// second time, so a zone that wraps its errors wrapped this one twice.
Future<T> inCurrentZone<T>(Future<T> future, Zone origin) {
  final current = Zone.current;
  if (origin.inSameErrorZone(current)) return future;
  final bridged = Completer<T>();
  origin
      .run(() => future.then<void>(bridged.complete,
          onError: (Object error, StackTrace stackTrace) =>
              current.run(() => bridged.completeError(error, stackTrace))))
      .ignore();
  return bridged.future;
}
