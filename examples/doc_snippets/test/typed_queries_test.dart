// The behaviour the typed query definitions guide and its neighbours claim,
// run against the samples in lib/typed_queries.dart. The regions marked here
// are shown on those pages as they are: a reader sees the assertions.
import 'package:doc_snippets/typed_queries.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

const lamp = Device(id: 'd1', name: 'Hall lamp', room: 'hall');

void main() {
  late QueryClient client;

  setUp(() => client = QueryClient());
  tearDown(() => client.clear());

  test('a definition puts its namespace, its name and its input in the key',
      () {
    // >>> guides/typed-queries.md#keys
    final devices = queries.devices;

    expect(devices.list.key.rawKey, QueryKey(['devices', 'list']));
    expect(
        devices.detail('d1').key.rawKey, QueryKey(['devices', 'detail', 'd1']));
    expect(devices.detail.rawKey, QueryKey(['devices', 'detail']));

    // Equal inputs give equal references: one entry, however often it is
    // asked for.
    expect(devices.detail('d1'), devices.detail('d1'));
    // <<<
  });

  test('the query-keys page: the keys a definition builds, and its prefixes',
      () async {
    // >>> guides/query-keys.md#definition-keys
    final devices = queries.devices;

    expect(devices.list.key.rawKey, QueryKey(['devices', 'list']));
    expect(devices.inRoom('kitchen').key.rawKey,
        QueryKey(['devices', 'inRoom', 'kitchen']));

    await devices.detail('d1').invalidate(client); // one device
    await devices.detail.invalidate(client); // every device detail
    await DeviceQueries.namespace.invalidate(client); // all about devices
    // <<<
  });

  test('a reference and a raw key with the same parts are one entry', () {
    // >>> guides/typed-queries.md#shared
    queries.devices.detail('d1').write(client, lamp);

    // The raw client sees the same entry, under the same parts.
    expect(
      client.getQueryData<Device>(QueryKey(['devices', 'detail', 'd1'])),
      lamp,
    );
    // <<<
  });

  test('reading and writing through a reference', () async {
    await readAndWrite(client);
    expect(
      queries.devices.detail('d1').read(client),
      const Device(id: 'd1', name: 'Porch lamp', room: 'porch'),
    );
  });

  test('a list fetch seeds every detail, through the sibling definition',
      () async {
    final devices = await queries.devices.list.fetch(client);
    expect(devices, hasLength(3));
    expect(queries.devices.detail('d3').read(client)?.name, 'Oven');
  });

  test('the lifecycle operations and the target list run', () async {
    await queries.devices.inRoom('hall').fetch(client);
    await lifecycle(client);
    expect(queries.devices.inRoom('hall').state(client), isNull,
        reason: 'removed');
    await targetList(client);
  });

  test('a typed key reads and writes its entry, and is a value', () {
    typedKeys(client, lamp);
    expect(queries.devices.detail('d1').read(client), lamp);
  });

  test('the seeded wrapper starts from a cached room list', () async {
    await queries.devices.inRoom('hall').fetch(client);
    final fetchesBefore = repository.fetches;

    final observer = QueryObserver(client, deviceQuery(client, 'd2'));
    expect(observer.currentResult.dataOrNull?.name, 'Hall heater');
    expect(repository.fetches, fetchesBefore);
  });

  test('an infinite reference reads and writes its InfiniteData', () async {
    await queries.events.feed.fetch(client);
    await infiniteReadWrite(client);
    final data = queries.events.feed.read(client)!;
    expect(data.pages.first.first.text, 'Renamed');
    expect(data.pageParams, [0]);
  });

  group('renameRoom', () {
    Future<void> fetchDetails() async {
      for (final id in ['d1', 'd2', 'd3']) {
        await queries.devices.detail(id).fetch(client);
      }
    }

    test('patches every cached detail of the room', () async {
      await fetchDetails();
      await MutationObserver(client, renameRoom(client))
          .mutateAsync((from: 'hall', to: 'lobby'));

      final rooms = [
        for (final (_, device) in queries.devices.detail.readAll(client))
          device?.room,
      ];
      expect(rooms, unorderedEquals(['lobby', 'lobby', 'kitchen']));
      await repository.renameRoom('lobby', 'hall');
    });

    test('puts each changed device back through its typed key', () async {
      await fetchDetails();
      repository.failNextWrite = Exception('offline');
      await expectLater(
        MutationObserver(client, renameRoom(client))
            .mutateAsync((from: 'hall', to: 'lobby')),
        throwsException,
      );
      expect(queries.devices.detail('d1').read(client)?.room, 'hall');
      expect(queries.devices.detail('d2').read(client)?.room, 'hall');
    });
  });

  test('options through a wider parameter make a wider entry', () async {
    final device = queries.devices.detail('d1');
    await warmWide(client, device.options());
    expect(() => device.read(client), throwsA(isA<QueryDataTypeError>()));
    expect(
        () => device.write(client, lamp), throwsA(isA<QueryDataTypeError>()));

    client.clear();
    await warm(client, device.options());
    expect(device.read(client), lamp);
  });

  // >>> guides/typed-queries.md#migrate-identity
  test('the room keys did not move', () {
    expect(roomDetail('r1').key.rawKey, roomKey('r1'));
    expect(roomList(null).key.rawKey, roomListKey(null));
    expect(roomList(2).key.rawKey, roomListKey(2));
  });
  // <<<

  group('limits and errors', () {
    test('an entry a typed key creates has no fetch function', () async {
      final key = queries.devices.detail('d1').key..write(client, lamp);
      await queries.devices.detail.refetch(client);
      expect(key.state(client)!.error, isA<MissingQueryFunctionError>());
      expect(key.read(client), lamp, reason: 'the data is kept');

      // A fetch through the reference brings the definition's function.
      await queries.devices.detail('d1').fetch(client);
      await queries.devices.detail.refetch(client);
      expect(key.state(client)!.status, QueryStatus.success);
    });

    test('a typed write into an entry of another type writes nothing', () {
      final raw = queries.devices.detail('d1').key.rawKey;
      client.setQueryData<Device?>(raw, lamp);
      expect(
        () => queries.devices.detail('d1').write(client, lamp),
        throwsA(isA<QueryDataTypeError>()
            .having((e) => e.expected, 'expected', Device)
            .having((e) => e.actual, 'actual', _typeOf<Device?>())),
      );
      expect(client.getQueryData<Device?>(raw), lamp);
    });

    test('a widened reference throws before it writes', () {
      final QueryRef<Object?> widened = queries.devices.detail('d1');
      expect(() => widened.write(client, 'not a device'),
          throwsA(isA<TypeError>()));
      expect(queries.devices.detail('d1').state(client), isNull);
    });

    test('configure returning options of a narrower type is a StateError', () {
      final owner = QueryFamily<String, Device?>(
        namespace: DeviceQueries.namespace,
        name: 'owner',
        configure: (base, room) => QueryObserverOptions<Device>(
          queryKey: base.queryKey,
        ),
      );
      expect(
        () => owner('hall').options(),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains("definition's own type"))),
      );
    });

    test('a debug build refuses a top type as an input', () {
      expect(
        () => QueryFamily<Object?, Device>(
          namespace: DeviceQueries.namespace,
          name: 'any',
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('read cannot tell a cached null from no entry; state can', () {
      final owner = QueryFamily<String, Device?>(
        namespace: DeviceQueries.namespace,
        name: 'owner',
      );
      owner('hall').write(client, null);
      expect(owner('hall').read(client), isNull);
      expect(owner('kitchen').read(client), isNull);
      expect(owner('hall').state(client)?.hasData, isTrue);
      expect(owner('kitchen').state(client), isNull);
    });

    test('a record input with a list needs keyOf', () {
      final withoutKeyOf = QueryFamily<({List<String> tags}), int>(
        namespace: DeviceQueries.namespace,
        name: 'tagged',
      );
      expect(withoutKeyOf((tags: ['a'])), isNot(withoutKeyOf((tags: ['a']))));
      expect(
        deviceSearch((room: 'hall', tags: ['a'])),
        deviceSearch((room: 'hall', tags: ['a'])),
      );
    });

    test('select changes what a reader sees, not the cached type', () async {
      final device = queries.devices.detail('d1');
      final observer = QueryObserver(
        client,
        device.options().withSelect((device) => device.name),
      );
      final unsubscribe = observer.subscribe((_) {});
      await device.fetch(client);
      expect(observer.currentResult.dataOrNull, 'Hall lamp');
      expect(device.read(client), lamp);
      unsubscribe();
    });
  });
}

Type _typeOf<T>() => T;
