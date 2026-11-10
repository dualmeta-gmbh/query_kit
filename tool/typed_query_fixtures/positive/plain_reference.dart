/// Open-1, plain queries: every type at an ordinary call site is inferred
/// exactly, with no annotation and no type argument on the call.
///
/// Each line proves it twice: by assigning to a variable of the precise
/// type, which a wider inferred type would fail, and by
/// `expectStaticType`, which a wider *or* a narrower one fails.
library;

import '../support/models.dart';
import '../support/static_type.dart';
import '../surface.dart';

Future<void> plainReference(QueryClient client, Device updated) async {
  // The declaration and the entry point.
  final family = queries.devices.detail;
  family.expectStaticType<Exactly<QueryFamily<String, Device>>>();

  // Binding an input.
  final device = queries.devices.detail('d1');
  final QueryRef<Device> typedDevice = device;
  device.expectStaticType<Exactly<QueryRef<Device>>>();

  // Options, as every consumer takes them.
  final options = device.options();
  final QueryObserverOptions<Device> typedOptions = options;
  options.expectStaticType<Exactly<QueryObserverOptions<Device>>>();

  // Reading through the reference and through its key.
  final cached = device.read(client);
  final Device? typedCached = cached;
  cached.expectStaticType<Exactly<Device?>>();

  final key = device.key;
  final TypedQueryKey<Device> typedKey = key;
  key.expectStaticType<Exactly<TypedQueryKey<Device>>>();

  final byKey = key.read(client);
  final Device? typedByKey = byKey;
  byKey.expectStaticType<Exactly<Device?>>();

  final state = device.state(client);
  final QueryState<Device>? typedState = state;
  state.expectStaticType<Exactly<QueryState<Device>?>>();
  key.state(client).expectStaticType<Exactly<QueryState<Device>?>>();

  key.rawKey.expectStaticType<Exactly<QueryKey>>();

  // Fetching.
  final pending = device.fetch(client);
  pending.expectStaticType<Exactly<Future<Device>>>().ignore();
  final fetched = await pending;
  final Device typedFetched = fetched;
  fetched.expectStaticType<Exactly<Device>>();

  // Writing: the value's type comes from the receiver.
  final written = device.write(client, updated);
  final Device typedWritten = written;
  written.expectStaticType<Exactly<Device>>();

  // Updating: the updater's parameter and return are inferred.
  final next = device.update(client, (previous) {
    previous.expectStaticType<Exactly<Device?>>();
    return previous?.copyWith(isOn: true);
  });
  final Device? typedNext = next;
  next.expectStaticType<Exactly<Device?>>();

  // A subtype is a valid value, and the reference keeps its type.
  device
      .write(client, const Thermostat('d1', target: 21))
      .expectStaticType<Exactly<Device>>();

  // The typed key writes under the same types: it knows the data type,
  // and nothing else of the definition.
  final writtenByKey = key.write(client, updated);
  final Device typedWrittenByKey = writtenByKey;
  writtenByKey.expectStaticType<Exactly<Device>>();
  final nextByKey = key.update(client, (previous) {
    previous.expectStaticType<Exactly<Device?>>();
    return previous?.copyWith(isOn: true);
  });
  final Device? typedNextByKey = nextByKey;
  nextByKey.expectStaticType<Exactly<Device?>>();
  key
      .write(client, const Thermostat('d1', target: 21), updatedAt: DateTime(1))
      .expectStaticType<Exactly<Device>>();
  queries.devices
      .lookup('d1')
      .key
      .write(client, null)
      .expectStaticType<Exactly<Device?>>();

  // The existing consumers infer from the options alone.
  QueryObserver(client, device.options())
      .expectStaticType<Exactly<QueryObserver<Device, Device>>>();
  client
      .observe(device.options())
      .expectStaticType<Exactly<QueryObserver<Device, Device>>>();
  client
      .query(device.options())
      .expectStaticType<Exactly<Future<Device>>>()
      .ignore();

  // A per-use override keeps the type.
  device
      .options()
      .copyWith(staleTime: const StaleTime.duration(Duration(minutes: 1)))
      .expectStaticType<Exactly<QueryObserverOptions<Device>>>();

  // Lifecycle: exact for a reference, prefix for a family and a namespace.
  await device.invalidate(client);
  await queries.devices.detail.invalidate(client);
  await queries.devices.invalidate(client);
  await device.refetch(client);
  await device.cancel(client);
  await device.reset(client);
  device.remove(client);
  device.filters().expectStaticType<Exactly<QueryFilters>>();
  queries.devices.detail
      .filters(type: QueryTypeFilter.active)
      .expectStaticType<Exactly<QueryFilters>>();
  DeviceQueries.namespace
      .filters(stale: true)
      .expectStaticType<Exactly<QueryFilters>>();
  DeviceQueries.namespace.rawKey.expectStaticType<Exactly<QueryKey>>();
  queries.devices.detail.rawKey.expectStaticType<Exactly<QueryKey>>();

  _use([
    typedDevice,
    typedOptions,
    typedCached,
    typedKey,
    typedByKey,
    typedState,
    typedFetched,
    typedWritten,
    typedNext,
    typedWrittenByKey,
    typedNextByKey,
  ]);
}

void _use(List<Object?> values) {}
