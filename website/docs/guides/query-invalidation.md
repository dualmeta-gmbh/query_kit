---
title: Query invalidation
description: invalidateQueries marks matching queries stale and refetches the ones on screen — prefix matching, exact, predicates, refetchType and cancelRefetch.
---

# Query invalidation

Waiting for data to go stale by itself is fine for data that changes
elsewhere. It is not good enough when *your app* just changed it: the user
renamed a task, and the list on the previous screen still shows the old name
for as long as its `staleTime` says it is fresh. You know the cached
data is wrong. `invalidate` is how you say so — on a namespace, a family or
one reference, from [typed query definitions](typed-queries.md):

```dart snippet="guides/query-invalidation.md#typed-invalidate"
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
```

With raw keys, the same calls are `invalidateQueries` with a filter:

```dart snippet="guides/query-invalidation.md#invalidate"
// Every key that starts with ['tasks']: the lists and every detail.
await client.invalidateQueries(
  filters: QueryFilters(queryKey: TaskKeys.all),
);

// This one detail only.
await client.invalidateQueries(
  filters: QueryFilters(queryKey: TaskKeys.detail(id), exact: true),
);

// Mark everything under ['tasks'] stale, and refetch nothing now.
await client.invalidateQueries(
  filters: QueryFilters(queryKey: TaskKeys.all),
  refetchType: RefetchType.none,
);
```

An invalidation does two things to every query it matches:

1. **It marks the query stale**, whatever its `staleTime` says — except
   `StaleTime.static`, which an invalidation leaves fresh. So the next mount,
   focus or reconnect refetches it.
2. **It refetches the query now if it is active** — if a widget or an
   observer is reading it. A query nobody reads waits until something reads
   it again, and then refetches because it is stale.

The future completes when those refetches have settled. A refetch that fails
does not fail it — the error lands in the query's state, where its readers
see it — and a refetch paused because the device is offline is not waited
for.

## Keys decide what an invalidation reaches

A filter's `queryKey` matches as a **prefix**: `['tasks']` matches
`['tasks']`, `['tasks', 'list', 'open']` and `['tasks', 'detail', '7']`. That
is why keys are built from the most general part down, and why an app
usually keeps them in one place. In a smart-home app, the device queries are
declared once, and every level of the hierarchy is something you can name —
the namespace, each family, each reference:

```dart snippet="guides/query-invalidation.md#device-queries"
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
```

With that, every invalidation in the app is a sentence about the domain
rather than a list of string arrays:

```dart snippet="guides/query-invalidation.md#typed-device-invalidations"
// Something changed about this device: its detail, and every room list.
await deviceQueries.detail(device.id).invalidate(client);
await deviceQueries.list.invalidate(client);

// A bulk import from the hub: everything about devices is suspect.
await DeviceQueries.namespace.invalidate(client);
```

A reference matches its own entry exactly; a family matches every input's
entry, by the prefix `['devices', 'list']`; a namespace matches everything
under its parts.

### With raw keys

A key factory does the same naming by hand:

```dart snippet="guides/query-invalidation.md#device-keys"
// lib/data/device_keys.dart
abstract final class DeviceKeys {
  static final QueryKey all = QueryKey(<Object?>['devices']);

  static final QueryKey lists = all.append(<Object?>['list']);

  static QueryKey list({required String room}) => lists.append(<Object?>[room]);

  static final QueryKey details = all.append(<Object?>['detail']);

  static QueryKey detail(String id) => details.append(<Object?>[id]);
}
```

and the invalidations name its levels:

```dart snippet="guides/query-invalidation.md#device-invalidations"
// Something changed about this device: its detail, and every room list.
await client.invalidateQueries(
  filters: QueryFilters(queryKey: DeviceKeys.detail(device.id)),
);
await client.invalidateQueries(
  filters: QueryFilters(queryKey: DeviceKeys.lists),
);

// A bulk import from the hub: everything about devices is suspect.
await client.invalidateQueries(
  filters: QueryFilters(queryKey: DeviceKeys.all),
);
```

`DeviceKeys.lists` matches every room's list; `DeviceKeys.all` matches the
lists, every detail and anything filed under a detail. See [query
keys](query-keys.md) for how keys compare, maps inside keys included.

## Narrowing the match

**`exact: true`** matches the key itself and nothing below it —
`QueryFilters(queryKey: DeviceKeys.lists, exact: true)` matches a query whose
key is exactly `['devices', 'list']`, and no room's list. A reference is
always exact, and a family or a namespace never is.

**`predicate`** takes the `Query` and says yes or no, for anything a key
prefix cannot express. It runs after the other fields have matched, so give
it a prefix to keep the set it is asked about small. A target's `filters()`
is that prefix, with the other fields as arguments:

```dart snippet="guides/query-invalidation.md#typed-predicate"
// The kitchen and the hallway were merged on the hub: invalidate the lists
// of both rooms, and nothing else.
const merged = <String>{'kitchen', 'hallway'};
await client.invalidateQueries(
  filters: deviceQueries.list.filters(
    predicate: (query) => merged.contains(query.queryKey.parts.last),
  ),
);
```

With raw keys, the prefix is a `QueryFilters` of its own:

```dart snippet="guides/query-invalidation.md#predicate"
// The kitchen and the hallway were merged on the hub: invalidate the lists
// of both rooms, and nothing else.
const merged = <String>{'kitchen', 'hallway'};
await client.invalidateQueries(
  filters: QueryFilters(
    queryKey: DeviceKeys.lists,
    predicate: (query) => merged.contains(query.queryKey.parts.last),
  ),
);
```

The other [filters](filters.md) work too: `type`, `stale`, `status` and
`fetchStatus`.

## Which queries refetch

`refetchType` decides the second step:

| `RefetchType` | Refetches |
|---|---|
| `active` | matching queries a reader is observing — the default, unless the filters' own `type` says otherwise |
| `inactive` | matching queries nobody is observing |
| `all` | both |
| `none` | nothing — the queries are only marked stale |

`RefetchType.all` is for data you know will be needed again soon, such as a
list behind the screen the user will return to. `RefetchType.none` is for a
change that should show up only when the data is next read.

A disabled query is marked but never refetched by an invalidation, and
neither is an observed query whose `staleTime` is `StaleTime.static`.

## A fetch already in flight

`cancelRefetch` (default `true`) decides what happens to a matching query
that is already fetching. If the query holds data, its fetch is cancelled and
a new one started, so what lands was fetched after your call — the fetch that
was running may have left before the server saw your write. If it has no data
yet, the running fetch is joined instead: that first load is the answer
anyway. Pass `false` to join a running fetch in every case.

## Awaiting it, or not

`await` the invalidation when the caller has to know the screen is
consistent — a pull-to-refresh whose indicator should stay until the new data
is there. Otherwise call `.ignore()` on the future and let the refetch run
behind whatever comes next. After a mutation the choice decides how long the
mutation stays `pending`; see [invalidations from
mutations](invalidations-from-mutations.md).

The [`invalidation-and-filters` screen](../examples/invalidation-and-filters.mdx) runs every one of these calls against a
small cache: the posts list, two observed posts, one post nobody reads, and
the todos. Press *Invalidate posts prefix* and watch the three observed posts
entries refetch while post 3 is only marked stale; *Invalidate posts exactly*
refetches the list alone, and *Invalidate inactive too* fetches post 3 as
well.

<LiveDemo feature="invalidation-and-filters" />

## Related operations

| Call | What it does |
|---|---|
| `refetchQueries` | refetches matching queries now, without marking anything stale; skips disabled and static ones |
| `resetQueries` | puts matching queries back to their initial state (their `initialData`, or nothing), then refetches the active ones |
| `removeQueries` | drops matching queries from the cache — for keys nobody is watching; a reader still attached keeps showing what it had |
| `cancelQueries` | cancels matching fetches in flight and, by default, puts each query back to the state it had before the fetch |

A namespace, a family and a reference have each of these as a method —
`refetch`, `reset`, `remove` and `cancel` — over the same filters their
`invalidate` uses.

:::note[In React Query]
The same `queryClient.invalidateQueries`, with the same prefix matching,
`exact`, `predicate`, `refetchType` and `cancelRefetch`. The filters are a
named `filters:` argument here rather than the first argument, and
`StaleTime.static` is TanStack Query's `staleTime: 'static'`.
:::

## See also

- Examples: the [cache inspector](../examples/cache-inspector.mdx) lists every entry with buttons for refetch, invalidate and remove.
- Cookbook: [Realtime updates over a WebSocket](../cookbook/realtime-websockets.md) invalidates on a server event, and [sign out and multiple accounts](../cookbook/sign-out-and-multi-account.md) clears the cache on a change of user.
