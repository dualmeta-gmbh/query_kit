/// Mutations over typed query definitions: the cache work a mutation's
/// callbacks do, written with references instead of keys and type
/// arguments. Port-only behaviour; PORTING_NOTES' "Typed query definitions"
/// section.
///
/// The file has two halves. **The recipes** are application code as a guide
/// would print it: a small domain, its definitions, and one function per
/// mutation that returns the existing `MutationOptions`. Nothing in them is
/// a test helper. **The cases** then run each recipe against a backend that
/// can be slow and can refuse, and look at the cache after every step: the
/// stored type, the state, and that nothing beside the entry was touched.
///
/// There is no mutation definition: a mutation stays `MutationOptions`, and
/// what the typed layer gives it is the reference it reads, writes and
/// invalidates.
library;

import 'dart:async';

import 'package:query_kit/query_kit.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

// ============================================================ the domain

class Device {
  const Device(this.id, {this.name = '', this.room = 'hall'});

  final String id;
  final String name;
  final String room;

  Device copyWith({String? name, String? room}) =>
      Device(id, name: name ?? this.name, room: room ?? this.room);

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

class Event {
  const Event(this.id, this.text);

  final int id;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is Event && other.id == id && other.text == text;

  @override
  int get hashCode => Object.hash(id, text);

  @override
  String toString() => 'Event($id, $text)';
}

typedef EventFeed = InfiniteData<List<Event>, int>;

/// The backend, as an application's repository would wrap it.
abstract interface class DeviceApi {
  Future<Device> device(String id);
  Future<List<Device>> devices();
  Future<Device?> owner(String room);
  Future<List<Event>> events({required int before});

  Future<Device> save(Device device);
  Future<Device> rename(String id, String name);
  Future<Device?> assign(String room, String? deviceId);
  Future<List<Device>> moveAll(String room);
  Future<void> renameRoom(String from, String to);
  Future<Event> log(String text);
}

// ======================================================= the definitions

/// One class per namespace, one member per query.
final class DeviceQueries {
  DeviceQueries(this._api);

  final DeviceApi _api;

  static final namespace = QueryNamespace(['devices']);

  late final detail = QueryFamily<String, Device>(
    namespace: namespace,
    name: 'detail',
    queryFn: (id, context) => _api.device(id),
  );

  late final list = QueryDefinition<List<Device>>(
    namespace: namespace,
    name: 'list',
    queryFn: (context) => _api.devices(),
  );

  /// The device that controls a room, or `null` when the room has none:
  /// nullable data, so "no owner" is a cached answer.
  late final owner = QueryFamily<String, Device?>(
    namespace: namespace,
    name: 'owner',
    queryFn: (room, context) => _api.owner(room),
  );

  /// The event log, newest first, twenty ids per page.
  late final events = InfiniteQueryDefinition<List<Event>, int>(
    namespace: namespace,
    name: 'events',
    pageFn: (context) => _api.events(before: context.pageParam),
    initialPageParam: 1 << 30,
    getNextPageParam: (page, pages, pageParam, pageParams) =>
        page.isEmpty ? null : page.last.id,
  );
}

// ============================================================ the recipes

// ---------------------------------------------------- 1. optimistic write
//
// Rename a device and show the new name before the server answers.
//
//   onMutate   cancel the entry's fetch, remember what is cached, patch it
//   onError    put back what was cached
//   onSettled  invalidate: the server has the last word either way
//
// `device.cancel` comes first and is not optional. A fetch already in
// flight left before the write; landing after the patch, it would write
// the old name over it.

MutationOptions<Device, String, Device> renameDevice(
  QueryClient client,
  DeviceQueries queries,
  DeviceApi api,
  String id,
) {
  final device = queries.detail(id); // QueryRef<Device>
  return MutationOptions<Device, String, Device>(
    mutationFn: (name) => api.rename(id, name),
    onMutate: (name) async {
      await device.cancel(client);
      final previous = device.read(client); // Device?
      // Nothing cached, nothing to patch: the updater returns null and
      // the update writes nothing.
      device.update(client, (current) => current?.copyWith(name: name));
      return previous;
    },
    onError: (error, stackTrace, name, previous) {
      if (previous != null) {
        device.write(client, previous);
      }
    },
    onSettled: (data, error, stackTrace, name, previous) =>
        device.invalidate(client),
  );
}

// ------------------------------------------- 2. a snapshot, and a restore
//
// `read` returns `null` for three different things: no entry, an entry
// that holds no data yet, and (under a nullable type) a cached `null`. A
// rollback that has to tell them apart snapshots `state` instead:
//
//   state == null     nothing is cached under the key
//   !state.hasData    an entry, still without data (its first fetch is
//                     running, or failed)
//   state.hasData     data, which may be a cached null
//
// and puts each back in its own way. The snapshot travels in a record,
// because `onError` receives `null` when `onMutate` never returned, and
// "no entry" is a `null` state: the record keeps the two apart.

typedef Snapshot<T> = ({QueryState<T>? before});

/// Puts [entry] back to what [before] says it was.
void restore<T>(
    QueryClient client, QueryEntryRef<T> entry, QueryState<T>? before) {
  if (before == null) {
    // Nothing was cached, so nothing is again: the entry the optimistic
    // write created is removed, exactly that one.
    entry.remove(client);
  } else if (!before.hasData) {
    // An entry without data. Resetting takes the optimistic value out and
    // fetches again where something is watching.
    entry.reset(client).ignore();
  } else {
    // The data and the time it was fetched at, so that the rollback does
    // not make old data look fresh. A cached null is written as null.
    entry.write(client, before.data as T, updatedAt: before.dataUpdatedAt);
  }
}

/// Replace a device as a whole: the optimistic value does not depend on
/// what is cached, so it is written whether or not there is an entry.
MutationOptions<Device, Device, Snapshot<Device>> saveDevice(
  QueryClient client,
  DeviceQueries queries,
  DeviceApi api,
) =>
    MutationOptions<Device, Device, Snapshot<Device>>(
      mutationFn: api.save,
      onMutate: (edited) async {
        final device = queries.detail(edited.id);
        await device.cancel(client);
        final before = device.state(client);
        device.write(client, edited);
        return (before: before);
      },
      onError: (error, stackTrace, edited, snapshot) {
        if (snapshot != null) {
          restore(client, queries.detail(edited.id), snapshot.before);
        }
      },
      onSettled: (data, error, stackTrace, edited, snapshot) =>
          queries.detail(edited.id).invalidate(client),
    );

/// The same over nullable data: a room's owner, which may be nobody.
MutationOptions<Device?, String?, Snapshot<Device?>> assignOwner(
  QueryClient client,
  DeviceQueries queries,
  DeviceApi api,
  String room,
) {
  final owner = queries.owner(room); // QueryRef<Device?>
  return MutationOptions<Device?, String?, Snapshot<Device?>>(
    mutationFn: (deviceId) => api.assign(room, deviceId),
    onMutate: (deviceId) async {
      await owner.cancel(client);
      final before = owner.state(client);
      // `write`, not `update`: an updater that returns null writes
      // nothing, and "nobody" is a value here.
      owner.write(
        client,
        deviceId == null ? null : queries.detail(deviceId).read(client),
      );
      return (before: before);
    },
    onError: (error, stackTrace, deviceId, snapshot) {
      if (snapshot != null) {
        restore(client, owner, snapshot.before);
      }
    },
    onSettled: (data, error, stackTrace, deviceId, snapshot) =>
        owner.invalidate(client),
  );
}

// ------------------------------------------- 3. the server's answer, kept
//
// The response of a write is the newest copy of the row there is. Writing
// it into the cache saves the refetch: the detail's entry, and the row in
// the list.

MutationOptions<Device, Device, void> saveDeviceAndKeepTheAnswer(
  QueryClient client,
  DeviceQueries queries,
  DeviceApi api,
) =>
    MutationOptions.simple(
      mutationFn: api.save,
      onSuccess: (saved, edited, _) {
        queries.detail(saved.id).write(client, saved);
        queries.list.update(
          client,
          // A list that was never fetched stays unfetched.
          (list) => list == null
              ? null
              : [for (final row in list) row.id == saved.id ? saved : row],
        );
      },
    );

// --------------------------- 4. a list written, its family invalidated
//
// One request changed many rows and answered with the list. The list is
// written from the answer; every cached detail may now be out of date,
// and the family invalidates them all in one call, whatever their ids.
// Returned from `onSuccess`, so the mutation stays pending until the
// details on screen have refetched.

MutationOptions<List<Device>, String, void> moveAllDevices(
  QueryClient client,
  DeviceQueries queries,
  DeviceApi api,
) =>
    MutationOptions.simple(
      mutationFn: api.moveAll,
      onSuccess: (moved, room, _) {
        queries.list.write(client, moved);
        return queries.detail.invalidate(client);
      },
    );

// ------------------------------------- 5. every cached detail, patched
//
// A room is renamed: every cached device in it shows the new name at once.
// `updateAll` runs over the family's entries and writes what the updater
// returns; `null` leaves an entry alone.
//
// `readAll` returns each entry's typed key with its data, and that pair is
// the snapshot: the rollback writes every device back through the key it
// was read with. It puts back the devices this mutation changed and no
// others, because another write may have touched a neighbour in the
// meantime.
//
// The key knows the entry's type and nothing else of the definition. An
// entry that is still there is written as its reference would write it.
// One that was removed in the meantime is made again from the key alone:
// the right type, the client's defaults, and no fetch function until the
// query is used again.

typedef RoomRename = ({String from, String to});

typedef ChangedDevices = List<(TypedQueryKey<Device>, Device)>;

MutationOptions<void, RoomRename, ChangedDevices> renameRoom(
  QueryClient client,
  DeviceQueries queries,
  DeviceApi api,
) =>
    MutationOptions<void, RoomRename, ChangedDevices>(
      mutationFn: (rename) => api.renameRoom(rename.from, rename.to),
      onMutate: (rename) async {
        await queries.detail.cancel(client);
        final changed = [
          for (final (key, device) in queries.detail.readAll(client))
            if (device != null && device.room == rename.from) (key, device),
        ];
        queries.detail.updateAll(
          client,
          (device) => device?.room == rename.from
              ? device!.copyWith(room: rename.to)
              : null,
        );
        return changed;
      },
      onError: (error, stackTrace, rename, changed) {
        if (changed != null) {
          for (final (key, device) in changed) {
            key.write(client, device);
          }
        }
      },
      onSettled: (data, error, stackTrace, rename, changed) =>
          DeviceQueries.namespace.invalidate(client),
    );

// ------------------------------------------------ 6. an infinite query
//
// The same three steps over pages. The reference reads and writes the
// whole `InfiniteData`; `copyWith` replaces its pages.

MutationOptions<Event, String, Snapshot<EventFeed>> logEvent(
  QueryClient client,
  DeviceQueries queries,
  DeviceApi api,
) {
  final events = queries.events; // InfiniteQueryRef<List<Event>, int>
  return MutationOptions<Event, String, Snapshot<EventFeed>>(
    mutationFn: api.log,
    onMutate: (text) async {
      await events.cancel(client);
      final before = events.state(client);
      events.update(
        client,
        // Only into pages that are there: a feed nobody opened stays empty.
        (data) => data == null || data.pages.isEmpty
            ? null
            : data.copyWith(
                pages: [
                  [Event(-1, text), ...data.pages.first],
                  ...data.pages.skip(1),
                ],
              ),
      );
      return (before: before);
    },
    onError: (error, stackTrace, text, snapshot) {
      if (snapshot != null) {
        restore(client, events, snapshot.before);
      }
    },
    onSettled: (data, error, stackTrace, text, snapshot) =>
        events.invalidate(client),
  );
}

// ============================================================== the cases

/// A backend held in memory. Every call takes ten milliseconds, is counted
/// under its name, and a write fails once when [refuseNextWrite] is set.
final class FakeDeviceApi implements DeviceApi {
  final rows = <String, Device>{
    'd1': const Device('d1', name: 'lamp', room: 'hall'),
    'd2': const Device('d2', name: 'radio', room: 'hall'),
    'd3': const Device('d3', name: 'kettle', room: 'kitchen'),
  };
  final owners = <String, String?>{'hall': 'd1', 'attic': null};
  final log_ = <Event>[
    for (var id = 50; id >= 1; id--) Event(id, 'event $id'),
  ];
  final calls = <String, int>{};
  bool refuseNextWrite = false;

  Future<void> _call(String name, {bool write = false}) async {
    calls[name] = (calls[name] ?? 0) + 1;
    await sleep(ms(10));
    if (write && refuseNextWrite) {
      refuseNextWrite = false;
      throw StateError('refused');
    }
  }

  @override
  Future<Device> device(String id) async {
    await _call('device $id');
    return rows[id]!;
  }

  @override
  Future<List<Device>> devices() async {
    await _call('devices');
    return rows.values.toList();
  }

  @override
  Future<Device?> owner(String room) async {
    await _call('owner $room');
    return rows[owners[room]];
  }

  @override
  Future<List<Event>> events({required int before}) async {
    await _call('events');
    return log_.where((event) => event.id < before).take(20).toList();
  }

  @override
  Future<Device> save(Device device) async {
    await _call('save', write: true);
    return rows[device.id] = device.copyWith(name: '${device.name} (saved)');
  }

  @override
  Future<Device> rename(String id, String name) async {
    await _call('rename', write: true);
    return rows[id] = rows[id]!.copyWith(name: name);
  }

  @override
  Future<Device?> assign(String room, String? deviceId) async {
    await _call('assign', write: true);
    owners[room] = deviceId;
    return rows[deviceId];
  }

  @override
  Future<List<Device>> moveAll(String room) async {
    await _call('moveAll', write: true);
    rows.updateAll((id, device) => device.copyWith(room: room));
    return rows.values.toList();
  }

  @override
  Future<void> renameRoom(String from, String to) async {
    await _call('renameRoom', write: true);
    rows.updateAll(
      (id, device) => device.room == from ? device.copyWith(room: to) : device,
    );
  }

  @override
  Future<Event> log(String text) async {
    await _call('log', write: true);
    final event = Event(log_.first.id + 1, text);
    log_.insert(0, event);
    return event;
  }
}

Type typeOf<T>() => T;

typedef World = ({
  QueryClient client,
  FakeDeviceApi api,
  DeviceQueries queries,
});

World world() {
  final api = FakeDeviceApi();
  return (client: testClient(), api: api, queries: DeviceQueries(api));
}

/// Every entry in the cache as `key: Query<type>`, sorted: what a step may
/// not change behind the entry it is about.
List<String> entries(QueryClient client) => [
      for (final query in client.queryCache.findAll())
        '${query.queryKey.parts.join('/')}: Query<${query.dataType}>',
    ]..sort();

/// The entry under [entry], which must hold the reference's own type.
Query<Object?> entryOf(QueryClient client, QueryEntryRef<Object?> entry) =>
    client.queryCache.findAll(filters: entry.filters()).single;

/// What [future] completes with, once the backend's ten milliseconds are
/// over.
Future<T> fetched<T>(FakeTime time, Future<T> future) async {
  await time.advance(ms(10));
  return future;
}

/// Starts [options] with [variables] and returns how it ended: the data,
/// or the error it failed with.
Future<Object?> run<TData, TVariables, TOnMutateResult>(
  QueryClient client,
  MutationOptions<TData, TVariables, TOnMutateResult> options,
  TVariables variables,
) =>
    executeMutation(client, options, variables).then<Object?>(
      (data) => data,
      onError: (Object error) => error,
    );

void main() {
  group('1. an optimistic write, with a request in flight', () {
    testFakeAsync('cancel, patch, fail, roll back, refetch: every step',
        (time) async {
      final (:client, :api, :queries) = world();
      final device = queries.detail('d1');
      final seen = <String>[];
      final unsubscribe = QueryObserver<Device, Device>(
        client,
        device.options(),
      ).subscribe((result) {
        final name = result.dataOrNull?.name ?? '-';
        if (seen.isEmpty || seen.last != name) {
          seen.add(name);
        }
      });
      await time.advance(ms(10));
      final fetchedAt = device.state(client)!.dataUpdatedAt;
      expect(device.read(client), const Device('d1', name: 'lamp'));

      // A refetch on its way, which left before the write. Somebody else
      // has renamed the device since, so its answer can be told from what
      // is cached.
      await time.advance(ms(100));
      api.rows['d1'] = const Device('d1', name: 'floor lamp');
      device.refetch(client).ignore();
      await time.advance(ms(5));
      expect(device.state(client)!.fetchStatus, FetchStatus.fetching);

      api.refuseNextWrite = true;
      final outcome =
          run(client, renameDevice(client, queries, api, 'd1'), 'desk lamp');

      // `onMutate` has run: the fetch is cancelled and the state it had
      // begun to change is back, then the patch.
      await time.flushMicrotasks();
      var state = device.state(client)!;
      expect(state.data, const Device('d1', name: 'desk lamp'));
      expect(state.status, QueryStatus.success);
      expect(state.fetchStatus, FetchStatus.idle);
      expect(state.dataUpdatedAt, time.now);
      expect(entryOf(client, device).dataType, Device);
      expect(entries(client), ['devices/detail/d1: Query<Device>']);
      expect(api.calls, {'device d1': 2, 'rename': 1});

      // The moment the cancelled response would have landed: it does not.
      await time.advance(ms(5));
      expect(device.read(client), const Device('d1', name: 'desk lamp'));
      expect(device.state(client)!.fetchStatus, FetchStatus.idle);

      // The write is refused. `onError` puts the old value back, and
      // `onSettled` invalidates, which starts the refetch.
      await time.advance(ms(5));
      state = device.state(client)!;
      expect(state.data, const Device('d1', name: 'lamp'));
      expect(state.status, QueryStatus.success);
      expect(state.error, isNull);
      expect(state.isInvalidated, isTrue);
      expect(state.fetchStatus, FetchStatus.fetching);
      expect(entryOf(client, device).dataType, Device);

      // The server has the last word.
      await time.advance(ms(10));
      state = device.state(client)!;
      expect(state.data, const Device('d1', name: 'floor lamp'));
      expect(state.isInvalidated, isFalse);
      expect(state.fetchStatus, FetchStatus.idle);
      expect(state.dataUpdatedAt, isNot(fetchedAt));
      expect(await outcome, isStateError);
      expect(api.calls, {'device d1': 3, 'rename': 1});
      expect(entries(client), ['devices/detail/d1: Query<Device>']);
      // What a widget showed, change by change: the cancelled response
      // never came between the patch and the rollback.
      expect(seen, ['-', 'lamp', 'desk lamp', 'lamp', 'floor lamp']);
      unsubscribe();
      client.clear();
    });

    // The control for the case above: the same mutation without the
    // cancel, and the response on its way overwrites the patch.
    testFakeAsync('without the cancel the response in flight wins',
        (time) async {
      final (:client, :api, :queries) = world();
      final device = queries.detail('d1');
      final unsubscribe = QueryObserver<Device, Device>(
        client,
        device.options(),
      ).subscribe((result) {});
      await time.advance(ms(10));
      api.rows['d1'] = const Device('d1', name: 'floor lamp');
      device.refetch(client).ignore();
      await time.advance(ms(5));

      final outcome = run(
        client,
        MutationOptions<Device, String, Device>(
          mutationFn: (name) => api.rename('d1', name),
          onMutate: (name) {
            device.update(client, (current) => current?.copyWith(name: name));
            return null;
          },
        ),
        'desk lamp',
      );
      await time.flushMicrotasks();
      expect(device.read(client), const Device('d1', name: 'desk lamp'));
      await time.advance(ms(5));
      expect(device.read(client), const Device('d1', name: 'floor lamp'));
      await time.advance(ms(10));
      expect(await outcome, const Device('d1', name: 'desk lamp'));
      unsubscribe();
      client.clear();
    });

    testFakeAsync('the write succeeds: the patch stays until the refetch',
        (time) async {
      final (:client, :api, :queries) = world();
      final device = queries.detail('d1');
      await fetched(time, device.fetch(client));
      final outcome =
          run(client, renameDevice(client, queries, api, 'd1'), 'desk lamp');
      await time.flushMicrotasks();
      expect(device.read(client), const Device('d1', name: 'desk lamp'));
      await time.advance(ms(10));
      expect(await outcome, const Device('d1', name: 'desk lamp'));
      // Nothing observes the entry: invalidated, and fetched when next
      // used.
      expect(device.state(client)!.isInvalidated, isTrue);
      expect(device.read(client), const Device('d1', name: 'desk lamp'));
      expect(api.calls, {'device d1': 1, 'rename': 1});
      client.clear();
    });

    testFakeAsync('nothing cached: nothing is patched, created or restored',
        (time) async {
      final (:client, :api, :queries) = world();
      api.refuseNextWrite = true;
      final outcome =
          run(client, renameDevice(client, queries, api, 'd1'), 'desk lamp');
      await time.flushMicrotasks();
      expect(entries(client), isEmpty);
      await time.advance(ms(10));
      expect(await outcome, isStateError);
      expect(entries(client), isEmpty);
      client.clear();
    });
  });

  group('2. a snapshot tells three kinds of nothing apart', () {
    testFakeAsync('no entry: the rollback removes the one the write made',
        (time) async {
      final (:client, :api, :queries) = world();
      final device = queries.detail('d9');
      // A neighbour, to show the removal is exact.
      queries.detail('d1').write(client, const Device('d1', name: 'lamp'));
      queries.list.write(client, const [Device('d1', name: 'lamp')]);
      final before = entries(client);
      expect(device.state(client), isNull);

      api.refuseNextWrite = true;
      final outcome = run(
        client,
        saveDevice(client, queries, api),
        const Device('d9', name: 'new'),
      );
      await time.flushMicrotasks();
      expect(device.read(client), const Device('d9', name: 'new'));
      expect(entryOf(client, device).dataType, Device);
      expect(entries(client), [
        'devices/detail/d1: Query<Device>',
        'devices/detail/d9: Query<Device>',
        'devices/list: Query<List<Device>>',
      ]);

      await time.advance(ms(10));
      expect(await outcome, isStateError);
      expect(device.state(client), isNull);
      expect(entries(client), before);
      expect(
        queries.detail('d1').read(client),
        const Device('d1', name: 'lamp'),
      );
      client.clear();
    });

    testFakeAsync(
        'an entry without data, its first fetch in flight: reset and '
        'refetched', (time) async {
      final (:client, :api, :queries) = world();
      final device = queries.detail('d1');
      final unsubscribe = QueryObserver<Device, Device>(
        client,
        device.options(),
      ).subscribe((result) {});
      await time.advance(ms(5));
      var state = device.state(client)!;
      expect(state.hasData, isFalse);
      expect(state.fetchStatus, FetchStatus.fetching);

      api.refuseNextWrite = true;
      final outcome = run(
        client,
        saveDevice(client, queries, api),
        const Device('d1', name: 'edited'),
      );
      await time.flushMicrotasks();
      state = device.state(client)!;
      expect(state.data, const Device('d1', name: 'edited'));
      expect(state.status, QueryStatus.success);
      expect(state.fetchStatus, FetchStatus.idle);
      expect(entryOf(client, device).dataType, Device);

      // When the cancelled first fetch would have answered.
      await time.advance(ms(5));
      expect(device.read(client), const Device('d1', name: 'edited'));

      // Refused: back to an entry without data, which the observer has
      // fetched again.
      await time.advance(ms(5));
      state = device.state(client)!;
      expect(state.hasData, isFalse);
      expect(state.status, QueryStatus.pending);
      expect(state.error, isNull);
      expect(state.fetchStatus, FetchStatus.fetching);
      expect(entryOf(client, device).dataType, Device);

      await time.advance(ms(10));
      expect(await outcome, isStateError);
      expect(device.read(client), const Device('d1', name: 'lamp'));
      expect(device.state(client)!.fetchStatus, FetchStatus.idle);
      // One fetch cancelled, one made by the reset; the invalidation
      // joined it.
      expect(api.calls, {'device d1': 2, 'save': 1});
      expect(entries(client), ['devices/detail/d1: Query<Device>']);
      unsubscribe();
      client.clear();
    });

    testFakeAsync('an entry without data that nothing observes: reset, idle',
        (time) async {
      final (:client, :api, :queries) = world();
      final device = queries.detail('d1');
      // An entry made by an observer that never fetched.
      final observer = QueryObserver<Device, Device>(
        client,
        device.options().copyWith(enabled: Enabled.no),
      );
      final unsubscribe = observer.subscribe((result) {});
      unsubscribe();
      expect(device.state(client)!.hasData, isFalse);

      api.refuseNextWrite = true;
      final outcome = run(
        client,
        saveDevice(client, queries, api),
        const Device('d1', name: 'edited'),
      );
      await time.flushMicrotasks();
      expect(device.read(client), const Device('d1', name: 'edited'));
      await time.advance(ms(10));
      expect(await outcome, isStateError);
      final state = device.state(client)!;
      expect(state.hasData, isFalse);
      expect(state.status, QueryStatus.pending);
      expect(state.fetchStatus, FetchStatus.idle);
      expect(api.calls, {'save': 1});
      client.clear();
    });

    testFakeAsync('a cached null: written back as null, with its timestamp',
        (time) async {
      final (:client, :api, :queries) = world();
      final owner = queries.owner('attic');
      queries.detail('d2').write(client, const Device('d2', name: 'radio'));
      expect(await fetched(time, owner.fetch(client)), isNull);
      final fetchedAt = owner.state(client)!.dataUpdatedAt;
      expect(owner.state(client)!.hasData, isTrue);
      await time.advance(ms(100));

      api.refuseNextWrite = true;
      final outcome =
          run(client, assignOwner(client, queries, api, 'attic'), 'd2');
      await time.flushMicrotasks();
      expect(owner.read(client), const Device('d2', name: 'radio'));
      expect(entryOf(client, owner).dataType, typeOf<Device?>());

      await time.advance(ms(10));
      expect(await outcome, isStateError);
      final state = owner.state(client)!;
      expect(state.hasData, isTrue);
      expect(state.data, isNull);
      expect(state.status, QueryStatus.success);
      expect(state.dataUpdatedAt, fetchedAt);
      expect(entryOf(client, owner).dataType, typeOf<Device?>());
      // Not `Null`, and not a second entry.
      expect(entries(client), [
        'devices/detail/d2: Query<Device>',
        'devices/owner/attic: Query<Device?>',
      ]);
      client.clear();
    });

    testFakeAsync('a value over a cached value, and null over a value',
        (time) async {
      final (:client, :api, :queries) = world();
      final owner = queries.owner('hall');
      expect(await fetched(time, owner.fetch(client)), api.rows['d1']);
      final fetchedAt = owner.state(client)!.dataUpdatedAt;
      await time.advance(ms(100));

      // Optimistically nobody, refused: the device is back.
      api.refuseNextWrite = true;
      var outcome =
          run(client, assignOwner(client, queries, api, 'hall'), null);
      await time.flushMicrotasks();
      expect(owner.read(client), isNull);
      expect(owner.state(client)!.hasData, isTrue);
      await time.advance(ms(10));
      expect(await outcome, isStateError);
      expect(owner.read(client), api.rows['d1']);
      expect(owner.state(client)!.dataUpdatedAt, fetchedAt);

      // Optimistically nobody, accepted: null stays cached.
      outcome = run(client, assignOwner(client, queries, api, 'hall'), null);
      await time.advance(ms(10));
      expect(await outcome, isNull);
      expect(owner.read(client), isNull);
      expect(owner.state(client)!.hasData, isTrue);
      client.clear();
    });

    test('read alone cannot tell the three apart; state can', () {
      final (:client, api: _, :queries) = world();
      final absent = queries.owner('nowhere');
      final empty = queries.owner('empty');
      final nobody = queries.owner('attic');
      final unsubscribe = QueryObserver<Device?, Device?>(
        client,
        empty.options().copyWith(enabled: Enabled.no),
      ).subscribe((result) {});
      nobody.write(client, null);

      expect(
        [absent.read(client), empty.read(client), nobody.read(client)],
        [null, null, null],
      );
      expect(absent.state(client), isNull);
      expect(empty.state(client)!.hasData, isFalse);
      expect(nobody.state(client)!.hasData, isTrue);
      unsubscribe();
      client.clear();
    });
  });

  group('3. the server\'s answer is written into the cache', () {
    testFakeAsync('the detail and its row in the list, with no refetch',
        (time) async {
      final (:client, :api, :queries) = world();
      await fetched(time, queries.list.fetch(client));
      await fetched(time, queries.detail('d1').fetch(client));
      final calls = {...api.calls};

      final outcome = run(
        client,
        saveDeviceAndKeepTheAnswer(client, queries, api),
        const Device('d1', name: 'desk lamp'),
      );
      await time.advance(ms(10));
      const saved = Device('d1', name: 'desk lamp (saved)');
      expect(await outcome, saved);
      expect(queries.detail('d1').read(client), saved);
      expect(queries.list.read(client), [
        saved,
        const Device('d2', name: 'radio'),
        const Device('d3', name: 'kettle', room: 'kitchen'),
      ]);
      expect(api.calls, {...calls, 'save': 1});
      expect(entries(client), [
        'devices/detail/d1: Query<Device>',
        'devices/list: Query<List<Device>>',
      ]);
      client.clear();
    });

    testFakeAsync('a detail never read is created; a list never read is not',
        (time) async {
      final (:client, :api, :queries) = world();
      final outcome = run(
        client,
        saveDeviceAndKeepTheAnswer(client, queries, api),
        const Device('d2', name: 'radio'),
      );
      await time.advance(ms(10));
      expect(await outcome, const Device('d2', name: 'radio (saved)'));
      expect(entries(client), ['devices/detail/d2: Query<Device>']);
      client.clear();
    });

    testFakeAsync('a refused write leaves the cache as it was', (time) async {
      final (:client, :api, :queries) = world();
      await fetched(time, queries.detail('d1').fetch(client));
      api.refuseNextWrite = true;
      final outcome = run(
        client,
        saveDeviceAndKeepTheAnswer(client, queries, api),
        const Device('d1', name: 'desk lamp'),
      );
      await time.advance(ms(10));
      expect(await outcome, isStateError);
      expect(
        queries.detail('d1').read(client),
        const Device('d1', name: 'lamp'),
      );
      client.clear();
    });
  });

  group('4. a list is written and its family invalidated', () {
    testFakeAsync(
        'every cached detail is marked, the observed ones refetched, and '
        'the mutation waits for them', (time) async {
      final (:client, :api, :queries) = world();
      await fetched(time, queries.list.fetch(client));
      await fetched(time, queries.detail('d2').fetch(client));
      final owner = await fetched(time, queries.owner('hall').fetch(client));
      final unsubscribe = QueryObserver<Device, Device>(
        client,
        queries.detail('d1').options(),
      ).subscribe((result) {});
      await time.advance(ms(10));
      final calls = {...api.calls};

      var settled = false;
      final outcome = run(client, moveAllDevices(client, queries, api), 'loft')
          .whenComplete(() => settled = true);
      await time.advance(ms(10));
      // The answer is in the list at once; the details are stale, and the
      // one on screen is fetching.
      expect(
        queries.list.read(client)!.map((device) => device.room).toSet(),
        {'loft'},
      );
      expect(queries.list.state(client)!.isInvalidated, isFalse);
      expect(queries.detail('d1').state(client)!.isInvalidated, isTrue);
      expect(
        queries.detail('d1').state(client)!.fetchStatus,
        FetchStatus.fetching,
      );
      expect(queries.detail('d2').state(client)!.isInvalidated, isTrue);
      expect(
        queries.detail('d2').state(client)!.fetchStatus,
        FetchStatus.idle,
      );
      // Not a detail: the family's prefix does not reach it.
      expect(queries.owner('hall').state(client)!.isInvalidated, isFalse);
      expect(queries.owner('hall').read(client), owner);
      expect(settled, isFalse);

      await time.advance(ms(10));
      expect(settled, isTrue);
      expect(await outcome, hasLength(3));
      expect(queries.detail('d1').read(client)!.room, 'loft');
      expect(queries.detail('d2').read(client)!.room, 'hall');
      expect(api.calls, {...calls, 'moveAll': 1, 'device d1': 2});
      unsubscribe();
      client.clear();
    });
  });

  group('5. every cached detail is patched with updateAll', () {
    Future<World> cached(FakeTime time) async {
      final it = world();
      for (final id in ['d1', 'd2', 'd3']) {
        await fetched(time, it.queries.detail(id).fetch(it.client));
      }
      await fetched(time, it.queries.list.fetch(it.client));
      return it;
    }

    Map<String, String> rooms(World it) => {
          for (final (_, device) in it.queries.detail.readAll(it.client))
            device!.id: device.room,
        };

    testFakeAsync('patched at once, and only the family\'s entries',
        (time) async {
      final it = await cached(time);
      final (:client, :api, :queries) = it;
      final list = queries.list.read(client);
      final outcome = run(
        client,
        renameRoom(client, queries, api),
        (from: 'hall', to: 'lobby'),
      );
      await time.flushMicrotasks();
      expect(rooms(it), {'d1': 'lobby', 'd2': 'lobby', 'd3': 'kitchen'});
      // The list is another definition; the settle invalidates it.
      expect(identical(queries.list.read(client), list), isTrue);

      await time.advance(ms(10));
      expect(await outcome, isNull);
      expect(rooms(it), {'d1': 'lobby', 'd2': 'lobby', 'd3': 'kitchen'});
      expect(
        client.queryCache
            .findAll(filters: DeviceQueries.namespace.filters(stale: true)),
        hasLength(4),
      );
      expect(entries(client), [
        'devices/detail/d1: Query<Device>',
        'devices/detail/d2: Query<Device>',
        'devices/detail/d3: Query<Device>',
        'devices/list: Query<List<Device>>',
      ]);
      client.clear();
    });

    testFakeAsync(
        'refused: the devices it changed are put back, a neighbour\'s '
        'later write is kept', (time) async {
      final it = await cached(time);
      final (:client, :api, :queries) = it;
      api.refuseNextWrite = true;
      final outcome = run(
        client,
        renameRoom(client, queries, api),
        (from: 'hall', to: 'lobby'),
      );
      await time.flushMicrotasks();
      expect(rooms(it), {'d1': 'lobby', 'd2': 'lobby', 'd3': 'kitchen'});
      // Something else writes a device this mutation did not touch.
      queries
          .detail('d3')
          .update(client, (device) => device?.copyWith(name: 'new kettle'));

      await time.advance(ms(10));
      expect(await outcome, isStateError);
      expect(rooms(it), {'d1': 'hall', 'd2': 'hall', 'd3': 'kitchen'});
      expect(queries.detail('d3').read(client)!.name, 'new kettle');
      expect(queries.detail('d1').read(client), api.rows['d1']);
      client.clear();
    });

    testFakeAsync(
        'refused, a changed device removed in between: the rollback makes '
        'its entry again, from the key alone', (time) async {
      final it = await cached(time);
      final (:client, :api, :queries) = it;
      api.refuseNextWrite = true;
      final outcome = run(
        client,
        renameRoom(client, queries, api),
        (from: 'hall', to: 'lobby'),
      );
      await time.flushMicrotasks();
      queries.detail('d2').remove(client);
      expect(rooms(it), {'d1': 'lobby', 'd3': 'kitchen'});

      await time.advance(ms(10));
      expect(await outcome, isStateError);
      expect(rooms(it), {'d1': 'hall', 'd2': 'hall', 'd3': 'kitchen'});
      expect(entries(client), [
        'devices/detail/d1: Query<Device>',
        'devices/detail/d2: Query<Device>',
        'devices/detail/d3: Query<Device>',
        'devices/list: Query<List<Device>>',
      ]);
      // The entry that stayed kept the definition's fetch function; the one
      // made again has none, until the query is used again.
      expect(entryOf(client, queries.detail('d1')).options.queryFn, isNotNull);
      expect(entryOf(client, queries.detail('d2')).options.queryFn, isNull);
      final calls = api.calls['device d2'];
      expect(
        await fetched(time, queries.detail('d2').fetch(client)),
        api.rows['d2'],
      );
      expect(api.calls['device d2'], calls! + 1);
      expect(entryOf(client, queries.detail('d2')).options.queryFn, isNotNull);
      client.clear();
    });

    testFakeAsync('with a detail\'s fetch in flight: cancelled, then patched',
        (time) async {
      final it = await cached(time);
      final (:client, :api, :queries) = it;
      queries.detail.refetch(client).ignore();
      await time.advance(ms(5));
      expect(client.isFetching(filters: queries.detail.filters()), 3);

      final outcome = run(
        client,
        renameRoom(client, queries, api),
        (from: 'hall', to: 'lobby'),
      );
      await time.flushMicrotasks();
      expect(client.isFetching(filters: queries.detail.filters()), 0);
      expect(rooms(it), {'d1': 'lobby', 'd2': 'lobby', 'd3': 'kitchen'});
      await time.advance(ms(5));
      // The cancelled responses would have said 'hall'.
      expect(rooms(it), {'d1': 'lobby', 'd2': 'lobby', 'd3': 'kitchen'});
      await time.advance(ms(5));
      expect(await outcome, isNull);
      client.clear();
    });
  });

  group('6. an infinite query, with a request in flight', () {
    EventFeed feed(QueryClient client, DeviceQueries queries) =>
        queries.events.read(client)!;

    testFakeAsync('cancel, patch, fail, roll back, refetch: every step',
        (time) async {
      final (:client, :api, :queries) = world();
      final events = queries.events;
      final observer = InfiniteQueryObserver(client, events.options());
      final unsubscribe = observer.subscribe((result) {});
      await time.advance(ms(10));
      observer.fetchNextPage().ignore();
      await time.advance(ms(10));
      final before = feed(client, queries);
      final fetchedAt = events.state(client)!.dataUpdatedAt;
      expect(before.pages.map((page) => page.length), [20, 20]);
      expect(before.pageParams, [1 << 30, 31]);
      expect(before.runtimeType, typeOf<EventFeed>());

      // A refetch of both pages on its way.
      await time.advance(ms(100));
      events.refetch(client).ignore();
      await time.advance(ms(15));
      expect(events.state(client)!.fetchStatus, FetchStatus.fetching);

      api.refuseNextWrite = true;
      final outcome = run(client, logEvent(client, queries, api), 'door');

      await time.flushMicrotasks();
      var state = events.state(client)!;
      expect(state.fetchStatus, FetchStatus.idle);
      expect(state.status, QueryStatus.success);
      expect(state.dataUpdatedAt, time.now);
      var data = state.data!;
      expect(data.pages.first.first, const Event(-1, 'door'));
      expect(data.pages.map((page) => page.length), [21, 20]);
      expect(data.pageParams, before.pageParams);
      // The stored value has the declared page types, as the entry does.
      expect(data.runtimeType, typeOf<EventFeed>());
      expect(entryOf(client, events).dataType, typeOf<EventFeed>());
      expect(entries(client), [
        'devices/events: Query<${typeOf<EventFeed>()}>',
      ]);

      // When the cancelled refetch would have finished its second page.
      await time.advance(ms(5));
      expect(feed(client, queries).pages.first.first, const Event(-1, 'door'));
      expect(events.state(client)!.fetchStatus, FetchStatus.idle);

      // Refused: the pages from before, and their timestamp; invalidated
      // and refetching.
      await time.advance(ms(5));
      state = events.state(client)!;
      data = state.data!;
      expect(data.pages, before.pages);
      expect(data.pageParams, before.pageParams);
      expect(state.dataUpdatedAt, fetchedAt);
      expect(data.runtimeType, typeOf<EventFeed>());
      expect(state.isInvalidated, isTrue);
      expect(state.fetchStatus, FetchStatus.fetching);
      expect(entryOf(client, events).dataType, typeOf<EventFeed>());

      await time.advance(ms(20));
      state = events.state(client)!;
      expect(state.fetchStatus, FetchStatus.idle);
      expect(state.isInvalidated, isFalse);
      expect(state.dataUpdatedAt, isNot(fetchedAt));
      expect(state.data!.pages, before.pages);
      expect(await outcome, isStateError);
      // Two pages, two cancelled halfway (one answered, one did not), two
      // for the refetch.
      expect(api.calls, {'events': 6, 'log': 1});
      // The observer still pages on from where it was.
      expect(observer.hasNextPage, isTrue);
      unsubscribe();
      client.clear();
    });

    testFakeAsync('accepted: the server\'s row replaces the optimistic one',
        (time) async {
      final (:client, :api, :queries) = world();
      final events = queries.events;
      final unsubscribe = InfiniteQueryObserver(client, events.options())
          .subscribe((result) {});
      await time.advance(ms(10));

      final outcome = run(client, logEvent(client, queries, api), 'door');
      await time.flushMicrotasks();
      expect(feed(client, queries).pages.first.first, const Event(-1, 'door'));
      await time.advance(ms(20));
      expect(await outcome, const Event(51, 'door'));
      final data = feed(client, queries);
      expect(data.pages.single.first, const Event(51, 'door'));
      expect(data.pages.single, hasLength(20));
      expect(data.runtimeType, typeOf<EventFeed>());
      unsubscribe();
      client.clear();
    });

    testFakeAsync('a feed nobody opened: nothing is created or restored',
        (time) async {
      final (:client, :api, :queries) = world();
      api.refuseNextWrite = true;
      final outcome = run(client, logEvent(client, queries, api), 'door');
      await time.flushMicrotasks();
      expect(entries(client), isEmpty);
      await time.advance(ms(10));
      expect(await outcome, isStateError);
      expect(entries(client), isEmpty);
      client.clear();
    });

    // A patch built from literals has narrower type arguments than the
    // feed declares. Stored through the reference it is the declared type,
    // so the rollback and the next page still fit.
    testFakeAsync('a narrower optimistic value is stored under the page types',
        (time) async {
      final (:client, :api, :queries) = world();
      final events = queries.events;
      final unsubscribe = InfiniteQueryObserver(client, events.options())
          .subscribe((result) {});
      await time.advance(ms(10));

      api.refuseNextWrite = true;
      final outcome = run(
        client,
        MutationOptions<Event, String, Snapshot<EventFeed>>(
          mutationFn: api.log,
          onMutate: (text) async {
            await events.cancel(client);
            final before = events.state(client);
            events.write(
              client,
              InfiniteData<List<Never>, int>(
                pages: const [[]],
                pageParams: const [0],
              ),
            );
            return (before: before);
          },
          onError: (error, stackTrace, text, snapshot) =>
              restore(client, events, snapshot!.before),
        ),
        'door',
      );
      await time.flushMicrotasks();
      final optimistic = feed(client, queries);
      expect(optimistic.pages, [<Event>[]]);
      expect(optimistic.runtimeType, typeOf<EventFeed>());
      // What a narrower value would refuse.
      expect(
        optimistic
            .copyWith(pages: [
              [const Event(1, 'fits')],
            ])
            .pages
            .single,
        [const Event(1, 'fits')],
      );
      await time.advance(ms(10));
      expect(await outcome, isStateError);
      expect(feed(client, queries).pages.single, hasLength(20));
      expect(feed(client, queries).runtimeType, typeOf<EventFeed>());
      unsubscribe();
      client.clear();
    });
  });

  group('a refused write leaves no half-written cache', () {
    // Each recipe once more, refused, over one populated cache: afterwards
    // every entry holds what it held and the type it had.
    testFakeAsync('every recipe, refused: entries, types and data as before',
        (time) async {
      final (:client, :api, :queries) = world();
      for (final id in ['d1', 'd2', 'd3']) {
        await fetched(time, queries.detail(id).fetch(client));
      }
      await fetched(time, queries.list.fetch(client));
      await fetched(time, queries.owner('hall').fetch(client));
      await fetched(time, queries.owner('attic').fetch(client));
      await fetched(time, queries.events.fetch(client));
      await time.advance(ms(100));

      // The timestamp is left out: the first recipe's rollback is a plain
      // write, which stamps the entry anew; the cases above look at it
      // where a recipe keeps it.
      Map<String, Object?> picture() => {
            for (final query in client.queryCache.findAll())
              '${query.queryKey.parts.join('/')}: Query<${query.dataType}>': [
                switch (query.state.data) {
                  final EventFeed feed => [feed.pages, feed.pageParams],
                  final data => data,
                },
                query.state.status,
                query.state.fetchStatus,
              ],
          };
      final before = picture();
      expect(before, hasLength(7));

      final refused = <Future<Object?> Function()>[
        () => run(client, renameDevice(client, queries, api, 'd1'), 'x'),
        () => run(
              client,
              saveDevice(client, queries, api),
              const Device('d2', name: 'x'),
            ),
        () => run(client, assignOwner(client, queries, api, 'attic'), 'd3'),
        () => run(client, assignOwner(client, queries, api, 'hall'), null),
        () => run(
              client,
              saveDeviceAndKeepTheAnswer(client, queries, api),
              const Device('d3', name: 'x'),
            ),
        () => run(client, moveAllDevices(client, queries, api), 'x'),
        () => run(
              client,
              renameRoom(client, queries, api),
              (from: 'hall', to: 'x'),
            ),
        () => run(client, logEvent(client, queries, api), 'x'),
      ];
      for (final start in refused) {
        api.refuseNextWrite = true;
        final outcome = start();
        await time.advance(ms(10));
        expect(await outcome, isStateError);
        // Nothing observes these entries, so the settle's invalidation
        // marks and does not fetch: what is left is the rollback's work.
        expect(picture(), before);
      }
      client.clear();
    });
  });
}
