---
title: Typed query definitions
description: Declare a query once, with its key, its input and its data type, and read, write and invalidate it through references that carry the type.
---

# Typed query definitions

With raw keys, a key and its data type meet again at every call:
`client.getQueryData<Device>(key)` is right only while every caller repeats
the type that the query function returns, and spells the key the same way.
A **definition** says both once. Calling it gives a **reference** to one
cache entry, and the reference reads, writes, fetches and invalidates that
entry with the declared type and no type argument.

Typed query definitions arrive in `query_kit` 1.1.0, `query_kit_flutter`
1.2.0 and `query_kit_hooks` 0.1.3. They sit on top of the client and change
nothing about it: a reference and a raw key with the same parts are the same
entry, so an app can move one query at a time.

Five words, used the same way on every page:

- a **definition** (`QueryDefinition`, `QueryFamily`,
  `InfiniteQueryDefinition`, `InfiniteQueryFamily`) is declared once and
  holds no state;
- a **reference** (`QueryRef`, `InfiniteQueryRef`) is one entry, made by
  calling a family with its input; a definition without an input is its own
  reference;
- a **typed key** (`TypedQueryKey`) is a reference's key together with its
  data type;
- a **namespace** (`QueryNamespace`) is a key prefix with no data type;
- a **target** (`QueryTarget`) is anything that can be invalidated,
  refetched, cancelled, reset or removed.

## What a definition buys

Each of these lines is refused by the analyzer, with the diagnostic named
beside it. With raw keys the same mistakes are a string, a key part or a
type argument, and the analyzer accepts every one of them:

```dart snippet="prose-only: each line is refused by the analyzer, which is the point; tool/check_typed_query_fixtures.dart proves every code"
queries.devces.detail('d1');                 // undefined_getter
queries.devices.detial('d1');                // undefined_method
queries.devices.detail(123);                 // argument_type_not_assignable
device.write(client, 'not a device');        // argument_type_not_assignable
device.update(client, (_) => 42);            // return_of_invalid_type_from_closure
String? wrongRead = device.key.read(client); // invalid_assignment
```

Here `device` is `queries.devices.detail('d1')`, a `QueryRef<Device>`. A
misspelled namespace or operation does not compile, and neither does an
input, a written value, an updater or a read of the wrong type.

## Declaring definitions

Group the definitions of one resource in a class that holds what they fetch
from, one field per operation. The strings of the key appear here and
nowhere else:

```dart snippet="guides/typed-queries.md#declare"
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
```

- **`QueryDefinition<T>`** is a query without an input, such as "every
  device". Its fetch function takes the context.
- **`QueryFamily<TInput, T>`** is one query per input, such as "the device
  with this id". Its fetch function takes the input and the context.
- **`configure`** sets the other options. It is handed options that already
  hold the key and the fetch function, and returns them changed, usually with
  `copyWith`. A family's `configure` also gets the input.
- **`late final`** rather than an initializer list: a field initializer
  cannot use `this`, and these fetch functions do. A definition that needs
  nothing from its class can be a top-level `final` instead.

Make the class once and give the app one place to reach it. A record with a
field per namespace keeps every name checked:

```dart snippet="guides/typed-queries.md#entry-point"
// lib/data/queries.dart: one field per namespace, made once.
final queries = (
  devices: DeviceQueries(repository),
  events: EventQueries(repository),
);
```

### The key

A definition's key is the namespace's parts, then the name, then the input:
`[...namespace, name, ...keyOf(input)]`. Without a `keyOf`, the input is one
part, `[input]`, so it follows [the rules of a key
part](query-keys.md#a-value-not-a-string): strings, numbers, enums, lists,
maps and records of those compare by value, and a class of your own needs
`==` and `hashCode`.

```dart snippet="guides/typed-queries.md#keys"
final devices = queries.devices;

expect(devices.list.key.rawKey, QueryKey(['devices', 'list']));
expect(
    devices.detail('d1').key.rawKey, QueryKey(['devices', 'detail', 'd1']));
expect(devices.detail.rawKey, QueryKey(['devices', 'detail']));

// Equal inputs give equal references: one entry, however often it is
// asked for.
expect(devices.detail('d1'), devices.detail('d1'));
```

`keyOf` turns an input into the parts after the name, when the input is not
what the key should hold: to spread it over several parts, so that a prefix
selects a subset, or to keep a key layout that an app already has. A record
that holds a list needs one, because a record compares its fields with `==`
and a list is equal only to itself:

```dart snippet="guides/typed-queries.md#key-of"
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
```

The key is computed once, when the family is called. A list in the input is
copied into it, but the fetch function is handed the input itself, so an
input should be an immutable value.

### Why the type arguments are written

Every sample on this site writes a definition's type arguments out:
`QueryDefinition<List<Device>>`, `QueryFamily<String, Device>`,
`InfiniteQueryDefinition<List<DeviceEvent>, int>`. Dart cannot infer all of
them:

- nothing tells it a family's input type, so without `<String, Device>` the
  input is `Object?` and `detail(123)` compiles;
- an infinite definition's page type gets lost: a `getNextPageParam` that
  reads its page does not compile, and beside a `configure` the pages become
  `Object?` without a word from the analyzer.

A debug build refuses such a declaration with an `AssertionError` that names
the type argument. A release build does not check. Writing the type
arguments on every definition, including the ones that would infer, keeps
the rule simple. A declared type on the field that holds the definition
works as well.

An input that really can be anything is declared as `Object`, or as a
nullable or sealed type: the debug check refuses only `dynamic`, `Object?`
and `void`, and `Null` as a data type.

## References

Calling a family with an input returns the reference of that input's entry.
Calling it fetches nothing and creates no entry. A definition without an
input is its own reference.

A reference's `options()` are ordinary options, so it goes wherever options
go. Every call style takes them, and none of the four is the default:

```dart snippet="guides/typed-queries.md#observe-context guides/typed-queries.md#observe-builder guides/typed-queries.md#observe-mixin guides/typed-queries.md#observe-controller"
// context.query, in any widget's build:
final device = context.query(queries.devices.detail(id).options());

// QueryBuilder, a widget:
Widget deviceTitle(String id) => QueryBuilder<Device>(
      options: queries.devices.detail(id).options(),
      builder: (context, device) => Text(device.dataOrNull?.name ?? '…'),
    );

// watchQuery, in the build of a State with QueryMixin:
final device = watchQuery(queries.devices.detail(widget.id).options());

// QueryController, a ValueListenable you own:
final device =
    QueryController.create(client, queries.devices.detail(id).options());
// … device.value, device.addListener, device.refetch() …
device.dispose();
```

[Four ways to read a query](reading-queries-in-widgets.md) says what each
style is for. With `query_kit_hooks`, `useQuery(ref.options())` reads the
same entry; see [hooks](hooks.md).

`options()` makes new options on every call, and two calls never return
`==` objects. What an observer compares on a rebuild is the options once
defaulted. A definition without an input hands out the function it was
declared with, so its options are equal once defaulted, as long as its
`configure` builds nothing new each time it runs. A family's reference binds
its input into a new fetch function each time, so its options differ even
then, and an observer handed them again on a rebuild takes them as changed
options, as it does with options written inline in `build`. That costs [one
defaulting pass and nothing
else](query-options.md#options-built-in-build-are-fine). A family declared
without a fetch function has nothing to bind, and its options are equal
once defaulted, as a definition's are.

## Reading and writing

```dart snippet="guides/typed-queries.md#read-write"
final device = queries.devices.detail('d1'); // QueryRef<Device>

// The cached data when it is fresh, otherwise a fetch: client.query.
final Device fetched = await device.fetch(client);

final Device? cached = device.read(client); // null when nothing is cached
final QueryState<Device>? state = device.state(client); // hasData, …

device.write(client, fetched.copyWith(name: 'Porch lamp'));
device.update(client, (current) => current?.copyWith(room: 'porch'));
```

- **`fetch`** is `client.query` with the reference's options: cached data
  that is still fresh, otherwise a fetch. `revalidateIfStale: true` returns
  the cached data and refetches behind it.
- **`read`** returns the cached data, or `null`. Under a nullable data type
  that `null` can mean a cached `null` or nothing cached; **`state`** tells
  them apart: no state is no entry, and `state.hasData` says whether there
  is data.
- **`write`** stores a value. An entry it creates gets the definition's
  options, its fetch function included.
- **`update`** hands the updater the current data, or `null`, and writes
  what it returns. Returning `null` writes nothing.

A typed write is exact. The entry must hold the reference's own data type,
or the write throws `QueryDataTypeError` and changes nothing; the raw
`setQueryData` is more lenient there. See
[errors](../reference/errors.md#from-a-typed-write).

## Typed keys

A reference's `key` is its **typed key**: the raw key together with the data
type. It reads and writes the entry with no type argument, and it is a value,
so it can go in a set or be a map key:

```dart snippet="guides/typed-queries.md#typed-key"
final TypedQueryKey<Device> key = queries.devices.detail('d1').key;

final Device? cached = key.read(client);
key.write(client, device);

// A value: equal for equal parts and type, so it can go in a set or a map.
final seen = <TypedQueryKey<Device>>{key, queries.devices.detail('d1').key};
assert(seen.length == 1);

// The plain key, for an API that takes one.
final QueryKey raw = key.rawKey; // ['devices', 'detail', 'd1']
```

A typed key knows the entry's key and data type, and not the definition.
That shows in one place: an entry that a typed key's `write` or `update`
**creates** is built from the key and the type alone. It gets the client's
defaults and the key's own (`setQueryDefaults`), none of the definition's
options, and no fetch function. A refetch of it before an observer or a
`fetch` through the reference supplies one fails it with
`MissingQueryFunctionError` and keeps its data: a `refetch` that reaches it,
or an invalidation with a `refetchType` of `all` or `inactive`. A default
invalidation refetches only the entries an observer reads, so it only marks
this one stale. Write through the reference to create an entry with the
definition's options. An entry that already exists is written exactly as
the reference writes it.

Only a definition or a reference makes a typed key: there is no public
constructor, because the data type would then be whatever the caller
claimed. A family's `readAll` returns one per entry; see [bulk
operations](#bulk-operations).

## Namespaces and targets

Every definition, every reference and every namespace is a **target**: it
can be invalidated, refetched, cancelled, reset and removed. A reference
acts on exactly its entry. A family acts on every input's entry, and a
namespace on everything under its prefix:

```dart snippet="guides/typed-queries.md#targets"
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
```

`invalidate` takes `refetchType` and `cancelRefetch`, `cancel` takes
`revert` and `silent`, as the client's calls do. `filters()` returns the
`QueryFilters` of the target's selection, narrowed by `type`, `stale`,
`fetchStatus`, `status` or a `predicate`; see [filters](filters.md).

A namespace claims no data type, so it reads and writes nothing. It is the
prefix a group of definitions shares, and the way to reach all of them at
once.

A list of references of different data types is declared as a list of
targets. It has every lifecycle operation and no `write`:

```dart snippet="guides/typed-queries.md#target-list"
// References of different data types, as targets: no write, every
// lifecycle operation.
final onScreen = <QueryTarget>[
  queries.devices.detail('d1'),
  queries.devices.list,
  queries.events.feed,
];
await Future.wait([for (final target in onScreen) target.invalidate(client)]);
```

## Options per use

What a definition's `configure` sets holds for every use. One screen that
needs something else changes a copy:

```dart snippet="guides/typed-queries.md#per-use"
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
```

`withSelect` changes what one reader sees, never what the cache holds; see
[describing a query once](query-options.md#withselect). A `copyWith` can set
an option, and cannot unset one that the definition set: `null` means "not
configured". A `copyWith(queryKey: …)` or `copyWith(queryFn: …)` leaves the
definition behind and is a raw query from then on.

An option that needs the client cannot live in the definition, which holds
no client. A function that takes the client and returns the reference's
options with a per-use change is the place for it. This one seeds a detail
from a room list that is already cached:

```dart snippet="guides/typed-queries.md#seeded"
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
```

The [initial query data](initial-query-data.md) guide says when a seed is
used and when it is not.

## Infinite definitions

Paged data is declared with `InfiniteQueryDefinition<TPageData, TPageParam>`
or `InfiniteQueryFamily<TInput, TPageData, TPageParam>`. The paging
functions are the ones `InfiniteQueryOptions` takes; a family's take the
input first, and its first page param is a function of the input:

```dart snippet="guides/typed-queries.md#declare-infinite"
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
```

The reference's `options()` are `InfiniteQueryObserverOptions`, which the
infinite reads take in all four call styles:

```dart snippet="guides/typed-queries.md#observe-infinite"
final feed = context.infiniteQuery(queries.events.feed.options());
final events =
    feed.value.dataOrNull?.flatten<DeviceEvent>() ?? const <DeviceEvent>[];
```

An infinite reference reads and writes the whole `InfiniteData`, typed with
both page types:

```dart snippet="guides/typed-queries.md#infinite-write"
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
```

A value written there, and a `structuralSharing` or `initialData` that its
`configure` sets, is stored under the declared page types even when it was
built with narrower type arguments. [Infinite queries](infinite-queries.md)
covers paging itself.

## Bulk operations

A family's `readAll` returns every input's cached data, each with its typed
key: `List<(TypedQueryKey<T>, T?)>`, with `null` where an entry holds no
data yet. `updateAll` runs an updater over every input's data and writes
what it returns; returning `null` leaves that entry as it is. The infinite
family has both, over `InfiniteData`.

Together they make an optimistic update over a whole family. The snapshot is
the pairs `readAll` returned, and the rollback writes each one back through
the typed key it was read under:

```dart snippet="guides/typed-queries.md#bulk"
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
```

The rollback puts back the devices this rename changed and no others, so a
write to a neighbour in the meantime survives it. An entry removed while the
request ran is created again by its key's `write`, and such an entry has no
fetch function until an observer or a `fetch` through the reference brings
one (see [typed keys](#typed-keys)). The [optimistic
updates](optimistic-updates.md) guide has the single-entry form.

`readAll`'s `null` means "no data" only for a non-null data type. For a
family of a nullable type, `Device?` say, a cached `null` reads as `null`
too, so the snapshot keeps each key's `state(client)` and the rollback writes
back `state.data` wherever `state.hasData` is true.

`updateAll` checks the types before it writes anything: every entry under
the prefix must hold exactly the family's data type, every updater runs, and
every result must be of that type, or the call throws with the cache as it
was. Each updater sees the data from before the call.

That check covers the types and what the updaters return. It does not cover
the writes, which are made one after the other in one batch, and a write can
still fail. An entry's `structuralSharing` may throw, and a cache listener
that answers an earlier write may put an entry of another type in a later
one's place. The call then throws at that entry with the earlier writes made
and the later ones not, as the client's `updateQueriesData` does. It is not
a transaction, and nothing is rolled back. A cache listener that throws
stops no write: its error is reported to the zone.

## Where the raw API still fits

The raw `QueryKey` API stays, and it reaches the same entries:

```dart snippet="guides/typed-queries.md#shared"
queries.devices.detail('d1').write(client, lamp);

// The raw client sees the same entry, under the same parts.
expect(
  client.getQueryData<Device>(QueryKey(['devices', 'detail', 'd1'])),
  lamp,
);
```

It fits where no definition does: a key built at run time from parts the
app does not know in advance, a [default query
function](default-query-function.md) that serves many keys, `setQueryDefaults`
for a prefix, a filter with a `predicate` over entries of many types, or
`getQueriesData` across definitions. `rawKey` hands the plain key to any of
these: on a typed key, so `ref.key.rawKey` for a reference, and on a family
or a namespace directly. From there on the type argument is yours to get
right again.

## Limits

What a definition checks, and when, in three parts.

### What the analyzer refuses

- A misspelled namespace or operation, an input of the wrong type, a written
  value or an updater result of the wrong type, and a read assigned to the
  wrong type: [the six lines above](#what-a-definition-buys).
- A write on a namespace or a target: neither has one.
- A `select` on a reference's options that does not fit the data type, as on
  any options.

### What only the runtime refuses

- **A missing type argument.** A definition whose type argument is left to
  become `dynamic`, `Object?` or `void`, or whose data type is `Null`, is
  refused by an `AssertionError` in a debug build. A release build does not
  check, and the definition works with the wider type.
- **A widened reference.** Assigned to a wider type, such as a
  `QueryRef<Object?>`, a reference compiles a write of the wrong type, and so
  do a family, a typed key or an updater upcast the same way, a `dynamic` and
  a cast. The write is refused before anything is written: by Dart's
  `TypeError` on the VM and in a default dart2js build, and by
  `QueryDataTypeError` (a widened family's input: `ArgumentError`) in a
  dart2js build at `-O3` or `-O4`, which is Flutter's web release level.
  dart2wasm at those levels has not been measured; Flutter's wasm default is
  `-O2`.
- **A collection literal widens without being asked.** References of two
  data types, `[devices.detail('d1'), devices.inRoom('hall')]`, make a
  `List<QueryRef<Object>>`, and a write through an element is checked only
  when it runs. A set, a map and a conditional expression do the same.
  Declare a mixed lifecycle list as `<QueryTarget>[…]`, which has no write.
- **A typed write is exact.** Into an entry of another type, wider
  (`Device?` for `Device`) or narrower, the write throws
  `QueryDataTypeError` and changes nothing.
- **`configure` returns options of the definition's own type**: the ones it
  is handed, or a `copyWith` of them. Options of a narrower data type satisfy
  its return type, and making the options throws a `StateError` that names
  the key and both types. An infinite definition whose first page param is
  `null` cannot have it changed there, and throws the same way.
- **Two definitions of one key with different data types** are found at the
  first read or write of the second type, with a `QueryDataTypeError`.
- **A key nested under a family's prefix** belongs to the family's bulk and
  lifecycle operations. With another data type, it makes `readAll` and
  `updateAll` throw. Give a nested operation a name of its own beside the
  family instead.
- **An entry a typed key created** has no fetch function, and a refetch of
  it fails with `MissingQueryFunctionError` until an observer or a `fetch`
  through the reference supplies one. See [typed keys](#typed-keys).
- **An input without value equality** is refused by `QueryKey`'s debug
  assertion only.
- **Options through a wider parameter.** A helper that takes
  `QueryObserverOptions<Object>` creates an `Object` entry, which the
  family's typed calls then refuse with `QueryDataTypeError`. A list of
  options of two data types handed to a `QueriesController` does the same.
  The cure is a generic helper, which keeps the options' own type:

```dart snippet="guides/typed-queries.md#generic-helper"
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
```

### What nothing checks

- **A raw call on the same key.** `setQueryData` on a reference's raw key is
  not checked against the definition, and keeps its leniency: a raw first
  write creates an entry of the value's own type, which a typed read may then
  refuse.
- **Two definitions of one key with the same data type** and different
  fetch functions are one entry, and give equal references. Nothing reports
  it. Nothing registers definitions either.
- **A record input that holds a list, a map or a set** without a `keyOf` is
  a new entry for every call, however equal the inputs.
- **A migrated key.** A family's default key is `[input]`. A hand-written
  key that held something else, such as a filter's JSON map, needs a `keyOf`
  to keep its layout, and only a test can say that it did; see [migrating
  from raw keys](#migrating-from-raw-keys).
- **`read` and a cached `null`.** `read` cannot tell a cached `null` from no
  data; `state` can.
- **`select` and the cache type.** A `select` or `withSelect` changes what an
  observer sees, never the type the entry holds, so a typed read of the
  entry still returns the definition's data type.
- **A changed input.** The key is computed when the family is called; the
  fetch function gets the input itself. Inputs are immutable values.
- **A plain definition of paged data.** A `QueryDefinition<InfiniteData<P,
  Q>>` stores what it is given, as any other type. Only an infinite
  definition holds a written `InfiniteData` to its page types; declare paged
  data with one.
- **A per-use `copyWith`** cannot unset a definition's option.
- **`updateAll` is not a transaction**, as [bulk
  operations](#bulk-operations) says.

[Errors](../reference/errors.md#typed-query-definitions) lists the cause and
the cure of each error above, and
[troubleshooting](../reference/troubleshooting.md#a-typed-write-throws-querydatatypeerror)
starts from the symptom.

## Migrating from raw keys

Move one query at a time. A raw key and a reference with the same parts
reach the same entry, so the code that is not migrated yet keeps working
beside the code that is. A changed key layout, though, is a changed cache
identity: an entry under the old key is not found under the new one.

Say the app has this:

```dart snippet="guides/typed-queries.md#migrate-before"
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
```

**1. Move the key parts and the fetch function into a definition.** The
first parts become the namespace, the next the name, and what varies the
input. Check what the old key held after the name: the default is the input
as one part, and the list key here held a map, so its family has a `keyOf`.

```dart snippet="guides/typed-queries.md#migrate-definition"
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
```

**2. Pin the raw key with a test**, while the old factory still exists to
compare with:

```dart snippet="guides/typed-queries.md#migrate-identity"
test('the room keys did not move', () {
  expect(roomDetail('r1').key.rawKey, roomKey('r1'));
  expect(roomList(null).key.rawKey, roomListKey(null));
  expect(roomList(2).key.rawKey, roomListKey(2));
});
```

**3. Replace the consumers.** Every read of the old options function reads
the reference's options instead:

```dart snippet="guides/typed-queries.md#migrate-consumers"
// Before: context.query(roomQuery(id))
final room = context.query(roomDetail(id).options());
```

**4. Then replace the cache writes and invalidations**, which is where the
type arguments were repeated:

```dart snippet="guides/typed-queries.md#migrate-writes"
// Before: client.setQueryData<Room>(roomKey(room.id), room);
roomDetail(room.id).write(client, room);

// Before: client.invalidateQueries(
//   filters: QueryFilters(queryKey: QueryKey(['rooms'])));
await rooms.invalidate(client);
```

When nothing uses the old factory any more, delete it, and keep the identity
test with literal keys in its place if the layout matters beyond this app:
a persisted cache, say, or a server push that names keys.

Typed writes are stricter than raw ones. A raw `setQueryData` into an
entry of `Room?` takes a `Room`; a typed write into it throws, because the
entry is not of the reference's type. If a step-four write throws
`QueryDataTypeError`, look for the raw code that created that entry with
another type.

## See it running

The showcase's [*typed queries* screen](../examples/typed-queries.mdx)
declares a family and a definition, writes and patches through them, and
invalidates one post, every detail and the whole namespace. A raw
`QueryBuilder` reads the same entry beside them:

<LiveDemo feature="typed-queries" />

## See also

- [Query keys](query-keys.md): what a key is underneath, and how keys
  compare.
- [Describing a query once](query-options.md): the options a reference
  makes.
- [Type safety in Dart](../dart-type-safety.md): the one-type-per-key rule
  the typed calls rest on.
- [Optimistic updates](optimistic-updates.md) and [updates from mutation
  responses](updates-from-mutation-responses.md): the mutation recipes,
  written with references.
