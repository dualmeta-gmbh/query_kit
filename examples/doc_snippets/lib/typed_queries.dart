/// The samples of the typed query definitions guide, and the typed samples of
/// the pages that introduce the library: the overview, the quick start, query
/// keys, describing a query once, type safety and the reference pages.
///
/// Its own domain, as `c4a_guides.dart` has one: a device in a room, an event
/// log, a room. The repository is in memory, because
/// `test/typed_queries_test.dart` runs the samples that show behaviour
/// against it, and a test needs to make a write fail.
///
/// Every definition writes its type arguments out, as the guide asks.
library;

import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'doc_snippets.dart' show Task, TaskTile, api;

// ---------------------------------------------------------------------------
// The domain
// ---------------------------------------------------------------------------

@immutable
class Device {
  const Device({required this.id, required this.name, required this.room});

  final String id;
  final String name;
  final String room;

  Device copyWith({String? name, String? room}) =>
      Device(id: id, name: name ?? this.name, room: room ?? this.room);

  @override
  bool operator ==(Object other) =>
      other is Device &&
      other.id == id &&
      other.name == name &&
      other.room == room;

  @override
  int get hashCode => Object.hash(id, name, room);

  @override
  String toString() => 'Device($id, $name, $room)';
}

@immutable
class DeviceEvent {
  const DeviceEvent(this.id, this.text);

  final int id;
  final String text;
}

@immutable
class Room {
  const Room({required this.id, required this.name, required this.floor});

  final String id;
  final String name;
  final int floor;
}

/// The backend, in memory. [failNextWrite] makes the next write throw, for
/// the rollback the test drives.
class DeviceRepository {
  DeviceRepository()
      : _devices = <String, Device>{
          'd1': const Device(id: 'd1', name: 'Hall lamp', room: 'hall'),
          'd2': const Device(id: 'd2', name: 'Hall heater', room: 'hall'),
          'd3': const Device(id: 'd3', name: 'Oven', room: 'kitchen'),
        };

  final Map<String, Device> _devices;

  int fetches = 0;

  Object? failNextWrite;

  Future<List<Device>> devices({String? room, QueryCancelToken? signal}) async {
    fetches++;
    return <Device>[
      for (final device in _devices.values)
        if (room == null || device.room == room) device,
    ];
  }

  Future<Device> device(String id, {QueryCancelToken? signal}) async {
    fetches++;
    return _devices[id] ?? (throw StateError('no device $id'));
  }

  Future<List<Device>> search(
    String room,
    List<String> tags, {
    QueryCancelToken? signal,
  }) =>
      devices(room: room, signal: signal);

  Future<List<DeviceEvent>> events({
    required int offset,
    QueryCancelToken? signal,
  }) async =>
      offset >= 6
          ? const <DeviceEvent>[]
          : <DeviceEvent>[
              for (var id = offset; id < offset + 3; id++)
                DeviceEvent(id, 'event $id'),
            ];

  Future<List<DeviceEvent>> history(
    String deviceId, {
    required int offset,
    QueryCancelToken? signal,
  }) =>
      events(offset: offset, signal: signal);

  Future<Room> room(String id, {QueryCancelToken? signal}) async =>
      Room(id: id, name: 'Hall', floor: 0);

  Future<List<Room>> rooms({int? floor, QueryCancelToken? signal}) async =>
      const <Room>[Room(id: 'r1', name: 'Hall', floor: 0)];

  Future<void> renameRoom(String from, String to) async {
    final failure = failNextWrite;
    if (failure != null) {
      failNextWrite = null;
      throw failure;
    }
    _devices.updateAll(
      (id, device) => device.room == from ? device.copyWith(room: to) : device,
    );
  }
}

/// However the app provides it. The samples read it as a top-level.
final DeviceRepository repository = DeviceRepository();

// ---------------------------------------------------------------------------
// guides/typed-queries.md: declaring definitions
// ---------------------------------------------------------------------------

// >>> guides/typed-queries.md#declare
// lib/data/device_queries.dart
final class DeviceQueries {
  DeviceQueries(this._repository);

  final DeviceRepository _repository;

  /// The prefix every key below starts with: ['devices'].
  static final namespace = QueryNamespace(['devices']);

  // `late final`, because the fetch functions use `this`: the repository,
  // and in `list` the sibling `detail`.
  late final list = QueryDefinition<List<Device>>(
    namespace: namespace,
    name: 'list',
    queryFn: (context) async {
      final devices = await _repository.devices(signal: context.signal);
      for (final device in devices) {
        detail(device.id).write(context.client, device);
      }
      return devices;
    },
  );

  late final detail = QueryFamily<String, Device>(
    namespace: namespace,
    name: 'detail',
    queryFn: (id, context) => _repository.device(id, signal: context.signal),
  );

  late final inRoom = QueryFamily<String, List<Device>>(
    namespace: namespace,
    name: 'inRoom',
    queryFn: (room, context) =>
        _repository.devices(room: room, signal: context.signal),
    configure: (base, room) => base.copyWith(
      staleTime: const StaleTime.duration(Duration(minutes: 1)),
    ),
  );
}
// <<<

// >>> guides/typed-queries.md#declare-infinite
// lib/data/event_queries.dart
final class EventQueries {
  EventQueries(this._repository);

  final DeviceRepository _repository;

  static final namespace = QueryNamespace(['events']);

  /// Every event, three to a page.
  late final feed = InfiniteQueryDefinition<List<DeviceEvent>, int>(
    namespace: namespace,
    name: 'feed',
    pageFn: (context) =>
        _repository.events(offset: context.pageParam, signal: context.signal),
    initialPageParam: 0,
    getNextPageParam: (page, pages, pageParam, pageParams) =>
        page.isEmpty ? null : pageParam + page.length,
    configure: (base) => base.copyWith(maxPages: 5),
  );

  /// One device's events. Every paging function takes the input first.
  late final ofDevice = InfiniteQueryFamily<String, List<DeviceEvent>, int>(
    namespace: namespace,
    name: 'ofDevice',
    pageFn: (id, context) => _repository.history(
      id,
      offset: context.pageParam,
      signal: context.signal,
    ),
    initialPageParam: (id) => 0,
    getNextPageParam: (id, page, pages, pageParam, pageParams) =>
        page.isEmpty ? null : pageParam + page.length,
  );
}
// <<<

// >>> guides/typed-queries.md#entry-point
// lib/data/queries.dart: one field per namespace, made once.
final queries = (
  devices: DeviceQueries(repository),
  events: EventQueries(repository),
);
// <<<

// >>> guides/typed-queries.md#key-of
/// A record that holds a list compares the list by identity, so `keyOf`
/// spreads it into the key, where lists compare by value.
final deviceSearch =
    QueryFamily<({String room, List<String> tags}), List<Device>>(
  namespace: DeviceQueries.namespace,
  name: 'search',
  keyOf: (input) => [input.room, input.tags],
  queryFn: (input, context) =>
      repository.search(input.room, input.tags, signal: context.signal),
);
// <<<

// ---------------------------------------------------------------------------
// guides/typed-queries.md: observing, in the four call styles
// ---------------------------------------------------------------------------

class DeviceTitle extends StatelessWidget {
  const DeviceTitle(this.id, {super.key});

  final String id;

  @override
  Widget build(BuildContext context) {
    // >>> guides/typed-queries.md#observe-context
    // context.query, in any widget's build:
    final device = context.query(queries.devices.detail(id).options());
    // <<<
    return Text(device.dataOrNull?.name ?? '…');
  }
}

// >>> guides/typed-queries.md#observe-builder
// QueryBuilder, a widget:
Widget deviceTitle(String id) => QueryBuilder<Device>(
      options: queries.devices.detail(id).options(),
      builder: (context, device) => Text(device.dataOrNull?.name ?? '…'),
    );
// <<<

class DeviceTitleMixin extends StatefulWidget {
  const DeviceTitleMixin(this.id, {super.key});

  final String id;

  @override
  State<DeviceTitleMixin> createState() => _DeviceTitleMixinState();
}

class _DeviceTitleMixinState extends State<DeviceTitleMixin> with QueryMixin {
  @override
  Widget build(BuildContext context) {
    // >>> guides/typed-queries.md#observe-mixin
    // watchQuery, in the build of a State with QueryMixin:
    final device = watchQuery(queries.devices.detail(widget.id).options());
    // <<<
    return Text(device.dataOrNull?.name ?? '…');
  }
}

void deviceController(QueryClient client, String id) {
  // >>> guides/typed-queries.md#observe-controller
  // QueryController, a ValueListenable you own:
  final device =
      QueryController.create(client, queries.devices.detail(id).options());
  // … device.value, device.addListener, device.refetch() …
  device.dispose();
  // <<<
}

class EventLog extends StatelessWidget {
  const EventLog({super.key});

  @override
  Widget build(BuildContext context) {
    // >>> guides/typed-queries.md#observe-infinite
    final feed = context.infiniteQuery(queries.events.feed.options());
    final events =
        feed.value.dataOrNull?.flatten<DeviceEvent>() ?? const <DeviceEvent>[];
    // <<<
    return ListView(
      children: <Widget>[
        for (final event in events) Text(event.text),
        if (feed.hasNextPage)
          TextButton(
            onPressed: () => feed.fetchNextPage().ignore(),
            child: const Text('More'),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// guides/typed-queries.md: reading and writing
// ---------------------------------------------------------------------------

Future<void> readAndWrite(QueryClient client) async {
  // >>> guides/typed-queries.md#read-write
  final device = queries.devices.detail('d1'); // QueryRef<Device>

  // The cached data when it is fresh, otherwise a fetch: client.query.
  final Device fetched = await device.fetch(client);

  final Device? cached = device.read(client); // null when nothing is cached
  final QueryState<Device>? state = device.state(client); // hasData, …

  device.write(client, fetched.copyWith(name: 'Porch lamp'));
  device.update(client, (current) => current?.copyWith(room: 'porch'));
  // <<<
  debugPrint('$cached ${state?.hasData}');
}

Future<void> lifecycle(QueryClient client) async {
  // >>> guides/typed-queries.md#targets
  final devices = queries.devices;

  await devices.detail('d1').invalidate(client); // one entry
  await devices.detail.invalidate(client); // every detail, whatever its id
  await DeviceQueries.namespace.invalidate(client); // all under ['devices']

  await devices.list.refetch(client);
  await devices.detail('d1').cancel(client);
  await devices.inRoom.reset(client);
  devices.inRoom('hall').remove(client);

  // The same selection as QueryFilters, for anything that takes filters.
  final stale = client.queryCache.findAll(
    filters: devices.detail.filters(stale: true),
  );
  // <<<
  debugPrint('${stale.length}');
}

Future<void> targetList(QueryClient client) async {
  // >>> guides/typed-queries.md#target-list
  // References of different data types, as targets: no write, every
  // lifecycle operation.
  final onScreen = <QueryTarget>[
    queries.devices.detail('d1'),
    queries.devices.list,
    queries.events.feed,
  ];
  await Future.wait([for (final target in onScreen) target.invalidate(client)]);
  // <<<
}

void typedKeys(QueryClient client, Device device) {
  // >>> guides/typed-queries.md#typed-key
  final TypedQueryKey<Device> key = queries.devices.detail('d1').key;

  final Device? cached = key.read(client);
  key.write(client, device);

  // A value: equal for equal parts and type, so it can go in a set or a map.
  final seen = <TypedQueryKey<Device>>{key, queries.devices.detail('d1').key};
  assert(seen.length == 1);

  // The plain key, for an API that takes one.
  final QueryKey raw = key.rawKey; // ['devices', 'detail', 'd1']
  // <<<
  debugPrint('$cached $raw');
}

// ---------------------------------------------------------------------------
// guides/typed-queries.md: options per use
// ---------------------------------------------------------------------------

class DeviceScreen extends StatelessWidget {
  const DeviceScreen(this.id, {super.key});

  final String id;

  @override
  Widget build(BuildContext context) {
    // >>> guides/typed-queries.md#per-use
    final options = queries.devices.detail(id).options();

    // One reader polls. The key and the fetch function stay the definition's.
    final device = context.query(
      options.copyWith(
        refetchInterval: const RefetchInterval.every(Duration(seconds: 5)),
      ),
    );

    // Another reads the name only. The entry still holds a Device.
    final name =
        context.selectQuery(options.withSelect((device) => device.name));
    // <<<
    return Text('${name.dataOrNull} ${device.dataOrNull?.room}');
  }
}

// >>> guides/typed-queries.md#seeded
/// One device as a screen observes it: the definition's options, seeded from
/// a cached room list when one already holds the device.
QueryObserverOptions<Device> deviceQuery(QueryClient client, String id) {
  final devices = queries.devices;
  final options = devices.detail(id).options();
  for (final (list, data) in devices.inRoom.readAll(client)) {
    for (final device in data ?? const <Device>[]) {
      if (device.id == id) {
        return options.copyWith(
          initialData: InitialData.compute(() => device),
          // The list's age, so that the seed is not taken for fresh data.
          initialDataUpdatedAt: list.state(client)?.dataUpdatedAt,
        );
      }
    }
  }
  return options;
}
// <<<

Future<void> infiniteReadWrite(QueryClient client) async {
  // >>> guides/typed-queries.md#infinite-write
  final feed = queries.events.feed; // InfiniteQueryRef<List<DeviceEvent>, int>

  // The whole InfiniteData, typed: pages and page params.
  final InfiniteData<List<DeviceEvent>, int>? cached = feed.read(client);

  // A new event at the top of the first page, if there is one.
  feed.update(
    client,
    (data) => data == null || data.pages.isEmpty
        ? null
        : data.copyWith(
            pages: [
              [const DeviceEvent(-1, 'Renamed'), ...data.pages.first],
              ...data.pages.skip(1),
            ],
          ),
  );

  // One device's log: a family, called with its input.
  await queries.events.ofDevice('d1').invalidate(client);
  // <<<
  debugPrint('${cached?.pages.length}');
}

// ---------------------------------------------------------------------------
// guides/typed-queries.md: bulk operations
// ---------------------------------------------------------------------------

// >>> guides/typed-queries.md#bulk
typedef RoomRename = ({String from, String to});

/// Each device the rename changed, with the typed key it was read under.
typedef ChangedDevices = List<(TypedQueryKey<Device>, Device)>;

MutationOptions<void, RoomRename, ChangedDevices> renameRoom(
  QueryClient client,
) {
  final detail = queries.devices.detail;
  return MutationOptions<void, RoomRename, ChangedDevices>(
    mutationFn: (rename) => repository.renameRoom(rename.from, rename.to),
    onMutate: (rename) async {
      await detail.cancel(client);
      final changed = [
        for (final (key, device) in detail.readAll(client))
          if (device != null && device.room == rename.from) (key, device),
      ];
      // null leaves an entry as it is.
      detail.updateAll(
        client,
        (device) => device?.room == rename.from
            ? device!.copyWith(room: rename.to)
            : null,
      );
      return changed;
    },
    onError: (error, stackTrace, rename, changed) {
      for (final (key, device)
          in changed ?? const <(TypedQueryKey<Device>, Device)>[]) {
        key.write(client, device);
      }
    },
    onSettled: (data, error, stackTrace, rename, changed) =>
        DeviceQueries.namespace.invalidate(client),
  );
}
// <<<

// ---------------------------------------------------------------------------
// guides/typed-queries.md: limits, and migrating from raw keys
// ---------------------------------------------------------------------------

// >>> guides/typed-queries.md#generic-helper
// Widens: the options arrive as QueryObserverOptions<Object>, and the entry
// this creates holds Object. The typed reads of the family then refuse it.
Future<Object> warmWide(
  QueryClient client,
  QueryObserverOptions<Object> options,
) =>
    client.query(options);

// Keeps the type: T is the options' own data type.
Future<T> warm<T>(QueryClient client, QueryObserverOptions<T> options) =>
    client.query(options);
// <<<

// >>> guides/typed-queries.md#migrate-before
// Before: a key factory and an options function.
QueryKey roomKey(String id) => QueryKey(['rooms', 'detail', id]);

QueryKey roomListKey(int? floor) => QueryKey([
      'rooms',
      'list',
      {'floor': floor},
    ]);

QueryObserverOptions<Room> roomQuery(String id) => QueryObserverOptions(
      queryKey: roomKey(id),
      queryFn: (context) => repository.room(id, signal: context.signal),
    );
// <<<

// >>> guides/typed-queries.md#migrate-definition
// After: the same parts and the same fetch function, in definitions.
final rooms = QueryNamespace(['rooms']);

final roomDetail = QueryFamily<String, Room>(
  namespace: rooms,
  name: 'detail',
  queryFn: (id, context) => repository.room(id, signal: context.signal),
);

// The old list key held a map. keyOf keeps that layout.
final roomList = QueryFamily<int?, List<Room>>(
  namespace: rooms,
  name: 'list',
  keyOf: (floor) => [
    {'floor': floor},
  ],
  queryFn: (floor, context) =>
      repository.rooms(floor: floor, signal: context.signal),
);
// <<<

class RoomTitle extends StatelessWidget {
  const RoomTitle(this.id, {super.key});

  final String id;

  @override
  Widget build(BuildContext context) {
    // >>> guides/typed-queries.md#migrate-consumers
    // Before: context.query(roomQuery(id))
    final room = context.query(roomDetail(id).options());
    // <<<
    return Text(room.dataOrNull?.name ?? '…');
  }
}

Future<void> roomWrites(QueryClient client, Room room) async {
  // >>> guides/typed-queries.md#migrate-writes
  // Before: client.setQueryData<Room>(roomKey(room.id), room);
  roomDetail(room.id).write(client, room);

  // Before: client.invalidateQueries(
  //   filters: QueryFilters(queryKey: QueryKey(['rooms'])));
  await rooms.invalidate(client);
  // <<<
}

// ---------------------------------------------------------------------------
// overview.md
// ---------------------------------------------------------------------------

// >>> overview.md#typed-example
// lib/data/device_queries.dart: what the data is, declared once.
final allDevices = QueryDefinition<List<Device>>(
  namespace: QueryNamespace(['devices']),
  name: 'all',
  queryFn: (context) => repository.devices(signal: context.signal),
);

// lib/ui/device_list.dart: a widget that shows it.
class DeviceList extends StatelessWidget {
  const DeviceList({super.key});

  @override
  Widget build(BuildContext context) {
    return switch (context.query(allDevices.options())) {
      QueryPending() => const Center(child: CircularProgressIndicator()),
      QueryError(:final error) => Center(child: Text('Could not load: $error')),
      QuerySuccess(:final data) => ListView(
          children: <Widget>[
            for (final device in data) ListTile(title: Text(device.name)),
          ],
        ),
    };
  }
}
// <<<

// ---------------------------------------------------------------------------
// quick-start.md
// ---------------------------------------------------------------------------

// >>> quick-start.md#definition
final allTasks = QueryDefinition<List<Task>>(
  namespace: QueryNamespace(['tasks']),
  name: 'all',
  queryFn: (context) => api.listTasks(signal: context.signal),
  configure: (options) => options.copyWith(
    staleTime: const StaleTime.duration(Duration(seconds: 30)),
  ),
);
// <<<

// >>> quick-start.md#typed-screen
class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tasks = context.query(allTasks.options());

    return Scaffold(
      appBar: AppBar(title: const Text('Tasks')),
      body: switch (tasks) {
        QueryPending() => const Center(child: CircularProgressIndicator()),
        QueryError(:final error) => Center(child: Text('$error')),
        QuerySuccess(:final data) => ListView(
            children: <Widget>[
              for (final task in data) TaskTile(task),
            ],
          ),
      },
    );
  }
}
// <<<

class AddTaskButton extends StatelessWidget {
  const AddTaskButton({super.key});

  // >>> quick-start.md#typed-mutation
  @override
  Widget build(BuildContext context) {
    // Take the client here, in build, not inside the callback. A mutation
    // outlives the widget that started it, so `onSuccess` can run after this
    // element is gone, and looking an ancestor up from a deactivated element
    // throws.
    final client = QueryClientProvider.of(context);

    final add = context.mutation(
      MutationOptions.simple(
        mutationFn: api.addTask,
        onSuccess: (_, __, ___) => allTasks.invalidate(client),
      ),
    );

    return FilledButton(
      onPressed: add.value.isPending ? null : () => add.mutate('New task'),
      child: Text(add.value.isPending ? 'Adding…' : 'Add'),
    );
  }
  // <<<
}

// ---------------------------------------------------------------------------
// guides/query-keys.md, guides/query-options.md, dart-type-safety.md
// ---------------------------------------------------------------------------

Future<void> referenceOptions(QueryClient client, String id) async {
  // >>> guides/query-options.md#reference-options
  // A reference's options are ordinary options: every reader, every
  // prefetch and every helper that takes options takes these.
  final QueryObserverOptions<Device> options =
      queries.devices.detail(id).options();

  await client.query(options); // a prefetch
  // <<<
}

void typedWrites(QueryClient client, Device device) {
  // >>> dart-type-safety.md#typed-writes
  final ref = queries.devices.detail(device.id); // QueryRef<Device>

  ref.write(client, device.copyWith(name: 'Porch lamp'));
  ref.update(client, (current) => current?.copyWith(room: 'porch'));
  final Device? cached = ref.read(client); // no type argument to repeat
  // <<<
  debugPrint('$cached');
}
