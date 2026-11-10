/// A list of references of several data types, declared as what it is for:
/// a list of targets.
///
/// Left to inference, such a literal takes whatever its elements share,
/// and two references of one class share a class that still has `write`
/// (`boundary/mixed_list.dart`). With the element type said, the list
/// holds any reference, family or namespace, offers every lifecycle
/// operation and none that needs a data type (the refusals are in
/// `negative/surface_limits.dart`).
library;

import '../support/models.dart';
import '../support/static_type.dart';
import '../surface.dart';

Future<void> targetList(QueryClient client) async {
  final targets = <QueryTarget>[
    queries.devices.detail('d1'), // QueryRef<Device>
    queries.devices.reading('d1'), // QueryRef<Reading>
    queries.devices.lookup('d1'), // QueryRef<Device?>
    queries.devices.list, // QueryDefinition<List<Device>>
    queries.devices.feed, // an infinite definition
    queries.devices.history('d1'), // an infinite reference
    queries.devices.detail, // every detail
    DeviceQueries.namespace, // everything under 'devices'
  ];
  targets.expectStaticType<Exactly<List<QueryTarget>>>();

  for (final target in targets) {
    target.filters(stale: true).expectStaticType<Exactly<QueryFilters>>();
    await target.cancel(client);
    await target.invalidate(client, refetchType: RefetchType.none);
    await target.refetch(client, cancelRefetch: false);
    await target.reset(client);
    target.remove(client);
  }

  // The data type is still there for whoever asks for it by pattern: the
  // type is sealed, so the switch is exhaustive.
  for (final target in targets) {
    final what = switch (target) {
      QueryEntryRef<Object?>() => 'one entry',
      QueryFamily<Object?, Object?>() => 'every input of a query',
      InfiniteQueryFamily<Object?, Object?, Object?>() =>
        'every input of an infinite query',
      QueryNamespace() => 'a prefix',
    };
    what.expectStaticType<Exactly<String>>();
  }

  // A function that takes targets takes the same literal, and a list of
  // one data type as well.
  Future<void> refresh(Iterable<QueryTarget> targets) =>
      Future.wait([for (final target in targets) target.invalidate(client)]);
  await refresh([queries.devices.detail('d1'), queries.devices.reading('d1')]);
  await refresh([queries.devices.detail('d1'), queries.devices.detail('d2')]);
}
