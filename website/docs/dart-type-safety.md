---
title: Type safety in Dart
description: Sealed results, typed query definitions, one key one exact type, two options shapes, and the analyzer setting that catches the one literal inference cannot type.
---

# Type safety in Dart

TanStack Query leans on TypeScript: generics that thread a key's shape into
its function, and a data type the compiler infers through `queryOptions()`
and trusts, with no check at runtime.
Dart's type system is sound and has sealed classes, so the port leans on those
instead. The result is fewer type parameters, no `!`, and one runtime check
that is stricter than you may expect. What you feel at the call site:

## The result is sealed

A query result is one of `QueryPending`, `QuerySuccess` or `QueryError`. A
`switch` over it is exhaustive, so the compiler tells you when a state is not
handled, and the data is a non-nullable field of `QuerySuccess` — no `data!`.
`QueryError` carries `staleData`, the last good value, for a refetch that
failed with data already on screen. See [queries](guides/queries.md).

```dart snippet="dart-type-safety.md#sealed-switch"
Widget deviceTitle(QueryResult<Device> device) => switch (device) {
      QueryPending() => const Text('…'),
      QuerySuccess(:final data) => Text(data.name),
      // `staleData` is a Device? — the last good value, when there was one.
      QueryError(:final staleData?) => Text('${staleData.name} (offline)'),
      QueryError() => const Text('Unknown device'),
    };
```

Case order matters in the usual Dart way: the `QueryError(:final staleData?)`
arm matches only when there is stale data, so the plain `QueryError()` after it
catches the rest.

A mutation result is sealed the same way: `MutationIdle`, `MutationPending`,
`MutationSuccess`, `MutationError`.

## Two type parameters, not five

- `Query<TQueryData>` at the cache layer, `QueryObserver<TQueryData, TData>`
  where a `select` needs a second.
- There is no `TError`: errors are an `Object` plus a `StackTrace`, as
  everywhere in Dart.
- There is no `TQueryKey`: a `QueryKey` is a value type, deep-frozen and
  compared by value. See [query keys](guides/query-keys.md).

## Two options shapes

Observer options come in two shapes: `QueryObserverOptions<TData>`, with no
`select` and one type argument, and `QuerySelectOptions<TQueryData, TData>`,
with `select` required. The required `select` is what anchors the second type,
so neither shape has a type argument inference cannot fill. See [describing a
query once](guides/query-options.md).

## The one literal inference cannot type

A key-only options literal — neither a `queryFn` nor a type argument, relying
on a cached entry or a [default query function](guides/default-query-function.md)
— has nothing to infer its data type from, and Dart would silently make it
`dynamic`. Two things catch it:

- the binding's controllers refuse it in debug builds, with a message naming
  the cure;
- the analyzer reports it at the literal once `analysis_options.yaml` asks
  for strict inference. Recommended:

```yaml
analyzer:
  language:
    strict-inference: true
```

The cure is an explicit type argument:

```dart snippet="dart-type-safety.md#key-only"
// Nothing to infer the type from — no queryFn, no expected type — so name
// it. Without <Device>, this would be a QueryResult<dynamic>.
final device = context.query(
  QueryObserverOptions<Device>(queryKey: DeviceKeys.detail(id)),
);
```

## One key, one exact type

A key is bound to the data type it was first used with, and reading it as any
other type throws `QueryDataTypeError` — **related types included**. `int` and
`int?` are two types. So are `List<Device>` and `List<Object?>`.

```dart snippet="dart-type-safety.md#one-type"
final key = DeviceKeys.list();
client.setQueryData<List<Device>>(key, const <Device>[]);

client.getQueryData<List<Device>>(key); // the entry's own type: fine
client.getQueryData<List<Object?>>(key); // throws QueryDataTypeError
```

The error is thrown by the call itself, synchronously, and names the key, the
type asked for and the type the entry holds.

In TanStack Query a key made by `queryOptions()` carries its data type as a
`DataTag`, so `getQueryData(options.queryKey)` is inferred; a plain key or a
`getQueriesData` filter gives `unknown` unless a type argument is written,
and that argument is trusted, not checked. Here `getQueryData<T>`,
`getQueriesData<T>` and an observer's `TQueryData` all have to agree with the
key's first use, at runtime. It is the single most likely thing to catch
you out when porting JavaScript, and it is catching a real bug.

A **write** is the one place a related type is welcome. `setQueryData` infers
its type from the value (and so do `updateQueryData` and `updateQueriesData`
from the updater), so an entry that already exists takes any value its own
type can hold — a `String` into a `String?` query, a sealed type's variant
into a query of the sealed type — and keeps its type:

```dart snippet="dart-type-safety.md#writes"
// The type comes from the value: a Device, into an entry holding a Device.
client.setQueryData(
    DeviceKeys.detail(device.id), device.copyWith(isOn: true));

// The type comes from the updater's parameter.
client.updateQueryData(
  DeviceKeys.list(),
  (List<Device>? devices) => <Device>[
    for (final each in devices ?? const <Device>[])
      each.id == device.id ? device : each,
  ],
);
```

Name the type when the write *creates* the entry, as when seeding a key before
its query exists: `setQueryData<List<Device>>(key, const [])`. A bare
`setQueryData(key, null)` writes nothing.

The showcase's [*diagnostics* screen](examples/diagnostics.mdx) holds an `int` under one key. Press *Read
as String* and the facts read `read=QueryDataTypeError`, `expected=String`,
`actual=int`; *Read as int* succeeds, and *Write a String* is refused the same
way. The second card shows a mutation with no function failing with
`MissingMutationFunctionError` until *Register a default mutationFn* supplies
one:

<LiveDemo feature="diagnostics" />

When one key prefix spans entries of different types, give each type its own
key, or store a wrapper type that says what the entry is. See
[troubleshooting](reference/troubleshooting.md#querydatatypeerror-for-a-list-that-is-the-right-type).

## Typed query definitions

A [typed query definition](guides/typed-queries.md) declares a key, its
fetch function and its data type once. The reference it hands out reads and
writes the entry with no key and no type argument at the call site, so a
mismatch the client would refuse at runtime becomes one the analyzer refuses
at the call:

```dart snippet="dart-type-safety.md#typed-writes"
final ref = queries.devices.detail(device.id); // QueryRef<Device>

ref.write(client, device.copyWith(name: 'Porch lamp'));
ref.update(client, (current) => current?.copyWith(room: 'porch'));
final Device? cached = ref.read(client); // no type argument to repeat
```

The one-type rule above still holds underneath: a reference's write into an
entry that holds another type throws `QueryDataTypeError`, and so does a raw
call that disagrees with the definition. What the analyzer checks, what only
the runtime checks and what nothing checks are listed in the guide's
[limits](guides/typed-queries.md#limits).

## Sealed values instead of magic numbers

`null` means "not configured" on every option field. An option with modes is
a sealed value type — `StaleTime`, `GcTime`, `Enabled`, `RetryPolicy`,
`RetryDelay`, `RefetchOn`, `RefetchInterval` — never a magic number, string
or boolean. `staleTime: 0`, `staleTime: Infinity` and `staleTime: 'static'`
are three ideas JavaScript squeezes into one field; here they are three
constructors of one sealed class, and a `switch` over them is exhaustive. See
[describing a query once](guides/query-options.md#two-rules) for the
computed forms.

## Where the types live in an app

The pattern the guides use: one file per data area under `lib/data/`, holding
that area's definitions, a namespace and one definition or family per query.
Widgets call a reference and never write a type argument; the reference
carries it, the result is typed from its options, and the one place a key is
bound to its type is the one declaration that builds it. Without
definitions, the same file holds a key factory and one function per query
returning fully typed options, `QueryObserverOptions<List<Device>>
devicesQuery(...)`. See [typed query definitions](guides/typed-queries.md),
[query keys](guides/query-keys.md) and [describing a query
once](guides/query-options.md).

:::note[In React Query]
TanStack's `queryOptions()` helper and its `DataTag`-branded keys tie a key to
its data type at the type level, and an app can register the shape every
query key must have through the `Register` interface. Here a definition's
reference carries the type, and the cache checks it at runtime as well. See
[differences from TanStack Query](reference/differences-from-tanstack.md).
:::

## Cancellation and time

- **Cancellation is `QueryCancelToken.onCancel`**, because Dart has no
  ecosystem-wide cancellation primitive. See [query
  cancellation](guides/query-cancellation.md).
- **Time goes through `package:clock`**, so fake time in tests controls
  staleness and garbage collection completely. See
  [testing](guides/testing.md).
