/// Typed query definitions over plain queries: namespaces, definitions,
/// families, references and typed keys, and what each does to the client's
/// cache. Port-only behaviour (upstream has no such layer); PORTING_NOTES'
/// "Typed query definitions" section says what each group is for. The
/// infinite twins are in `infinite_query_definition_test.dart`.
library;

import 'dart:async';

import 'package:query_kit/query_kit.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

class Device {
  const Device(this.id, {this.name = ''});

  final String id;
  final String name;

  Device renamed(String name) => Device(id, name: name);

  @override
  bool operator ==(Object other) =>
      other is Device &&
      other.runtimeType == runtimeType &&
      other.id == id &&
      other.name == name;

  @override
  int get hashCode => Object.hash(runtimeType, id, name);

  @override
  String toString() => '$runtimeType($id, $name)';
}

class Thermostat extends Device {
  const Thermostat(super.id, {super.name});
}

sealed class Reading {
  const Reading();
}

final class Temperature extends Reading {
  const Temperature(this.celsius);

  final double celsius;

  @override
  bool operator ==(Object other) =>
      other is Temperature && other.celsius == celsius;

  @override
  int get hashCode => celsius.hashCode;
}

Type typeOf<T>() => T;

/// Whether this run evaluates `assert`.
bool get assertionsOn {
  var on = false;
  assert(() {
    on = true;
    return true;
  }());
  return on;
}

/// A matcher for the cache's type error with exactly these fields.
Matcher dataTypeError(QueryKey key, Type expected, Type actual) =>
    isA<QueryDataTypeError>()
        .having((e) => e.queryKey, 'queryKey', key)
        .having((e) => e.expected, 'expected', expected)
        .having((e) => e.actual, 'actual', actual);

/// What a write through a widened receiver throws. The VM and a checked
/// JavaScript build refuse the argument at the call, a `TypeError`; a
/// JavaScript build at `-O3` or `-O4` reaches the library's own check
/// (`tool/typed_query_fixtures/runtime/` runs those).
final Matcher refusedAtRuntime = throwsA(
  anyOf(isA<TypeError>(), isA<QueryDataTypeError>(), isA<ArgumentError>()),
);

final devices = QueryNamespace(['devices']);

QueryFamily<String, Device> deviceDetail({
  FutureOr<Device> Function(String id, QueryFunctionContext context)? queryFn,
  QueryObserverOptions<Device> Function(
    QueryObserverOptions<Device> base,
    String id,
  )? configure,
}) =>
    QueryFamily<String, Device>(
      namespace: devices,
      name: 'detail',
      queryFn: queryFn ?? (id, context) => Device(id),
      configure: configure,
    );

QueryDefinition<List<Device>> deviceList({
  FutureOr<List<Device>> Function(QueryFunctionContext context)? queryFn,
  QueryObserverOptions<List<Device>> Function(
    QueryObserverOptions<List<Device>> base,
  )? configure,
}) =>
    QueryDefinition<List<Device>>(
      namespace: devices,
      name: 'list',
      queryFn: queryFn ?? (context) => const [Device('d1'), Device('d2')],
      configure: configure,
    );

/// The data type of the entry under [key], or `null` when there is none.
Type? entryType(QueryClient client, QueryKey key) => client.queryCache
    .findAll(filters: QueryFilters(queryKey: key, exact: true))
    .firstOrNull
    ?.dataType;

/// The one entry under [key].
Query<Object?> entry(QueryClient client, QueryKey key) => client.queryCache
    .findAll(filters: QueryFilters(queryKey: key, exact: true))
    .single;

/// Records every cache event as `name key`.
List<String> recordEvents(QueryClient client) {
  final events = <String>[];
  client.queryCache.subscribe(
    (event) => events
        .add('${eventName(event)} ${event.query.queryKey.parts.join('/')}'),
  );
  return events;
}

void main() {
  group('keys and identity', () {
    test('a definition\'s key is its namespace, then its name', () {
      final list = deviceList();
      expect(devices.rawKey, QueryKey(['devices']));
      expect(list.key.rawKey, QueryKey(['devices', 'list']));
      expect(list.key.dataType, typeOf<List<Device>>());
    });

    test('a family\'s reference adds the input, or what keyOf makes of it', () {
      final detail = deviceDetail();
      expect(detail.rawKey, QueryKey(['devices', 'detail']));
      expect(detail('d1').key.rawKey, QueryKey(['devices', 'detail', 'd1']));

      final search = QueryFamily<({String room, List<String> tags}), int>(
        namespace: devices,
        name: 'search',
        keyOf: (input) => [input.room, input.tags],
      );
      expect(
        search((room: 'hall', tags: ['a', 'b'])).key.rawKey,
        QueryKey([
          'devices',
          'search',
          'hall',
          ['a', 'b'],
        ]),
      );
    });

    test('a namespace of several parts prefixes every key under it', () {
      final tenant = QueryNamespace(['tenant', 7, 'devices']);
      final detail = QueryFamily<String, Device>(
        namespace: tenant,
        name: 'detail',
      );
      expect(
        detail('d1').key.rawKey,
        QueryKey(['tenant', 7, 'devices', 'detail', 'd1']),
      );
    });

    test('references from equal inputs are equal, and not the same object', () {
      final detail = deviceDetail();
      final a = detail('d1');
      final b = detail('d1');
      expect(identical(a, b), isFalse);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.key, b.key);
      expect(a.key.hashCode, b.key.hashCode);
      expect(a, isNot(detail('d2')));
      expect({a, b, detail('d2')}, hasLength(2));
    });

    test('a definition made again is the same query: nothing is registered',
        () {
      // Two instances with different closures, as a hot reload or a second
      // repository instance leaves behind.
      final first = deviceDetail(queryFn: (id, context) => Device(id));
      final second = deviceDetail(queryFn: (id, context) => Thermostat(id));
      expect(first('d1'), second('d1'));
      expect(first('d1').hashCode, second('d1').hashCode);
      expect(deviceList(), deviceList());

      final client = testClient();
      first('d1').write(client, const Device('d1', name: 'first'));
      expect(second('d1').read(client), const Device('d1', name: 'first'));
      expect(client.queryCache.findAll(), hasLength(1));
      client.clear();
    });

    test('equality is the entry: its key and its data type, not its maker', () {
      final detail = deviceDetail();
      // The same key by another route.
      final direct = QueryDefinition<Device>(
        namespace: QueryNamespace(['devices', 'detail']),
        name: 'd1',
      );
      expect(direct, detail('d1'));
      expect(direct.hashCode, detail('d1').hashCode);

      // The same key under another data type is another reference.
      final nullable = QueryFamily<String, Device?>(
        namespace: devices,
        name: 'detail',
      );
      expect(nullable('d1'), isNot(detail('d1')));
      expect(nullable('d1').key, isNot(detail('d1').key));
      expect(nullable('d1').key.rawKey, detail('d1').key.rawKey);

      // And a plain reference is never an infinite one.
      final plain = QueryDefinition<InfiniteData<int, int>>(
        namespace: devices,
        name: 'feed',
      );
      final infinite = InfiniteQueryDefinition<int, int>(
        namespace: devices,
        name: 'feed',
        pageFn: (context) => context.pageParam,
        initialPageParam: 0,
        getNextPageParam: (page, pages, pageParam, pageParams) => null,
      );
      expect(plain.key, infinite.key);
      expect(plain, isNot(infinite));
      expect(infinite, isNot(plain));
    });

    test('a widened reference is still equal to itself narrow', () {
      final detail = deviceDetail();
      final QueryRef<Object?> wide = detail('d1');
      final QueryEntryRef<Object?> wider = wide;
      expect(wide, detail('d1'));
      expect(wider.key, detail('d1').key);
      expect(wide.key.dataType, Device);
    });

    test('inputs are compared as key parts: records, lists and maps by value',
        () {
      final byRecord = QueryFamily<({String room, int page}), int>(
        namespace: devices,
        name: 'page',
      );
      expect(
        byRecord((room: 'hall', page: 1)),
        byRecord((room: 'hall', page: 1)),
      );
      expect(
        byRecord((room: 'hall', page: 1)),
        isNot(byRecord((room: 'hall', page: 2))),
      );

      final byList = QueryFamily<List<String>, int>(
        namespace: devices,
        name: 'ids',
      );
      expect(byList(['a', 'b']), byList(['a', 'b']));

      final byMap = QueryFamily<Map<String, int>, int>(
        namespace: devices,
        name: 'filter',
      );
      expect(byMap({'a': 1, 'b': 2}), byMap({'b': 2, 'a': 1}));
    });

    test('the key is computed at binding: a list changed later moves nothing',
        () {
      final byList = QueryFamily<List<String>, int>(
        namespace: devices,
        name: 'ids',
      );
      final ids = ['a'];
      final ref = byList(ids);
      ids.add('b');
      expect(ref, byList(['a']));
      expect(ref, isNot(byList(ids)));
    });

    // The documented limit: a record compares its fields with `==`, a list
    // is equal only to itself, and `QueryKey` cannot look into a record.
    test('a record holding a list is two entries without keyOf, one with it',
        () {
      final without = QueryFamily<({String room, List<String> tags}), int>(
        namespace: devices,
        name: 'search',
      );
      expect(
        without((room: 'hall', tags: ['a'])),
        isNot(without((room: 'hall', tags: ['a']))),
      );

      final withKeyOf = QueryFamily<({String room, List<String> tags}), int>(
        namespace: devices,
        name: 'search',
        keyOf: (input) => [input.room, input.tags],
      );
      expect(
        withKeyOf((room: 'hall', tags: ['a'])),
        withKeyOf((room: 'hall', tags: ['a'])),
      );
    });

    test('a typed key is a value: a map key that still reads its entry', () {
      final detail = deviceDetail();
      final client = testClient();
      detail('d1').write(client, const Device('d1', name: 'one'));

      final names = <TypedQueryKey<Device>, String>{
        detail('d1').key: 'first',
      };
      expect(names[detail('d1').key], 'first');
      expect(names[detail('d2').key], isNull);
      expect(names.keys.single.read(client), const Device('d1', name: 'one'));
      expect(names.keys.single.state(client)!.status, QueryStatus.success);
      client.clear();
    });

    test('toString names the kind, the types and the key', () {
      final detail = deviceDetail();
      expect('$devices', 'QueryNamespace(${devices.rawKey.debugString})');
      expect(
        '$detail',
        'QueryFamily<String, Device>(${detail.rawKey.debugString})',
      );
      expect(
        '${detail('d1')}',
        'QueryRef<Device>(${detail('d1').key.rawKey.debugString})',
      );
      expect(
        '${detail('d1').key}',
        'TypedQueryKey<Device>(${detail('d1').key.rawKey.debugString})',
      );
      expect(
        '${deviceList()}',
        'QueryRef<List<Device>>(${deviceList().key.rawKey.debugString})',
      );
    });

    test('a target is one of four kinds, and a switch over it is exhaustive',
        () {
      String kind(QueryTarget target) => switch (target) {
            QueryNamespace() => 'namespace',
            QueryFamily() => 'family',
            InfiniteQueryFamily() => 'infinite family',
            QueryEntryRef() => switch (target) {
                QueryRef() => 'reference',
                InfiniteQueryRef() => 'infinite reference',
              },
          };
      expect(
        [devices, deviceDetail(), deviceDetail()('d1'), deviceList()].map(kind),
        ['namespace', 'family', 'reference', 'reference'],
      );
    });
  });

  group('declaring and binding do no work', () {
    testFakeAsync('no entry, event, timer, fetch or configure call',
        (time) async {
      final client = testClient();
      final events = recordEvents(client);
      var fetches = 0;
      var configured = 0;

      final namespace = QueryNamespace(['idle']);
      final list = QueryDefinition<List<Device>>(
        namespace: namespace,
        name: 'list',
        queryFn: (context) {
          fetches++;
          return const [];
        },
        configure: (base) {
          configured++;
          return base;
        },
      );
      final detail = QueryFamily<String, Device>(
        namespace: namespace,
        name: 'detail',
        queryFn: (id, context) {
          fetches++;
          return Device(id);
        },
        configure: (base, id) {
          configured++;
          return base;
        },
      );
      final ref = detail('d1');
      // Everything a reference offers that is not a cache operation.
      expect(ref == detail('d1'), isTrue);
      expect(ref.key.dataType, Device);
      expect(ref.filters().queryKey, ref.key.rawKey);
      expect('$ref $list $namespace', isNotEmpty);
      expect(configured, 0);

      // Options are made without a client, and run `configure`, no more.
      ref.options();
      list.options();
      expect(configured, 2);

      // A read of nothing leaves nothing behind.
      expect(ref.read(client), isNull);
      expect(ref.state(client), isNull);
      expect(list.key.read(client), isNull);
      expect(detail.readAll(client), isEmpty);

      await time.flushMicrotasks();
      expect(fetches, 0);
      expect(events, isEmpty);
      expect(client.queryCache.findAll(), isEmpty);
      expect(time.pendingTimers, 0);
    });

    test('two clients are independent: a reference holds none', () {
      final detail = deviceDetail();
      final ref = detail('d1');
      final a = testClient();
      final b = testClient();
      ref.write(a, const Device('d1', name: 'a'));
      expect(ref.read(a), const Device('d1', name: 'a'));
      expect(ref.read(b), isNull);
      expect(ref.state(b), isNull);
      ref.write(b, const Device('d1', name: 'b'));
      expect(ref.read(a), const Device('d1', name: 'a'));
      detail.remove(a);
      expect(ref.read(b), const Device('d1', name: 'b'));
      a.clear();
      b.clear();
    });
  });

  group('a reference and a plain key are one entry', () {
    test('a typed write is read through the plain key, and the reverse', () {
      final client = testClient();
      final ref = deviceDetail()('d1');
      ref.write(client, const Device('d1', name: 'typed'));
      expect(
        client.getQueryData<Device>(ref.key.rawKey),
        const Device('d1', name: 'typed'),
      );

      client.setQueryData<Device>(
        QueryKey(['devices', 'detail', 'd1']),
        const Device('d1', name: 'raw'),
      );
      expect(ref.read(client), const Device('d1', name: 'raw'));
      expect(ref.state(client)!.dataUpdateCount, 2);
      expect(client.queryCache.findAll(), hasLength(1));
      client.clear();
    });

    testFakeAsync(
        'an observer on plain options and one on the reference\'s options '
        'share a fetch and see each other\'s writes', (time) async {
      final client = testClient();
      var fetches = 0;
      final detail = deviceDetail(
        queryFn: (id, context) async {
          fetches++;
          await sleep(ms(10));
          return Device(id, name: 'fetched');
        },
      );
      final ref = detail('d1');

      final typed = QueryObserver<Device, Device>(client, ref.options());
      final raw = QueryObserver<Device, Device>(
        client,
        QueryObserverOptions<Device>(
          queryKey: QueryKey(['devices', 'detail', 'd1']),
          queryFn: (context) async {
            fetches++;
            await sleep(ms(10));
            return const Device('d1', name: 'raw fetch');
          },
        ),
      );
      final typedSeen = <Device?>[];
      final rawSeen = <Device?>[];
      final unsubscribeTyped =
          typed.subscribe((result) => typedSeen.add(result.dataOrNull));
      final unsubscribeRaw =
          raw.subscribe((result) => rawSeen.add(result.dataOrNull));

      await time.advance(ms(10));
      expect(fetches, 1);
      expect(typedSeen.last, const Device('d1', name: 'fetched'));
      expect(rawSeen.last, const Device('d1', name: 'fetched'));

      ref.write(client, const Device('d1', name: 'typed write'));
      expect(rawSeen.last, const Device('d1', name: 'typed write'));
      client.setQueryData<Device>(
        ref.key.rawKey,
        const Device('d1', name: 'raw write'),
      );
      expect(typedSeen.last, const Device('d1', name: 'raw write'));

      unsubscribeTyped();
      unsubscribeRaw();
      client.clear();
    });

    testFakeAsync('fetch joins a client.query in flight on the same key',
        (time) async {
      final client = testClient();
      var fetches = 0;
      final ref = deviceDetail(
        queryFn: (id, context) async {
          fetches++;
          await sleep(ms(10));
          return Device(id, name: 'typed');
        },
      )('d1');

      final raw = client.query<Device>(
        QueryOptions<Device>(
          queryKey: ref.key.rawKey,
          queryFn: (context) async {
            fetches++;
            await sleep(ms(10));
            return const Device('d1', name: 'raw');
          },
        ),
      );
      final typed = ref.fetch(client);
      await time.advance(ms(10));
      expect(fetches, 1);
      expect(await raw, const Device('d1', name: 'raw'));
      expect(await typed, const Device('d1', name: 'raw'));
      client.clear();
    });
  });

  group('a first write creates the declared type', () {
    test('a sealed base written with a concrete variant', () {
      final client = testClient();
      final reading = QueryFamily<String, Reading>(
        namespace: devices,
        name: 'reading',
      );
      final ref = reading('d1');
      expect(ref.write(client, const Temperature(21)), const Temperature(21));
      expect(entryType(client, ref.key.rawKey), Reading);
      expect(ref.read(client), const Temperature(21));

      // The control: the client infers the entry from the value, and the
      // typed read of that entry is refused.
      final other = reading('d2');
      client.setQueryData(other.key.rawKey, const Temperature(21));
      expect(entryType(client, other.key.rawKey), Temperature);
      expect(
        () => other.read(client),
        throwsA(dataTypeError(other.key.rawKey, Reading, Temperature)),
      );
      client.clear();
    });

    test('a List<Device> written with a narrower literal', () {
      final client = testClient();
      final list = deviceList();
      list.write(client, const <Thermostat>[Thermostat('t1')]);
      expect(entryType(client, list.key.rawKey), typeOf<List<Device>>());
      expect(list.read(client), const [Thermostat('t1')]);
      // And the next write of plain devices fits.
      list.write(client, const [Device('d1')]);
      expect(list.read(client), const [Device('d1')]);
      client.clear();
    });

    test('a nullable type written with a value', () {
      final client = testClient();
      final selected = QueryDefinition<Device?>(
        namespace: devices,
        name: 'selected',
      );
      selected.write(client, const Device('d1'));
      expect(entryType(client, selected.key.rawKey), typeOf<Device?>());
      selected.write(client, null);
      expect(entryType(client, selected.key.rawKey), typeOf<Device?>());
      client.clear();
    });

    test('an update that creates the entry does the same', () {
      final client = testClient();
      final reading = QueryFamily<String, Reading>(
        namespace: devices,
        name: 'reading',
      );
      final ref = reading('d1');
      expect(
        ref.update(client, (previous) {
          expect(previous, isNull);
          return const Temperature(3);
        }),
        const Temperature(3),
      );
      expect(entryType(client, ref.key.rawKey), Reading);
      client.clear();
    });
  });

  group('a typed write is exact', () {
    test('write, update and read over a wider entry throw, and write nothing',
        () {
      final client = testClient();
      final ref = deviceDetail()('d1');
      final key = ref.key.rawKey;
      client.setQueryData<Device?>(key, const Device('d1', name: 'raw'));
      expect(entryType(client, key), typeOf<Device?>());
      final events = recordEvents(client);
      final refused = throwsA(dataTypeError(key, Device, typeOf<Device?>()));

      expect(() => ref.write(client, const Device('d1')), refused);
      var updaterRan = false;
      expect(
        () => ref.update(client, (previous) {
          updaterRan = true;
          return const Device('d1');
        }),
        refused,
      );
      expect(updaterRan, isFalse);
      expect(() => ref.read(client), refused);
      expect(() => ref.state(client), refused);
      expect(() => ref.key.read(client), refused);

      expect(events, isEmpty);
      expect(
        client.getQueryData<Device?>(key),
        const Device('d1', name: 'raw'),
      );

      // The client's own write is lenient, as it was: a `Device` fits an
      // entry of `Device?`.
      client.setQueryData<Device>(key, const Device('d1', name: 'lenient'));
      expect(
        client.getQueryData<Device?>(key),
        const Device('d1', name: 'lenient'),
      );
      expect(entryType(client, key), typeOf<Device?>());
      client.clear();
    });

    test('a narrower entry is refused as well', () {
      final client = testClient();
      final ref = deviceDetail()('d1');
      final key = ref.key.rawKey;
      client.setQueryData<Thermostat>(key, const Thermostat('d1'));
      expect(
        () => ref.write(client, const Device('d1')),
        throwsA(dataTypeError(key, Device, Thermostat)),
      );
      expect(
        () => ref.write(client, const Thermostat('d1', name: 'fits the value')),
        throwsA(dataTypeError(key, Device, Thermostat)),
      );
      expect(client.getQueryData<Thermostat>(key), const Thermostat('d1'));
      client.clear();
    });

    test('an entry without data, of another type, is refused too', () {
      final client = testClient();
      final ref = deviceDetail()('d1');
      final key = ref.key.rawKey;
      // An entry and no data: what an observer that has not fetched leaves.
      client.queryCache.build<String>(
        client,
        client.defaultQueryOptions<String>(QueryOptions<String>(queryKey: key)),
      );
      expect(
        () => ref.write(client, const Device('d1')),
        throwsA(dataTypeError(key, Device, String)),
      );
      expect(
        () => ref.update(client, (previous) => const Device('d1')),
        throwsA(dataTypeError(key, Device, String)),
      );
      expect(entry(client, key).state.hasData, isFalse);
      client.clear();
    });

    test('through a widened receiver a wrong value is refused, nothing written',
        () {
      final client = testClient();
      final ref = deviceDetail()('d1');
      final QueryEntryRef<Object?> wide = ref;
      final events = recordEvents(client);

      expect(() => wide.write(client, 'not a device'), refusedAtRuntime);
      expect(() => wide.write(client, null), refusedAtRuntime);
      expect(
        () => wide.update(client, (previous) => 'not a device'),
        refusedAtRuntime,
      );
      expect(events, isEmpty);
      expect(client.queryCache.findAll(), isEmpty);

      // The right type through the same widened receiver is an ordinary
      // write, into an entry of the reference's type.
      wide.write(client, const Thermostat('d1'));
      expect(entryType(client, ref.key.rawKey), Device);
      expect(ref.read(client), const Thermostat('d1'));
      client.clear();
    });

    test('through a widened family a wrong input is refused', () {
      final detail = deviceDetail();
      final QueryFamily<Object?, Device> wide = detail;
      expect(() => wide(42), refusedAtRuntime);
      expect(wide('d1'), detail('d1'));
    });
  });

  group('absence, no data and a cached null', () {
    test('read cannot tell a cached null from nothing; state can', () {
      final client = testClient();
      final selected = QueryDefinition<Device?>(
        namespace: devices,
        name: 'selected',
      );
      expect(selected.read(client), isNull);
      expect(selected.state(client), isNull);

      expect(selected.write(client, null), isNull);
      expect(selected.read(client), isNull);
      final state = selected.state(client)!;
      expect(state.hasData, isTrue);
      expect(state.data, isNull);
      expect(state.status, QueryStatus.success);
      expect(selected.key.state(client), state);
      client.clear();
    });

    test('an update returning null writes nothing and creates nothing', () {
      final client = testClient();
      final ref = deviceDetail()('d1');
      final events = recordEvents(client);
      expect(ref.update(client, (previous) => null), isNull);
      expect(events, isEmpty);
      expect(client.queryCache.findAll(), isEmpty);

      ref.write(client, const Device('d1', name: 'kept'));
      events.clear();
      expect(ref.update(client, (previous) => null), isNull);
      expect(events, isEmpty);
      expect(ref.read(client), const Device('d1', name: 'kept'));
      expect(ref.state(client)!.dataUpdateCount, 1);
      client.clear();
    });

    test('on a nullable type an update cannot store null; a write can', () {
      final client = testClient();
      final selected = QueryDefinition<Device?>(
        namespace: devices,
        name: 'selected',
      );
      selected.write(client, const Device('d1'));
      expect(selected.update(client, (previous) => null), isNull);
      expect(selected.read(client), const Device('d1'));
      selected.write(client, null);
      expect(selected.state(client)!.hasData, isTrue);
      expect(selected.read(client), isNull);
      client.clear();
    });

    test('an update sees the cached value, and null for an entry without data',
        () {
      final client = testClient();
      final ref = deviceDetail()('d1');
      ref.write(client, const Device('d1', name: 'one'));
      final seen = <Device?>[];
      expect(
        ref.update(client, (previous) {
          seen.add(previous);
          return previous!.renamed('two');
        }),
        const Device('d1', name: 'two'),
      );
      expect(seen, [const Device('d1', name: 'one')]);

      final empty = deviceDetail()('d2');
      client.queryCache.build<Device>(
        client,
        client.defaultQueryOptions<Device>(empty.options()),
      );
      expect(empty.state(client)!.hasData, isFalse);
      empty.update(client, (previous) {
        seen.add(previous);
        return const Device('d2');
      });
      expect(seen.last, isNull);
      expect(empty.read(client), const Device('d2'));
      client.clear();
    });

    test('an updater that throws leaves the cache as it was', () {
      final client = testClient();
      final ref = deviceDetail()('d1');
      final events = recordEvents(client);
      expect(
        () => ref.update(client, (previous) => throw StateError('no')),
        throwsStateError,
      );
      expect(events, isEmpty);
      expect(client.queryCache.findAll(), isEmpty);
      client.clear();
    });

    test('an updater that removes the entry: the write makes it again', () {
      final client = testClient();
      final ref = deviceDetail()('d1');
      ref.write(client, const Device('d1', name: 'one'));
      final written = ref.update(client, (previous) {
        ref.remove(client);
        return previous!.renamed('two');
      });
      expect(written, const Device('d1', name: 'two'));
      expect(ref.read(client), const Device('d1', name: 'two'));
      expect(ref.state(client)!.dataUpdateCount, 1);
      client.clear();
    });

    test('an updater that swaps the entry for a wider one is refused', () {
      final client = testClient();
      final ref = deviceDetail()('d1');
      final key = ref.key.rawKey;
      ref.write(client, const Device('d1', name: 'one'));
      expect(
        () => ref.update(client, (previous) {
          client
            ..removeQueries(filters: ref.filters())
            ..setQueryData<Device?>(key, const Device('d1', name: 'wider'));
          return previous!.renamed('two');
        }),
        throwsA(dataTypeError(key, Device, typeOf<Device?>())),
      );
      expect(
        client.getQueryData<Device?>(key),
        const Device('d1', name: 'wider'),
      );
      client.clear();
    });
  });

  group('a write is the client\'s write', () {
    testFakeAsync('the timestamp is now, or the one given', (time) async {
      final client = testClient();
      final ref = deviceDetail()('d1');
      await time.advance(ms(50));
      ref.write(client, const Device('d1'));
      expect(ref.state(client)!.dataUpdatedAt, time.now);

      final at = DateTime.utc(2020, 2, 2);
      ref.write(client, const Device('d1', name: 'dated'), updatedAt: at);
      expect(ref.state(client)!.dataUpdatedAt, at);

      final later = DateTime.utc(2021, 3, 3);
      ref.update(
        client,
        (previous) => previous!.renamed('later'),
        updatedAt: later,
      );
      expect(ref.state(client)!.dataUpdatedAt, later);
      client.clear();
    });

    test('it returns what the cache holds after structural sharing', () {
      final client = testClient();
      final list = deviceList();
      final first = [const Device('d1'), const Device('d2')];
      expect(list.write(client, first), same(first));
      // An equal value: the cached instance is kept and returned.
      expect(
        list.write(client, [const Device('d1'), const Device('d2')]),
        same(first),
      );
      expect(
        list.update(client, (previous) => [...previous!]),
        same(first),
      );
      expect(list.read(client), same(first));
      client.clear();
    });

    test('it notifies as the client\'s write does, event for event', () {
      List<String> run(void Function(QueryClient client, QueryKey key) body) {
        final client = testClient();
        final events = recordEvents(client);
        body(client, QueryKey(['devices', 'detail', 'd1']));
        client.clear();
        return events;
      }

      final ref = deviceDetail()('d1');
      final typed = run((client, key) {
        ref
          ..write(client, const Device('d1', name: 'one'))
          ..write(client, const Device('d1', name: 'two'))
          ..update(client, (previous) => previous!.renamed('three'));
      });
      final raw = run((client, key) {
        client
          ..setQueryData<Device>(key, const Device('d1', name: 'one'))
          ..setQueryData<Device>(key, const Device('d1', name: 'two'))
          ..updateQueryData<Device>(
            key,
            (previous) => previous!.renamed('three'),
          );
      });
      expect(typed, raw);
      expect(typed.take(4), [
        'added devices/detail/d1',
        'updated devices/detail/d1',
        'updated devices/detail/d1',
        'updated devices/detail/d1',
      ]);
    });

    testFakeAsync('a subscribed observer sees the write synchronously',
        (time) async {
      final client = testClient();
      final ref = deviceDetail()('d1');
      final observer = QueryObserver<Device, Device>(
        client,
        ref.options().copyWith(enabled: Enabled.no),
      );
      final seen = <Device?>[];
      final unsubscribe =
          observer.subscribe((result) => seen.add(result.dataOrNull));
      ref.write(client, const Device('d1', name: 'now'));
      expect(seen, [const Device('d1', name: 'now')]);
      unsubscribe();
      client.clear();
    });
  });

  group('an entry a write creates', () {
    testFakeAsync('has the definition\'s gcTime from the first write',
        (time) async {
      final client = testClient();
      final short = deviceDetail(
        configure: (base, id) =>
            base.copyWith(gcTime: GcTime.duration(const Duration(minutes: 1))),
      );
      short('d1').write(client, const Device('d1'));
      // The control: an entry the client's write creates has the default,
      // five minutes, and never gets a shorter one.
      client.setQueryData<Device>(short('d2').key.rawKey, const Device('d2'));
      expect(entry(client, short('d1').key.rawKey).gcTime,
          GcTime.duration(const Duration(minutes: 1)));
      expect(entry(client, short('d2').key.rawKey).gcTime, GcTime.defaultValue);

      await time.advance(const Duration(minutes: 1));
      expect(short('d1').state(client), isNull);
      expect(short('d2').state(client), isNotNull);
      await time.advance(const Duration(minutes: 4));
      expect(short('d2').state(client), isNull);
    });

    testFakeAsync('with GcTime.never arms no timer at all', (time) async {
      final client = testClient();
      final kept = deviceDetail(
        configure: (base, id) => base.copyWith(gcTime: GcTime.never),
      );
      kept('d1').write(client, const Device('d1'));
      expect(time.pendingTimers, 0);
      await time.advance(const Duration(days: 1));
      expect(kept('d1').read(client), const Device('d1'));
      client.clear();
    });

    test('has the definition\'s structuralSharing from the first write', () {
      final client = testClient();
      final unshared = deviceList(
        configure: (base) =>
            base.copyWith(structuralSharing: noStructuralSharing()),
      );
      final first = [const Device('d1')];
      final second = [const Device('d1')];
      unshared.write(client, first);
      expect(unshared.write(client, second), same(second));
      client.clear();
    });

    test('an existing entry keeps the options it has', () {
      final client = testClient();
      final unshared = deviceList(
        configure: (base) =>
            base.copyWith(structuralSharing: noStructuralSharing()),
      );
      var configured = 0;
      final counted = deviceList(
        configure: (base) {
          configured++;
          return base;
        },
      );
      final first = [const Device('d1')];
      // Created by the client's write: default sharing.
      client.setQueryData<List<Device>>(unshared.key.rawKey, first);
      expect(unshared.write(client, [const Device('d1')]), same(first));
      // Nor are the definition's options even resolved for it.
      counted
        ..write(client, [const Device('d2')])
        ..update(client, (previous) => [...previous!, const Device('d3')]);
      expect(configured, 0);
      client.clear();
    });

    testFakeAsync('is not fetched, observed or different from an observer\'s',
        (time) async {
      var fetches = 0;
      final list = deviceList(
        queryFn: (context) {
          fetches++;
          return const [];
        },
        configure: (base) => base.copyWith(
          gcTime: GcTime.duration(const Duration(minutes: 2)),
          staleTime: const StaleTime.duration(Duration(minutes: 1)),
          retry: const RetryPolicy.times(1),
          meta: 'list',
        ),
      );

      final written = testClient();
      list.write(written, const [Device('d1')]);
      final byWrite = entry(written, list.key.rawKey);
      await time.flushMicrotasks();
      expect(fetches, 0);
      expect(byWrite.observersCount, 0);
      expect(byWrite.state.fetchStatus, FetchStatus.idle);
      expect(byWrite.future, isNull);

      // What an observer's own build establishes, on another client.
      final observed = testClient();
      // Not subscribed: an observer builds its entry and fetches nothing.
      QueryObserver<List<Device>, List<Device>>(observed, list.options());
      final byObserver = entry(observed, list.key.rawKey);
      expect(byWrite.options, byObserver.options);
      expect(byWrite.gcTime, byObserver.gcTime);
      expect(byWrite.meta, 'list');

      // And what `client.query` builds before it fetches.
      final fetched = testClient();
      unawaited(list.fetch(fetched));
      expect(byWrite.options, entry(fetched, list.key.rawKey).options);
      await time.flushMicrotasks();

      written.clear();
      observed.clear();
      fetched.clear();
    });

    test('is seeded by the definition\'s initialData, then written', () {
      final client = testClient();
      final seeded = deviceList(
        configure: (base) => base.copyWith(
          initialData: const InitialData.value([Device('seed')]),
        ),
      );
      // The updater is asked before the entry exists: nothing is cached.
      final seen = <List<Device>?>[];
      seeded.update(client, (previous) {
        seen.add(previous);
        return const [Device('written')];
      });
      expect(seen, [null]);
      expect(seeded.read(client), const [Device('written')]);
      // The seed is what a reset goes back to, as for an observed entry.
      expect(entry(client, seeded.key.rawKey).resetState.data,
          const [Device('seed')]);
      client.clear();
    });
  });

  // A typed key writes as its reference does, through the same private
  // function, with one difference: it has no definition, so an entry it
  // creates is built from the key and the data type alone.
  group('a typed key writes its entry', () {
    /// One script, through whatever [write] and [update] are handed: the
    /// events it caused and the state it left.
    ({List<String> events, QueryState<List<Device>> state, bool shared}) script(
      List<Device> Function(
        QueryClient client,
        List<Device> value, {
        DateTime? updatedAt,
      }) write,
      List<Device>? Function(
        QueryClient client,
        List<Device>? Function(List<Device>? previous) updater, {
        DateTime? updatedAt,
      }) update,
    ) {
      final client = testClient();
      final list = deviceList();
      // The entry exists, made by the reference with the definition's
      // options.
      final first = [const Device('d1')];
      list.write(client, first, updatedAt: DateTime.utc(2020));
      final events = recordEvents(client);
      // An equal value: sharing keeps and returns the cached instance.
      final shared = identical(write(client, [const Device('d1')]), first);
      write(
        client,
        const [Device('d1'), Device('d2')],
        updatedAt: DateTime.utc(2021),
      );
      update(
        client,
        (previous) => [...previous!, const Device('d3')],
        updatedAt: DateTime.utc(2022),
      );
      update(client, (previous) => null);
      final state = list.state(client)!;
      client.clear();
      return (events: events, state: state, shared: shared);
    }

    test(
        'on an entry that exists: the reference\'s write, event for event, '
        'sharing and timestamp included', () {
      final list = deviceList();
      final byReference = script(list.write, list.update);
      final byKey = script(list.key.write, list.key.update);

      expect(byKey.events, byReference.events);
      expect(byKey.events.take(3), [
        'updated devices/list',
        'updated devices/list',
        'updated devices/list',
      ]);
      expect(byKey.shared, isTrue);
      expect(byReference.shared, isTrue);
      expect(byKey.state.data, byReference.state.data);
      expect(byKey.state.data, const [
        Device('d1'),
        Device('d2'),
        Device('d3'),
      ]);
      expect(byKey.state.dataUpdatedAt, DateTime.utc(2022));
      expect(byKey.state.dataUpdatedAt, byReference.state.dataUpdatedAt);
      expect(byKey.state.dataUpdateCount, byReference.state.dataUpdateCount);
      expect(byKey.state.status, byReference.state.status);
      expect(byKey.state.isInvalidated, byReference.state.isInvalidated);
    });

    testFakeAsync('the timestamp is now, or the one given', (time) async {
      final client = testClient();
      final key = deviceDetail()('d1').key;
      await time.advance(ms(50));
      key.write(client, const Device('d1'));
      expect(key.state(client)!.dataUpdatedAt, time.now);

      final at = DateTime.utc(2020, 2, 2);
      key.write(client, const Device('d1', name: 'dated'), updatedAt: at);
      expect(key.state(client)!.dataUpdatedAt, at);

      final later = DateTime.utc(2021, 3, 3);
      key.update(
        client,
        (previous) => previous!.renamed('later'),
        updatedAt: later,
      );
      expect(key.state(client)!.dataUpdatedAt, later);
      client.clear();
    });

    testFakeAsync('a subscribed observer sees the write synchronously',
        (time) async {
      final client = testClient();
      final ref = deviceDetail()('d1');
      final observer = QueryObserver<Device, Device>(
        client,
        ref.options().copyWith(enabled: Enabled.no),
      );
      final seen = <Device?>[];
      final unsubscribe =
          observer.subscribe((result) => seen.add(result.dataOrNull));
      ref.key.write(client, const Device('d1', name: 'now'));
      ref.key.update(client, (previous) => previous!.renamed('then'));
      expect(seen, [
        const Device('d1', name: 'now'),
        const Device('d1', name: 'then'),
      ]);
      unsubscribe();
      client.clear();
    });

    test('over a wider entry write and update throw, and write nothing', () {
      final client = testClient();
      final typed = deviceDetail()('d1').key;
      final key = typed.rawKey;
      client.setQueryData<Device?>(key, const Device('d1', name: 'raw'));
      final events = recordEvents(client);
      final refused = throwsA(dataTypeError(key, Device, typeOf<Device?>()));

      expect(() => typed.write(client, const Device('d1')), refused);
      var updaterRan = false;
      expect(
        () => typed.update(client, (previous) {
          updaterRan = true;
          return const Device('d1');
        }),
        refused,
      );
      expect(updaterRan, isFalse);
      expect(events, isEmpty);
      expect(
        client.getQueryData<Device?>(key),
        const Device('d1', name: 'raw'),
      );
      expect(entryType(client, key), typeOf<Device?>());

      // The control: the client's own write takes the wider entry.
      client.setQueryData<Device>(key, const Device('d1', name: 'lenient'));
      expect(
        client.getQueryData<Device?>(key),
        const Device('d1', name: 'lenient'),
      );
      client.clear();
    });

    test('a narrower entry, and one of another type without data, are refused',
        () {
      final client = testClient();
      final narrower = deviceDetail()('d1').key;
      client.setQueryData<Thermostat>(narrower.rawKey, const Thermostat('d1'));
      expect(
        () => narrower.write(client, const Thermostat('d1', name: 'fits')),
        throwsA(dataTypeError(narrower.rawKey, Device, Thermostat)),
      );
      expect(
        client.getQueryData<Thermostat>(narrower.rawKey),
        const Thermostat('d1'),
      );

      final empty = deviceDetail()('d2').key;
      client.queryCache.build<String>(
        client,
        client.defaultQueryOptions<String>(
          QueryOptions<String>(queryKey: empty.rawKey),
        ),
      );
      expect(
        () => empty.write(client, const Device('d2')),
        throwsA(dataTypeError(empty.rawKey, Device, String)),
      );
      expect(
        () => empty.update(client, (previous) => const Device('d2')),
        throwsA(dataTypeError(empty.rawKey, Device, String)),
      );
      expect(entry(client, empty.rawKey).state.hasData, isFalse);
      client.clear();
    });

    test('an entry it creates has the key\'s type, whatever the value\'s is',
        () {
      final client = testClient();
      // A nullable type written a value: `Device?`, not `Device`.
      final selected = QueryDefinition<Device?>(
        namespace: devices,
        name: 'selected',
      ).key;
      expect(selected.write(client, const Device('d1')), const Device('d1'));
      expect(entryType(client, selected.rawKey), typeOf<Device?>());
      expect(selected.read(client), const Device('d1'));
      // And `null` is then a value the entry takes.
      expect(selected.write(client, null), isNull);
      expect(selected.state(client)!.hasData, isTrue);

      // A sealed base written a variant, through `update`.
      final reading = QueryFamily<String, Reading>(
        namespace: devices,
        name: 'reading',
      )('d1')
          .key;
      expect(
        reading.update(client, (previous) {
          expect(previous, isNull);
          return const Temperature(3);
        }),
        const Temperature(3),
      );
      expect(entryType(client, reading.rawKey), Reading);

      // A list written a narrower literal.
      final list = deviceList().key;
      list.write(client, const <Thermostat>[Thermostat('t1')]);
      expect(entryType(client, list.rawKey), typeOf<List<Device>>());
      list.write(client, const [Device('d1')]);
      expect(list.read(client), const [Device('d1')]);

      // The control: the client's write, left to infer, makes an entry of
      // the value's own type, which the typed key then refuses.
      final other = deviceDetail()('raw').key;
      client.setQueryData(other.rawKey, const Thermostat('raw'));
      expect(entryType(client, other.rawKey), Thermostat);
      expect(
        () => other.read(client),
        throwsA(dataTypeError(other.rawKey, Device, Thermostat)),
      );
      client.clear();
    });

    testFakeAsync(
        'an entry it creates has none of the definition\'s options; the '
        'reference\'s has them', (time) async {
      var configured = 0;
      final detail = deviceDetail(
        configure: (base, id) {
          configured++;
          return base.copyWith(
            gcTime: GcTime.duration(const Duration(minutes: 1)),
            structuralSharing: noStructuralSharing(),
            initialData: const InitialData.value(Device('seed')),
            meta: 'detail',
          );
        },
      );
      final client = testClient();

      // Through the key: the key and the type, and nothing of `configure`.
      final byKey = detail('d1').key;
      configured = 0;
      byKey.write(client, const Device('d1'));
      expect(configured, 0);
      final keyEntry = entry(client, byKey.rawKey);
      expect(keyEntry.dataType, Device);
      expect(keyEntry.gcTime, GcTime.defaultValue);
      expect(keyEntry.meta, isNull);
      expect(keyEntry.resetState.hasData, isFalse);
      expect(keyEntry.observersCount, 0);
      expect(keyEntry.state.fetchStatus, FetchStatus.idle);
      // Default sharing: an equal value keeps the cached instance.
      final cached = byKey.read(client);
      expect(byKey.write(client, const Device('d1')), same(cached));

      // It is the entry the client's own typed write makes.
      final raw = testClient();
      raw.setQueryData<Device>(byKey.rawKey, const Device('d1'));
      expect(keyEntry.options, entry(raw, byKey.rawKey).options);

      // Through the reference: the definition's options, from that write.
      final ref = detail('d2');
      ref.write(client, const Device('d2'));
      expect(configured, 1);
      final refEntry = entry(client, ref.key.rawKey);
      expect(refEntry.gcTime, GcTime.duration(const Duration(minutes: 1)));
      expect(refEntry.meta, 'detail');
      expect(refEntry.resetState.data, const Device('seed'));
      expect(keyEntry.options, isNot(refEntry.options));

      // Which is what collects the two: one minute, and the default five.
      await time.advance(const Duration(minutes: 1));
      expect(ref.state(client), isNull);
      expect(byKey.state(client), isNotNull);
      await time.advance(const Duration(minutes: 4));
      expect(byKey.state(client), isNull);
      raw.clear();
    });

    test('the client\'s and the key\'s defaults apply to an entry it creates',
        () {
      final client = testClient(
        defaultOptions: const DefaultOptions(
          queries: QueryDefaults(gcTime: GcTime.never, meta: 'client'),
        ),
      );
      client.setQueryDefaults(
        deviceDetail().rawKey,
        const QueryDefaults(meta: 'key'),
      );
      final key = deviceDetail()('d1').key..write(client, const Device('d1'));
      final made = entry(client, key.rawKey);
      expect(made.gcTime, GcTime.never);
      expect(made.meta, 'key');
      client.clear();
    });

    testFakeAsync(
        'an entry it creates has no fetch function until the definition '
        'gives it one', (time) async {
      var fetches = 0;
      final detail = deviceDetail(
        queryFn: (id, context) {
          fetches++;
          return Device(id, name: 'fetched');
        },
      );
      final client = testClient();

      // The key's entry: no function, as an entry of the client's own
      // write. A refetch of everything fails it, and keeps its data.
      final byKey = detail('d1').key
        ..write(client, const Device('d1', name: 'written'));
      expect(entry(client, byKey.rawKey).options.queryFn, isNull);
      await detail.refetch(client);
      expect(fetches, 0);
      expect(byKey.state(client)!.status, QueryStatus.error);
      expect(
        byKey.state(client)!.error,
        isA<MissingQueryFunctionError>(),
      );
      expect(byKey.read(client), const Device('d1', name: 'written'));

      // The reference's entry has the definition's function from its
      // first write.
      final ref = detail('d2')
        ..write(client, const Device('d2', name: 'written'));
      expect(entry(client, ref.key.rawKey).options.queryFn, isNotNull);
      await ref.refetch(client);
      expect(fetches, 1);
      expect(ref.read(client), const Device('d2', name: 'fetched'));

      // And the first use of the definition's options gives the key's
      // entry what it lacked: a fetch through the reference, an observer.
      expect(await detail('d1').fetch(client), isA<Device>());
      expect(entry(client, byKey.rawKey).options.queryFn, isNotNull);
      await detail.refetch(client);
      expect(byKey.state(client)!.status, QueryStatus.success);
      expect(byKey.read(client), const Device('d1', name: 'fetched'));
      client.clear();
    });

    test('an entry that exists keeps the options it has', () {
      final client = testClient();
      final unshared = deviceList(
        configure: (base) =>
            base.copyWith(structuralSharing: noStructuralSharing()),
      );
      final first = [const Device('d1')];
      final second = [const Device('d1')];
      // Made by the reference, with the definition's opt-out of sharing.
      unshared.write(client, first);
      expect(unshared.key.write(client, second), same(second));
      client.clear();
    });

    test('an update returning null writes nothing and creates nothing', () {
      final client = testClient();
      final key = deviceDetail()('d1').key;
      final events = recordEvents(client);
      expect(key.update(client, (previous) => null), isNull);
      expect(events, isEmpty);
      expect(client.queryCache.findAll(), isEmpty);

      key.write(client, const Device('d1', name: 'kept'));
      events.clear();
      final seen = <Device?>[];
      expect(
        key.update(client, (previous) {
          seen.add(previous);
          return null;
        }),
        isNull,
      );
      expect(seen, [const Device('d1', name: 'kept')]);
      expect(events, isEmpty);
      expect(key.state(client)!.dataUpdateCount, 1);
      client.clear();
    });

    test('an updater that throws leaves the cache as it was', () {
      final client = testClient();
      final key = deviceDetail()('d1').key;
      final events = recordEvents(client);
      expect(
        () => key.update(client, (previous) => throw StateError('no')),
        throwsStateError,
      );
      expect(events, isEmpty);
      expect(client.queryCache.findAll(), isEmpty);
      client.clear();
    });

    test('an updater that removes the entry: the write makes it again, bare',
        () {
      final client = testClient();
      final ref = deviceDetail(
        configure: (base, id) => base.copyWith(meta: 'detail'),
      )('d1');
      ref.write(client, const Device('d1', name: 'one'));
      expect(entry(client, ref.key.rawKey).meta, 'detail');

      final written = ref.key.update(client, (previous) {
        ref.remove(client);
        return previous!.renamed('two');
      });
      expect(written, const Device('d1', name: 'two'));
      expect(ref.read(client), const Device('d1', name: 'two'));
      expect(ref.state(client)!.dataUpdateCount, 1);
      expect(entry(client, ref.key.rawKey).meta, isNull);

      // The control: the reference's update makes it with the definition's.
      ref.update(client, (previous) {
        ref.remove(client);
        return previous!.renamed('three');
      });
      expect(entry(client, ref.key.rawKey).meta, 'detail');
      client.clear();
    });

    test('an updater that swaps the entry for a wider one is refused', () {
      final client = testClient();
      final ref = deviceDetail()('d1');
      final key = ref.key.rawKey;
      ref.write(client, const Device('d1', name: 'one'));
      expect(
        () => ref.key.update(client, (previous) {
          client
            ..removeQueries(filters: ref.filters())
            ..setQueryData<Device?>(key, const Device('d1', name: 'wider'));
          return previous!.renamed('two');
        }),
        throwsA(dataTypeError(key, Device, typeOf<Device?>())),
      );
      expect(
        client.getQueryData<Device?>(key),
        const Device('d1', name: 'wider'),
      );
      client.clear();
    });

    test('through a widened key a wrong value is refused, nothing written', () {
      final client = testClient();
      final key = deviceDetail()('d1').key;
      final TypedQueryKey<Object?> wide = key;
      final events = recordEvents(client);

      expect(() => wide.write(client, 'not a device'), refusedAtRuntime);
      expect(() => wide.write(client, null), refusedAtRuntime);
      expect(
        () => wide.update(client, (previous) => 'not a device'),
        refusedAtRuntime,
      );
      expect(events, isEmpty);
      expect(client.queryCache.findAll(), isEmpty);

      // The right type through the same widened key is an ordinary write,
      // into an entry of the key's type and not of the receiver's.
      wide.write(client, const Thermostat('d1'));
      expect(entryType(client, key.rawKey), Device);
      expect(key.read(client), const Thermostat('d1'));
      client.clear();
    });

    test('two clients are independent: a typed key holds none', () {
      final a = testClient();
      final b = testClient();
      final key = deviceDetail()('d1').key;
      key.write(a, const Device('d1', name: 'a'));
      expect(key.read(a), const Device('d1', name: 'a'));
      expect(key.state(b), isNull);
      key.write(b, const Device('d1', name: 'b'));
      expect(key.read(a), const Device('d1', name: 'a'));
      a.clear();
      b.clear();
    });

    // What the two methods are for: `readAll` hands out keys and no
    // references, and a family cannot turn a key back into an input.
    test('a snapshot from readAll is put back through its keys', () {
      final client = testClient();
      final detail = deviceDetail();
      final list = deviceList();
      final at = DateTime.utc(2020);
      detail('d1')
          .write(client, const Device('d1', name: 'one'), updatedAt: at);
      detail('d2')
          .write(client, const Device('d2', name: 'two'), updatedAt: at);
      // An entry without data: nothing to put back.
      client.queryCache.build<Device>(
        client,
        client.defaultQueryOptions<Device>(detail('d3').options()),
      );
      list.write(client, const [Device('d1'), Device('d2')]);

      final snapshot = detail.readAll(client);
      // The optimistic patch; the second entry is removed meanwhile.
      detail.updateAll(client, (device) => device?.renamed('patched'));
      detail('d2').remove(client);
      expect(detail('d1').read(client), const Device('d1', name: 'patched'));

      final events = recordEvents(client);
      for (final (key, data) in snapshot) {
        if (data != null) {
          key.write(client, data, updatedAt: at);
        }
      }
      expect(events, [
        'updated devices/detail/d1',
        'added devices/detail/d2',
        'updated devices/detail/d2',
      ]);
      expect(detail('d1').read(client), const Device('d1', name: 'one'));
      expect(detail('d2').read(client), const Device('d2', name: 'two'));
      expect(detail('d1').state(client)!.dataUpdatedAt, at);
      expect(detail('d3').state(client)!.hasData, isFalse);
      expect(entryType(client, detail('d2').key.rawKey), Device);
      expect(list.read(client), const [Device('d1'), Device('d2')]);
      client.clear();
    });

    // The rollback above skips `null`, which means "no data" only for a
    // non-null data type. For a nullable one a cached `null` reads as
    // `null` too; the snapshot `readAll`'s dartdoc gives for that case keeps
    // each key's state, whose `hasData` tells the two apart.
    test('a nullable family\'s snapshot is put back from each key\'s state',
        () {
      final client = testClient();
      final paired = QueryFamily<String, Device?>(
        namespace: devices,
        name: 'paired',
      );
      final at = DateTime.utc(2020);
      paired('none').write(client, null, updatedAt: at); // a cached null
      paired('lamp').write(client, const Device('lamp'), updatedAt: at);
      // An entry without data.
      client.queryCache.build<Device?>(
        client,
        client.defaultQueryOptions<Device?>(paired('empty').options()),
      );

      // `readAll` reads the cached null and the missing data alike.
      final values = paired.readAll(client);
      expect(values, [
        (paired('none').key, null),
        (paired('lamp').key, const Device('lamp')),
        (paired('empty').key, null),
      ]);
      final states = [
        for (final (key, _) in paired.readAll(client)) (key, key.state(client)),
      ];

      // Every entry overwritten, the cached null included.
      void patch() =>
          paired.updateAll(client, (device) => const Device('patched'));

      // The rollback over the values cannot put the cached null back.
      patch();
      expect(paired('none').read(client), const Device('patched'));
      for (final (key, data) in values) {
        if (data != null) key.write(client, data, updatedAt: at);
      }
      expect(paired('none').read(client), const Device('patched'));
      expect(paired('lamp').read(client), const Device('lamp'));

      // The rollback over the states puts every entry back as it was.
      patch();
      for (final (key, state) in states) {
        if (state != null && state.hasData) {
          key.write(client, state.data, updatedAt: at);
        }
      }
      expect(paired('none').state(client)!.hasData, isTrue);
      expect(paired('none').read(client), isNull);
      expect(paired('lamp').read(client), const Device('lamp'));
      // An updater sees no data as `null` as well, so it patched the entry
      // without data too, and neither rollback can take data away again.
      expect(paired('empty').read(client), const Device('patched'));
      client.clear();
    });

    test('the keys updateAll returns write as well', () {
      final client = testClient();
      final detail = deviceDetail();
      detail('d1').write(client, const Device('d1', name: 'one'));
      final [(key, patched)] = detail.updateAll(
        client,
        (device) => device!.renamed('patched'),
      );
      expect(patched, const Device('d1', name: 'patched'));
      expect(
        key.update(client, (device) => device!.renamed('again')),
        const Device('d1', name: 'again'),
      );
      expect(detail('d1').read(client), const Device('d1', name: 'again'));
      client.clear();
    });
  });

  // Review of the core, SC-1. A typed write holds an entry across code of
  // the application's that runs before the value is stored: the cache's
  // listeners hear `QueryAdded` for an entry the write creates, the entry's
  // `structuralSharing` is handed the value, and an `update` runs its
  // updater. Each may remove or replace the entry. The rule, at every one
  // of those points: the value goes into the entry the cache holds under
  // the key when it is stored, or the write throws. It never returns a
  // value that went into an entry the cache had already dropped.
  group('a write goes into the entry the cache holds (SC-1)', () {
    const value = Device('d1', name: 'written');
    const other = Device('d1', name: 'other');
    final rawKey = QueryKey(['devices', 'detail', 'd1']);

    final writes =
        <String, Device? Function(QueryClient client, QueryRef<Device> ref)>{
      'ref.write': (client, ref) => ref.write(client, value),
      'ref.update': (client, ref) => ref.update(client, (_) => value),
      'key.write': (client, ref) => ref.key.write(client, value),
      'key.update': (client, ref) => ref.key.update(client, (_) => value),
    };

    void remove(QueryClient client, QueryRef<Device> ref) => ref.remove(client);

    void putAnotherType(QueryClient client, QueryRef<Device> ref) {
      ref.remove(client);
      client.setQueryData<String>(ref.key.rawKey, 'replacement');
    }

    void putTheSameType(QueryClient client, QueryRef<Device> ref) {
      ref.remove(client);
      client.setQueryData<Device>(ref.key.rawKey, other);
    }

    /// [act], and what became of it: what it returned or threw, the events
    /// it caused and the entry the cache holds under the key afterwards.
    ({
      Object? returned,
      Object? thrown,
      List<String> events,
      Query<Object?>? held,
    }) outcome(
      QueryClient client,
      QueryRef<Device> ref,
      List<String> events,
      Device? Function() act,
    ) {
      events.clear();
      Object? returned;
      Object? thrown;
      try {
        returned = act();
      } on Object catch (error) {
        thrown = error;
      }
      final held =
          client.queryCache.findAll(filters: ref.filters()).firstOrNull;
      final recorded = [...events];
      client.clear();
      return (
        returned: returned,
        thrown: thrown,
        events: recorded,
        held: held,
      );
    }

    /// [write] where there is no entry, on a client whose listener answers
    /// the first `QueryAdded` with [onAdded].
    ({
      Object? returned,
      Object? thrown,
      List<String> events,
      Query<Object?>? held,
    }) created(
      Device? Function(QueryClient client, QueryRef<Device> ref) write,
      void Function(QueryClient client, QueryRef<Device> ref) onAdded,
    ) {
      final client = testClient();
      final ref = deviceDetail()('d1');
      final events = recordEvents(client);
      var answered = false;
      client.queryCache.subscribe((event) {
        if (!answered && event is QueryAdded) {
          answered = true;
          onAdded(client, ref);
        }
      });
      return outcome(client, ref, events, () => write(client, ref));
    }

    /// [write] into an entry that exists and whose `structuralSharing`
    /// runs [whileSharing] when it is handed [value].
    ({
      Object? returned,
      Object? thrown,
      List<String> events,
      Query<Object?>? held,
    }) shared(
      Device? Function(QueryClient client, QueryRef<Device> ref) write,
      void Function(QueryClient client, QueryRef<Device> ref) whileSharing, {
      bool existing = true,
    }) {
      final client = testClient();
      late final QueryRef<Device> ref;
      var ran = false;
      ref = deviceDetail(
        configure: (base, id) => base.copyWith(
          structuralSharing: (previous, next) {
            if (!ran && next == value) {
              ran = true;
              whileSharing(client, ref);
            }
            return next;
          },
        ),
      )('d1');
      if (existing) {
        ref.write(client, const Device('d1', name: 'before'));
      }
      final events = recordEvents(client);
      return outcome(client, ref, events, () => write(client, ref));
    }

    for (final MapEntry(key: name, value: write) in writes.entries) {
      group(name, () {
        test('an entry of another type put in its place when it was added', () {
          final result = created(write, putAnotherType);
          expect(result.thrown, dataTypeError(rawKey, Device, String));
          expect(result.held!.state.data, 'replacement');
          // The replacement's own write, and none after it: nothing was
          // stored in the entry the cache had dropped.
          expect(result.events, [
            'added devices/detail/d1',
            'removed devices/detail/d1',
            'added devices/detail/d1',
            'updated devices/detail/d1',
          ]);
        });

        test('an entry of the same type put in its place is the one written',
            () {
          final result = created(write, putTheSameType);
          expect(result.thrown, isNull);
          expect(result.returned, value);
          expect(result.held!.dataType, Device);
          expect(result.held!.state.data, value);
          // The listener's write and this one, into the same entry.
          expect(result.held!.state.dataUpdateCount, 2);
          expect(result.events, [
            'added devices/detail/d1',
            'removed devices/detail/d1',
            'added devices/detail/d1',
            'updated devices/detail/d1',
            'updated devices/detail/d1',
          ]);
        });

        test('an entry removed when it was added: StateError, nothing stored',
            () {
          final result = created(write, remove);
          expect(result.thrown, isStateError);
          expect(result.held, isNull);
          expect(result.events, [
            'added devices/detail/d1',
            'removed devices/detail/d1',
          ]);
        });

        test('the control: a listener that writes the new entry itself', () {
          final result = created(
            write,
            (client, ref) => ref.write(client, other),
          );
          expect(result.thrown, isNull);
          expect(result.returned, value);
          expect(result.held!.state.data, value);
          expect(result.held!.state.dataUpdateCount, 2);
        });

        test('structuralSharing that removes its entry: StateError', () {
          final result = shared(write, remove);
          expect(result.thrown, isStateError);
          expect(result.held, isNull);
          // No update of an entry that is gone.
          expect(result.events, ['removed devices/detail/d1']);
        });

        test('structuralSharing that puts another type in its place', () {
          final result = shared(write, putAnotherType);
          expect(result.thrown, dataTypeError(rawKey, Device, String));
          expect(result.held!.state.data, 'replacement');
          expect(result.events, [
            'removed devices/detail/d1',
            'added devices/detail/d1',
            'updated devices/detail/d1',
          ]);
        });

        test('structuralSharing that puts the same type in its place', () {
          final result = shared(write, putTheSameType);
          // The value it shared belongs to the entry that is gone.
          expect(result.thrown, isStateError);
          expect(result.held!.state.data, other);
          expect(result.held!.state.dataUpdateCount, 1);
        });

        test('the control: structuralSharing that resets its entry', () {
          final result = shared(
            write,
            (client, ref) => unawaited(ref.reset(client)),
          );
          expect(result.thrown, isNull);
          expect(result.returned, value);
          expect(result.held!.state.data, value);
        });

        test('what a listener does in answer to the write comes after it', () {
          for (final (answer, removes) in [
            (remove, true),
            (putAnotherType, false),
          ]) {
            final client = testClient();
            final ref = deviceDetail()('d1');
            ref.write(client, const Device('d1', name: 'before'));
            var answered = false;
            client.queryCache.subscribe((event) {
              if (!answered && event is QueryUpdated) {
                answered = true;
                answer(client, ref);
              }
            });
            // Stored, heard, and then changed by who heard it.
            expect(write(client, ref), value);
            if (removes) {
              expect(ref.state(client), isNull);
            } else {
              expect(
                () => ref.read(client),
                throwsA(dataTypeError(rawKey, Device, String)),
              );
            }
            client.clear();
          }
        });
      });
    }

    test('an entry a reference creates, removed by its structuralSharing', () {
      final result = shared(
        (client, ref) => ref.write(client, value),
        remove,
        existing: false,
      );
      expect(result.thrown, isStateError);
      expect(result.held, isNull);
      expect(result.events, [
        'added devices/detail/d1',
        'removed devices/detail/d1',
      ]);
    });

    test('an updater that puts the same type in its place: that one is written',
        () {
      for (final byKey in [false, true]) {
        final client = testClient();
        final ref = deviceDetail()('d1');
        ref.write(client, const Device('d1', name: 'before'));
        Device? updater(Device? previous) {
          putTheSameType(client, ref);
          return previous!.renamed('written');
        }

        final stored = byKey
            ? ref.key.update(client, updater)
            : ref.update(client, updater);
        expect(stored, value);
        expect(ref.read(client), value);
        // The replacement's own write and the update's.
        expect(ref.state(client)!.dataUpdateCount, 2);
        client.clear();
      }
    });

    // The control for all of the above: the client's own write reports a
    // value the cache does not hold.
    test('the control: setQueryData returns a value it did not store', () {
      final client = testClient();
      final ref = deviceDetail()('d1');
      var answered = false;
      client.queryCache.subscribe((event) {
        if (!answered && event is QueryAdded) {
          answered = true;
          putAnotherType(client, ref);
        }
      });
      expect(client.setQueryData<Device>(rawKey, value), value);
      expect(entry(client, rawKey).state.data, 'replacement');
      client.clear();
    });
  });

  group('options and defaults', () {
    test('options are made anew on every call, with the input', () {
      final inputs = <String>[];
      final detail = deviceDetail(
        configure: (base, id) {
          inputs.add(id);
          return base.copyWith(meta: id);
        },
      );
      final ref = detail('d1');
      final a = ref.options();
      final b = ref.options();
      expect(identical(a, b), isFalse);
      expect(inputs, ['d1', 'd1']);
      expect(a.meta, 'd1');
      expect(a.queryKey, ref.key.rawKey);
      expect(detail('d2').options().meta, 'd2');
    });

    test(
        'a definition without an input hands out the function it was '
        'given; a family\'s reference binds a new one per call', () {
      final client = testClient();
      DefaultedQueryObserverOptions<T, T> resolved<T>(
        QueryObserverOptions<T> options,
      ) =>
          client.defaultQueryObserverOptions<T, T>(options);

      // No input: new options every call, the same function in them, and
      // so equal once the client has resolved them.
      final list = deviceList();
      final a = list.options();
      final b = list.options();
      expect(identical(a, b), isFalse);
      expect(identical(a.queryFn, b.queryFn), isTrue);
      expect(resolved(a), resolved(b));
      expect(resolved(a).hashCode, resolved(b).hashCode);

      // With a `configure` that returns equal options, the same.
      final configured = deviceList(
        configure: (base) => base.copyWith(
          staleTime: const StaleTime.duration(Duration(minutes: 1)),
        ),
      );
      expect(resolved(configured.options()), resolved(configured.options()));

      // A `configure` that makes something new per call is what it makes.
      final churning = deviceList(
        configure: (base) =>
            base.copyWith(enabled: Enabled.when((query) => true)),
      );
      expect(
        resolved(churning.options()),
        isNot(resolved(churning.options())),
      );

      // A definition made again holds another function.
      expect(resolved(deviceList().options()), isNot(resolved(a)));

      // A family binds the input into a function of its own, per call.
      final ref = deviceDetail()('d1');
      final c = ref.options();
      final d = ref.options();
      expect(c.queryFn == d.queryFn, isFalse);
      expect(resolved(c), isNot(resolved(d)));
      // A family without a fetch function has nothing to bind.
      final bare = QueryFamily<String, Device>(namespace: devices, name: 'b');
      expect(resolved(bare('d1').options()), resolved(bare('d1').options()));
      client.clear();
    });

    test(
        'an observer handed a held definition\'s options again hears no '
        'change; a family reference\'s are a change every time', () {
      final client = testClient();
      List<String> optionEvents(List<String> events) => [
            for (final event in events)
              if (event.startsWith('observerOptionsUpdated')) event,
          ];

      // A definition held in a field, its options asked for per rebuild.
      final list = deviceList();
      final listObserver = QueryObserver(client, list.options());
      final events = recordEvents(client);
      listObserver
        ..setOptions(list.options())
        ..setOptions(list.options());
      expect(optionEvents(events), isEmpty);

      // The same definition made again per rebuild: a new function.
      listObserver.setOptions(deviceList().options());
      expect(optionEvents(events), ['observerOptionsUpdated devices/list']);
      events.clear();

      // A family's reference, however it is held.
      final ref = deviceDetail()('d1');
      final refObserver = QueryObserver(client, ref.options());
      events.clear();
      refObserver
        ..setOptions(ref.options())
        ..setOptions(ref.options());
      expect(optionEvents(events), [
        'observerOptionsUpdated devices/detail/d1',
        'observerOptionsUpdated devices/detail/d1',
      ]);

      // The control: raw options written inline, a closure per rebuild.
      QueryObserverOptions<int> raw() => QueryObserverOptions<int>(
            queryKey: QueryKey(const ['raw']),
            queryFn: (context) => 1,
          );
      final rawObserver = QueryObserver(client, raw());
      events.clear();
      rawObserver.setOptions(raw());
      expect(optionEvents(events), ['observerOptionsUpdated raw']);

      listObserver.destroy();
      refObserver.destroy();
      rawObserver.destroy();
      client.clear();
    });

    test('precedence: client, key defaults, definition, per use', () {
      const fromClient = StaleTime.duration(Duration(seconds: 1));
      const fromKey = StaleTime.duration(Duration(seconds: 2));
      const fromDefinition = StaleTime.duration(Duration(seconds: 3));
      const perUse = StaleTime.duration(Duration(seconds: 4));

      final client = testClient(
        defaultOptions: const DefaultOptions(
          queries: QueryDefaults(staleTime: fromClient, retryOnMount: false),
        ),
      );
      final configured = deviceDetail(
        configure: (base, id) => base.copyWith(staleTime: fromDefinition),
      );
      final plain = deviceDetail();
      StaleTime resolved(QueryObserverOptions<Device> options) =>
          client.defaultQueryObserverOptions<Device, Device>(options).staleTime;

      // Nothing above the client's default.
      expect(resolved(plain('d1').options()), fromClient);

      client.setQueryDefaults(
          devices.rawKey, const QueryDefaults(staleTime: fromKey));
      expect(resolved(plain('d1').options()), fromKey);
      expect(resolved(configured('d1').options()), fromDefinition);
      expect(
        resolved(configured('d1').options().copyWith(staleTime: perUse)),
        perUse,
      );
      // A per-use `copyWith` cannot unset: null keeps the definition's.
      expect(
        resolved(configured('d1').options().copyWith()),
        fromDefinition,
      );
      // A field nothing above the client names is the client's.
      expect(
        client
            .defaultQueryObserverOptions<Device, Device>(
              configured('d1').options(),
            )
            .retryOnMount,
        isFalse,
      );
      client.clear();
    });

    testFakeAsync('the definition\'s staleTime decides what fetch refetches',
        (time) async {
      final client = testClient();
      var fetches = 0;
      final ref = deviceDetail(
        queryFn: (id, context) {
          fetches++;
          return Device(id, name: 'fetch $fetches');
        },
        configure: (base, id) => base.copyWith(
          staleTime: const StaleTime.duration(Duration(minutes: 1)),
        ),
      )('d1');

      expect(await ref.fetch(client), const Device('d1', name: 'fetch 1'));
      await time.advance(const Duration(seconds: 59));
      expect(await ref.fetch(client), const Device('d1', name: 'fetch 1'));
      expect(fetches, 1);
      await time.advance(const Duration(seconds: 1));
      expect(await ref.fetch(client), const Device('d1', name: 'fetch 2'));
      client.clear();
    });

    testFakeAsync(
        'the definition\'s fetch function beats a default one; a definition '
        'without one takes the default', (time) async {
      final client = testClient();
      client.setQueryDefaults(
        devices.rawKey,
        QueryDefaults(
          queryFn: (context) =>
              Device('${context.queryKey.parts.last}', name: 'default'),
        ),
      );
      final own = deviceDetail(
        queryFn: (id, context) => Device(id, name: 'own'),
      );
      final keyOnly = QueryFamily<String, Device>(
        namespace: devices,
        name: 'detail',
      );
      expect(await own('d1').fetch(client), const Device('d1', name: 'own'));
      expect(
        await keyOnly('d2').fetch(client),
        const Device('d2', name: 'default'),
      );
      expect(entryType(client, keyOnly('d2').key.rawKey), Device);

      // A default function's result is checked when it arrives, not before.
      final wrong = QueryFamily<String, String>(
        namespace: devices,
        name: 'name',
      );
      await expectLater(
        wrong('d3').fetch(client),
        throwsA(dataTypeError(wrong('d3').key.rawKey, String, Device)),
      );
      client.clear();
    });

    testFakeAsync('a definition without a fetch function and no default fails',
        (time) async {
      final client = testClient();
      final keyOnly = QueryDefinition<Device?>(
        namespace: devices,
        name: 'selected',
      );
      await expectLater(keyOnly.fetch(client), throwsA(anything));
      // It is still an ordinary entry to write and read.
      keyOnly.write(client, const Device('d1'));
      expect(keyOnly.read(client), const Device('d1'));
      client.clear();
    });

    testFakeAsync('configure cannot move the key or swap the fetch function',
        (time) async {
      final client = testClient();
      final elsewhere = QueryKey(['elsewhere']);
      final detail = deviceDetail(
        queryFn: (id, context) => Device(id, name: 'the definition\'s'),
        configure: (base, id) => base.copyWith(
          queryKey: elsewhere,
          queryFn: (context) => const Device('x', name: 'configure\'s'),
        ),
      );
      final list = deviceList(
        queryFn: (context) => const [Device('the definition\'s')],
        configure: (base) => QueryObserverOptions<List<Device>>(
          queryKey: elsewhere,
          queryFn: (context) => const [Device('configure\'s')],
          meta: 'kept',
        ),
      );
      expect(detail('d1').options().queryKey, detail('d1').key.rawKey);
      expect(list.options().queryKey, list.key.rawKey);
      expect(list.options().meta, 'kept');
      expect(
        await detail('d1').fetch(client),
        const Device('d1', name: 'the definition\'s'),
      );
      expect(await list.fetch(client), const [Device('the definition\'s')]);
      expect(
          client.queryCache.findAll(filters: QueryFilters(queryKey: elsewhere)),
          isEmpty);
      client.clear();
    });

    testFakeAsync('configure may give a definition without one its function',
        (time) async {
      final client = testClient();
      final selected = QueryDefinition<Device?>(
        namespace: devices,
        name: 'selected',
        configure: (base) =>
            base.copyWith(queryFn: (context) => const Device('configured')),
      );
      final byInput = QueryFamily<String, Device>(
        namespace: devices,
        name: 'configured',
        configure: (base, id) => base.copyWith(
          queryFn: (context) => Device(id, name: 'configured'),
        ),
      );
      expect(await selected.fetch(client), const Device('configured'));
      expect(
        await byInput('d1').fetch(client),
        const Device('d1', name: 'configured'),
      );
      client.clear();
    });

    // `configure` is typed to return the definition's options, and options
    // of a narrower data type are a subtype of those: the analyzer accepts
    // them. The definition then cannot put its own fetch function back,
    // and where that is not noticed it hands out options that are not of
    // its type. So what `configure` returns is checked for the exact type.
    group('configure returns options of the definition\'s own type (S0-2)', () {
      Matcher wrongOptions(String key, Type returned, Type declared) => throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('configure'),
                contains(key),
                contains('$returned'),
                contains('$declared'),
              ),
            ),
          );

      test('a definition: refused when the options are made, with both types',
          () {
        final total = QueryDefinition<num>(
          namespace: devices,
          name: 'total',
          queryFn: (context) => 1.5,
          configure: (base) => QueryObserverOptions<int>(
            queryKey: base.queryKey,
          ),
        );
        expect(
          total.options,
          wrongOptions(
            '["devices","total"]',
            typeOf<QueryObserverOptions<int>>(),
            typeOf<QueryObserverOptions<num>>(),
          ),
        );
      });

      // Without a fetch function of its own the definition has nothing
      // that fails to fit the narrower options, so nothing but this check
      // stands between them and the caller.
      test('a definition without a fetch function is checked the same', () {
        final total = QueryDefinition<num>(
          namespace: devices,
          name: 'total',
          configure: (base) => QueryObserverOptions<int>(
            queryKey: base.queryKey,
            queryFn: (context) => 1,
          ),
        );
        expect(
          total.options,
          wrongOptions(
            '["devices","total"]',
            typeOf<QueryObserverOptions<int>>(),
            typeOf<QueryObserverOptions<num>>(),
          ),
        );
      });

      test('a family: refused per input, naming that input\'s key', () {
        final detail = deviceDetail(
          configure: (base, id) => QueryObserverOptions<Thermostat>(
            queryKey: base.queryKey,
          ),
        );
        // Binding is not making options: the reference exists.
        final reference = detail('d1');
        expect(
          reference.options,
          wrongOptions(
            '["devices","detail","d1"]',
            typeOf<QueryObserverOptions<Thermostat>>(),
            typeOf<QueryObserverOptions<Device>>(),
          ),
        );
      });

      testFakeAsync('nothing is fetched, and a write creates no entry',
          (time) async {
        final client = testClient();
        var fetches = 0;
        final detail = deviceDetail(
          queryFn: (id, context) {
            fetches++;
            return Device(id);
          },
          configure: (base, id) => QueryObserverOptions<Thermostat>(
            queryKey: base.queryKey,
          ),
        );
        expect(() => detail('d1').fetch(client), throwsStateError);
        // A write resolves the options to create the entry.
        expect(
          () => detail('d1').write(client, const Device('d1')),
          throwsStateError,
        );
        await time.advance(ms(10));
        expect(fetches, 0);
        expect(client.queryCache.findAll(), isEmpty);
        client.clear();
      });

      // The control: options of exactly the declared type pass, whether
      // they are the base changed or options made from nothing.
      testFakeAsync('options of the declared type pass, however they are made',
          (time) async {
        final client = testClient();
        final copied = deviceDetail(
          configure: (base, id) => base.copyWith(meta: 'copied'),
        );
        final untouched = deviceDetail(configure: (base, id) => base);
        final made = deviceDetail(
          configure: (base, id) => QueryObserverOptions<Device>(
            queryKey: base.queryKey,
            meta: 'made',
          ),
        );
        // Declared with a supertype as the static type of the closure's
        // result: what counts is the object, not how the closure is typed.
        Object build(QueryObserverOptions<Device> base, String id) =>
            base.copyWith(meta: 'wide');
        final wide = deviceDetail(
          configure: (base, id) =>
              build(base, id) as QueryObserverOptions<Device>,
        );
        expect(copied('d1').options().meta, 'copied');
        expect(untouched('d1').options().meta, isNull);
        expect(made('d1').options().meta, 'made');
        expect(wide('d1').options().meta, 'wide');
        expect(await made('d1').fetch(client), const Device('d1'));
        client.clear();
      });
    });

    testFakeAsync('the fetch function gets the input and the query\'s context',
        (time) async {
      final client = testClient();
      final seen = <Object?>[];
      final detail = QueryFamily<({String id, int revision}), Device>(
        namespace: devices,
        name: 'revision',
        queryFn: (input, context) {
          seen
            ..add(input)
            ..add(context.queryKey)
            ..add(identical(context.client, client));
          return Device(input.id);
        },
      );
      final ref = detail((id: 'd1', revision: 2));
      await ref.fetch(client);
      expect(seen, [(id: 'd1', revision: 2), ref.key.rawKey, true]);
      client.clear();
    });

    testFakeAsync('withSelect changes what an observer sees, not the entry',
        (time) async {
      final client = testClient();
      final ref = deviceDetail()('d1');
      final observer = QueryObserver<Device, String>(
        client,
        ref.options().withSelect((device) => device.name),
      );
      final names = <String?>[];
      final unsubscribe =
          observer.subscribe((result) => names.add(result.dataOrNull));
      await time.flushMicrotasks();
      ref.write(client, const Device('d1', name: 'selected'));
      expect(names.last, 'selected');
      expect(entryType(client, ref.key.rawKey), Device);
      unsubscribe();
      client.clear();
    });
  });

  group('fetch is client.query', () {
    // One scenario, run through the reference and through the client with
    // options written by hand: the requests made and every result must be
    // the same.
    Future<List<String>> scenario(
      FakeTime time,
      Future<Device> Function(QueryClient client, {bool revalidateIfStale})
              Function(Future<Device> Function() request)
          fetcher,
    ) async {
      final client = testClient();
      final log = <String>[];
      var requests = 0;
      var fail = false;
      final fetch = fetcher(() async {
        final request = ++requests;
        await sleep(ms(10));
        if (fail) {
          throw StateError('request $request');
        }
        return Device('d1', name: 'request $request');
      });

      Future<void> run(String step, {bool revalidateIfStale = false}) async {
        Object? outcome;
        var done = false;
        fetch(client, revalidateIfStale: revalidateIfStale).then<void>(
          (device) {
            outcome = device.name;
            done = true;
          },
          onError: (Object error) {
            outcome = '$error';
            done = true;
          },
        ).ignore();
        await time.flushMicrotasks();
        log.add('$step: ${done ? 'at once, $outcome' : 'pending'}');
        await time.advance(ms(10));
        log.add('$step: $outcome, $requests requests');
      }

      // Nothing cached: a request.
      await run('empty');
      // Fresh by the stale time: none.
      await run('fresh');
      // Stale: a request, awaited.
      await time.advance(const Duration(seconds: 30));
      await run('stale');
      // Stale, revalidating: the cached value at once, a request behind it.
      await time.advance(const Duration(seconds: 30));
      await run('revalidate', revalidateIfStale: true);
      // Two at once join one request.
      await time.advance(const Duration(seconds: 30));
      final first = fetch(client);
      final second = fetch(client);
      await time.advance(ms(10));
      log.add('joined: ${(await first).name}, ${(await second).name}, '
          '$requests requests');
      // A failure is thrown, and an imperative fetch does not retry.
      await time.advance(const Duration(seconds: 30));
      fail = true;
      await run('failing');
      await time.advance(const Duration(seconds: 40));
      log.add('after a backoff: $requests requests');
      client.clear();
      return log;
    }

    testFakeAsync('freshness, joining, revalidation and failure are the same',
        (time) async {
      const staleTime = StaleTime.duration(Duration(seconds: 20));
      final typed = await scenario(time, (request) {
        final ref = deviceDetail(
          queryFn: (id, context) => request(),
          configure: (base, id) => base.copyWith(staleTime: staleTime),
        )('d1');
        return ref.fetch;
      });
      final raw = await scenario(time, (request) {
        final options = QueryOptions<Device>(
          queryKey: QueryKey(['devices', 'detail', 'd1']),
          queryFn: (context) => request(),
          staleTime: staleTime,
        );
        return (client, {revalidateIfStale = false}) => client.query<Device>(
              options,
              revalidateIfStale: revalidateIfStale,
            );
      });
      expect(typed, raw);
      expect(typed, [
        'empty: pending',
        'empty: request 1, 1 requests',
        'fresh: at once, request 1',
        'fresh: request 1, 1 requests',
        'stale: pending',
        'stale: request 2, 2 requests',
        'revalidate: at once, request 2',
        'revalidate: request 2, 3 requests',
        'joined: request 4, request 4, 4 requests',
        'failing: pending',
        'failing: Bad state: request 5, 5 requests',
        'after a backoff: 5 requests',
      ]);
    });
  });

  group('exact for a reference, prefix for a family and a namespace', () {
    // Two details, the list, another family beside them, a key nested under
    // one detail and an entry of a namespace that only looks alike.
    ({
      QueryClient client,
      QueryFamily<String, Device> detail,
      QueryDefinition<List<Device>> list,
      QueryFamily<String, String> lookup,
      QueryKey nested,
      QueryKey lookalike,
    }) populated() {
      final client = testClient();
      final detail = deviceDetail();
      final list = deviceList();
      final lookup = QueryFamily<String, String>(
        namespace: devices,
        name: 'lookup',
      );
      detail('d1').write(client, const Device('d1'));
      detail('d2').write(client, const Device('d2'));
      list.write(client, const [Device('d1'), Device('d2')]);
      lookup('serial').write(client, 'd1');
      final nested = QueryKey(['devices', 'detail', 'd1', 'history']);
      client.setQueryData<Device>(nested, const Device('d1', name: 'old'));
      final lookalike = QueryKey(['devices2', 'detail', 'd1']);
      client.setQueryData<Device>(lookalike, const Device('d1'));
      return (
        client: client,
        detail: detail,
        list: list,
        lookup: lookup,
        nested: nested,
        lookalike: lookalike,
      );
    }

    List<String> selectedBy(QueryClient client, QueryTarget target) => [
          for (final query
              in client.queryCache.findAll(filters: target.filters()))
            query.queryKey.parts.join('/'),
        ];

    test('filters select one entry, a family\'s, a namespace\'s', () {
      final world = populated();
      expect(
        selectedBy(world.client, world.detail('d1')),
        ['devices/detail/d1'],
      );
      expect(selectedBy(world.client, world.list), ['devices/list']);
      // The nested key is under the family's prefix: selected with it.
      expect(selectedBy(world.client, world.detail), [
        'devices/detail/d1',
        'devices/detail/d2',
        'devices/detail/d1/history',
      ]);
      expect(selectedBy(world.client, world.lookup), ['devices/lookup/serial']);
      expect(selectedBy(world.client, devices), [
        'devices/detail/d1',
        'devices/detail/d2',
        'devices/list',
        'devices/lookup/serial',
        'devices/detail/d1/history',
      ]);
      world.client.clear();
    });

    test('filters carry the target\'s key and exactness, and every argument',
        () {
      final detail = deviceDetail();
      bool predicate(Query<Object?> query) => true;

      final exact = detail('d1').filters(
        type: QueryTypeFilter.inactive,
        stale: true,
        fetchStatus: FetchStatus.idle,
        status: QueryStatus.success,
        predicate: predicate,
      );
      expect(exact.queryKey, detail('d1').key.rawKey);
      expect(exact.exact, isTrue);
      expect(exact.type, QueryTypeFilter.inactive);
      expect(exact.stale, isTrue);
      expect(exact.fetchStatus, FetchStatus.idle);
      expect(exact.status, QueryStatus.success);
      expect(exact.predicate, same(predicate));

      final family = detail.filters();
      expect(family.queryKey, detail.rawKey);
      expect(family.exact, isFalse);
      expect(family.type, isNull);
      expect(family.stale, isNull);
      expect(family.fetchStatus, isNull);
      expect(family.status, isNull);
      expect(family.predicate, isNull);

      final namespace = devices.filters(stale: false);
      expect(namespace.queryKey, devices.rawKey);
      expect(namespace.exact, isFalse);
      expect(namespace.stale, isFalse);
    });

    test('filters narrow what the target selects', () {
      final world = populated();
      world.client.invalidateQueries(filters: world.detail('d2').filters());
      expect(
        world.client.queryCache
            .findAll(filters: world.detail.filters(stale: true))
            .map((query) => query.queryKey.parts.last),
        ['d2'],
      );
      expect(
        world.client.isFetching(filters: devices.filters()),
        0,
      );
      world.client.clear();
    });

    test('invalidate marks one entry, a family\'s, a namespace\'s', () async {
      List<String> invalidated(QueryClient client) => [
            for (final query in client.queryCache.findAll())
              if (query.state.isInvalidated) query.queryKey.parts.join('/'),
          ];

      var world = populated();
      await world.detail('d1').invalidate(world.client);
      expect(invalidated(world.client), ['devices/detail/d1']);
      world.client.clear();

      world = populated();
      await world.detail.invalidate(world.client);
      expect(invalidated(world.client), [
        'devices/detail/d1',
        'devices/detail/d2',
        'devices/detail/d1/history',
      ]);
      world.client.clear();

      world = populated();
      await devices.invalidate(world.client);
      expect(invalidated(world.client), [
        'devices/detail/d1',
        'devices/detail/d2',
        'devices/list',
        'devices/lookup/serial',
        'devices/detail/d1/history',
      ]);
      world.client.clear();
    });

    test('remove takes one entry, a family\'s, a namespace\'s', () {
      List<String> left(QueryClient client) => [
            for (final query in client.queryCache.findAll())
              query.queryKey.parts.join('/'),
          ];

      final world = populated();
      world.detail('d1').remove(world.client);
      expect(left(world.client), [
        'devices/detail/d2',
        'devices/list',
        'devices/lookup/serial',
        'devices/detail/d1/history',
        'devices2/detail/d1',
      ]);
      // Removed is absent: what a rollback restores.
      expect(world.detail('d1').state(world.client), isNull);

      world.detail.remove(world.client);
      expect(left(world.client), [
        'devices/list',
        'devices/lookup/serial',
        'devices2/detail/d1',
      ]);
      devices.remove(world.client);
      expect(left(world.client), ['devices2/detail/d1']);
      world.client.clear();
    });
  });

  group('the lifecycle operations are the client\'s', () {
    // Three observed details whose fetch can be counted, held and failed.
    ({
      QueryClient client,
      QueryFamily<String, Device> detail,
      Map<String, int> fetches,
      void Function() dispose,
    }) observed() {
      final client = testClient();
      final fetches = <String, int>{};
      final detail = deviceDetail(
        queryFn: (id, context) async {
          fetches[id] = (fetches[id] ?? 0) + 1;
          await sleep(ms(10));
          return Device(id, name: 'fetch ${fetches[id]}');
        },
      );
      final unsubscribes = [
        for (final id in ['d1', 'd2'])
          QueryObserver<Device, Device>(client, detail(id).options())
              .subscribe((result) {}),
      ];
      return (
        client: client,
        detail: detail,
        fetches: fetches,
        dispose: () {
          for (final unsubscribe in unsubscribes) {
            unsubscribe();
          }
          client.clear();
        },
      );
    }

    testFakeAsync('invalidate refetches what is observed, exactly or by prefix',
        (time) async {
      final world = observed();
      await time.advance(ms(10));
      expect(world.fetches, {'d1': 1, 'd2': 1});

      unawaited(world.detail('d1').invalidate(world.client));
      await time.advance(ms(10));
      expect(world.fetches, {'d1': 2, 'd2': 1});

      unawaited(world.detail.invalidate(world.client));
      await time.advance(ms(10));
      expect(world.fetches, {'d1': 3, 'd2': 2});

      // `refetchType` reaches the client: marked, not refetched.
      unawaited(
        devices.invalidate(world.client, refetchType: RefetchType.none),
      );
      await time.advance(ms(10));
      expect(world.fetches, {'d1': 3, 'd2': 2});
      expect(world.detail('d1').state(world.client)!.isInvalidated, isTrue);
      world.dispose();
    });

    testFakeAsync('invalidate and refetch pass cancelRefetch on', (time) async {
      final world = observed();
      await time.advance(ms(10));

      // A refetch in flight is kept when `cancelRefetch` is off...
      unawaited(world.detail('d1').refetch(world.client));
      await time.advance(ms(5));
      unawaited(world.detail('d1').refetch(world.client, cancelRefetch: false));
      unawaited(
        world.detail('d1').invalidate(world.client, cancelRefetch: false),
      );
      await time.advance(ms(10));
      expect(world.fetches['d1'], 2);

      // ...and replaced when it is on, the default.
      unawaited(world.detail('d1').refetch(world.client));
      await time.advance(ms(5));
      unawaited(world.detail('d1').refetch(world.client));
      await time.advance(ms(10));
      expect(world.fetches['d1'], 4);
      expect(world.fetches['d2'], 1);
      world.dispose();
    });

    testFakeAsync('refetch fetches one entry, or a family\'s', (time) async {
      final world = observed();
      await time.advance(ms(10));
      unawaited(world.detail('d2').refetch(world.client));
      await time.advance(ms(10));
      expect(world.fetches, {'d1': 1, 'd2': 2});
      unawaited(world.detail.refetch(world.client));
      await time.advance(ms(10));
      expect(world.fetches, {'d1': 2, 'd2': 3});
      unawaited(devices.refetch(world.client));
      await time.advance(ms(10));
      expect(world.fetches, {'d1': 3, 'd2': 4});
      world.dispose();
    });

    testFakeAsync('cancel stops one entry\'s fetch, and reverts it',
        (time) async {
      final world = observed();
      await time.advance(ms(10));
      unawaited(world.detail.refetch(world.client));
      await time.advance(ms(5));
      expect(world.client.isFetching(filters: world.detail.filters()), 2);

      await world.detail('d1').cancel(world.client);
      expect(world.client.isFetching(filters: world.detail.filters()), 1);
      expect(
        world.detail('d1').state(world.client)!.fetchStatus,
        FetchStatus.idle,
      );
      await time.advance(ms(10));
      expect(
        world.detail('d1').read(world.client),
        const Device('d1', name: 'fetch 1'),
      );
      expect(
        world.detail('d2').read(world.client),
        const Device('d2', name: 'fetch 2'),
      );
      world.dispose();
    });

    testFakeAsync('cancel passes revert and silent on', (time) async {
      // An unobserved first fetch, so that the cancellation has nothing to
      // go back to and an error to report or keep.
      Future<(QueryState<Device>, Object?)> cancelled({
        required bool revert,
        required bool silent,
      }) async {
        final client = testClient();
        final ref = deviceDetail(
          queryFn: (id, context) async {
            await sleep(ms(10));
            return Device(id);
          },
        )('d1');
        Object? thrown;
        ref.fetch(client).then<void>((_) {}, onError: (Object error) {
          thrown = error;
        }).ignore();
        await time.advance(ms(5));
        await ref.cancel(client, revert: revert, silent: silent);
        await time.flushMicrotasks();
        final state = ref.state(client)!;
        client.clear();
        return (state, thrown);
      }

      Future<(QueryState<Device>, Object?)> cancelledByClient({
        required bool revert,
        required bool silent,
      }) async {
        final client = testClient();
        final ref = deviceDetail(
          queryFn: (id, context) async {
            await sleep(ms(10));
            return Device(id);
          },
        )('d1');
        Object? thrown;
        ref.fetch(client).then<void>((_) {}, onError: (Object error) {
          thrown = error;
        }).ignore();
        await time.advance(ms(5));
        await client.cancelQueries(
          filters: ref.filters(),
          revert: revert,
          silent: silent,
        );
        await time.flushMicrotasks();
        final state = ref.state(client)!;
        client.clear();
        return (state, thrown);
      }

      for (final revert in [true, false]) {
        for (final silent in [true, false]) {
          final (state, thrown) =
              await cancelled(revert: revert, silent: silent);
          final (expectedState, expectedThrown) =
              await cancelledByClient(revert: revert, silent: silent);
          expect(
            (state.status, state.fetchStatus, state.error.runtimeType),
            (
              expectedState.status,
              expectedState.fetchStatus,
              expectedState.error.runtimeType,
            ),
            reason: 'revert: $revert, silent: $silent',
          );
          expect(thrown, isA<CancelledError>());
          final error = thrown! as CancelledError;
          final expected = expectedThrown! as CancelledError;
          expect(
              (error.revert, error.silent), (expected.revert, expected.silent));
          expect((error.revert, error.silent), (revert, silent));
        }
      }
    });

    testFakeAsync('reset puts an entry back and refetches it while observed',
        (time) async {
      final world = observed();
      await time.advance(ms(10));
      world.detail('d1').write(world.client, const Device('d1', name: 'local'));

      unawaited(world.detail('d1').reset(world.client));
      expect(world.detail('d1').state(world.client)!.hasData, isFalse);
      expect(world.detail('d2').state(world.client)!.hasData, isTrue);
      await time.advance(ms(10));
      expect(world.fetches, {'d1': 2, 'd2': 1});

      unawaited(world.detail.reset(world.client));
      expect(world.detail('d2').state(world.client)!.hasData, isFalse);
      await time.advance(ms(10));
      expect(world.fetches, {'d1': 3, 'd2': 2});

      unawaited(devices.reset(world.client, cancelRefetch: false));
      await time.advance(ms(10));
      expect(world.fetches, {'d1': 4, 'd2': 3});
      world.dispose();
    });
  });

  // A reset cancels what is in flight before it refetches, so its
  // `cancelRefetch` has something to act on only when a fetch starts
  // between the two, and only for an entry the reset left with data: a
  // seeded one, whose fetch a cache listener starts as it hears the reset.
  group('reset passes cancelRefetch on', () {
    Future<int> fetchesAfterReset(
      FakeTime time, {
      required bool? cancelRefetch,
    }) async {
      final client = testClient();
      var fetches = 0;
      final detail = deviceDetail(
        queryFn: (id, context) async {
          fetches++;
          await sleep(ms(10));
          return Device(id, name: 'fetch $fetches');
        },
        configure: (base, id) => base.copyWith(
          initialData: InitialData.value(Device(id, name: 'seed')),
        ),
      );
      final device = detail('d1');
      final unsubscribe =
          QueryObserver<Device, Device>(client, device.options())
              .subscribe((result) {});
      await time.advance(ms(10));
      expect(fetches, 1);

      var started = false;
      client.queryCache.subscribe((event) {
        // The reset's own update: the entry is back at its seed.
        if (!started &&
            event is QueryUpdated &&
            event.query.state.fetchStatus == FetchStatus.idle &&
            device.read(client)?.name == 'seed') {
          started = true;
          device.fetch(client).ignore();
        }
      });
      final done = cancelRefetch == null
          ? device.reset(client)
          : device.reset(client, cancelRefetch: cancelRefetch);
      expect(started, isTrue);
      await time.advance(ms(20));
      await done;
      final after = fetches - 1;
      unsubscribe();
      client.clear();
      return after;
    }

    testFakeAsync('off: the refetch joins the fetch already started',
        (time) async {
      expect(await fetchesAfterReset(time, cancelRefetch: false), 1);
    });

    testFakeAsync('on, the default: the refetch replaces it', (time) async {
      expect(await fetchesAfterReset(time, cancelRefetch: true), 2);
      expect(await fetchesAfterReset(time, cancelRefetch: null), 2);
    });

    // The control: the client's own call, over the same filters.
    testFakeAsync('as client.resetQueries does', (time) async {
      Future<int> raw(bool cancelRefetch) async {
        final client = testClient();
        var fetches = 0;
        final key = QueryKey(['devices', 'detail', 'd1']);
        final options = QueryObserverOptions<Device>(
          queryKey: key,
          queryFn: (context) async {
            fetches++;
            await sleep(ms(10));
            return Device('d1', name: 'fetch $fetches');
          },
          initialData: const InitialData.value(Device('d1', name: 'seed')),
        );
        final unsubscribe =
            QueryObserver<Device, Device>(client, options).subscribe((_) {});
        await time.advance(ms(10));
        var started = false;
        client.queryCache.subscribe((event) {
          if (!started &&
              event is QueryUpdated &&
              event.query.state.fetchStatus == FetchStatus.idle &&
              client.getQueryData<Device>(key)?.name == 'seed') {
            started = true;
            client.query(options).ignore();
          }
        });
        final done = client.resetQueries(
          filters: QueryFilters(queryKey: key, exact: true),
          cancelRefetch: cancelRefetch,
        );
        await time.advance(ms(20));
        await done;
        final after = fetches - 1;
        unsubscribe();
        client.clear();
        return after;
      }

      expect(await raw(false), 1);
      expect(await raw(true), 2);
    });
  });

  group('a family\'s bulk operations', () {
    ({
      QueryClient client,
      QueryFamily<String, Device> detail,
      QueryDefinition<List<Device>> list,
    }) populated() {
      final client = testClient();
      final detail = deviceDetail();
      final list = deviceList();
      detail('d1').write(client, const Device('d1', name: 'one'));
      detail('d2').write(client, const Device('d2', name: 'two'));
      list.write(client, const [Device('d1'), Device('d2')]);
      return (client: client, detail: detail, list: list);
    }

    test('readAll returns every input\'s data under its typed key', () {
      final world = populated();
      // An entry without data reads as null.
      world.client.queryCache.build<Device>(
        world.client,
        world.client.defaultQueryOptions<Device>(world.detail('d3').options()),
      );
      final all = world.detail.readAll(world.client);
      expect(all, [
        (world.detail('d1').key, const Device('d1', name: 'one')),
        (world.detail('d2').key, const Device('d2', name: 'two')),
        (world.detail('d3').key, null),
      ]);
      // A typed key from the result reads its entry again.
      expect(all.first.$1.read(world.client), const Device('d1', name: 'one'));
      world.client.clear();
    });

    test('readAll refuses an entry of another type under the prefix', () {
      final world = populated();
      final nested = QueryKey(['devices', 'detail', 'd1', 'history']);
      world.client.setQueryData<String>(nested, 'log');
      expect(
        () => world.detail.readAll(world.client),
        throwsA(dataTypeError(nested, Device, String)),
      );
      world.client.clear();
    });

    test('updateAll writes every input and nothing beside the family', () {
      final world = populated();
      final updated = world.detail.updateAll(
        world.client,
        (previous) => previous!.renamed('${previous.name}!'),
      );
      expect(updated, [
        (world.detail('d1').key, const Device('d1', name: 'one!')),
        (world.detail('d2').key, const Device('d2', name: 'two!')),
      ]);
      expect(
        world.detail('d1').read(world.client),
        const Device('d1', name: 'one!'),
      );
      expect(
        world.detail('d2').read(world.client),
        const Device('d2', name: 'two!'),
      );
      expect(world.list.read(world.client), const [Device('d1'), Device('d2')]);
      expect(world.list.state(world.client)!.dataUpdateCount, 1);
      world.client.clear();
    });

    test('an updater returning null leaves that entry as it is', () {
      final world = populated();
      final events = recordEvents(world.client);
      final updated = world.detail.updateAll(
        world.client,
        (previous) => previous!.id == 'd2' ? previous.renamed('changed') : null,
      );
      expect(updated, [
        (world.detail('d1').key, null),
        (world.detail('d2').key, const Device('d2', name: 'changed')),
      ]);
      expect(events, ['updated devices/detail/d2']);
      expect(world.detail('d1').state(world.client)!.dataUpdateCount, 1);
      world.client.clear();
    });

    test('an entry without data gets null, and is written when one returns',
        () {
      final world = populated();
      world.client.queryCache.build<Device>(
        world.client,
        world.client.defaultQueryOptions<Device>(world.detail('d3').options()),
      );
      final seen = <Device?>[];
      world.detail.updateAll(world.client, (previous) {
        seen.add(previous);
        return previous ?? const Device('d3', name: 'new');
      });
      expect(seen.last, isNull);
      expect(
        world.detail('d3').read(world.client),
        const Device('d3', name: 'new'),
      );
      world.client.clear();
    });

    test('updatedAt dates every write', () {
      final world = populated();
      final at = DateTime.utc(2020, 2, 2);
      world.detail.updateAll(
        world.client,
        (previous) => previous!.renamed('dated'),
        updatedAt: at,
      );
      expect(world.detail('d1').state(world.client)!.dataUpdatedAt, at);
      expect(world.detail('d2').state(world.client)!.dataUpdatedAt, at);
      world.client.clear();
    });

    test('an empty family updates nothing and returns nothing', () {
      final client = testClient();
      var ran = false;
      expect(
        deviceDetail().updateAll(client, (previous) {
          ran = true;
          return previous;
        }),
        isEmpty,
      );
      expect(ran, isFalse);
      client.clear();
    });

    testFakeAsync('every updater runs before the first write, in one batch',
        (time) async {
      // What is cached at each step, through the typed and the raw bulk
      // update: the same.
      Future<List<String>> run(bool typed) async {
        final world = populated();
        final order = <String>[];
        String cached() => world.detail
            .readAll(world.client)
            .map((entry) => entry.$2!.name)
            .join(' ');
        world.client.queryCache
          ..subscribe(
            (event) => order.add(
              '${eventName(event)} ${event.query.queryKey.parts.last}: '
              '${cached()}',
            ),
          )
          ..subscribe(
            world.client.notifyManager.batchCalls(
              (event) => order.add(
                'batched ${eventName(event)} '
                '${event.query.queryKey.parts.last}: ${cached()}',
              ),
            ),
          );
        final unsubscribe = QueryObserver<Device, Device>(
          world.client,
          world.detail('d1').options().copyWith(enabled: Enabled.no),
        ).subscribe((result) => order.add('observer: ${cached()}'));
        await time.flushMicrotasks();
        order.clear();

        Device? updater(Device? previous) {
          order.add('updater ${previous!.id}: ${cached()}');
          return previous.renamed('${previous.name}!');
        }

        if (typed) {
          world.detail.updateAll(world.client, updater);
        } else {
          world.client.updateQueriesData<Device>(
            updater,
            filters: world.detail.filters(),
          );
        }
        order.add('returned');
        await time.flushMicrotasks();
        final recorded = [...order];
        unsubscribe();
        world.client.clear();
        return recorded;
      }

      final typed = await run(true);
      expect(typed, await run(false));
      // No updater sees another's result. A direct listener hears each
      // write as it is made, as always; what goes through the notify
      // manager waits for the last one.
      expect(typed, [
        'updater d1: one two',
        'updater d2: one two',
        'observer: one! two',
        'observerResultsUpdated d1: one! two',
        'updated d1: one! two',
        'updated d2: one! two!',
        'returned',
        'batched observerResultsUpdated d1: one! two!',
        'batched updated d1: one! two!',
        'batched updated d2: one! two!',
      ]);
    });

    test(
        'an entry of another type under the prefix: nothing runs or is written',
        () {
      final world = populated();
      final nested = QueryKey(['devices', 'detail', 'd1', 'history']);
      // No data, and still another type: the client's bulk update lets it
      // pass, the typed one does not.
      world.client.queryCache.build<String>(
        world.client,
        world.client.defaultQueryOptions<String>(
            QueryOptions<String>(queryKey: nested)),
      );
      final events = recordEvents(world.client);
      var ran = 0;
      expect(
        () => world.detail.updateAll(world.client, (previous) {
          ran++;
          return previous?.renamed('changed');
        }),
        throwsA(dataTypeError(nested, Device, String)),
      );
      expect(ran, 0);
      expect(events, isEmpty);
      expect(
        () => world.detail.readAll(world.client),
        throwsA(dataTypeError(nested, Device, String)),
      );

      // The control: the client's own bulk update completes and writes.
      world.client.updateQueriesData<Device>(
        (previous) => previous?.renamed('raw'),
        filters: world.detail.filters(),
      );
      expect(
        world.client.getQueryData<Device>(world.detail('d1').key.rawKey),
        const Device('d1', name: 'raw'),
      );
      world.client.clear();
    });

    test('a wider entry under the prefix: refused where the client writes', () {
      final world = populated();
      final wider = world.detail('d3').key.rawKey;
      world.client
          .setQueryData<Device?>(wider, const Device('d3', name: 'raw'));
      final events = recordEvents(world.client);
      expect(
        () => world.detail.updateAll(
          world.client,
          (previous) => previous?.renamed('changed'),
        ),
        throwsA(dataTypeError(wider, Device, typeOf<Device?>())),
      );
      expect(events, isEmpty);
      expect(
        world.detail('d1').read(world.client),
        const Device('d1', name: 'one'),
      );

      world.client.updateQueriesData<Device>(
        (previous) => previous?.renamed('changed'),
        filters: world.detail.filters(),
      );
      expect(
        world.client.getQueryData<Device?>(wider),
        const Device('d3', name: 'changed'),
      );
      world.client.clear();
    });

    test('an updater that throws for a later entry: no earlier one is written',
        () {
      final world = populated();
      final events = recordEvents(world.client);
      expect(
        () => world.detail.updateAll(
          world.client,
          (previous) => previous!.id == 'd2'
              ? throw StateError('d2')
              : previous.renamed('changed'),
        ),
        throwsStateError,
      );
      expect(events, isEmpty);
      expect(
        world.detail('d1').read(world.client),
        const Device('d1', name: 'one'),
      );
      world.client.clear();
    });

    test('through a widened family a wrong result is refused, nothing written',
        () {
      final world = populated();
      final QueryFamily<Object?, Object?> wide = world.detail;
      final events = recordEvents(world.client);
      expect(
        () => wide.updateAll(world.client, (previous) => 'not a device'),
        refusedAtRuntime,
      );
      expect(events, isEmpty);
      world.client.clear();
    });

    // What the caller's code does to the cache while the updaters run. The
    // rule is the client's bulk update's, and each case runs through both.
    group('re-entrant updaters', () {
      // The same world and the same updater through the typed and the raw
      // bulk update: the events and what is cached afterwards.
      ({List<String> events, Map<String, Object?> cached, Object? thrown}) run(
        bool typed,
        Device? Function(
          QueryClient client,
          QueryFamily<String, Device> detail,
          Device? previous,
        ) updater,
      ) {
        final world = populated();
        final events = recordEvents(world.client);
        Object? thrown;
        try {
          if (typed) {
            world.detail.updateAll(
              world.client,
              (previous) => updater(world.client, world.detail, previous),
            );
          } else {
            world.client.updateQueriesData<Device>(
              (previous) => updater(world.client, world.detail, previous),
              filters: world.detail.filters(),
            );
          }
        } on Object catch (error) {
          thrown = error;
        }
        final cached = {
          for (final query in world.client.queryCache
              .findAll(filters: world.detail.filters()))
            '${query.queryKey.parts.last} ${query.dataType}': query.state.data,
        };
        final recorded = [...events];
        world.client.clear();
        return (events: recorded, cached: cached, thrown: thrown);
      }

      test('an entry removed by an updater is made again by its write', () {
        Device? updater(
          QueryClient client,
          QueryFamily<String, Device> detail,
          Device? previous,
        ) {
          if (previous!.id == 'd1') {
            detail('d2').remove(client);
          }
          // `d2`'s updater still runs, on what was read before any ran.
          return previous.renamed('${previous.name}!');
        }

        final typed = run(true, updater);
        expect(typed.thrown, isNull);
        expect(typed.cached, {
          'd1 Device': const Device('d1', name: 'one!'),
          'd2 Device': const Device('d2', name: 'two!'),
        });
        expect(typed.events, [
          'removed devices/detail/d2',
          'updated devices/detail/d1',
          'added devices/detail/d2',
          'updated devices/detail/d2',
        ]);
        final raw = run(false, updater);
        expect(typed.events, raw.events);
        expect(typed.cached, raw.cached);
      });

      test('an entry added by an updater is not part of the call', () {
        var calls = 0;
        Device? updater(
          QueryClient client,
          QueryFamily<String, Device> detail,
          Device? previous,
        ) {
          calls++;
          detail('d3').write(client, const Device('d3', name: 'added'));
          return previous!.renamed('${previous.name}!');
        }

        final typed = run(true, updater);
        expect(calls, 2);
        expect(typed.cached, {
          'd1 Device': const Device('d1', name: 'one!'),
          'd2 Device': const Device('d2', name: 'two!'),
          'd3 Device': const Device('d3', name: 'added'),
        });
        final raw = run(false, updater);
        expect(typed.events, raw.events);
        expect(typed.cached, raw.cached);
      });

      test('an updater sees what was cached before the call, whatever it wrote',
          () {
        final seen = <String>[];
        Device? updater(
          QueryClient client,
          QueryFamily<String, Device> detail,
          Device? previous,
        ) {
          seen.add(previous!.name);
          detail('d2').write(client, const Device('d2', name: 're-entrant'));
          return previous.renamed('${previous.name}!');
        }

        final typed = run(true, updater);
        expect(seen, ['one', 'two']);
        // The call's own result wins: it is written last.
        expect(typed.cached['d2 Device'], const Device('d2', name: 'two!'));
        seen.clear();
        final raw = run(false, updater);
        expect(seen, ['one', 'two']);
        expect(typed.events, raw.events);
        expect(typed.cached, raw.cached);
      });

      // Here the two part: the client's write takes any entry that can hold
      // the value. The typed call looks every entry up once more after the
      // updaters ran, so a swap one of them made refuses the whole call
      // before its first write.
      test('an entry swapped for a wider one refuses the call, nothing written',
          () {
        Device? updater(
          QueryClient client,
          QueryFamily<String, Device> detail,
          Device? previous,
        ) {
          if (previous!.id == 'd1') {
            final key = detail('d2').key.rawKey;
            client
              ..removeQueries(filters: QueryFilters(queryKey: key, exact: true))
              ..setQueryData<Device?>(key, const Device('d2', name: 'wider'));
          }
          return previous.renamed('${previous.name}!');
        }

        final typed = run(true, updater);
        expect(
          typed.thrown,
          dataTypeError(
            QueryKey(['devices', 'detail', 'd2']),
            Device,
            typeOf<Device?>(),
          ),
        );
        // `d1` is not written either: what the cache holds is what the
        // updater itself did to it.
        expect(typed.cached, {
          'd1 Device': const Device('d1', name: 'one'),
          'd2 Device?': const Device('d2', name: 'wider'),
        });
        expect(typed.events, [
          'removed devices/detail/d2',
          'added devices/detail/d2',
          'updated devices/detail/d2'
        ]);

        final raw = run(false, updater);
        expect(raw.thrown, isNull);
        expect(raw.cached, {
          'd1 Device': const Device('d1', name: 'one!'),
          'd2 Device?': const Device('d2', name: 'two!'),
        });
      });
    });

    // What is left of "not a transaction": the writes are made one after
    // the other, and a cache listener hears each. One that answers the
    // first write by swapping a later entry makes that entry's write
    // throw, with the first one made. The client's own bulk update writes
    // into the wider entry instead.
    test('a listener that swaps an entry during the writes: the earlier stay',
        () {
      ({Map<String, Object?> cached, Object? thrown}) run(bool typed) {
        final world = populated();
        final swapped = world.detail('d2').key.rawKey;
        var done = false;
        world.client.queryCache.subscribe((event) {
          if (!done && event is QueryUpdated) {
            done = true;
            world.client
              ..removeQueries(
                filters: QueryFilters(queryKey: swapped, exact: true),
              )
              ..setQueryData<Device?>(
                swapped,
                const Device('d2', name: 'wider'),
              );
          }
        });
        Device? updater(Device? previous) =>
            previous!.renamed('${previous.name}!');
        Object? thrown;
        try {
          if (typed) {
            world.detail.updateAll(world.client, updater);
          } else {
            world.client.updateQueriesData<Device>(
              updater,
              filters: world.detail.filters(),
            );
          }
        } on Object catch (error) {
          thrown = error;
        }
        final cached = {
          for (final query in world.client.queryCache
              .findAll(filters: world.detail.filters()))
            '${query.queryKey.parts.last} ${query.dataType}': query.state.data,
        };
        world.client.clear();
        return (cached: cached, thrown: thrown);
      }

      final typed = run(true);
      expect(
        typed.thrown,
        dataTypeError(
          QueryKey(['devices', 'detail', 'd2']),
          Device,
          typeOf<Device?>(),
        ),
      );
      expect(typed.cached, {
        'd1 Device': const Device('d1', name: 'one!'),
        'd2 Device?': const Device('d2', name: 'wider'),
      });

      final raw = run(false);
      expect(raw.thrown, isNull);
      expect(raw.cached, {
        'd1 Device': const Device('d1', name: 'one!'),
        'd2 Device?': const Device('d2', name: 'two!'),
      });
    });

    // Review of the core, SC-1 and SC-2: what the writes of one batch do
    // when the entry under one of them changed since the batch began, and
    // what is left when one of them fails. Each case runs through the
    // client's own bulk update as well.
    group('the writes of a batch (SC-1, SC-2)', () {
      /// A bulk update, typed or the client's, over `d1` and `d2` while
      /// [listener] hears every cache event: what it threw and what the
      /// family's entries hold afterwards.
      ({Map<String, Object?> cached, Object? thrown}) bulk(
        bool typed, {
        QueryFamily<String, Device>? family,
        void Function(
          QueryClient client,
          QueryFamily<String, Device> detail,
          QueryCacheEvent event,
        )? listener,
        Device? Function(
          QueryClient client,
          QueryFamily<String, Device> detail,
          Device? previous,
        )? updater,
      }) {
        final client = testClient();
        final detail = family ?? deviceDetail();
        detail('d1').write(client, const Device('d1', name: 'one'));
        detail('d2').write(client, const Device('d2', name: 'two'));
        if (listener != null) {
          client.queryCache.subscribe(
            (event) => listener(client, detail, event),
          );
        }
        Device? update(Device? previous) => updater == null
            ? previous!.renamed('${previous.name}!')
            : updater(client, detail, previous);
        Object? thrown;
        try {
          if (typed) {
            detail.updateAll(client, update);
          } else {
            client.updateQueriesData<Device>(
              update,
              filters: detail.filters(),
            );
          }
        } on Object catch (error) {
          thrown = error;
        }
        final cached = {
          for (final query
              in client.queryCache.findAll(filters: detail.filters()))
            '${query.queryKey.parts.last} ${query.dataType}': query.state.data,
        };
        client.clear();
        return (cached: cached, thrown: thrown);
      }

      final d2 = QueryKey(['devices', 'detail', 'd2']);

      /// An updater that removes `d2` before the writes, so that `d2`'s
      /// write makes the entry again and the cache's listeners hear of it.
      Device? removingD2(
        QueryClient client,
        QueryFamily<String, Device> detail,
        Device? previous,
      ) {
        if (previous!.id == 'd1') {
          detail('d2').remove(client);
        }
        return previous.renamed('${previous.name}!');
      }

      test('a later entry removed by a listener is made again by its write',
          () {
        ({Map<String, Object?> cached, Object? thrown}) run(bool typed) {
          var done = false;
          return bulk(
            typed,
            listener: (client, detail, event) {
              if (!done && event is QueryUpdated) {
                done = true;
                detail('d2').remove(client);
              }
            },
          );
        }

        final typed = run(true);
        expect(typed.thrown, isNull);
        expect(typed.cached, {
          'd1 Device': const Device('d1', name: 'one!'),
          'd2 Device': const Device('d2', name: 'two!'),
        });
        final raw = run(false);
        expect(raw.thrown, isNull);
        expect(raw.cached, typed.cached);
      });

      test(
          'a later entry replaced by a listener with one of the same type: '
          'that one is written', () {
        ({Map<String, Object?> cached, Object? thrown}) run(bool typed) {
          var done = false;
          return bulk(
            typed,
            listener: (client, detail, event) {
              if (!done && event is QueryUpdated) {
                done = true;
                detail('d2').remove(client);
                client.setQueryData<Device>(
                  d2,
                  const Device('d2', name: 'listener'),
                );
              }
            },
          );
        }

        final typed = run(true);
        expect(typed.thrown, isNull);
        expect(typed.cached, {
          'd1 Device': const Device('d1', name: 'one!'),
          'd2 Device': const Device('d2', name: 'two!'),
        });
        final raw = run(false);
        expect(raw.thrown, isNull);
        expect(raw.cached, typed.cached);
      });

      test(
          'an entry made again in the batch, and another type put in its '
          'place when it was added: refused, the earlier write stays', () {
        ({Map<String, Object?> cached, Object? thrown}) run(bool typed) => bulk(
              typed,
              updater: removingD2,
              listener: (client, detail, event) {
                if (event is QueryAdded && event.query.dataType == Device) {
                  detail('d2').remove(client);
                  client.setQueryData<String>(d2, 'replacement');
                }
              },
            );

        final typed = run(true);
        expect(typed.thrown, dataTypeError(d2, Device, String));
        expect(typed.cached, {
          'd1 Device': const Device('d1', name: 'one!'),
          'd2 String': 'replacement',
        });
        // The control: the client's update reports a write it lost.
        final raw = run(false);
        expect(raw.thrown, isNull);
        expect(raw.cached, typed.cached);
      });

      test(
          'an entry made again in the batch and removed when it was added: '
          'StateError, the earlier write stays', () {
        ({Map<String, Object?> cached, Object? thrown}) run(bool typed) => bulk(
              typed,
              updater: removingD2,
              listener: (client, detail, event) {
                if (event is QueryAdded) {
                  detail('d2').remove(client);
                }
              },
            );

        final typed = run(true);
        expect(typed.thrown, isStateError);
        expect(typed.cached, {'d1 Device': const Device('d1', name: 'one!')});
        final raw = run(false);
        expect(raw.thrown, isNull);
        expect(raw.cached, typed.cached);
      });

      // SC-2. Every type check passes and every updater returns a value;
      // the second write fails in its entry's own `structuralSharing`.
      test(
          'a structuralSharing that throws at a later entry: the earlier '
          'write stays, as with the client\'s update', () {
        ({Map<String, Object?> cached, Object? thrown}) run(bool typed) => bulk(
              typed,
              family: deviceDetail(
                configure: (base, id) => base.copyWith(
                  structuralSharing: (previous, next) =>
                      previous != null && next.id == 'd2'
                          ? throw StateError('sharing rejected')
                          : next,
                ),
              ),
            );

        for (final result in [run(true), run(false)]) {
          expect(
            result.thrown,
            isStateError.having(
                (e) => e.message, 'message', 'sharing rejected'),
          );
          expect(result.cached, {
            'd1 Device': const Device('d1', name: 'one!'),
            'd2 Device': const Device('d2', name: 'two'),
          });
        }
      });

      test(
          'the same when an updater installed it: the second lookup looks '
          'at types, not at what a write will run', () {
        ({Map<String, Object?> cached, Object? thrown}) run(bool typed) => bulk(
              typed,
              updater: (client, detail, previous) {
                if (previous!.id == 'd1') {
                  // An observer hands its options to the entry it is for.
                  QueryObserver<Device, Device>(
                    client,
                    detail('d2').options().copyWith(
                          structuralSharing: (previous, next) =>
                              throw StateError('sharing rejected'),
                        ),
                  );
                }
                return previous.renamed('${previous.name}!');
              },
            );

        for (final result in [run(true), run(false)]) {
          expect(
            result.thrown,
            isStateError.having(
                (e) => e.message, 'message', 'sharing rejected'),
          );
          expect(result.cached, {
            'd1 Device': const Device('d1', name: 'one!'),
            'd2 Device': const Device('d2', name: 'two'),
          });
        }
      });

      test('a listener that throws stops no write: its error goes to the zone',
          () {
        for (final typed in [true, false]) {
          final uncaught = <Object>[];
          late final ({Map<String, Object?> cached, Object? thrown}) result;
          runZonedGuarded(
            () => result = bulk(
              typed,
              listener: (client, detail, event) {
                if (event is QueryUpdated) {
                  throw StateError('listener');
                }
              },
            ),
            (error, stackTrace) => uncaught.add(error),
          );
          expect(result.thrown, isNull);
          expect(result.cached, {
            'd1 Device': const Device('d1', name: 'one!'),
            'd2 Device': const Device('d2', name: 'two!'),
          });
          expect(uncaught, [isStateError, isStateError]);
        }
      });
    });

    test(
        'an entry made again by a bulk write is plain: a family cannot know '
        'its input', () {
      final client = testClient();
      final detail = deviceDetail(
        configure: (base, id) => base.copyWith(gcTime: GcTime.never),
      );
      detail('d1').write(client, const Device('d1'));
      detail('d2').write(client, const Device('d2'));
      detail.updateAll(client, (previous) {
        if (previous!.id == 'd1') {
          detail('d2').remove(client);
        }
        return previous.renamed('again');
      });
      expect(entry(client, detail('d1').key.rawKey).gcTime, GcTime.never);
      expect(
          entry(client, detail('d2').key.rawKey).gcTime, GcTime.defaultValue);
      client.clear();
    });
  });

  group('debug checks on a definition\'s type arguments', () {
    void refused(Object? Function() declare, List<String> message) {
      if (!assertionsOn) {
        expect(declare(), isNotNull);
        return;
      }
      expect(
        declare,
        throwsA(
          isA<AssertionError>().having(
            (error) => '${error.message}',
            'message',
            allOf([for (final part in message) contains(part)]),
          ),
        ),
      );
    }

    test('a top type is what a forgotten type argument infers', () {
      refused(
        () => QueryDefinition<dynamic>(namespace: devices, name: 'x'),
        ['QueryDefinition', 'the type argument T', 'dynamic'],
      );
      refused(
        () => QueryDefinition<Object?>(namespace: devices, name: 'x'),
        ['QueryDefinition', 'the type argument T', 'Object?'],
      );
      refused(
        () => QueryDefinition<void>(namespace: devices, name: 'x'),
        ['QueryDefinition', 'the type argument T', 'void'],
      );
      refused(
        () => QueryFamily<Object?, Device>(namespace: devices, name: 'x'),
        ['QueryFamily', 'the type argument TInput', 'Object?'],
      );
      refused(
        () => QueryFamily<String, dynamic>(namespace: devices, name: 'x'),
        ['QueryFamily', 'the type argument T ', 'dynamic'],
      );
      // What it looks like when it happens: no type arguments, and closures
      // that give inference nothing.
      refused(
        // ignore: inference_failure_on_instance_creation
        () => QueryFamily(namespace: devices, name: 'x'),
        ['QueryFamily', 'write them out'],
      );
    });

    test('Null is not a data type', () {
      refused(
        () => QueryDefinition<Null>(namespace: devices, name: 'x'),
        ['QueryDefinition', 'the data type is Null'],
      );
      refused(
        () => QueryFamily<String, Null>(namespace: devices, name: 'x'),
        ['QueryFamily', 'the data type is Null'],
      );
    });

    test('Object, a nullable and a sealed type are real choices', () {
      expect(
        QueryFamily<Object, Device>(namespace: devices, name: 'any')(42)
            .key
            .rawKey,
        QueryKey(['devices', 'any', 42]),
      );
      expect(
        QueryFamily<String?, Device?>(namespace: devices, name: 'maybe')(null)
            .key
            .rawKey,
        QueryKey(['devices', 'maybe', null]),
      );
      expect(
        QueryDefinition<Reading>(namespace: devices, name: 'reading')
            .key
            .dataType,
        Reading,
      );
      expect(
        QueryDefinition<Object>(namespace: devices, name: 'anything')
            .key
            .dataType,
        Object,
      );
    });
  });
}
