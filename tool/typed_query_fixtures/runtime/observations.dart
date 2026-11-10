/// What the analyzer cannot answer: the surface run, not analyzed. One line
/// per observation, `id | what was done | what happened`, compared by the
/// runner with a recorded file per runtime:
///
/// * `observations.debug.expect`: the VM with assertions on;
/// * `observations.release.expect`: the VM without them, and dart2js at
///   its default level, which both check covariant parameters;
/// * `observations.unchecked.expect`: dart2js at `-O3` and `-O4`, which
///   omit that check (`-O4` is Flutter's web release build).
///
/// Open-7 is the `O7` block; D4's fixture that is not about types is the
/// `D4` block. Nothing here prints a type's own name, a hash code or a
/// message: dart2js minifies type names, so every label is decided by an
/// `is` test or a `Type` comparison.
library;

import 'dart:async';

import '../support/client_style_setter.dart';
import '../support/models.dart';
import '../support/namespace_factories.dart';
import '../surface.dart';

Future<void> main() async {
  _open7Controls();
  _open7Surface();
  _d2GenericSetter();
  _d4Values();
  _d5DeclaredTypes();
  _d5Infinite();
  await _d7Prefixes();
  _d9MixedList();
  _d10Backstop();
  _keyOfDefault();
  await _fetching();
  // A client owns `gcTime` timers; node would wait for them.
  for (final client in _clients) {
    client.clear();
  }
}

// ---------------------------------------------------------------- Open-7

/// The smallest covariant parameter there is.
final class _Box<T> {
  Object? held;

  void put(T value) => held = value;
}

/// A reference without D2's explicit check: the typed operations as plain
/// delegation to the raw client.
final class _NaiveRef<T> {
  _NaiveRef(this.rawKey);

  final QueryKey rawKey;

  T write(QueryClient client, T value) => client.setQueryData<T>(rawKey, value);

  T? update(QueryClient client, T? Function(T? previous) updater) =>
      client.updateQueryData<T>(rawKey, updater);

  void updateAll(
    QueryClient client,
    QueryKey prefix,
    T? Function(T? previous) updater,
  ) =>
      client.updateQueriesData<T>(
        updater,
        filters: QueryFilters(queryKey: prefix),
      );
}

void _open7Controls() {
  // Dart's own check, with no library code involved.
  final _Box<Object?> box = _Box<Device>();
  final put = _attempt(() => box.put('not a device'));
  _note(
    'O7-control-1',
    'a String into a Box<Device> held as Box<Object?>',
    put == 'completed' ? 'no check: the Box holds ${_value(box.held)}' : put,
  );

  // The same widening over plain delegation to the raw client.
  final client = _client();
  final writeKey = QueryKey(const ['naive', 'write']);
  final _NaiveRef<Object?> write = _NaiveRef<Device>(writeKey);
  _note(
    'O7-control-2',
    'naive write of a String, delegating to setQueryData<Device>',
    '${_attempt(() => write.write(client, 'not a device'))}; '
        'cache: ${_entry(client, writeKey)}',
  );

  final updateKey = QueryKey(const ['naive', 'update']);
  client.setQueryData<Device>(updateKey, const Device('d1'));
  final _NaiveRef<Object?> update = _NaiveRef<Device>(updateKey);
  _note(
    'O7-control-3',
    'naive update returning an int, delegating to updateQueryData<Device>',
    '${_attempt(() => update.update(client, (previous) => 42))}; '
        'cache: ${_entry(client, updateKey)}',
  );

  final prefix = QueryKey(const ['naive', 'bulk']);
  final member = prefix.append(const ['a']);
  client.setQueryData<Device>(member, const Device('a'));
  final _NaiveRef<Object?> bulk = _NaiveRef<Device>(prefix);
  _note(
    'O7-control-4',
    'naive bulk update returning a String, delegating to '
        'updateQueriesData<Device>',
    '${_attempt(() => bulk.updateAll(client, prefix, (previous) => 'x'))}; '
        'cache: ${_entry(client, member)}',
  );
}

void _open7Surface() {
  final queries = DeviceQueries(const DeviceRepository());

  // A single write.
  {
    final client = _client();
    final device = queries.detail('d1');
    final QueryRef<Object?> widened = device;
    _note(
      'O7-write-1',
      'write of a String through a QueryRef<Device> held as '
          'QueryRef<Object?>, no entry yet',
      '${_attempt(() => widened.write(client, 'not a device'))}; '
          'cache: ${_entry(client, device.key.rawKey)}',
    );
    device.write(client, const Device('d1', name: 'kept'));
    _note(
      'O7-write-2',
      'the same with a Device cached',
      '${_attempt(() => widened.write(client, 'not a device'))}; '
          'cache: ${_entry(client, device.key.rawKey)}, '
          'kept: ${device.read(client)?.name == 'kept'}',
    );
    final QueryEntryRef<Object?> entry = device;
    _note(
      'O7-write-3',
      'write of an int through the same reference held as '
          'QueryEntryRef<Object?>',
      '${_attempt(() => entry.write(client, 42))}; '
          'kept: ${device.read(client)?.name == 'kept'}',
    );
    _note(
      'O7-write-4',
      'the valid write through the widened reference',
      '${_attempt(() => widened.write(client, const Device('d1')))}; '
          'cache: ${_entry(client, device.key.rawKey)}',
    );
  }

  // Nullable data.
  {
    final client = _client();
    final lookup = queries.lookup('d1');
    final QueryRef<Object?> widened = lookup;
    _note(
      'O7-write-5',
      'write of a String through a QueryRef<Device?> held as '
          'QueryRef<Object?>',
      '${_attempt(() => widened.write(client, 'not a device'))}; '
          'cache: ${_entry(client, lookup.key.rawKey)}',
    );
    _note(
      'O7-write-6',
      'write of null through the same widened reference',
      '${_attempt(() => widened.write(client, null))}; '
          'cache: ${_entry(client, lookup.key.rawKey)}',
    );
  }

  // A single update.
  {
    final client = _client();
    final device = queries.detail('d1');
    final QueryRef<Object?> widened = device;
    _note(
      'O7-update-1',
      'update returning an int through a widened QueryRef<Device>, no '
          'entry yet',
      '${_attempt(() => widened.update(client, (previous) => 42))}; '
          'cache: ${_entry(client, device.key.rawKey)}',
    );
    device.write(client, const Device('d1', name: 'kept'));
    _note(
      'O7-update-2',
      'the same with a Device cached',
      '${_attempt(() => widened.update(client, (previous) => 42))}; '
          'cache: ${_entry(client, device.key.rawKey)}, '
          'kept: ${device.read(client)?.name == 'kept'}',
    );
    _note(
      'O7-update-3',
      'an updater typed Object? Function(Object?) returning a String',
      '${_attempt(() => widened.update(client, _toString))}; '
          'kept: ${device.read(client)?.name == 'kept'}',
    );
  }

  // A family's bulk update.
  {
    final client = _client();
    queries.detail('a').write(client, const Device('a', name: 'kept'));
    queries.detail('b').write(client, const Device('b', name: 'kept'));
    final QueryFamily<Object?, Object?> widened = queries.detail;
    _note(
      'O7-bulk-1',
      'updateAll returning a String through a QueryFamily<String, Device> '
          'held as QueryFamily<Object?, Object?>, two entries',
      '${_attempt(() => widened.updateAll(client, (previous) => 'x'))}; '
          'kept: ${_allKept(client, queries)}',
    );
    var calls = 0;
    _note(
      'O7-bulk-2',
      'the same, the updater valid for the first entry only',
      '${_attempt(
        () => widened.updateAll(
          client,
          (previous) => calls++ == 0 ? const Device('a', name: 'new') : 'x',
        ),
      )}; kept: ${_allKept(client, queries)}',
    );
  }

  // Paged data.
  {
    final client = _client();
    final feed = queries.feed;
    final InfiniteQueryRef<Object?, Object?> widened = feed;
    _note(
      'O7-infinite-1',
      'write of an InfiniteData<String, String> through an '
          'InfiniteQueryRef<List<Device>, int> held as '
          'InfiniteQueryRef<Object?, Object?>',
      '${_attempt(
        () => widened.write(
          client,
          InfiniteData<String, String>(
            pages: const ['a page'],
            pageParams: const ['a param'],
          ),
        ),
      )}; cache: ${_entry(client, feed.key.rawKey)}',
    );
    final InfiniteQueryFamily<Object?, Object?, Object?> history =
        queries.history;
    _note(
      'O7-infinite-2',
      'updateAll returning a String through a widened InfiniteQueryFamily',
      '${_attempt(() {
        queries.history('d1').write(
              client,
              InfiniteData(pages: const [], pageParams: const []),
            );
        history.updateAll(
          client,
          (previous) => InfiniteData<String, String>(
            pages: const ['a page'],
            pageParams: const ['a param'],
          ),
        );
      })}; cache: ${_entry(client, queries.history('d1').key.rawKey)}',
    );
  }

  // The input of a family.
  {
    final client = _client();
    final QueryFamily<Object?, Object?> widened = queries.detail;
    _note(
      'O7-input-1',
      'binding an int to a QueryFamily<String, Device> held as '
          'QueryFamily<Object?, Object?>',
      '${_attempt(() => widened(42))}; '
          'entries: ${client.queryCache.findAll().length}',
    );
    final InfiniteQueryFamily<Object?, Object?, Object?> history =
        queries.history;
    _note(
      'O7-input-2',
      'binding an int to a widened InfiniteQueryFamily<String, …>',
      _attempt(() => history(42)),
    );
    _note(
      'O7-input-3',
      'the valid input through the widened family',
      _attempt(() => widened('d1')),
    );
  }
}

Object? _toString(Object? previous) => 'not a device';

/// `==` between two static types the analyzer knows to be unrelated.
bool _same(Object a, Object b) => a == b;

bool _allKept(QueryClient client, DeviceQueries queries) =>
    queries.detail.readAll(client).every((entry) => entry.$2?.name == 'kept');

// ------------------------------------------------- D2's generic setter

void _d2GenericSetter() {
  final queries = DeviceQueries(const DeviceRepository());
  final client = _client();
  final device = queries.detail('d1');

  // `boundary/generic_setter.dart` at runtime: `T` was solved as `Object`.
  _note(
    'D2-setter-1',
    'setData(client, device.key, a String), which compiles with T = Object',
    '${_attempt(() {
      setData(client, device.key, 'not a device');
    })}; '
        'cache: ${_entry(client, device.key.rawKey)}',
  );
  _note(
    'D2-setter-2',
    'the reference reading its own key afterwards',
    _attempt(() => device.read(client)),
  );

  final other = queries.detail('d2');
  other.write(client, const Device('d2', name: 'kept'));
  _note(
    'D2-setter-3',
    'the same setter over a Device entry that exists',
    '${_attempt(() {
      setData(client, other.key, 'not a device');
    })}; '
        'cache: ${_entry(client, other.key.rawKey)}',
  );
}

// --------------------------------------------------------------------- D4

void _d4Values() {
  const repository = DeviceRepository();
  final first = DeviceQueries(repository);
  final second = DeviceQueries(repository);

  _note(
    'D4-1',
    'two references from equal inputs of one family',
    '== ${first.detail('d1') == first.detail('d1')}, '
        'same hashCode '
        '${first.detail('d1').hashCode == first.detail('d1').hashCode}',
  );
  _note(
    'D4-2',
    'two references from equal inputs of a recreated family',
    '== ${first.detail('d1') == second.detail('d1')}, '
        'same hashCode '
        '${first.detail('d1').hashCode == second.detail('d1').hashCode}',
  );
  _note(
    'D4-3',
    'references from different inputs',
    '== ${first.detail('d1') == first.detail('d2')}',
  );
  _note(
    'D4-4',
    'their typed keys',
    'equal inputs == ${first.detail('d1').key == second.detail('d1').key}, '
        'different inputs == '
        '${first.detail('d1').key == first.detail('d2').key}',
  );
  _note(
    'D4-5',
    'a zero-input definition and its recreation',
    '== ${first.list == second.list}, '
        'identical ${identical(first.list, second.list)}',
  );
  _note(
    'D4-6',
    'infinite references, zero-input and from a family',
    '== ${first.feed == second.feed}, '
        '== ${first.history('d1') == second.history('d1')}, '
        'different inputs == ${first.history('d1') == first.history('d2')}',
  );
  _note(
    'D4-7',
    'a value object and a record as equal inputs',
    '== ${first.filtered(const DeviceFilter(room: Room.hall)) == second.filtered(const DeviceFilter(room: Room.hall))}, '
        '== ${first.inRoom((room: Room.hall, onlyOn: true)) == second.inRoom((
                  onlyOn: true,
                  room: Room.hall
                ))}',
  );

  // The same raw key under another data type.
  final nullable = QueryFamily<String, Device?>(
    namespace: DeviceQueries.namespace,
    name: 'detail',
  );
  _note(
    'D4-8',
    'the same raw key declared as Device and as Device?',
    'raw keys == '
        '${first.detail('d1').key.rawKey == nullable('d1').key.rawKey}, '
        'typed keys == ${first.detail('d1').key == nullable('d1').key}, '
        'references == ${first.detail('d1') == nullable('d1')}',
  );

  // The same raw key and data type, plain and infinite.
  final plainFeed = QueryDefinition<InfiniteData<List<Device>, int>>(
    namespace: DeviceQueries.namespace,
    name: 'feed',
  );
  _note(
    'D4-9',
    'a plain and an infinite definition of one key and one data type',
    'typed keys == ${plainFeed.key == first.feed.key}, '
        'references == ${_same(plainFeed, first.feed)}',
  );

  // The same typed key, reached by a family and by a zero-input definition.
  final direct = QueryDefinition<Device>(
    namespace: QueryNamespace(const ['devices', 'detail']),
    name: 'd1',
  );
  _note(
    'D4-10',
    'a family-bound reference and a zero-input definition of the same key '
        'and type',
    '== ${direct == first.detail('d1')}, '
        'symmetric ${first.detail('d1') == direct}, '
        'same hashCode ${direct.hashCode == first.detail('d1').hashCode}',
  );

  _note(
    'D4-11',
    'references and typed keys as set members and map keys',
    'set ${{first.detail('d1')}.contains(second.detail('d1'))}, '
        'map ${{first.detail('d1').key: 1}[second.detail('d1').key] == 1}',
  );

  final reference = first.detail('d1');
  _note(
    'D4-12',
    'the options of one reference, asked for twice',
    'identical ${identical(reference.options(), reference.options())}, '
        'same fetcher '
        '${reference.options().queryFn == reference.options().queryFn}, '
        'same key '
        '${reference.options().queryKey == reference.options().queryKey}',
  );

  // A reference holds no client.
  final one = _client();
  final two = _client();
  first.detail('d2').options();
  first.feed.options();
  _note(
    'D4-13',
    'binding references and asking for options, before any client is used',
    'entries: ${one.queryCache.findAll().length} and '
        '${two.queryCache.findAll().length}',
  );
  reference.write(one, const Device('d1', name: 'one'));
  _note(
    'D4-14',
    'one reference written through one client, read through two',
    'first: ${_value(reference.read(one))}, '
        'second: ${_value(reference.read(two))}',
  );
  reference.write(two, const Device('d1', name: 'two'));
  _note(
    'D4-15',
    'the same reference written through the second client',
    'first holds its own: ${reference.read(one)?.name == 'one'}, '
        'second holds its own: ${reference.read(two)?.name == 'two'}',
  );
}

// --------------------------------------------------------------------- D5

void _d5DeclaredTypes() {
  final queries = DeviceQueries(const DeviceRepository());
  final client = _client();

  // The declared type, not the value's.
  queries.reading('r1').write(client, const Temperature(21));
  _note(
    'D5-1',
    'first typed write of a Temperature under QueryFamily<String, Reading>',
    _entry(client, queries.reading('r1').key.rawKey),
  );
  final rawReading = QueryKey(const ['raw', 'reading']);
  client.setQueryData(rawReading, const Temperature(21));
  _note(
    'D5-2',
    'the raw setQueryData of the same value, no type argument',
    _entry(client, rawReading),
  );
  queries.list.write(client, const <Thermostat>[Thermostat('t1')]);
  _note(
    'D5-3',
    'first typed write of a List<Thermostat> under '
        'QueryDefinition<List<Device>>',
    _entry(client, queries.list.key.rawKey),
  );
  queries.lookup('d1').write(client, const Device('d1'));
  _note(
    'D5-4',
    'first typed write of a Device under QueryFamily<String, Device?>',
    _entry(client, queries.lookup('d1').key.rawKey),
  );

  // Null and absence.
  final stored = queries.lookup('d2');
  stored.write(client, null);
  _note(
    'D5-5',
    'write(null) on a nullable definition',
    '${_entry(client, stored.key.rawKey)}; '
        'read: ${_value(stored.read(client))}, '
        'state.hasData: ${stored.state(client)?.hasData}',
  );
  final absent = queries.lookup('d3');
  _note(
    'D5-6',
    'a reference nothing was written for',
    '${_entry(client, absent.key.rawKey)}; '
        'read: ${_value(absent.read(client))}, '
        'state: ${_value(absent.state(client))}',
  );

  // Updates.
  final updated = queries.detail('u1');
  _note(
    'D5-7',
    'update returning null, no entry yet',
    'returned ${_value(updated.update(client, (previous) => previous?.copyWith(isOn: true)))}; '
        'cache: ${_entry(client, updated.key.rawKey)}',
  );
  _note(
    'D5-8',
    'update returning a Device, no entry yet',
    'returned ${_value(updated.update(client, (previous) => previous ?? const Device('u1')))}; '
        'cache: ${_entry(client, updated.key.rawKey)}',
  );
  _note(
    'D5-9',
    'update seeing the cached Device and switching it on',
    'returned on: ${updated.update(client, (previous) => previous?.copyWith(isOn: true))?.isOn}, '
        'cached on: ${updated.read(client)?.isOn}',
  );
  final at = DateTime.utc(2020);
  updated.write(client, const Device('u1'), updatedAt: at);
  _note(
    'D5-10',
    'write with updatedAt',
    'state.dataUpdatedAt is it: '
        '${updated.state(client)?.dataUpdatedAt == at}',
  );

  // A wider raw entry under the reference's key.
  final wide = queries.detail('w1');
  client.setQueryData<Device?>(wide.key.rawKey, const Device('w1'));
  _note(
    'D5-11',
    'typed write of a Device over a raw Query<Device?>',
    '${_attempt(() => wide.write(client, const Device('w1', name: 'new')))}; '
        'cache: ${_entry(client, wide.key.rawKey)}, '
        'unchanged: ${client.getQueryData<Device?>(wide.key.rawKey)?.name == ''}',
  );
  _note(
    'D5-12',
    'typed update and typed read of the same entry',
    'update: ${_attempt(() => wide.update(client, (previous) => previous))}, '
        'read: ${_attempt(() => wide.read(client))}',
  );
  _note(
    'D5-13',
    'the raw setQueryData<Device> over the same entry (lenient)',
    '${_attempt(() => client.setQueryData<Device>(wide.key.rawKey, const Device('w1', name: 'raw')))}; '
        'cache: ${_entry(client, wide.key.rawKey)}, '
        'written: ${client.getQueryData<Device?>(wide.key.rawKey)?.name == 'raw'}',
  );

  // A narrower raw entry.
  final narrow = queries.detail('n1');
  client.setQueryData<Thermostat>(narrow.key.rawKey, const Thermostat('n1'));
  _note(
    'D5-14',
    'typed write of a Device over a raw Query<Thermostat>',
    '${_attempt(() => narrow.write(client, const Device('n1')))}; '
        'cache: ${_entry(client, narrow.key.rawKey)}',
  );

  // The definition's own options apply to an entry a write creates.
  final pinned = QueryDefinition<Device>(
    namespace: DeviceQueries.namespace,
    name: 'pinned',
    configure: (base) => base.copyWith(gcTime: GcTime.never),
  );
  pinned.write(client, const Device('p1'));
  final rawPinned = QueryKey(const ['raw', 'pinned']);
  client.setQueryData<Device>(rawPinned, const Device('p1'));
  _note(
    'D5-15',
    'gcTime of an entry created by a typed write, the definition '
        'configured with GcTime.never; and by a raw write',
    'typed never: ${_gcTime(client, pinned.key.rawKey) == GcTime.never}, '
        'raw never: ${_gcTime(client, rawPinned) == GcTime.never}',
  );

  // `configure` cannot move the key.
  final moved = QueryDefinition<Device>(
    namespace: DeviceQueries.namespace,
    name: 'moved',
    queryFn: (context) => const Device('m1'),
    configure: (base) => base.copyWith(
      queryKey: QueryKey(const ['elsewhere']),
      queryFn: (context) => const Device('other'),
    ),
  );
  _note(
    'D5-16',
    'a configure that returns another key and another fetcher',
    'options keep the key: ${moved.options().queryKey == moved.key.rawKey}',
  );

  // The data type Null.
  _note(
    'D5-17',
    'declaring QueryDefinition<Null>',
    _attempt(
      () => QueryDefinition<Null>(
        namespace: DeviceQueries.namespace,
        name: 'nothing',
      ),
    ),
  );
}

GcTime? _gcTime(QueryClient client, QueryKey key) =>
    client.queryCache.find(filters: QueryFilters(queryKey: key))?.gcTime;

void _d5Infinite() {
  final queries = DeviceQueries(const DeviceRepository());

  // A narrower value is rebuilt under the declared page types.
  {
    final client = _client();
    final narrow = InfiniteData<List<Thermostat>, int>(
      pages: const [
        [Thermostat('t1')],
      ],
      pageParams: const [0],
    );
    final stored = queries.feed.write(client, narrow);
    _note(
      'D5-infinite-1',
      'write of an InfiniteData<List<Thermostat>, int> under '
          'InfiniteQueryDefinition<List<Device>, int>',
      '${_entry(client, queries.feed.key.rawKey)}; '
          'the value given back is the given one: '
          '${identical(stored, narrow)}, '
          'pages kept: ${stored.pages.length == 1 && stored.pages.first.first.id == 't1'}',
    );
    _note(
      'D5-infinite-2',
      'adding a page of plain Devices to what is cached',
      _attempt(
        () => queries.feed.update(
          client,
          (previous) => previous?.copyWith(
            pages: [
              ...previous.pages,
              [const Device('d2')],
            ],
            pageParams: [...previous.pageParams, 1],
          ),
        ),
      ),
    );
    final InfiniteData<List<Device>, int> held = narrow;
    _note(
      'D5-infinite-3',
      'the same on the narrower value itself, held as the declared type',
      _attempt(
        () => held.copyWith(
          pages: [
            ...held.pages,
            [const Device('d2')],
          ],
          pageParams: [...held.pageParams, 1],
        ),
      ),
    );
  }

  // An exact value is kept as it is.
  {
    final client = _client();
    final exact = InfiniteData<List<Device>, int>(
      pages: const [
        [Device('d1')],
      ],
      pageParams: const [0],
    );
    _note(
      'D5-infinite-4',
      'write of an exact InfiniteData<List<Device>, int>',
      '${_entry(client, queries.feed.key.rawKey)} before; '
          'the value given back is the given one: '
          '${identical(queries.feed.write(client, exact), exact)}; '
          '${_entry(client, queries.feed.key.rawKey)}',
    );
  }

  // An updater's result is normalised too, single and bulk.
  {
    final client = _client();
    final narrow = InfiniteData<List<Never>, int>(
      pages: const [],
      pageParams: const [],
    );
    final history = queries.history('d1');
    history.update(client, (previous) => narrow);
    _note(
      'D5-infinite-5',
      'update returning an InfiniteData<List<Never>, int> under '
          'InfiniteQueryFamily<String, List<DeviceEvent>, int>',
      _entry(client, history.key.rawKey),
    );
    queries.history.updateAll(client, (previous) => narrow);
    _note(
      'D5-infinite-6',
      'the same through the updateAll of the family',
      _entry(client, history.key.rawKey),
    );
  }
}

// --------------------------------------------------------------------- D7

Future<void> _d7Prefixes() async {
  final queries = DeviceQueries(const DeviceRepository());

  // The family is its prefix.
  {
    final client = _client();
    queries.detail('a').write(client, const Device('a'));
    queries.detail('b').write(client, const Device('b'));
    queries.list.write(client, const [Device('a')]);
    queries.lookup('a').write(client, const Device('a'));
    final updated = queries.detail.updateAll(
      client,
      (previous) => previous?.copyWith(isOn: true),
    );
    _note(
      'D7-1',
      'updateAll over a family with two inputs cached, a list and a '
          'lookup beside it',
      'returned ${updated.length}, '
          'all on: ${updated.every((entry) => entry.$2?.isOn ?? false)}, '
          'keys typed: ${updated.first.$1 == queries.detail('a').key || updated.first.$1 == queries.detail('b').key}; '
          'list untouched: ${queries.list.read(client)?.first.isOn == false}, '
          'lookup untouched: ${queries.lookup('a').read(client)?.isOn == false}',
    );
    _note(
      'D7-2',
      'readAll over the same family',
      'returned ${queries.detail.readAll(client).length}, '
          'all on: ${queries.detail.readAll(client).every((entry) => entry.$2?.isOn ?? false)}',
    );
    _note(
      'D7-3',
      'what the filters of the family select, and those of the namespace',
      'family ${client.queryCache.findAll(filters: queries.detail.filters()).length}, '
          'namespace ${client.queryCache.findAll(filters: DeviceQueries.namespace.filters()).length}, '
          'one reference ${client.queryCache.findAll(filters: queries.detail('a').filters()).length}',
    );

    // Lifecycle: exact, prefix, namespace.
    final nested = queries.detail('a').key.rawKey.append(const ['history']);
    client.setQueryData<String>(nested, 'nested');
    await queries.detail('a').invalidate(client);
    _note(
      'D7-4',
      'invalidate on one reference, a nested key under it',
      'invalidated: ${_invalidated(client)} of '
          '${client.queryCache.findAll().length}, '
          'the nested one: ${_isInvalidated(client, nested)}',
    );
    await queries.detail.invalidate(client);
    _note(
      'D7-5',
      'invalidate on the family',
      'invalidated: ${_invalidated(client)} of '
          '${client.queryCache.findAll().length}, '
          'the list: ${_isInvalidated(client, queries.list.key.rawKey)}',
    );
    await DeviceQueries.namespace.invalidate(client);
    _note(
      'D7-6',
      'invalidate on the namespace',
      'invalidated: ${_invalidated(client)} of '
          '${client.queryCache.findAll().length}',
    );
    queries.detail.remove(client);
    _note(
      'D7-7',
      'remove on the family',
      'entries left: ${client.queryCache.findAll().length}, '
          'the list: ${_entry(client, queries.list.key.rawKey)}',
    );
  }

  // An entry of another type under the prefix.
  {
    final client = _client();
    queries.detail('a').write(client, const Device('a', name: 'kept'));
    queries.detail('b').write(client, const Device('b', name: 'kept'));
    final foreign = queries.detail.rawKey.append(const ['x']);
    client.queryCache.build<String>(
      client,
      client
          .defaultQueryOptions<String>(QueryOptions<String>(queryKey: foreign)),
    );
    _note(
      'D7-8',
      'typed updateAll, a Query<String> without data under the prefix',
      '${_attempt(() => queries.detail.updateAll(client, (previous) => previous?.copyWith(name: 'new')))}; '
          'kept: ${_allKeptBut(client, queries, foreign)}',
    );
    _note(
      'D7-9',
      'typed readAll over the same prefix',
      _attempt(() => queries.detail.readAll(client)),
    );
    _note(
      'D7-10',
      'the raw updateQueriesData<Device> over the same prefix (lenient)',
      '${_attempt(() => client.updateQueriesData<Device>((previous) => previous?.copyWith(name: 'raw'), filters: queries.detail.filters()))}; '
          'written: ${client.getQueryData<Device>(queries.detail('a').key.rawKey)?.name == 'raw'}',
    );
  }

  // A wider entry under the prefix.
  {
    final client = _client();
    queries.detail('a').write(client, const Device('a', name: 'kept'));
    final wide = queries.detail.rawKey.append(const ['w']);
    client.setQueryData<Device?>(wide, const Device('w', name: 'kept'));
    _note(
      'D7-11',
      'typed updateAll, a raw Query<Device?> under the prefix',
      '${_attempt(() => queries.detail.updateAll(client, (previous) => previous?.copyWith(name: 'new')))}; '
          'kept: ${queries.detail('a').read(client)?.name == 'kept' && client.getQueryData<Device?>(wide)?.name == 'kept'}',
    );
    _note(
      'D7-12',
      'the raw updateQueriesData<Device> over the same prefix (lenient)',
      '${_attempt(() => client.updateQueriesData<Device>((previous) => previous?.copyWith(name: 'raw'), filters: queries.detail.filters()))}; '
          'the wider entry written: ${client.getQueryData<Device?>(wide)?.name == 'raw'}',
    );
  }

  // An updater that throws.
  {
    final client = _client();
    queries.detail('a').write(client, const Device('a', name: 'kept'));
    queries.detail('b').write(client, const Device('b', name: 'kept'));
    var calls = 0;
    _note(
      'D7-13',
      'updateAll whose updater throws for the second entry',
      '${_attempt(
        () => queries.detail.updateAll(
          client,
          (previous) => calls++ == 0
              ? previous?.copyWith(name: 'new')
              : throw StateError('no'),
        ),
      )}; kept: ${_allKept(client, queries)}',
    );
  }
}

int _invalidated(QueryClient client) => client.queryCache
    .findAll()
    .where((query) => query.state.isInvalidated)
    .length;

bool _isInvalidated(QueryClient client, QueryKey key) =>
    client.queryCache
        .find(filters: QueryFilters(queryKey: key))
        ?.state
        .isInvalidated ??
    false;

bool _allKeptBut(QueryClient client, DeviceQueries queries, QueryKey foreign) =>
    client.queryCache
        .findAll(filters: queries.detail.filters())
        .where((query) => query.queryKey != foreign)
        .every((query) => (query.state.data as Device?)?.name == 'kept');

// --------------------------------------------------------------------- D9

void _d9MixedList() {
  final queries = DeviceQueries(const DeviceRepository());

  final client = _client();
  final device = queries.detail('d1');
  QueriesObserver(client, [device.options(), queries.list.options()]);
  _note(
    'D9-1',
    'a QueriesObserver over the options of a QueryRef<Device> and a '
        'QueryRef<List<Device>>',
    'device: ${_entry(client, device.key.rawKey)}, '
        'list: ${_entry(client, queries.list.key.rawKey)}',
  );
  _note(
    'D9-2',
    'the references over those entries',
    'read: ${_attempt(() => device.read(client))}, '
        'write: ${_attempt(() => device.write(client, const Device('d1')))}, '
        'list read: ${_attempt(() => queries.list.read(client))}',
  );

  final control = _client();
  QueriesObserver(control, [
    queries.detail('d1').options(),
    queries.detail('d2').options(),
  ]);
  _note(
    'D9-3',
    'a QueriesObserver over two references of one data type',
    '${_entry(control, device.key.rawKey)}; '
        'read: ${_attempt(() => device.read(control))}',
  );
}

// -------------------------------------------------------------------- D10

void _d10Backstop() {
  const repository = DeviceRepository();
  final namespace = QueryNamespace(const ['backstop']);

  _note(
    'D10-1',
    'a family without type arguments (inferred QueryFamily<Object?, …>)',
    _attempt(
      () => QueryFamily(
        namespace: namespace,
        name: 'untyped',
        queryFn: (id, context) => repository.devices(),
      ),
    ),
  );
  _note(
    'D10-2',
    'the same in the factory form',
    _attempt(
      () => namespace.family(
        'untyped',
        queryFn: (id, context) => repository.devices(),
      ),
    ),
  );
  _note(
    'D10-3',
    'QueryFamily<dynamic, dynamic>, a key-only family that names nothing',
    _attempt(
      () => QueryFamily<dynamic, dynamic>(namespace: namespace, name: 'bare'),
    ),
  );
  _note(
    'D10-4',
    'QueryFamily<void, Device>',
    _attempt(
      () => QueryFamily<void, Device>(namespace: namespace, name: 'void'),
    ),
  );
  _note(
    'D10-5',
    'QueryFamily<Object, Device> and QueryFamily<String?, Device>',
    '${_attempt(() => QueryFamily<Object, Device>(namespace: namespace, name: 'object'))}, '
        '${_attempt(() => QueryFamily<String?, Device>(namespace: namespace, name: 'nullable'))}',
  );
  _note(
    'D10-6',
    'QueryDefinition<Object?> and QueryDefinition<Object>',
    '${_attempt(() => QueryDefinition<Object?>(namespace: namespace, name: 'top'))}, '
        '${_attempt(() => QueryDefinition<Object>(namespace: namespace, name: 'object'))}',
  );
  _note(
    'D10-7',
    'an infinite family without type arguments',
    _attempt(
      () => InfiniteQueryFamily(
        namespace: namespace,
        name: 'untypedInfinite',
        pageFn: (id, context) => repository.page(context.pageParam),
        initialPageParam: (id) => 0,
        getNextPageParam: (id, page, pages, pageParam, pageParams) =>
            pageParam + 1,
      ),
    ),
  );
  _note(
    'D10-8',
    'InfiniteQueryDefinition<Object?, int> and <List<Device>, dynamic>',
    '${_attempt(() => InfiniteQueryDefinition<Object?, int>(namespace: namespace, name: 'page', pageFn: (context) => null, initialPageParam: 0, getNextPageParam: (page, pages, pageParam, pageParams) => null))}, '
        '${_attempt(() => InfiniteQueryDefinition<List<Device>, dynamic>(namespace: namespace, name: 'param', pageFn: (context) => const [], initialPageParam: 0, getNextPageParam: (page, pages, pageParam, pageParams) => null))}',
  );
}

// ------------------------------------------- amendment 1: keyOf's default

final class _Opaque {
  _Opaque(this.id);

  final String id;
}

void _keyOfDefault() {
  final namespace = QueryNamespace(const ['k']);

  final byId = QueryFamily<String, Device>(namespace: namespace, name: 'byId');
  final spelled = QueryFamily<String, Device>(
    namespace: namespace,
    name: 'byId',
    keyOf: (id) => [id],
  );
  _note(
    'K-1',
    'a family without keyOf, a String input',
    'raw key is [k, byId, d1]: '
        '${byId('d1').key.rawKey == QueryKey(const ['k', 'byId', 'd1'])}, '
        '== the family with keyOf: (id) => [id]: '
        '${byId('d1') == spelled('d1')}',
  );

  final byFilter = QueryFamily<DeviceFilter, List<Device>>(
    namespace: namespace,
    name: 'byFilter',
  );
  _note(
    'K-2',
    'a value object as the input',
    'equal inputs == ${byFilter(const DeviceFilter(room: Room.hall)) == byFilter(const DeviceFilter(room: Room.hall))}, '
        'different inputs == ${byFilter(const DeviceFilter(room: Room.hall)) == byFilter(const DeviceFilter(room: Room.kitchen))}',
  );

  final byIds = QueryFamily<List<String>, List<Device>>(
    namespace: namespace,
    name: 'byIds',
  );
  final ids = ['a', 'b'];
  final bound = byIds(ids);
  ids.add('c');
  _note(
    'K-3',
    'a list as the input, changed after binding',
    'still == the binding of [a, b]: ${bound == byIds(['a', 'b'])}, '
        '== the binding of the changed list: ${bound == byIds(ids)}',
  );

  final byQuery = QueryFamily<Map<String, Object?>, List<Device>>(
    namespace: namespace,
    name: 'byQuery',
  );
  _note(
    'K-4',
    'a map as the input, its entries in another order',
    '== ${byQuery({'room': 'hall', 'on': true}) == byQuery({
              'on': true,
              'room': 'hall'
            })}',
  );

  final byRecord = QueryFamily<({Room room, bool onlyOn}), List<Device>>(
    namespace: namespace,
    name: 'byRecord',
  );
  _note(
    'K-5',
    'a record of scalars as the input, no keyOf',
    '== ${byRecord((room: Room.hall, onlyOn: true)) == byRecord((
              onlyOn: true,
              room: Room.hall
            ))}',
  );

  final byListRecord = QueryFamily<({List<String> ids}), List<Device>>(
    namespace: namespace,
    name: 'byListRecord',
  );
  final spread = QueryFamily<({List<String> ids}), List<Device>>(
    namespace: namespace,
    name: 'spread',
    keyOf: (input) => [input.ids],
  );
  _note(
    'K-6',
    'a record holding a list as the input',
    'no keyOf == ${byListRecord((ids: ['a'])) == byListRecord((ids: ['a']))}, '
        'keyOf: (input) => [input.ids] == '
        '${spread((ids: ['a'])) == spread((ids: ['a']))}',
  );

  final byNullable = QueryFamily<String?, Device>(
    namespace: namespace,
    name: 'byNullable',
  );
  _note(
    'K-7',
    'null as the input of a QueryFamily<String?, Device>',
    'raw key is [k, byNullable, null]: '
        '${byNullable(null).key.rawKey == QueryKey(const [
                  'k',
                  'byNullable',
                  null
                ])}',
  );

  final byOpaque = QueryFamily<_Opaque, Device>(
    namespace: namespace,
    name: 'byOpaque',
  );
  final converted = QueryFamily<_Opaque, Device>(
    namespace: namespace,
    name: 'converted',
    keyOf: (input) => [input.id],
  );
  _note(
    'K-8',
    'an input with identity equality',
    'no keyOf: ${_attempt(() => byOpaque(_Opaque('a')))}, '
        'keyOf: (input) => [input.id]: '
        '${_attempt(() => converted(_Opaque('a')))}, '
        '== ${converted(_Opaque('a')) == converted(_Opaque('a'))}',
  );
}

// ------------------------------------------------------------- fetching

Future<void> _fetching() async {
  final queries = DeviceQueries(const DeviceRepository());
  final client = _client();

  final device = await queries.detail('f1').fetch(client);
  _note(
    'F-1',
    'fetch through the reference of a family',
    'a Device of the input: ${device.id == 'f1'}; '
        'cache: ${_entry(client, queries.detail('f1').key.rawKey)}',
  );
  final list = await queries.list.fetch(client);
  _note(
    'F-2',
    'fetch through a zero-input definition',
    'two devices: ${list.length == 2}; '
        'cache: ${_entry(client, queries.list.key.rawKey)}',
  );
  final feed = await queries.feed.fetch(client);
  _note(
    'F-3',
    'fetch through an infinite definition',
    'one page: ${feed.pages.length == 1}, '
        'its param: ${feed.pageParams.first == 0}; '
        'cache: ${_entry(client, queries.feed.key.rawKey)}',
  );
  final history = await queries.history('f1').fetch(client);
  _note(
    'F-4',
    'fetch through the reference of an infinite family',
    'one page: ${history.pages.length == 1}; '
        'cache: ${_entry(client, queries.history('f1').key.rawKey)}',
  );
  final observer = QueryObserver(client, queries.detail('f1').options());
  _note(
    'F-5',
    'an observer made from the options of the reference',
    'sees the fetched Device: ${observer.currentResult.dataOrNull?.id == 'f1'}',
  );
}

// ---------------------------------------------------------------- helpers

final _clients = <QueryClient>[];

QueryClient _client() {
  final client = QueryClient();
  _clients.add(client);
  return client;
}

void _note(String id, String what, String outcome) {
  // One line per observation; the runner compares them line by line.
  // ignore: avoid_print
  print('$id | $what | $outcome');
}

String _attempt(void Function() body) {
  try {
    body();
    return 'completed';
  } on QueryDataTypeError {
    return 'QueryDataTypeError';
  } on ArgumentError {
    return 'ArgumentError';
  } on AssertionError {
    return 'AssertionError';
  } on TypeError {
    return 'TypeError';
  } on StateError {
    return 'StateError';
  } catch (_) {
    return 'another error';
  }
}

Type _typeOf<X>() => X;

final _typeNames = <(Type, String)>[
  (_typeOf<Device>(), 'Device'),
  (_typeOf<Device?>(), 'Device?'),
  (_typeOf<Thermostat>(), 'Thermostat'),
  (_typeOf<Reading>(), 'Reading'),
  (_typeOf<Temperature>(), 'Temperature'),
  (_typeOf<String>(), 'String'),
  (_typeOf<Object>(), 'Object'),
  (_typeOf<List<Device>>(), 'List<Device>'),
  (
    _typeOf<InfiniteData<List<Device>, int>>(),
    'InfiniteData<List<Device>, int>',
  ),
  (
    _typeOf<InfiniteData<List<DeviceEvent>, int>>(),
    'InfiniteData<List<DeviceEvent>, int>',
  ),
];

String _typeName(Type type) {
  for (final (known, name) in _typeNames) {
    if (known == type) {
      return name;
    }
  }
  return 'another type';
}

/// A value by `is` tests, most specific first.
String _value(Object? value) => switch (value) {
      null => 'null',
      Thermostat() => 'a Thermostat',
      Device() => 'a Device',
      Temperature() => 'a Temperature',
      String() => 'a String',
      int() => 'an int',
      List<Thermostat>() => 'a List<Thermostat>',
      List<Device>() => 'a List<Device>',
      InfiniteData<Object?, Object?>() => value.runtimeType ==
              _typeOf<InfiniteData<List<Device>, int>>()
          ? 'an InfiniteData<List<Device>, int>'
          : value.runtimeType == _typeOf<InfiniteData<List<DeviceEvent>, int>>()
              ? 'an InfiniteData<List<DeviceEvent>, int>'
              : 'an InfiniteData of other type arguments',
      QueryState<Object?>() => 'a state',
      _ => 'another value',
    };

/// What the cache holds under [key]: the entry's own type and its data.
String _entry(QueryClient client, QueryKey key) {
  final query = client.queryCache.find(filters: QueryFilters(queryKey: key));
  if (query == null) {
    return 'no entry';
  }
  final type = 'Query<${_typeName(query.dataType)}>';
  return query.state.hasData
      ? '$type holding ${_value(query.state.data)}'
      : '$type without data';
}
