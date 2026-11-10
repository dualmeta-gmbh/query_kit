/// Open-1, typed inputs: what a family is called with is checked against
/// `TInput`, whatever the input is, and the result is always a reference of
/// the family's data type. Inline and extracted declarations infer alike.
library;

import '../support/models.dart';
import '../support/static_type.dart';
import '../surface.dart';

final _devices = QueryNamespace(['devices']);
const _repository = DeviceRepository();

// Extracted callbacks: a tear-off anchors nothing more than a closure does,
// the type arguments are still what names the types.
Future<Device> _fetchDevice(String id, QueryFunctionContext context) =>
    _repository.device(id, signal: context.signal);

List<Object?> _keyOfFilter(DeviceFilter filter) => [filter.room, filter.onlyOn];

QueryObserverOptions<Device> _configureDetail(
  QueryObserverOptions<Device> base,
  String id,
) =>
    base.copyWith(staleTime: const StaleTime.duration(Duration(seconds: 30)));

// A top-level declaration, a primitive input, the default key part.
final byId = QueryFamily<String, Device>(
  namespace: _devices,
  name: 'detail',
  queryFn: _fetchDevice,
  configure: _configureDetail,
);

// An enum.
final byRoom = QueryFamily<Room, List<Device>>(
  namespace: _devices,
  name: 'room',
  queryFn: (room, context) =>
      _repository.devices(filter: DeviceFilter(room: room)),
);

// An int.
final byIndex = QueryFamily<int, Device>(
  namespace: _devices,
  name: 'index',
  queryFn: (index, context) => _repository.device('d$index'),
);

// A value object, spread into parts by an extracted `keyOf`.
final byFilter = QueryFamily<DeviceFilter, List<Device>>(
  namespace: _devices,
  name: 'filtered',
  keyOf: _keyOfFilter,
  queryFn: (filter, context) => _repository.devices(filter: filter),
);

// A record: positional and named fields are checked by the family's type.
final byPage = QueryFamily<(String, {int page}), List<DeviceEvent>>(
  namespace: _devices,
  name: 'events',
  keyOf: (input) => [input.$1, input.page],
  queryFn: (input, context) => _repository.events(input.$1, cursor: input.page),
);

// A nullable input and `Object`, the escape D10 names for "anything".
final byOptionalRoom = QueryFamily<Room?, List<Device>>(
  namespace: _devices,
  name: 'optionalRoom',
  queryFn: (room, context) =>
      _repository.devices(filter: DeviceFilter(room: room)),
);
final byAnything = QueryFamily<Object, String>(
  namespace: _devices,
  name: 'label',
  queryFn: (value, context) => '$value',
);

// A collection as the input: the key freezes it.
final byIds = QueryFamily<List<String>, List<Device>>(
  namespace: _devices,
  name: 'byIds',
  queryFn: (ids, context) => [for (final id in ids) Device(id)],
);

// A key-only family (D6): no fetcher, the types named explicitly.
final seeded = QueryFamily<String, Device>(namespace: _devices, name: 'seeded');

// Type arguments from a declared type instead of the constructor call (D10).
final QueryFamily<String, Device> declared = QueryFamily(
  namespace: _devices,
  name: 'declared',
  queryFn: (id, context) => _repository.device(id),
);

// Type arguments from typed closure parameters (D10).
final typedClosure = QueryFamily(
  namespace: _devices,
  name: 'typedClosure',
  queryFn: (String id, QueryFunctionContext context) => _repository.device(id),
);

void typedInputs(QueryClient client) {
  byId('d1').expectStaticType<Exactly<QueryRef<Device>>>();
  byRoom(Room.kitchen).expectStaticType<Exactly<QueryRef<List<Device>>>>();
  byIndex(3).expectStaticType<Exactly<QueryRef<Device>>>();
  byFilter(const DeviceFilter(onlyOn: true))
      .expectStaticType<Exactly<QueryRef<List<Device>>>>();
  byPage(('d1', page: 2))
      .expectStaticType<Exactly<QueryRef<List<DeviceEvent>>>>();
  byOptionalRoom(null).expectStaticType<Exactly<QueryRef<List<Device>>>>();
  byAnything(42).expectStaticType<Exactly<QueryRef<String>>>();
  byIds(['d1', 'd2']).expectStaticType<Exactly<QueryRef<List<Device>>>>();
  seeded('d1').expectStaticType<Exactly<QueryRef<Device>>>();

  declared.expectStaticType<Exactly<QueryFamily<String, Device>>>();
  typedClosure.expectStaticType<Exactly<QueryFamily<String, Device>>>();

  // An inline definition, used where it is declared.
  QueryFamily<int, String>(
    namespace: _devices,
    name: 'inline',
    queryFn: (index, context) => 'device $index',
  )(7)
      .read(client)
      .expectStaticType<Exactly<String?>>();

  // The callbacks of a declaration see the declared types.
  QueryFamily<String, Device>(
    namespace: _devices,
    name: 'callbacks',
    keyOf: (id) {
      id.expectStaticType<Exactly<String>>();
      return [id];
    },
    queryFn: (id, context) {
      id.expectStaticType<Exactly<String>>();
      context.expectStaticType<Exactly<QueryFunctionContext>>();
      return _repository.device(id);
    },
    configure: (base, id) {
      base.expectStaticType<Exactly<QueryObserverOptions<Device>>>();
      id.expectStaticType<Exactly<String>>();
      return base;
    },
  );
  QueryDefinition<List<Device>>(
    namespace: _devices,
    name: 'all',
    queryFn: (context) {
      context.expectStaticType<Exactly<QueryFunctionContext>>();
      return _repository.devices();
    },
    configure: (base) {
      base.expectStaticType<Exactly<QueryObserverOptions<List<Device>>>>();
      return base.copyWith(gcTime: const GcTime.duration(Duration(hours: 1)));
    },
  );

  // A zero-input definition infers its data type from the fetcher alone.
  // Measured here; the documented form writes the type argument
  // (`written_type_arguments.dart`).
  QueryDefinition(
    namespace: _devices,
    name: 'inferred',
    queryFn: (context) => _repository.devices(),
  ).expectStaticType<Exactly<QueryDefinition<List<Device>>>>();

  // Family bulk operations (D7) keep the family's type.
  final all = byId.readAll(client);
  final List<(TypedQueryKey<Device>, Device?)> typedAll = all;
  all.expectStaticType<Exactly<List<(TypedQueryKey<Device>, Device?)>>>();
  byId.updateAll(client, (previous) {
    previous.expectStaticType<Exactly<Device?>>();
    return previous?.copyWith(isOn: false);
  }).expectStaticType<Exactly<List<(TypedQueryKey<Device>, Device?)>>>();

  // A snapshot is put back through the keys it came with, no annotation
  // and no raw key anywhere.
  for (final (key, data) in all) {
    key.expectStaticType<Exactly<TypedQueryKey<Device>>>();
    data.expectStaticType<Exactly<Device?>>();
    if (data != null) {
      key.write(client, data).expectStaticType<Exactly<Device>>();
    }
  }
  for (final (key, _) in byId.updateAll(client, (previous) => previous)) {
    key.update(client, (previous) {
      previous.expectStaticType<Exactly<Device?>>();
      return previous;
    }).expectStaticType<Exactly<Device?>>();
  }

  _use([typedAll]);
}

void _use(List<Object?> values) {}
