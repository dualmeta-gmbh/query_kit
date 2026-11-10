/// Open-1: required selection, nullable data, subtypes and collection
/// literals. The cache type never moves; only what an observer reports does.
library;

import '../support/models.dart';
import '../support/static_type.dart';
import '../surface.dart';

void selection(QueryClient client) {
  final device = queries.devices.detail('d1');

  // Selection goes through the existing required `withSelect` (D6): the
  // selector's parameter is the cache type, its return the observed type.
  final name = device.options().withSelect((data) {
    data.expectStaticType<Exactly<Device>>();
    return data.name;
  });
  final QuerySelectOptions<Device, String> typedName = name;
  name.expectStaticType<Exactly<QuerySelectOptions<Device, String>>>();
  QueryObserver(client, name)
      .expectStaticType<Exactly<QueryObserver<Device, String>>>();

  // The key and the cached value stay the definition's.
  device.key.expectStaticType<Exactly<TypedQueryKey<Device>>>();
  name.queryKey.expectStaticType<Exactly<QueryKey>>();

  final count = queries.devices.list.options().withSelect((all) => all.length);
  count.expectStaticType<Exactly<QuerySelectOptions<List<Device>, int>>>();

  _use([typedName]);
}

void nullableData(QueryClient client) {
  final lookup = queries.devices.lookup('d1');
  lookup.expectStaticType<Exactly<QueryRef<Device?>>>();

  // `read` cannot tell a cached null from no data; `state` can (D5).
  final cached = lookup.read(client);
  final Device? typedCached = cached;
  cached.expectStaticType<Exactly<Device?>>();
  final state = lookup.state(client);
  state.expectStaticType<Exactly<QueryState<Device?>?>>();

  // A null is a value of the declared nullable type, and so is a device.
  lookup.write(client, null).expectStaticType<Exactly<Device?>>();
  lookup.write(client, const Device('d1')).expectStaticType<Exactly<Device?>>();
  lookup.update(client, (previous) {
    previous.expectStaticType<Exactly<Device?>>();
    return previous;
  }).expectStaticType<Exactly<Device?>>();

  lookup.options().expectStaticType<Exactly<QueryObserverOptions<Device?>>>();
  lookup.key.expectStaticType<Exactly<TypedQueryKey<Device?>>>();

  _use([typedCached]);
}

void subtypes(QueryClient client) {
  // A sealed base as the cache type: a variant is written under the base.
  final reading = queries.devices.reading('d1');
  reading.expectStaticType<Exactly<QueryRef<Reading>>>();
  reading
      .write(client, const Temperature(21))
      .expectStaticType<Exactly<Reading>>();
  reading.update(client, (previous) {
    previous.expectStaticType<Exactly<Reading?>>();
    return const Humidity(40);
  }).expectStaticType<Exactly<Reading?>>();

  // A switch over what was read is exhaustive over the sealed base.
  final label = switch (reading.read(client)) {
    null => 'none',
    Temperature(:final celsius) => '$celsius °C',
    Humidity(:final percent) => '$percent %',
  };
  label.expectStaticType<Exactly<String>>();

  // Collection literals take their element type from the receiver, so an
  // empty or a narrow literal is written under the declared type.
  final list = queries.devices.list;
  list.expectStaticType<Exactly<QueryDefinition<List<Device>>>>();
  final QueryRef<List<Device>> asReference = list;
  list.write(client, []).expectStaticType<Exactly<List<Device>>>();
  list.write(client, [const Thermostat('t1')]);
  list.update(client, (previous) {
    previous.expectStaticType<Exactly<List<Device>?>>();
    return [...?previous, const Device('d3')];
  }).expectStaticType<Exactly<List<Device>?>>();
  list.read(client).expectStaticType<Exactly<List<Device>?>>();
  list
      .options()
      .expectStaticType<Exactly<QueryObserverOptions<List<Device>>>>();

  // An updater may be declared with a wider parameter: function parameters
  // are contravariant, and a general updater serves every narrower entry.
  Device? switchOn(Object? previous) =>
      previous is Device ? previous.copyWith(isOn: true) : null;
  queries.devices.detail('d1').update(client, switchOn);

  _use([asReference]);
}

void _use(List<Object?> values) {}
