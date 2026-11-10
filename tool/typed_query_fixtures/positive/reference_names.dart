/// The naming call of D1: `QueryRef` beside the existing `QueryObserverRef`.
/// Both come from one import, neither shadows the other, and each reads as
/// what it is where it is used: a reference to a cache entry, and the
/// cache's name for an observer in its events.
library;

import '../support/models.dart';
import '../support/static_type.dart';
import '../surface.dart';

void referenceNames(QueryClient client) {
  // A reference to an entry, from a definition.
  final QueryRef<Device> device = queries.devices.detail('d1');

  // A reference to an observer, from a cache event.
  final observers = <QueryObserverRef>[];
  final unsubscribe = client.queryCache.subscribe((event) {
    if (event is QueryObserverAdded) {
      event.observer.expectStaticType<Exactly<QueryObserverRef>>();
      observers.add(event.observer);
    }
  });

  // The observer made from the entry's options is one of them.
  final observer = QueryObserver(client, device.options());
  observer.expectStaticType<Exactly<QueryObserver<Device, Device>>>();
  final QueryObserverRef asRef = observer;

  observers.add(asRef);
  unsubscribe();
}

/// The two sealed types are closed: a switch over the kinds of a reference,
/// and over everything a lifecycle operation can be aimed at, is exhaustive
/// without a default.
String kindOf(QueryEntryRef<Object?> reference) => switch (reference) {
      QueryRef() => 'plain',
      InfiniteQueryRef() => 'infinite',
    };

String targetOf(QueryTarget target) => switch (target) {
      QueryNamespace() => 'everything under a prefix',
      QueryFamily() || InfiniteQueryFamily() => 'every input of an operation',
      QueryEntryRef() => 'one entry',
    };
