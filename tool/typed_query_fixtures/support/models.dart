/// The application the fixtures pretend to be: models with value equality, a
/// repository, and the declarations of the plan's developer-experience
/// section, written as an application would write them.
library;

import '../surface.dart';

/// A model with value equality.
class Device {
  const Device(this.id, {this.name = '', this.isOn = false});

  final String id;
  final String name;
  final bool isOn;

  Device copyWith({String? name, bool? isOn}) =>
      Device(id, name: name ?? this.name, isOn: isOn ?? this.isOn);

  @override
  bool operator ==(Object other) =>
      other is Device &&
      other.runtimeType == runtimeType &&
      other.id == id &&
      other.name == name &&
      other.isOn == isOn;

  @override
  int get hashCode => Object.hash(runtimeType, id, name, isOn);
}

/// A subtype of [Device].
class Thermostat extends Device {
  const Thermostat(super.id, {super.name, super.isOn, this.target = 20});

  final double target;
}

/// A sealed base with two variants.
sealed class Reading {
  const Reading();
}

final class Temperature extends Reading {
  const Temperature(this.celsius);

  final double celsius;
}

final class Humidity extends Reading {
  const Humidity(this.percent);

  final int percent;
}

/// What a page of an infinite query holds.
class DeviceEvent {
  const DeviceEvent(this.at);

  final int at;
}

enum Room { kitchen, hall }

/// A filter object used as an input: a value class.
class DeviceFilter {
  const DeviceFilter({this.room, this.onlyOn = false});

  final Room? room;
  final bool onlyOn;

  @override
  bool operator ==(Object other) =>
      other is DeviceFilter && other.room == room && other.onlyOn == onlyOn;

  @override
  int get hashCode => Object.hash(room, onlyOn);
}

/// The backend, typed.
class DeviceRepository {
  const DeviceRepository();

  Future<Device> device(String id, {QueryCancelToken? signal}) async =>
      Device(id);

  Future<Device?> find(String id) async => id.isEmpty ? null : Device(id);

  Future<List<Device>> devices({DeviceFilter? filter}) async =>
      const [Device('d1'), Device('d2')];

  Future<Reading> reading(String id) async => const Temperature(21);

  Future<List<DeviceEvent>> events(String id, {required int cursor}) async =>
      [DeviceEvent(cursor)];

  Future<List<Device>> page(int cursor) async => [Device('d$cursor')];
}

/// The plan's declaration: one class per namespace, one member per
/// operation, the strings in the definition and nowhere else.
final class DeviceQueries {
  DeviceQueries(this._repository);

  final DeviceRepository _repository;

  static final namespace = QueryNamespace(['devices']);

  // `late final`, not an initializer list: a fetch function reads `this`.
  late final detail = QueryFamily<String, Device>(
    namespace: namespace,
    name: 'detail',
    queryFn: (id, context) => _repository.device(id, signal: context.signal),
  );

  late final list = QueryDefinition<List<Device>>(
    namespace: namespace,
    name: 'list',
    queryFn: (context) => _repository.devices(),
  );

  /// Nullable data: a device that may not exist.
  late final lookup = QueryFamily<String, Device?>(
    namespace: namespace,
    name: 'lookup',
    queryFn: (id, context) => _repository.find(id),
  );

  /// A sealed base as the cache type.
  late final reading = QueryFamily<String, Reading>(
    namespace: namespace,
    name: 'reading',
    queryFn: (id, context) => _repository.reading(id),
  );

  /// A value object as the input.
  late final filtered = QueryFamily<DeviceFilter, List<Device>>(
    namespace: namespace,
    name: 'filtered',
    queryFn: (filter, context) => _repository.devices(filter: filter),
  );

  /// A record as the input, spread into two key parts by `keyOf`.
  late final inRoom = QueryFamily<({Room room, bool onlyOn}), List<Device>>(
    namespace: namespace,
    name: 'inRoom',
    keyOf: (input) => [input.room, input.onlyOn],
    queryFn: (input, context) => _repository.devices(
      filter: DeviceFilter(room: input.room, onlyOn: input.onlyOn),
    ),
  );

  /// A zero-input infinite query.
  late final feed = InfiniteQueryDefinition<List<Device>, int>(
    namespace: namespace,
    name: 'feed',
    pageFn: (context) => _repository.page(context.pageParam),
    initialPageParam: 0,
    getNextPageParam: (page, pages, pageParam, pageParams) =>
        page.isEmpty ? null : pageParam + 1,
  );

  /// An infinite query per device.
  late final history = InfiniteQueryFamily<String, List<DeviceEvent>, int>(
    namespace: namespace,
    name: 'history',
    pageFn: (id, context) => _repository.events(id, cursor: context.pageParam),
    initialPageParam: (id) => 0,
    getNextPageParam: (id, page, pages, pageParam, pageParams) =>
        page.isEmpty ? null : pageParam + page.length,
  );

  Future<void> invalidate(QueryClient client) => namespace.invalidate(client);
}

/// The plan's entry point: a record gives each namespace a checked member.
final queries = (devices: DeviceQueries(const DeviceRepository()));
