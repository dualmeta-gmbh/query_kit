---
status: accepted
date: 2026-11-10
ticket: https://github.com/dualmeta-gmbh/query_kit/issues/132
---

# Typed query definitions are values over the client

Until now a key and its data type met at every call:
`client.getQueryData<Device>(key)` is right as long as each caller repeats
the type the fetch function returns, and `setQueryData` infers the entry's
type from whatever it is handed. Map #129 adds a layer that states both
once. Its plan is `docs/plans/typed-query-definitions.md` (D1 to D12, with
the review record); its analyzer fixtures are `tool/typed_query_fixtures/`.
This record keeps the parts of the public shape that cannot be changed
after a release without breaking the code written against them.

(Ticket #132 called this ADR-0005. That number and 0006 were taken in the
meantime.)

## Decision

The core exports ten types from one library,
`packages/query_kit/lib/src/query_definition.dart`, and adds nothing to
`QueryClient`, `QueryKey` or any options class.

1. **Four things with four lifetimes.** A *definition* (`QueryDefinition`,
   `QueryFamily`, `InfiniteQueryDefinition`, `InfiniteQueryFamily`) is made
   once and holds the key schema and the fetch function. A *reference*
   (`QueryRef`, `InfiniteQueryRef`, both a `QueryEntryRef`) is a definition
   bound to an input: one cache entry and its data type. A *typed key*
   (`TypedQueryKey`) is what the cache compares, with the type kept. A
   *namespace* (`QueryNamespace`) is a key prefix and claims no data type.
   A definition without an input is its own reference.
2. **Writes are anchored to the receiver.** `ref.write(client, value)` and
   `ref.update(client, updater)` take no type argument of their own: the
   type is the reference's before the argument is seen. There is no
   `client.setData<T>(key, value)`.
3. **Identity is structural, and nothing registers a definition.** A key
   is the namespace's parts, the name and the input (or what `keyOf` makes
   of it). References and typed keys are values: equal when they address
   the same entry with the same data type, whichever instance made them.
   Options are not values, and `options()` builds them anew on every call.
4. **`QueryTarget` and `QueryEntryRef` are sealed**, `QueryRef` and
   `InfiniteQueryRef` are `abstract final`, and `TypedQueryKey` has no
   public constructor. Nothing outside the library can be one.
5. **A declaration is a constructor call.** No factory method on a
   namespace, no top-level function, no typedef for the function types.
6. **`keyOf` is optional.** Without it the input is the one key part after
   the name.

## Why

**Four things, not one generic key.** A key that also carried the fetch
function would be a second options type, and a key that carried a data
type could not be a prefix: a namespace over devices, their list and a
lookup holds three data types and can still invalidate them, because it
never said it had one. The four lifetimes are also what the surface does
*not* offer, each an analyzer error at its line: a family has no `read`, a
namespace no `write`, a typed key no way in from a plain `QueryKey`.

**The receiver, because Dart widens.** In
`setData<T>(TypedQueryKey<T> key, T value)` Dart solves `T` from both
arguments and takes a common supertype: `setData(deviceKey, 'x')` compiles
with `T = Object` and creates a `Query<Object>` that the device's own next
read refuses. The fixtures hold that case (`boundary/generic_setter.dart`).
A method on the reference has its type before the argument is looked at.
This is not invariance. A `QueryRef<Device>` is assignable to
`QueryRef<Object?>`, and a write through that compiles; the VM refuses it
at the call, and a JavaScript build at `-O3` or `-O4` omits that check and
omits casts. So every typed write tests the value, and every updater's
result, with an explicit `is` through `Object?`, which each level keeps,
and a family tests its input the same way.

**No registry, because it could not finish the job.** The cache already
holds one exact data type per key and every typed read and write is exact,
so two definitions of one key with different types meet a
`QueryDataTypeError` at the first use of the second. A registry would add
what a definition does not have (a lifetime: remove, clear, two clients,
hot reload) to detect what it still could not: two definitions of one key
with the same type and different fetch functions are indistinguishable to
it, and a closure made again is equivalent and not identical. Identity
from the definition instance or its closure would be worse, since a
collision would then hide as a second entry and a hot reload would lose
the cache.

**Values, and options that are not.** A reference is equal to another of
the same kind (plain or infinite) with an equal typed key. That is what
lets a rebuild hand in `detail('d1')` again and what lets a user key a map
on it. Options carry closures, which are equal only to themselves, and
every call style re-applies options on every build on purpose (#84
re-evaluates an `Enabled.when` over outside state there). Gating that on
equality would bring #84 back; a memo per input would grow without bound.
The cost of unequal options is the one it is today for options written
inline: a `QueryObserverOptionsUpdated` event per rebuild.

**Sealed, so the checks are the library's.** A subclass could override
`write` and drop the check, or pose as a target. Sealing also makes a
`switch` over "what is this aimed at" exhaustive, and it is why all ten
types are one library: Dart wants every direct subtype of a sealed or
final class beside it.

**Constructors, because the two spellings buy the same.** A factory
(`devices.family<String, Device>('detail', ...)`) and the constructor infer
the same types, fail the same way without type arguments and hit the same
debug check; the factory saves the `namespace:` line. It costs
`devices.query('list', ...)` declaring one receiver away from
`client.query(...)` fetching, and two spellings of one thing in every
guide. A user who wants the factory writes it as an extension over the
public constructors; the fixtures hold one of some ninety lines.

**`keyOf` optional, because most inputs are already key parts.** A string,
a number, an enum, a list, a map and a record of those compare by value in
a `QueryKey`. Making `keyOf` required would add a line to every family for
the one case that needs it.

## Considered options

1. **One `QueryKey<T>` that is identity and definition.** `QueryKey` is
   final and its equality is what the cache runs on; a type argument in it
   would either enter equality, splitting one entry in two, or be a claim
   anyone can make with a cast.
2. **A generated client in the tRPC style.** Needs a generator, which
   neither published package may require.
3. **A client-style generic setter, alone or beside the reference's.**
   Compiles the wrong write, above. It may be added later only if it
   passes the same negative fixtures.
4. **A registry of definitions per client.** Above.
5. **Unsealed references**, so that an application can add its own kind.
   Nothing asked for one, and it would make the runtime check optional.
6. **Factories on the namespace, alone or beside the constructors.** Above.

## Consequences

- The ten names, their members and the equality of references and typed
  keys are under semantic versioning from the release that first exports
  them. Unsealing a type, adding a public constructor to `TypedQueryKey` or
  letting a reference's equality see its fetch function is a major.
- **Type arguments on a family are written out.** Dart infers the data
  type from the fetch function and nothing tells it the input type, so
  `QueryFamily(...)` without them has an input of `Object?`. Every
  definition's constructor refuses a top type in a debug build; it is a
  backstop, not a compile error, and the documentation says so.
- **Same-type collisions are not detected**: two definitions of one key
  with one data type are one entry, and the observer takes the fetch
  function it was last handed. Nor is an ordinary definition typed
  `InfiniteData<P, Q>` beside an infinite one of the same page types, or a
  key nested under a family's prefix that holds the family's type.
- **A record input that holds a list, a map or a set needs a `keyOf`.** A
  record compares its fields with `==` and `QueryKey` cannot look into
  one. That is the price of the optional `keyOf`, and it is documented on
  both families.
- **`rawKey` leaves the typed surface.** A typed reference and a plain key
  with the same parts are one entry, so an application migrates one query
  at a time; with the client's own `setQueryData` the type argument is the
  caller's to get right again, and that write stays lenient where the
  typed one is exact (a `Device` into an entry of `Device?`).
- The raw API does not change. Its tests stay green with no case rewritten,
  and the typed layer is tested against it: the same events, the same
  sharing, the same fetch behaviour.
- A family's bulk update runs its own pass in the order of the client's
  `updateQueriesData`, not that method: each of its steps is lenient where
  a typed write has to be exact.
- `options()` allocates on every call, and a write that creates an entry
  runs the definition's `configure` first, to build the entry with the
  definition's options.
