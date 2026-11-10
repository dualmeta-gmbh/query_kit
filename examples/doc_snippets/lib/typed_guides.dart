/// The typed samples of the guides whose subject is keys, cache reads and
/// writes, invalidation and paging: each page leads with these and keeps its
/// raw-key sample second.
///
/// Same rule as the rest of this package: each region is marked with the
/// page that shows it, and the fence on that page names the region. The
/// samples speak about the same app as the raw ones beside them — the
/// devices and settings of `c4c_guides.dart`, the tasks and posts of
/// `doc_snippets.dart` — so a reader compares like with like. Every
/// definition writes its type arguments out.
library;

import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'c4b_guides.dart' show DevicePage, deviceRepository, readDeviceLog;
import 'c4c_guides.dart'
    show
        Device,
        DeviceRepository,
        NotificationSettings,
        devices,
        settingsRepository;
import 'doc_snippets.dart' show Post, Task, api;

// ---------------------------------------------------------------------------
// The devices, declared once. The raw keys of `DeviceKeys` in
// `c4c_guides.dart` are the same: ['devices', 'list', room] and
// ['devices', 'detail', id].
// ---------------------------------------------------------------------------

// >>> guides/query-invalidation.md#device-queries
// lib/data/device_queries.dart
final class DeviceQueries {
  DeviceQueries(this._devices);

  final DeviceRepository _devices;

  static final QueryNamespace namespace = QueryNamespace(<Object?>['devices']);

  /// ['devices', 'list', room]
  late final QueryFamily<String, List<Device>> list =
      QueryFamily<String, List<Device>>(
    namespace: namespace,
    name: 'list',
    queryFn: (room, context) =>
        _devices.list(room: room, signal: context.signal),
  );

  /// ['devices', 'detail', id]
  late final QueryFamily<String, Device> detail = QueryFamily<String, Device>(
    namespace: namespace,
    name: 'detail',
    queryFn: (id, context) => _devices.get(id, signal: context.signal),
  );
}

final DeviceQueries deviceQueries = DeviceQueries(devices);
// <<<

/// A stand-in for the scenes endpoint of the bulk optimistic update.
class SceneRepository {
  Future<void> allOff(String room) async {}
}

final SceneRepository scenes = SceneRepository();

// ---------------------------------------------------------------------------
// The tasks and the feed of `doc_snippets.dart`, declared once.
// ---------------------------------------------------------------------------

final class TaskQueries {
  static final QueryNamespace namespace = QueryNamespace(<Object?>['tasks']);

  /// ['tasks', 'list']
  final QueryDefinition<List<Task>> list = QueryDefinition<List<Task>>(
    namespace: namespace,
    name: 'list',
    queryFn: (context) => api.listTasks(signal: context.signal),
  );

  /// ['tasks', 'detail', id]
  final QueryFamily<String, Task> detail = QueryFamily<String, Task>(
    namespace: namespace,
    name: 'detail',
    queryFn: (id, context) => api.getTask(id, signal: context.signal),
  );
}

final TaskQueries taskQueries = TaskQueries();

// >>> guides/infinite-queries.md#feed-definition
final QueryNamespace posts = QueryNamespace(<Object?>['posts']);

/// ['posts', 'feed']
final InfiniteQueryDefinition<List<Post>, int> feed =
    InfiniteQueryDefinition<List<Post>, int>(
  namespace: posts,
  name: 'feed',
  pageFn: (context) => api.feed(cursor: context.pageParam),
  initialPageParam: 0,
  getNextPageParam: (page, pages, pageParam, pageParams) =>
      page.isEmpty ? null : pageParam + page.length,
);
// <<<

// ---------------------------------------------------------------------------
// guides/query-invalidation.md
// ---------------------------------------------------------------------------

Future<void> typedInvalidate(QueryClient client, String id) async {
  // >>> guides/query-invalidation.md#typed-invalidate
  // Everything under ['devices']: every list and every detail.
  await DeviceQueries.namespace.invalidate(client);

  // Every room's list, whatever the room.
  await deviceQueries.list.invalidate(client);

  // This one detail only: a reference is its own entry, exactly.
  await deviceQueries.detail(id).invalidate(client);

  // Mark everything under ['devices'] stale, and refetch nothing now.
  await DeviceQueries.namespace.invalidate(
    client,
    refetchType: RefetchType.none,
  );
  // <<<
}

Future<void> typedInvalidationInAnApp(QueryClient client, Device device) async {
  // >>> guides/query-invalidation.md#typed-device-invalidations
  // Something changed about this device: its detail, and every room list.
  await deviceQueries.detail(device.id).invalidate(client);
  await deviceQueries.list.invalidate(client);

  // A bulk import from the hub: everything about devices is suspect.
  await DeviceQueries.namespace.invalidate(client);
  // <<<
}

Future<void> typedInvalidateByPredicate(QueryClient client) async {
  // >>> guides/query-invalidation.md#typed-predicate
  // The kitchen and the hallway were merged on the hub: invalidate the lists
  // of both rooms, and nothing else.
  const merged = <String>{'kitchen', 'hallway'};
  await client.invalidateQueries(
    filters: deviceQueries.list.filters(
      predicate: (query) => merged.contains(query.queryKey.parts.last),
    ),
  );
  // <<<
}

// ---------------------------------------------------------------------------
// guides/filters.md
// ---------------------------------------------------------------------------

Future<int> typedFilterSamples(QueryClient client) async {
  // >>> guides/filters.md#typed-query-filters
  // Every device query, lists and details alike.
  await DeviceQueries.namespace.invalidate(client);

  // The kitchen's list only: a reference matches its own key exactly.
  await deviceQueries.list('kitchen').refetch(client);

  // Device details nobody is showing: dropped, not refetched.
  client.removeQueries(
    filters: deviceQueries.detail.filters(type: QueryTypeFilter.inactive),
  );

  // Only what has gone stale, for a pull-to-refresh that skips fresh data.
  await client.refetchQueries(
    filters: DeviceQueries.namespace.filters(stale: true),
  );

  // How many device requests are out right now — for a spinner.
  final loading = client.isFetching(
    filters: DeviceQueries.namespace.filters(),
  );
  // <<<
  return loading;
}

// ---------------------------------------------------------------------------
// guides/invalidations-from-mutations.md
// ---------------------------------------------------------------------------

// >>> guides/invalidations-from-mutations.md#typed-remove-device
// lib/data/device_mutations.dart
MutationOptions<void, String, void> removeDeviceMutation(QueryClient client) =>
    MutationOptions.simple(
      mutationFn: devices.remove,
      onSuccess: (_, id, __) {
        // The device is gone: drop its detail rather than refetch a 404 …
        deviceQueries.detail(id).remove(client);
        // … and refetch every room list that may have shown it.
        return deviceQueries.list.invalidate(client);
      },
    );
// <<<

// >>> guides/invalidations-from-mutations.md#typed-move-device
MutationOptions<Device, String, void> moveDeviceMutation(
  QueryClient client,
  Device device,
) =>
    MutationOptions.simple(
      mutationFn: (String toRoom) => devices.move(device.id, toRoom),
      // Two lists changed. Both refetches run at once, and the mutation
      // settles when both have landed.
      onSuccess: (moved, toRoom, _) => Future.wait(<Future<void>>[
        deviceQueries.list(device.room).invalidate(client),
        deviceQueries.list(toRoom).invalidate(client),
      ]),
    );
// <<<

// ---------------------------------------------------------------------------
// guides/updates-from-mutation-responses.md
// ---------------------------------------------------------------------------

// >>> guides/updates-from-mutation-responses.md#typed-settings
// lib/data/settings_queries.dart
/// ['settings', 'notifications']
final QueryDefinition<NotificationSettings> notificationSettings =
    QueryDefinition<NotificationSettings>(
  namespace: QueryNamespace(<Object?>['settings']),
  name: 'notifications',
  queryFn: (context) => settingsRepository.load(signal: context.signal),
);

QueryObserverOptions<NotificationSettings> settingsQuery() =>
    notificationSettings.options();

MutationOptions<NotificationSettings, NotificationSettings, void>
    saveSettingsMutation(QueryClient client) => MutationOptions.simple(
          mutationFn: settingsRepository.save,
          // The server answers with what it stored — defaults applied,
          // values clamped. That is the new truth; there is nothing to
          // fetch.
          onSuccess: (saved, _, __) {
            notificationSettings.write(client, saved);
          },
        );
// <<<

void typedCacheWrites(QueryClient client, String id, Task task) {
  // >>> guides/updates-from-mutation-responses.md#typed-cache-writes
  final detail = taskQueries.detail(id); // QueryRef<Task>

  final Task? cached = detail.read(client);
  detail.write(client, task);
  detail.update(client, (previous) => previous?.copyWith(name: 'Renamed'));
  taskQueries.detail.updateAll(
    client,
    (previous) => previous?.copyWith(name: 'Renamed'),
  );
  // <<<
  debugPrint('$cached');
}

// >>> guides/updates-from-mutation-responses.md#typed-rename-everywhere
MutationOptions<Device, String, void> renameDeviceMutation(
  QueryClient client,
  String id,
) =>
    MutationOptions.simple(
      mutationFn: (String name) => devices.rename(id, name),
      onSuccess: (renamed, _, __) {
        deviceQueries.detail(id).write(client, renamed);
        // Every room list that holds it gets a new list with the new device;
        // `null` leaves the others untouched.
        deviceQueries.list.updateAll(
          client,
          (list) => list == null || !list.any((device) => device.id == id)
              ? null
              : <Device>[
                  for (final device in list) device.id == id ? renamed : device,
                ],
        );
      },
    );
// <<<

// ---------------------------------------------------------------------------
// guides/optimistic-updates.md
// ---------------------------------------------------------------------------

// >>> guides/optimistic-updates.md#typed-via-cache
int _temporaryIds = 0;

MutationOptions<Device, String, String> addDeviceOptimistically(
  QueryClient client,
  String room,
) {
  final list = deviceQueries.list(room); // QueryRef<List<Device>>
  return MutationOptions<Device, String, String>(
    mutationFn: (name) => devices.add(name: name, room: room),
    onMutate: (String name) async {
      // A refetch already in flight would land after the patch and undo it.
      await list.cancel(client);
      // Until the server names the device, a temporary id marks the row.
      final temporaryId = 'pending-${_temporaryIds++}';
      list.update(
        client,
        (devices) => <Device>[
          ...?devices,
          Device(id: temporaryId, name: name, room: room),
        ],
      );
      return temporaryId; // what onSuccess and onError need to find the row
    },
    onSuccess: (device, _, temporaryId) {
      // Swap in the server's device at once; the refetch below confirms it.
      list.update(
        client,
        (devices) => devices == null
            ? null
            : <Device>[
                for (final row in devices) row.id == temporaryId ? device : row,
              ],
      );
    },
    onError: (error, stackTrace, name, temporaryId) {
      // Take out this row only: another add may be in flight beside it.
      list.update(
        client,
        (devices) => devices?.where((row) => row.id != temporaryId).toList(),
      );
    },
    onSettled: (_, __, ___, ____, _____) => list.invalidate(client),
  );
}
// <<<

// >>> guides/optimistic-updates.md#typed-optimistic
MutationOptions<Task, String, Task?> renameOptimistically(
  QueryClient client,
  String id,
) {
  final task = taskQueries.detail(id); // QueryRef<Task>
  return MutationOptions<Task, String, Task?>(
    mutationFn: (name) => api.rename(id, name),
    onMutate: (String name) async {
      await task.cancel(client);
      final previous = task.read(client);
      // Nothing cached, nothing to patch: returning null writes nothing.
      task.update(client, (current) => current?.copyWith(name: name));
      return previous; // the rollback handle
    },
    onError: (error, stack, name, previous) {
      if (previous != null) task.write(client, previous);
    },
    onSettled: (_, __, ___, ____, _____) => task.invalidate(client),
  );
}
// <<<

// >>> guides/optimistic-updates.md#restore
/// What was cached before the write: no entry (`null`), an entry without
/// data, or data, which under a nullable type may be a cached `null`.
typedef Snapshot<T> = ({QueryState<T>? before});

/// Puts [entry] back to what [before] says it was.
void restore<T>(
  QueryClient client,
  QueryEntryRef<T> entry,
  QueryState<T>? before,
) {
  if (before == null) {
    // Nothing was cached: remove the entry the optimistic write created.
    entry.remove(client);
  } else if (!before.hasData) {
    // An entry without data yet: take the optimistic value out, refetch.
    entry.reset(client).ignore();
  } else {
    // The data, dated as it was, so the rollback does not look fresh.
    entry.write(client, before.data as T, updatedAt: before.dataUpdatedAt);
  }
}
// <<<

// >>> guides/optimistic-updates.md#save-device
/// Writes the edited device as a whole, cached or not.
MutationOptions<Device, Device, Snapshot<Device>> saveDevice(
  QueryClient client,
) =>
    MutationOptions<Device, Device, Snapshot<Device>>(
      mutationFn: (edited) => devices.setPower(edited.id, on: edited.isOn),
      onMutate: (Device edited) async {
        final device = deviceQueries.detail(edited.id);
        await device.cancel(client);
        final before = device.state(client);
        device.write(client, edited);
        return (before: before);
      },
      onError: (error, stackTrace, edited, snapshot) {
        if (snapshot != null) {
          restore(client, deviceQueries.detail(edited.id), snapshot.before);
        }
      },
      onSettled: (_, __, ___, edited, ____) =>
          deviceQueries.detail(edited.id).invalidate(client),
    );
// <<<

// >>> guides/optimistic-updates.md#room-off
typedef SwitchedOff = List<(TypedQueryKey<Device>, Device)>;

/// Every light in a room off at once, in every cached detail.
MutationOptions<void, String, SwitchedOff> roomOff(QueryClient client) =>
    MutationOptions<void, String, SwitchedOff>(
      mutationFn: scenes.allOff,
      onMutate: (String room) async {
        await deviceQueries.detail.cancel(client);
        // The snapshot: each detail this write changes, with its typed key.
        final switchedOff = <(TypedQueryKey<Device>, Device)>[
          for (final (key, device) in deviceQueries.detail.readAll(client))
            if (device != null && device.room == room && device.isOn)
              (key, device),
        ];
        deviceQueries.detail.updateAll(
          client,
          (device) => device != null && device.room == room && device.isOn
              ? device.copyWith(isOn: false)
              : null, // null leaves the entry alone
        );
        return switchedOff;
      },
      onError: (error, stackTrace, room, switchedOff) {
        if (switchedOff == null) return; // onMutate itself failed
        // Put back what this write changed, and nothing else.
        for (final (key, device) in switchedOff) {
          key.write(client, device);
        }
      },
      onSettled: (_, __, ___, ____, _____) =>
          DeviceQueries.namespace.invalidate(client),
    );
// <<<

// ---------------------------------------------------------------------------
// guides/infinite-queries.md
// ---------------------------------------------------------------------------

void typedFeedData(QueryClient client, Post post) {
  // >>> guides/infinite-queries.md#typed-data
  // The whole InfiniteData, typed: no type argument at the call.
  final List<List<Post>>? pages = feed.read(client)?.pages;

  // The user's own post, first in the first page. A feed nobody has opened
  // stays empty: returning null writes nothing.
  feed.update(
    client,
    (data) => data == null || data.pages.isEmpty
        ? null
        : data.copyWith(
            pages: <List<Post>>[
              <Post>[post, ...data.pages.first],
              ...data.pages.skip(1),
            ],
          ),
  );
  // <<<
  debugPrint('${pages?.length}');
}

// ---------------------------------------------------------------------------
// guides/initial-query-data.md
// ---------------------------------------------------------------------------

// >>> guides/initial-query-data.md#typed-seed-from-list
QueryObserverOptions<Task> taskSeededFromList(QueryClient client, String id) =>
    // The definition holds no client, so the seed is added here, per use.
    taskQueries.detail(id).options().copyWith(
          initialData: InitialData.compute(
            () => taskQueries.list
                .read(client)
                ?.where((task) => task.id == id)
                .firstOrNull,
          ),
          // As old as the list it came from.
          initialDataUpdatedAtCompute: () =>
              taskQueries.list.state(client)?.dataUpdatedAt,
        );
// <<<

// ---------------------------------------------------------------------------
// guides/prefetching.md
// ---------------------------------------------------------------------------

Future<List<Task>> typedFetch(QueryClient client) async {
  // >>> guides/prefetching.md#typed-imperative
  final tasks = await taskQueries.list.fetch(client); // List<Task>
  // <<<
  return tasks;
}

void typedPrimeFromList(QueryClient client, List<Device> list) {
  // >>> guides/prefetching.md#typed-prime
  // The room list already holds every device's fields: seed each detail, so
  // opening one shows it at once.
  for (final device in list) {
    deviceQueries.detail(device.id).write(client, device);
  }
  // <<<
}

// ---------------------------------------------------------------------------
// guides/query-cancellation.md
// ---------------------------------------------------------------------------

/// ['device-log', 'lines', deviceId]
final QueryFamily<String, List<String>> deviceLog =
    QueryFamily<String, List<String>>(
  namespace: QueryNamespace(<Object?>['device-log']),
  name: 'lines',
  queryFn: (deviceId, context) => readDeviceLog(context, deviceId),
);

// >>> guides/query-cancellation.md#typed-cancel-button
class CancelLogButton extends StatelessWidget {
  const CancelLogButton({super.key, required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: () => deviceLog(deviceId)
            .cancel(QueryClientProvider.read(context))
            .ignore(),
        child: const Text('Stop reading'),
      );
}
// <<<

// ---------------------------------------------------------------------------
// guides/paginated-queries.md
// ---------------------------------------------------------------------------

// >>> guides/paginated-queries.md#typed-page-query
/// ['devices', 'page', page]
final QueryFamily<int, DevicePage> devicePages = QueryFamily<int, DevicePage>(
  namespace: QueryNamespace(<Object?>['devices']),
  name: 'page',
  queryFn: (page, context) =>
      deviceRepository.page(page, signal: context.signal),
  configure: (base, page) => base.copyWith(
    placeholderData: const PlaceholderData.keepPrevious(),
    staleTime: const StaleTime.duration(Duration(seconds: 30)),
  ),
);

// The reader observes `devicePages(page).options()`, and prefetches with
// `devicePages(page + 1).fetch(client)`.
// <<<

QueryObserverOptions<DevicePage> typedDevicePageQuery(int page) =>
    devicePages(page).options();

void typedPrefetchNext(QueryClient client, int page) {
  devicePages(page + 1).fetch(client).ignore();
}

// ---------------------------------------------------------------------------
// guides/default-query-function.md
// ---------------------------------------------------------------------------

// >>> guides/default-query-function.md#typed-keyed-queries
// lib/data/device_queries.dart — no queryFn: the default for ['api'] serves
// it. `Object` says "some JSON", not which JSON: `select` checks the shape.
final QueryFamily<String, Object> roomDevicesJson = QueryFamily<String, Object>(
  namespace: QueryNamespace(<Object?>['api']),
  name: '/devices',
  // ['api', '/devices', {'room': room}]
  keyOf: (room) => <Object?>[
    <String, Object?>{'room': room},
  ],
);

QuerySelectOptions<Object, List<Device>> apiRoomDevices(String room) =>
    roomDevicesJson(room).options().withSelect(parseDevicesJson);

List<Device> parseDevicesJson(Object json) => <Device>[
      for (final item in json as List<Object?>)
        Device.fromJson(item! as Map<String, Object?>),
    ];
// <<<

// ---------------------------------------------------------------------------
// guides/mutations.md
// ---------------------------------------------------------------------------

// >>> guides/mutations.md#typed-set-power
// lib/data/device_mutations.dart
MutationOptions<Device, bool, void> setPowerMutation(
  QueryClient client,
  String id,
) =>
    MutationOptions.simple(
      mutationFn: (bool on) => devices.setPower(id, on: on),
      onSuccess: (device, _, __) {
        deviceQueries.detail(id).write(client, device);
        deviceQueries.list.invalidate(client).ignore();
      },
    );
// <<<
