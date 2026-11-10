/// D9's boundary: a list of references of two data types handed to
/// `QueriesObserver` **compiles**, as a list of raw options does. The list's
/// element type is the common supertype, so the observer is one of
/// `Object`, and it builds `Object` entries that every exact typed read then
/// refuses. What the cache holds afterwards is `runtime/observations.dart`.
///
/// Outside the guarantee, documented. A list of one data type is exact, and
/// that is the control.
///
/// The second half is the same question about the references themselves. A
/// collection literal of references of two data types has the type the
/// language gives it, and which one depends on what the elements share:
///
/// * two references of **different classes** (a family's reference and a
///   definition) share only the target: `List<QueryTarget>`, which has the
///   lifecycle operations and no write;
/// * two references of **one class** (two families' references, two
///   definitions, two infinite references) share that class, at the common
///   supertype of their data: `List<QueryRef<Object>>`. Its elements offer
///   `write`, the compiler checks the value against `Object`, and the
///   reference refuses a wrong one when the program runs.
///
/// So a list of references that is meant for the lifecycle operations says
/// so: `<QueryTarget>[a, b]` (`positive/target_list.dart`).
library;

import '../support/models.dart';
import '../support/static_type.dart';
import '../surface.dart';

void mixedList(QueryClient client) {
  final device = queries.devices.detail('d1');
  final list = queries.devices.list;

  // Two data types: `Device` and `List<Device>` meet at `Object`.
  final mixed = [device.options(), list.options()];
  mixed.expectStaticType<Exactly<List<QueryObserverOptions<Object>>>>();

  QueriesObserver(client, mixed)
      .expectStaticType<Exactly<QueriesObserver<Object, Object>>>();

  // Inline, the same.
  QueriesObserver(client, [device.options(), list.options()])
      .expectStaticType<Exactly<QueriesObserver<Object, Object>>>();

  // One data type: exact.
  QueriesObserver(client, [
    queries.devices.detail('d1').options(),
    queries.devices.detail('d2').options(),
  ]).expectStaticType<Exactly<QueriesObserver<Device, Device>>>();

  // References of two data types and two classes: what a family's
  // reference and a definition share is the target, which has the lifecycle
  // operations and no data type. (The write on its elements is refused in
  // `negative/surface_limits.dart`.)
  final targets = [device, list];
  targets.expectStaticType<Exactly<List<QueryTarget>>>();
  for (final target in targets) {
    target.invalidate(client).ignore();
  }
}

/// References of two data types and **one** class: the literal is a list of
/// references, and a write through an element compiles.
void mixedReferences(QueryClient client) {
  final device = queries.devices.detail('d1'); // QueryRef<Device>
  final reading = queries.devices.reading('d1'); // QueryRef<Reading>

  final references = [device, reading];
  references.expectStaticType<Exactly<List<QueryRef<Object>>>>();
  // Compiles: a `Temperature` is an `Object`. The first element is the
  // device's reference, which refuses it at run time
  // (`runtime/observations.dart`, D9-4).
  references.first.write(client, const Temperature(21));
  references.first.update(client, (previous) => const Temperature(21));
  references.first.read(client).expectStaticType<Exactly<Object?>>();

  // Every collection literal and every expression of two branches infers
  // the same way.
  ({device, reading}).expectStaticType<Exactly<Set<QueryRef<Object>>>>();
  ({'a': device, 'b': reading})
      .expectStaticType<Exactly<Map<String, QueryRef<Object>>>>();
  (client.isFetching() > 0 ? device : reading)
      .expectStaticType<Exactly<QueryRef<Object>>>();

  // A nullable and a non-nullable data type meet at the nullable one, so
  // `null` compiles as a value for the non-nullable reference.
  final lookups = [device, queries.devices.lookup('d1')];
  lookups.expectStaticType<Exactly<List<QueryRef<Device?>>>>();
  lookups.first.write(client, null);

  // Two definitions.
  final count = QueryDefinition<int>(
    namespace: DeviceQueries.namespace,
    name: 'count',
  );
  final definitions = [queries.devices.list, count];
  definitions.expectStaticType<Exactly<List<QueryDefinition<Object>>>>();
  definitions.first.write(client, 3);

  // Two infinite references: both page types widen.
  final log = InfiniteQueryFamily<String, List<Device>, String>(
    namespace: DeviceQueries.namespace,
    name: 'log',
    pageFn: (id, context) => const [],
    initialPageParam: (id) => '',
    getNextPageParam: (id, page, pages, pageParam, pageParams) => null,
  );
  final paged = [queries.devices.history('d1'), log('d1')];
  paged.expectStaticType<
      Exactly<List<InfiniteQueryRef<List<Object>, Object>>>>();
  paged.first.write(
    client,
    InfiniteData<List<Object>, Object>(pages: const [], pageParams: const []),
  );

  // Two families, and two typed keys.
  final families = [queries.devices.detail, queries.devices.reading];
  families.expectStaticType<Exactly<List<QueryFamily<String, Object>>>>();
  families.first.updateAll(client, (previous) => const Temperature(21));
  final keys = [device.key, reading.key];
  keys.expectStaticType<Exactly<List<TypedQueryKey<Object>>>>();
  keys.first.write(client, const Temperature(21));

  // The control: one data type stays exact, and so does the write.
  final same = [device, queries.devices.detail('d2')];
  same.expectStaticType<Exactly<List<QueryRef<Device>>>>();
  same.first.write(client, const Device('d1'));

  // And the spelling for a list meant for the lifecycle operations: the
  // element type is said, and the write is gone
  // (`negative/surface_limits.dart`).
  final lifecycle = <QueryTarget>[device, reading];
  for (final target in lifecycle) {
    target.invalidate(client).ignore();
  }
}
