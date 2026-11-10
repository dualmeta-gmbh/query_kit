# Plan: native typed query definitions

Status: proposed implementation plan, revised after three review rounds
(Fable, then GPT-6-Astra and Opus 5.5 independently twice, all 2026-10-18;
the [review record](#review-record) at the end says what each finding
became). Round 2 found that three decisions of round 1 rested on wrong claims
about the current code; round 3, scoped to round 2's diff, found no P1 and
closed the gaps round 2's fixes left. Further plan reviews were judged to
give diminishing returns; the remaining questions were Phase 0's.

**Phase 0 is done (TQ0, [#131](https://github.com/dualmeta-gmbh/query_kit/issues/131),
2026-11-10).** The analyzer fixtures, their runner and a working prototype of
the surface are in `tool/` ([Phase 0](#phase-0--prove-the-dart-api-before-implementing-the-facade)
says how to run them). Open-1, Open-2 and Open-7 are answered under their
decisions, each answer marked **Phase 0**; [Final surface (TQ0)](#final-surface-tq0)
is what Phase 1 implements; the [review record](#phase-0-tq0-2026-11-10)
lists every change Phase 0 made to this plan and why. Phase 0 changed no
package code: it touched nothing under `packages/` but PORTING_NOTES.

**Phase 1 is done (TQ1, [#132](https://github.com/dualmeta-gmbh/query_kit/issues/132),
2026-11-10).** The ten types are the core's
`packages/query_kit/lib/src/query_definition.dart`, exported from the
barrel; the prototype is deleted and the fixtures analyze and run against
the package alone. The lasting part of the shape is
[ADR-0007](../adr/0007-typed-query-definitions-are-values-over-the-client.md).
[Phase 1](#phase-1--ordinary-definitions-and-cache-operations) has a
"Done" block, and the [review record](#phase-1-tq1-2026-11-10) lists where
the implementation left this plan and why. Nothing is released: the
version bumps are Phase 4's (D11).

**Phase 2 is done (TQ2, [#133](https://github.com/dualmeta-gmbh/query_kit/issues/133),
2026-11-10), and with it the five findings of GPT-6.1-Sol's review of
TQ0.** Two claims of this plan were narrowed by that review, not
defended: a collection literal of references of one class and two data
types infers `QueryRef<Object>`, not `QueryTarget` (D9, limit 18), and
only an infinite definition holds a written `InfiniteData` to its page
types (D5, limit 20). Two things were fixed: options of another type
returned by `configure` are refused on every runtime (D6, limit 19), and
the fixture runner can no longer pass with less than it was committed
with ([Phase 0](#phase-0--prove-the-dart-api-before-implementing-the-facade)).
[Phase 2](#phase-2--families-infinite-queries-and-mutation-workflows) has
a "Done" block with the mutation recipes and the exit walked item by
item; the review record ends with one table for the review and one for
the phase. No signature changed.

Date: 2026-10-18. Repository baseline: `a5afe7d` (`main`). Phase 0 ran over
`51ab8ad`.

Decider: the agent, under the AFK rule of map
[#1](https://github.com/dualmeta-gmbh/query_kit/issues/1). Every decision
below names the options, the answer and the reason, so it can be reopened
from this document alone. Only what needed an analyzer to answer was left
for Phase 0; the [open questions](#open-questions-for-phase-0) list says
which those were and where each answer is.

## Goal and scope

Make a typed query definition the normal way to use `query_kit`. A developer
defines the input, cache identity and fetch function together, then uses the
resulting reference for observing, fetching, reading, writing and invalidating.
Ordinary application call sites should need neither string-list keys nor
repeated data type arguments. Misspelled members, wrong inputs and incompatible
writes must produce analyzer errors on the supported Dart versions.

This is a native capability of the pure-Dart core, available through all four
equal Flutter call styles and the optional hooks package. It uses the existing
cache, observers and lifecycle. No mandatory generator, state-management
integration or new runtime dependency is required.

This document is the plan. The implementation is tracked by wayfinder map
[#129](https://github.com/dualmeta-gmbh/query_kit/issues/129), one ticket per
phase (TQ0 to TQ6, #131 to #137), as
[CONTRIBUTING](../../CONTRIBUTING.md#where-the-plan-lives) asks for a change
to the API's shape. It waits for Christian's go: TQ-GO
([#130](https://github.com/dualmeta-gmbh/query_kit/issues/130), `hitl`)
blocks TQ0 (decided 2026-10-18). A generator stays outside this plan.

## Current behaviour and the gap

- [QueryKey](../../packages/query_kit/lib/src/query_key.dart) is a final,
  non-generic structural value built from `List<Object?>`. A misspelled string
  is a different valid identity. Collections are frozen; arbitrary user objects
  must provide stable value equality. Record fields containing collections
  have an explicitly documented equality limitation.
- [Query options](../../packages/query_kit/lib/src/query_options.dart) carry
  the cache type. Plain and selected options are separate shapes, following
  [ADR-0001](../adr/0001-one-type-slot-for-plain-queries.md). They must remain
  separate so an optional selector cannot introduce an unanchored type slot.
- [QueryClient](../../packages/query_kit/lib/src/query_client.dart) accepts an
  untyped key for `getQueryData<T>`, `getQueryState<T>`, writes and updates.
  Callers can choose a data type independently of the key.
- [QueryCache](../../packages/query_kit/lib/src/query_cache.dart) enforces one
  exact cache type per key at runtime. Writes have deliberate subtype rules;
  a write that creates an entry currently takes its type from the write call.
- The bulk read `getQueriesData` checks every entry under a prefix against
  the exact requested type and throws `QueryDataTypeError`. The writes are
  lenient: `setQueryData` and `updateQueriesData` accept any value the entry
  can hold (`_holds`, `_heldFor` in `query_client.dart`), so an
  `updateQueriesData<int>` writes into a `Query<num>`, an entry of another
  type with no data passes a null-returning updater, and a
  `setQueryData<Device>` lands in a `Query<Device?>`. Reproduced in round 2.
- Every call style re-applies options on every build by design
  (`read_set.dart`, `query_builder.dart`, the hooks' `ControllerHook`, which
  has no `keys`): that is how #84's rule re-evaluates an `Enabled.when` over
  outside state. `QueryOptions` has no value equality on purpose; the observer
  compares resolved values, `shouldFetchOptionally` runs on every
  `setOptions`, and the only thing an unequal `DefaultedQueryOptions` (its
  `==` compares `queryFn` with `==`) adds is one `notifyObserverOptionsUpdated`
  to the cache per rebuild. An inline closure costs that today.
- A method parameter typed by a covariant class type argument is checked at
  the call: `write('x')` on a `QueryRef<Device>` held as `QueryRef<Object?>`
  throws Dart's own `TypeError`, not the cache's. dart2js at `-O4`, Flutter's
  web release and profile level, omits that check and the write goes through;
  an explicit `is` check through `Object?` still fires there. Reproduced in
  round 2 on Dart 3.11.
- Imperative fetching is `client.query(...)` / `client.infiniteQuery(...)`,
  not an existing `fetchQuery` / `ensureQueryData` API. Freshness, background
  revalidation, cancellation and retry semantics must survive the new facade.
  `QueryObserverOptions<T>` extends `QueryOptions<T>`, so options a reference
  produces can be handed to `client.query` as they are.
- Prefix filters can span different data types. A namespace such as `devices`
  does not have one meaningful data type for reading or updating every entry.
- The Flutter binding already has an internal `QueryScope` widget in
  [query_context.dart](../../packages/query_kit_flutter/lib/src/query_context.dart).
  Use `QueryNamespace` as the working name for the new core hierarchy to avoid
  conflating cache-key grouping with widget ownership.

## Proposed developer experience

The names and examples below are the surface Phase 0 settled; every line of
them is a fixture (`tool/typed_query_fixtures/support/models.dart` holds the
declaration, `positive/plain_reference.dart` the call sites,
`negative/dx_misuses.dart` the six refused lines). The exact signatures are
under [Final surface (TQ0)](#final-surface-tq0).

One explicit declaration per operation, with a normal Dart namespace:

```dart
final class DeviceQueries {
  DeviceQueries(this._repository);

  final DeviceRepository _repository;
  static final namespace = QueryNamespace(['devices']);

  // `late final`, not an initializer list: a family whose fetch function
  // calls a sibling (a list that seeds its details) needs `this`, and an
  // initializer list has none.
  late final detail = QueryFamily<String, Device>(
    namespace: namespace,
    name: 'detail',
    queryFn: (id, context) =>
        _repository.device(id, signal: context.signal),
  );

  Future<void> invalidate(QueryClient client) => namespace.invalidate(client);
}

final queries = (devices: DeviceQueries(repository));
final device = queries.devices.detail('d1'); // QueryRef<Device>
```

The definition above produces the structural raw key
`['devices', 'detail', 'd1']`: the input is the one key part after the name
unless the family is given a `keyOf` (D3). Namespace and operation strings
occur in the definition, not throughout the application. Static queries need an equally
typed zero-input definition (`QueryDefinition<T>` is the working name), without
invented `null` or `dynamic` arguments at each call site.

```dart
final result = context.query(device.options()); // QueryResult<Device>
final cached = device.read(client);             // Device?
final key = device.key;                         // TypedQueryKey<Device>
final byKey = key.read(client);                 // Device?
final fetched = await device.fetch(client);     // Device

device.write(client, updatedDevice);
device.update(client, (previous) => previous?.copyWith(isOn: true));

await device.invalidate(client);                 // Exact entry
await queries.devices.detail.invalidate(client); // Every detail input
await queries.devices.invalidate(client);        // Whole namespace
```

These ordinary call sites are rejected statically, each with the analyzer
error named beside it, on Dart 3.6.2, 3.10.7 and 3.13.4 alike (Phase 0):

```dart
queries.devces.detail('d1');                 // undefined_getter
queries.devices.detial('d1');                // undefined_method
queries.devices.detail(123);                 // argument_type_not_assignable
device.write(client, 'not a device');        // argument_type_not_assignable
device.update(client, (_) => 42);            // return_of_invalid_type_from_closure
String? wrongRead = device.key.read(client); // invalid_assignment
```

Ordinary Dart classes or typed records provide member autocomplete. A map with
string keys cannot manufacture new statically checked Dart members at runtime.
A future generator may remove declaration boilerplate; it must build on the
same core definitions and provide no exclusive runtime capability.

## Decisions

Each decision names its options, the answer and why it beat the
alternatives. "Open" means an analyzer has to answer it; those are collected
under [open questions for Phase 0](#open-questions-for-phase-0).

### D1. Definition, identity, reference and namespace are different things

**Options:** (a) one `QueryKey<T>` that is both identity and definition;
(b) separate definition (`QueryFamily` / `QueryDefinition`), bound reference
(`QueryRef`), typed key (`TypedQueryKey`) and prefix group (`QueryNamespace`);
(c) a generated client in the tRPC style.

**Answer:** (b).

**Why:** a key alone cannot carry a fetch function without becoming a second
options type, and (c) needs a generator the core may not require. The four
things have four lifetimes: a definition is created once, a reference per
input, a key is what the cache compares, and a namespace is a prefix with no
data type. Keeping them apart is what lets a heterogeneous namespace offer
invalidation without lying about a data type.

- `QueryFamily<TInput, TCacheData>` owns one operation path, its input-to-key
  mapping and its typed fetch function. Calling it binds an input and returns
  `QueryRef<TCacheData>`.
- `QueryDefinition<TCacheData>` covers an operation without varying inputs.
- The references form one small hierarchy, because the two options types do
  not share a subtype (`QueryObserverOptions` and
  `InfiniteQueryObserverOptions` are separate `final` classes that meet only
  at `QueryOptions<InfiniteData<P, Q>>`):
  - a sealed `QueryEntryRef<T>` holds the typed key, `read`, `state`,
    `write`, `update` and the exact lifecycle operations, and no `options()`;
  - `QueryRef<T>` is the plain reference and owns `options()` (a
    `QueryObserverOptions<T>`) and `fetch`;
  - `InfiniteQueryRef<TPageData, TPageParam>` is a
    `QueryEntryRef<InfiniteData<TPageData, TPageParam>>` and owns its own
    `options()` (an `InfiniteQueryObserverOptions<TPageData, TPageParam>`)
    and `fetch` over `client.infiniteQuery`.
  A reference binds a definition and input and exposes operations whose data
  type comes from it. It does not retain a client, mount observers, fetch or
  register timers merely because it was constructed.
- `TypedQueryKey<TCacheData>` wraps the existing raw `QueryKey` and retains the
  cache type for key-only reads and state access. Creation goes through
  definitions and references, not a public arbitrary `fromRaw<T>` cast. Its
  `==` is the raw key plus `TCacheData`; its `rawKey` is what filters take.
- `QueryDefinition<TCacheData>` is itself a `QueryRef<TCacheData>`, and
  `InfiniteQueryDefinition<TPageData, TPageParam>` is itself an
  `InfiniteQueryRef`: a zero-input definition needs no call and no invented
  argument. Every infinite query in the shipped examples is zero-input (the
  hooks example's projects, the showcase's load-more and max-pages screens),
  so the infinite side needs the zero-input form as much as the plain one.
- The name `QueryRef` sits beside the public `QueryObserverRef`; both are
  references to a query from a different side, and the docs say which is
  which.
- `QueryNamespace` selects entries by prefix without claiming a data type.
  It supports lifecycle operations and filters, not typed data reads/writes.

**Phase 0 (the name):** `QueryRef` stays. Options: keep it; `QueryHandle`;
`QueryEntry`; `BoundQuery`. The two names never meet where a reader could
confuse them: `QueryObserverRef` is the cache's name for an observer inside
its events (`QueryObserverAdded.observer`), an interface whose every member
is `@internal`, while `QueryRef` is what an application declares and passes
around. `positive/reference_names.dart` uses both from one import in one
function, neither shadows the other, and
`final QueryObserverRef observer = queries.devices.detail('d1');` is an
`invalid_assignment` (`negative/surface_limits.dart`). `Ref` is also the
word the reader brings along: the plan, the map and every ticket say
"reference", and `ref.write(client, …)` reads as what it does. A rename
would buy nothing the fixtures show a need for, and `QueryEntry` would sit
one letter from `QueryEntryRef`. The docs introduce `QueryRef` as "a
reference to one cache entry" and mention `QueryObserverRef` only on the
cache-events page, where it already is.

**Phase 0 (one more type, `QueryTarget`):** the five lifecycle operations
and the filters are the same on a namespace, a family, an infinite family
and a reference, and D7 asks for "a typed filter adapter". Options: (a) the
operations written out on each of the four, and a free function for the
filters; (b) one sealed supertype, `QueryTarget`, that carries
`invalidate`, `refetch`, `cancel`, `reset`, `remove` and
`filters({type, stale, fetchStatus, status, predicate})`, and no data type.
Answer: (b). It is the adapter D7 names, it is the type a helper takes that
invalidates "whatever it is given", and it is the element type a list of
references of several data types is declared with, `<QueryTarget>[a, b]`,
so that it can be invalidated and its elements cannot be written
(`positive/target_list.dart`, `negative/surface_limits.dart`). Phase 0
claimed more: that such a list *infers* `List<QueryTarget>`. The review
of TQ0 showed that holds only for references of different classes (S0-1,
corrected under D9 and in limit 18). The cost is one more public name. It is
sealed, like `QueryEntryRef`, so a switch over "what is this aimed at" is
exhaustive (`positive/reference_names.dart`) and nothing outside the
library can pose as a target (`invalid_use_of_type_outside_library`).

**Phase 0 (Open-2, what the surface does not offer):** a namespace has no
`read`, `state`, `write`, `update`, `options` or `key`; a family has no
`read`, `write`, `options`, `fetch` or `key`; `QueryEntryRef` has no
`options` and no `fetch`; a plain reference is not an infinite one and the
reverse; `TypedQueryKey` has no public constructor, no `fromRaw`, no
`write`, is not assignable from a `QueryKey` and is not accepted where a
raw key is; `QueryRef<Device>()` does not exist; and none of
`QueryTarget`, `QueryEntryRef`, `QueryRef`, `TypedQueryKey` can be
implemented outside the library. Each is an analyzer error at its line
(`negative/surface_limits.dart`).

`QueryKey` and its equality/hashing stay unchanged. It is final, so the typed
key wraps it. No `T`, closure identity or definition instance identity enters
cache equality: that would hide a collision behind a second cache entry and
break raw/typed interoperability. The `rawKey` escape hatch documents the loss
of static guarantees.

### D2. Writes are anchored to the receiver's type

**Options:** (a) `client.setData<T>(TypedQueryKey<T> key, T value)`;
(b) `ref.write(client, TCacheData value)` and
`ref.update(client, TCacheData? Function(TCacheData?) updater)` with no type
parameter on the operation; (c) both.

**Answer:** (b). A client-style convenience may be added later only if it
passes the same negative analyzer fixtures.

**Why:** in (a) Dart infers `T` from both arguments and can widen it to a
common supertype, so `setData(deviceKey, 'x')` compiles with `T = Object`.
Making keys generic does not by itself establish the guarantee. In (b) the
type is fixed by the receiver before the argument is seen.

This does not make Dart generics invariant. `QueryRef<Device>` is assignable
to `QueryRef<Object?>`, and `write(client, 'x')` compiles on the widened
reference. At runtime the VM and dart2js at its default level throw Dart's
covariance `TypeError` before the method body runs; dart2js at `-O4`, which
is what Flutter's web release build uses, omits that check. So `write` and
`update` check the value, and the updater's result, explicitly through
`Object?` (`final Object? v = value; if (v is! TCacheData) throw
QueryDataTypeError(...)`), which `-O4` keeps; the operations are methods,
not callback fields, because reading a contravariant field through a widened
receiver can throw even for a valid argument. Explicit upcasts, raw
generics, `dynamic` and dishonest casts remain boundaries; the fixtures test
widened receivers as well as natural calls, and one fixture compiles with
`dart compile js -O4`. This closes Open-3 of round 1. The acceptance claim is the tested typed surface, not
that every expressible Dart program fails statically. Existing raw client
methods are not widened to `Object` or `dynamic` to simulate overloads.

**Phase 0 (Open-2, the generic setter):** option (a) was written out as
`T setData<T>(QueryClient client, TypedQueryKey<T> key, T value)`
(`support/client_style_setter.dart`). `setData(client, device.key, 'not a
device')` **compiles**, and `expectStaticType` pins its result as `Object`;
the same as a method of the client; `42` under a `Device?` key solves
`T = Object?`; an `InfiniteData<String, String>` under the feed's key solves
`InfiniteData<Object, Object>` (`boundary/generic_setter.dart`, clean under
the analyzer's defaults and under this repository's strict options, on
Dart 3.6.2, 3.10.7 and 3.13.4). Run, it creates a `Query<Object>` holding a
`String` under the device's key, after which the reference's own `read`
throws `QueryDataTypeError` (observations `D2-setter-1`, `-2`). The same
value written through the reference is `argument_type_not_assignable`.

The claim is narrower than round 2 wrote it, and the fixture says so: the
widening is a property of the **value** setter. A generic *updater*,
`updateData(client, device.key, (previous) => 42)`, is refused
(`return_of_invalid_type_from_closure`), because Dart solves `T` from the
non-closure arguments before it infers the closure; and an explicit
`setData<Device>(…)` is refused too (`negative/generic_setter.dart`). D2's
answer stands on `write` alone, which is the operation an optimistic update
and a server-response write use.

**Phase 0 (Open-7):** `runtime/observations.dart` runs the surface with
widened receivers on five runtimes per SDK (the VM with and without
assertions, dart2js at its default level, at `-O3` and at `-O4`, under
node), and the runner compares what each prints with a recorded file. On
Dart 3.6.2, 3.10.7 and 3.13.4 alike:

| Observation | VM, dart2js default | dart2js `-O3`, `-O4` |
|---|---|---|
| a `String` into a `Box<Device>` held as `Box<Object?>` (no library code) | `TypeError` | no check: the box holds a `String` |
| naive `write`, plain delegation to `setQueryData<Device>` | `TypeError` | completes: a `Query<Device>` holding a `String` |
| naive `update`, delegation to `updateQueryData<Device>` | `TypeError` | completes: a `Query<Device>` holding an `int` |
| naive bulk update, delegation to `updateQueriesData<Device>` | `TypeError` | completes, nothing written, nothing raised |
| `write` of a `String` through `QueryRef<Device>` as `QueryRef<Object?>`, entry absent or present | `TypeError` | `QueryDataTypeError`; no entry made, a cached value kept |
| the same through `QueryEntryRef<Object?>`, and under a nullable type | `TypeError` | `QueryDataTypeError` |
| `update` returning an `int`, entry absent or present; an updater typed `Object? Function(Object?)` | `TypeError` | `QueryDataTypeError`; cached value kept |
| family `updateAll` returning a `String` over two entries; an updater valid for the first entry only | `TypeError` | `QueryDataTypeError`; both entries kept |
| `write` of an `InfiniteData<String, String>` through a widened infinite reference; a widened infinite family's `updateAll` | `TypeError` | `QueryDataTypeError`; cache unchanged |
| the valid value, and `null` under a nullable type, through the widened reference | written | written |

So the covariance check is omitted at `-O3`/`-O4`, a plain delegation then
corrupts the cache (rows 2 and 3 are round 3's finding, reproduced), and
the explicit check through `Object?` fires for the single `write`, the
single `update` and the family bulk update, before anything is written. An
AOT executable of the same program (`dart compile exe`, Dart 3.10.7, run
once by hand, not part of the runner) printed what the VM prints.

**Phase 0 (the input, an addition):** the same widening reaches a family's
*input*. `QueryFamily<String, Device>` held as `QueryFamily<Object?,
Object?>` accepts `family(42)` statically; at `-O3`/`-O4` nothing would
refuse it, `42` would become a key part and reach the fetcher as a `String`.
Options: (a) document it as a limit, since the data type of the entry is
still right; (b) check the input through `Object?` in `call`, as D2 checks
the value. Answer: (b). It is one `is` test per binding, and it keeps "a
wrong input does not reach the fetcher" true where Flutter's web release
runs. It throws `ArgumentError`, not `QueryDataTypeError`: no cache data is
involved. Observed: `TypeError` on the VM and dart2js default,
`ArgumentError` at `-O3`/`-O4`, no entry created, for both family kinds
(`O7-input-1`, `-2`).

What stays a boundary compiles, and the fixtures hold that it does
(`boundary/widened_receiver.dart`): the upcasts above, a raw `QueryRef`
(`strict_raw_type` under this repository's options, clean under the
defaults), a `dynamic` value (`argument_type_not_assignable` under
`strict-casts` only), a `dynamic` receiver (`avoid_dynamic_calls` under
this repository's lints only), a cast, `rawKey` handed to the raw client,
and a per-use `copyWith(queryKey: …)`.

### D3. Identity is structural, and nothing else

**Options:** (a) raw identity from namespace parts, operation name and the
frozen parts of `keyOf(input)` (the input itself as one part when the
family has no `keyOf`), with no metadata; (b) the same identity plus a
client-local registry of definitions that detects duplicate declarations,
ordinary-versus-infinite conflicts and incompatible cache types; (c) identity
that includes the definition instance or closure.

**Answer:** (a). No registry, no metadata, no collision contract beyond what
the cache enforces today.

**Why:** the cache already enforces one exact data type per key: every read
throws `QueryDataTypeError` on another type, and D5 makes the typed writes
exact too. A registry would add a lifetime (remove, clear, dispose, two
clients, hot reload) and lookup cost for a check it cannot complete: two
same-named, same-typed fetchers with different meaning are indistinguishable
to it, and recreated closures are equivalent but not identical. (c) breaks
recreation and hot reload, and hides a collision as a second entry.

What this does not detect, and the guide says so: two definitions of one
key with the *same* cache type and different fetchers (the last `setOptions`
wins, as with raw options today); an ordinary definition typed
`InfiniteData<P, Q>` beside an infinite one of the same page types (the kind
is never checked at runtime, infinite fetching is behaviour on an ordinary
query); and a nested key under a family's prefix with the family's own type
(D7). Hot reload re-runs no top-level `final` initialiser, so a renamed
definition or a changed default needs a hot restart; the data under the old
key stays until collected.

The second of those has a consequence the review of TQ0 made explicit
(S0-3, D5): the ordinary definition typed `InfiniteData<P, Q>` is also
outside the infinite normalisation. It stores the value it is given, under
whatever type arguments that value has. Paged data is declared with an
infinite definition; the plain one typed `InfiniteData` stays allowed, as
any `T` is, and promises nothing about page types (limit 20).

Consequences: explicit stable names; no identity from closure identity,
`runtimeType.toString()`, construction order or a random token. Recreating a
definition with the same schema addresses the same entries, across widget
rebuilds and hot reload, because nothing but the parts is compared. Every
value that changes the result belongs in the identity or in a separate client:
IDs, tenant/account, locale, filters, backend environment. A captured
repository object is a dependency, not an identity component. Switching
accounts must not reuse another account's data.

`keyOf` is optional, and without it the input is the one key part after the
name: `[...namespace, name, input]`, which is what a raw key would hold.
(Until Phase 0 the plan made it a required parameter; the product owner
asked for the default, and the fixtures were to say whether it holds.)
**Options:** (a) required, so every family states its parts; (b) optional,
defaulting to `(input) => [input]`. **Answer:** (b). **Why:** for the
inputs that are the common case the required form is a line that can only
be written one way, `keyOf: (id) => [id]`, and a line that can only be
written one way is where a typo hides. `keyOf` stays for what the default
cannot do: spreading an input over several parts so a prefix selects a
subset, converting an input without value equality, leaving a field out of
the identity.

**Phase 0 (does the default hold):**

- *Inference is unchanged.* A family without type arguments infers
  `QueryFamily<Object?, …>` with a `keyOf` and without one, on all three
  SDKs (`boundary/untyped_definition.dart`); D10's limit and its backstop
  are untouched, and so are the declared-type and typed-closure anchors
  (`positive/typed_inputs.dart`).
- *What the default produces* (observations `K-1` to `K-8`): a `String`
  input gives `[k, byId, d1]`, and its reference is `==` the one of a
  family that spells `keyOf: (id) => [id]`; a value object with `==` gives
  equal references for equal inputs; a `List` input is frozen at binding
  (changing the caller's list afterwards changes nothing, and a binding of
  the changed list is another entry); a `Map` input is equal whatever the
  order of its entries; a record of scalars is equal field by field; `null`
  is the part `null` under a nullable input type.
- *Where `keyOf` is still needed, and it is a documented limit, not a
  check:* a **record holding a collection**. Two equal such inputs give two
  unequal references and two cache entries, because a record compares its
  fields with `==` and a list is `==` only to itself; `QueryKey` freezes
  collections but cannot look inside a record, and its debug assertion does
  not see it (`K-6`: no `keyOf` unequal, `keyOf: (input) => [input.ids]`
  equal). This is the raw key's own documented limit, neither added nor
  removed by the default; the required form had the same trap in
  `keyOf: (input) => [input]`. The guide states the rule where it
  introduces a record input.
- *An input with identity equality* (a class without `==`) is refused by
  `QueryKey`'s existing debug assertion at binding and is silently a new
  entry per binding in a release build, exactly as in a raw key (`K-8`);
  a `keyOf` that converts it is the cure.

Dart cannot inspect record fields generically or prove that captured
dependencies are included, so nothing here is checked beyond what `QueryKey`
checks. Collection key parts are frozen once when binding. Inputs must be
immutable, or the caller takes a snapshot; a retained input must not change
what is fetched after its key was computed. Freezing does not clone a user
model.

Raw entries with the same key and type are shared with typed consumers;
nothing marks them as adopted. Structural identity is not a serialisation
format: persistence, hydration codecs and cross-process migrations are
separate features.

### D4. References and typed keys are values; options are not

**Options:** (a) make `ref.options()` value-equal across rebuilds, by a
per-reference closure or a per-family memo, so the binding sees unchanged
options; (b) give `QueryRef` and `TypedQueryKey` value equality over their
structure, promise nothing about options equality, and keep every call
style's unconditional `setOptions`.

**Answer:** (b). Round 1 chose (a); round 2 showed its premise was wrong.

**Why:** every call style re-applies options on every build by design, and
`shouldFetchOptionally` runs on every `setOptions`; that is #84's rule, which
re-evaluates an `Enabled.when` over outside state. A criterion "no
`setOptions` reaches the observer for a recreated reference" could only be
met by gating `setOptions` on equality, which brings #84 back. The actual
cost of unequal options is one public `QueryObserverOptionsUpdated` cache
event per rebuild. `IsFetchingController` and the hooks' `useIsFetching`
hear every cache event and recount `client.isFetching` (a cache scan) for it,
without rebuilding, and the site's reference snippet filters the event out
because it fires on every reader's build. The site's recommended
options-function pattern pays exactly this today; a definition neither adds
nor removes it. And (a) cannot be delivered:
closures are `==` only to themselves, a closure held by a reference does not
survive `detail('d1')` being called again in the next build, a per-family
memo keyed by input grows by one entry per input ever bound, and a memo
shared across definition instances would hand the second definition the
first one's fetcher, keeping a stale repository alive.

Consequences:

- Every reference's `==` (`QueryRef`, `InfiniteQueryRef`, the definitions
  that are references) is its kind, plain or infinite, and its typed key;
  `TypedQueryKey.==` is the raw key and `TCacheData`. A hook or a user may
  key on a reference. The fetcher is not part of it, so two definitions of
  one operation with different fetchers produce equal references, and the
  observer takes the fetcher it was last handed.
- Namespace and name are in that equality as parts of the raw key and in no
  other way (Phase 0; the plan had listed them as fields of their own).
  Options: (a) compare them separately; (b) only through the raw key.
  Answer: (b). A reference keeps nothing of them but the key they produced
  (D3: no metadata), and (a) would make two references to one cache entry
  of one type unequal because their declarations split the same parts
  differently, a distinction the cache does not make and no operation acts
  on. So a reference bound by a family and a zero-input definition whose
  key and type coincide are equal (`D4-10`).
- `ref.options()` returns fresh options with a fresh bound closure each call,
  as an options function does today; nothing memoises them.
- A changed fetcher or a changed definition default is an options change and
  reaches the observer; nothing suppresses it.
- Acceptance is parity with raw options, because the observer never sees
  the reference and compares resolved values: a rebuild with an equal
  reference starts no fetch and restarts no timer when the resolved policies
  are unchanged, as the same rebuild with inline raw options does, and a
  changed `Enabled.when`, stale time or interval does trigger work, as it
  should. Not "no `setOptions`". What D4 itself decides is tested too: after
  a rebuild with a new definition instance, the next fetch uses the new
  fetcher.
- Until that rebuild or the entry's collection the query keeps the fetcher it
  was last handed, so an invalidation in between runs the old one, as with
  raw options.

Open-4 of round 1 is closed by this decision.

**Phase 0 (the fixture that is not about types):** observations `D4-1` to
`D4-15` in `runtime/observations.dart`, the same on every runtime of every
SDK.

| Observed | Result |
|---|---|
| two references from equal inputs of one family, and of a recreated family | `==`, same `hashCode` (`D4-1`, `D4-2`) |
| references from different inputs; their typed keys | unequal; keys equal for equal inputs only (`D4-3`, `D4-4`) |
| a zero-input definition and its recreation; the infinite twins | `==`, not identical (`D4-5`, `D4-6`) |
| a value object and a record as equal inputs | `==` (`D4-7`) |
| one raw key declared as `Device` and as `Device?` | raw keys equal, typed keys unequal, references unequal (`D4-8`) |
| a plain and an infinite definition of one key and one data type | typed keys equal, references unequal: the kind (`D4-9`) |
| a family's reference and a zero-input definition of one key and type | `==` both ways, same `hashCode` (`D4-10`) |
| references and typed keys as set members and map keys | found (`D4-11`) |
| the options of one reference, asked for twice | not identical, another fetcher closure, the same key (`D4-12`) |
| binding references and asking for options before a client is used | no entry in either client (`D4-13`) |
| one reference written through one client, read through two | the first holds the value, the second nothing; then each its own (`D4-14`, `D4-15`) |

That a reference holds no client is also what the signatures say: every
operation takes the client as its first argument, and a reference has no
other way to reach one.

A reference promises `==` and never identity, in either direction. Two
bindings of one input are two objects on the VM, and dart2js may make them
one: compiled at its default level by Dart 3.10.7,
`identical(detail('d1'), detail('d1'))` is the constant `true` (a probe
run by hand; the VM prints `false`). So no observation asks whether two
bindings are identical, and nothing in the surface may rely on either
answer.

### D5. Declared cache types, absence and null

**Options:** (a) infer the entry type afresh from each written value, as the
raw `setQueryData` does for an entry it creates; (b) every typed write or seed
uses the definition's declared type.

**Answer:** (b).

**Why:** the raw path infers narrowly because it has no other source; a
definition has one. A sealed base type receiving a concrete variant,
`List<Device>` receiving a narrow literal and `Device?` receiving a `Device`
must create an entry of the declared type, or the next typed read throws.

- Every typed read uses the exact declared type.
- **Every typed write and update has one shape, single and bulk alike
  (D7):** check, then write.
  1. The existing entry must be absent or of exactly `TCacheData`, else
     `QueryDataTypeError` before any write. The public
     `queryCache.get<TCacheData>` is exactly that check; `peek` is not
     needed. Without it a `ref.write` would land in a wider raw entry
     (`Device` into `Device?`) and the reference's own next `read` would
     throw (round 2).
  2. The value, and every updater's result, is checked through `Object?`
     (D2), so a widened receiver fails at dart2js `-O4` as well (round 3:
     handing an unchecked updater to the raw path stored `42` in a
     `Query<Device>` at `-O4`).
  3. An infinite value is normalised (below).
  4. An entry the write creates is built with the reference's own options,
     so the definition's `gcTime` and `structuralSharing` apply from the
     first write; the raw `setQueryData` builds a bare entry. An existing
     entry is written through the same `Query.setData(manual: true)` the raw
     path uses, so sharing and timestamps behave identically.
  The raw `setQueryData` and `updateQueriesData` keep their leniency.
- `write` and `update` take the raw path's `updatedAt`, which a rollback
  needs.
- **Infinite normalisation** rebuilds an `InfiniteData` whose runtime type is
  narrower than `InfiniteData<TPageData, TPageParam>` from its pages and
  params, as `List<TPageData>.unmodifiable` and `List<TPageParam>.unmodifiable`
  (the constructor does not copy), and skips the rebuild when the runtime
  type is already exact. It loses nothing: `InfiniteData` is `final` and
  holds only the two lists, and since structural sharing returns the incoming
  value when runtime types differ, normalising restores page sharing rather
  than defeating it. It applies to everything the definition writes or
  produces: `write`, every updater result, single and bulk, and the
  definition's own `structuralSharing` and `initialData`, which it wraps so
  that the value finally committed is normalised (round 3: a custom sharing
  callback returning the narrower value otherwise undid it). A narrower
  value supplied through a per-use `copyWith` is outside the guarantee and
  documented.
- `ref.read(client)` returns `TCacheData?` for compatibility and cannot
  distinguish absence from a cached null. `ref.state(client)` exposes the
  existing `QueryState` with `hasData` for that distinction.
- Returning `null` from `update` skips the write, as `updateQueryData` does.
  `ref.write(client, null)` on a nullable definition stores null under the
  declared nullable type; it does not infer `Null`.
- A definition with `TCacheData == Null` is rejected at construction in debug
  builds and documented as unsupported. The raw client's bare-`null` no-op is
  unchanged.
- A rollback recipe distinguishes an absent entry, an entry without data and a
  stored null, and restores absence by exact removal.
- Writes keep structural sharing, timestamps and synchronous notification.
  Runtime mismatches use the existing diagnostic and name key, expected type
  and actual type.
- `write` returns `TCacheData`, what the cache holds after sharing, and
  `update` returns `TCacheData?`, as the raw calls they stand for do
  (Phase 0; the plan had not said).

**Phase 0 (what the prototype does, run):** observations `D5-1` to `D5-17`
and `D5-infinite-1` to `-6`. Where a line differs between runtimes the
table says so; the rest is the same on all five runtimes of all three SDKs.

| Observed | Result |
|---|---|
| first typed write of a `Temperature` under `QueryFamily<String, Reading>` (a sealed base) | a `Query<Reading>` (`D5-1`) |
| the raw `setQueryData` of the same value with no type argument, the control | a `Query<Temperature>`, which the typed read would refuse (`D5-2`) |
| a `List<Thermostat>` under `QueryDefinition<List<Device>>`; a `Device` under `Device?` | `Query<List<Device>>`, `Query<Device?>` (`D5-3`, `D5-4`) |
| `write(null)` on a nullable definition | the entry holds `null`; `read` is `null`, `state.hasData` is `true` (`D5-5`) |
| a reference nothing was written for | no entry; `read` and `state` are `null` (`D5-6`) |
| `update` returning `null` with no entry | returns `null`, creates no entry (`D5-7`) |
| `update` returning a value with no entry; over a cached value; `write` with `updatedAt` | creates the entry; sees the cached value; `dataUpdatedAt` is the given time (`D5-8` to `D5-10`) |
| typed `write`, `update` and `read` over a raw `Query<Device?>` | `QueryDataTypeError`, the entry unchanged (`D5-11`, `D5-12`) |
| the raw `setQueryData<Device>` over the same entry | writes: the leniency is the raw path's and stays (`D5-13`) |
| typed write of a `Device` over a raw `Query<Thermostat>` | `QueryDataTypeError` (`D5-14`) |
| `gcTime` of an entry a typed write created, the definition configured with `GcTime.never`; of one a raw write created | the definition's; the default (`D5-15`) |
| declaring `QueryDefinition<Null>` | `AssertionError` with assertions on, constructed without (`D5-17`): debug-only, as the decision says |
| an `InfiniteData<List<Thermostat>, int>` written under `InfiniteQueryDefinition<List<Device>, int>` | stored as `InfiniteData<List<Device>, int>`, a rebuilt value with the same pages (`D5-infinite-1`) |
| adding a page of plain `Device`s to what is cached; to the narrower value itself | works; `TypeError` on the VM and dart2js default, unchecked at `-O3`/`-O4` (`D5-infinite-2`, `-3`), which is what the normalisation is for |
| an exact `InfiniteData` | stored as given, the same instance (`D5-infinite-4`) |
| an updater returning `InfiniteData<List<Never>, int>`, single and through the family | stored under the declared page types (`D5-infinite-5`, `-6`) |

Two things the prototype does not do, so Phase 0 proves neither. It does
not wrap the definition's own `structuralSharing` and `initialData` for the
infinite normalisation (round 3's A-1): that needs the core's internals and
tests of its own, and it is Phase 2's. And it builds the entry through the
public `QueryCache.build` on every write, where the module inside the core
builds it only when the entry is absent and writes through
`Query.setData(manual: true)` directly; the observable result is the one
above.

**Phase 1 (TQ1) does both**, and settles what the shape above left open.

- *One write path.* `write`, `update` and each write of `updateAll` end in
  one private function: the entry `queryCache.get<T>` found, or one built
  with the reference's own defaulted options, then
  `Query.setData(manual: true)`.
- *`update` looks the entry up twice.* Once to hand the updater what is
  cached, once after it returned. An updater is user code and may remove
  the entry or write the key itself. Options: (a) write into the `Query`
  found first, which after a `remove` is an object no longer in the cache,
  so the write is lost; (b) look it up again with the exact check. Answer:
  (b): a removed entry is made again with the definition's options, and a
  wider entry put there in the meantime is refused like any other.
- *The error's fields.* `QueryDataTypeError.expected` is the declared type.
  `actual` is the entry's `dataType` when the entry is the mismatch, and
  the value's `runtimeType` when the value is, which is what the client's
  own value check reports. The message says "holds"; for a value that
  reads loosely, and it is reachable only where the VM's own `TypeError`
  is not (dart2js `-O3`/`-O4`). Left as it is: the raw API is unchanged.
- *What is wrapped.* What `configure` returns passes through one function
  that re-pins key and paging functions and holds `structuralSharing` and
  `initialData` to the declared page types. A custom sharing function is
  wrapped. `null` (the default sharing) and the `noStructuralSharing()`
  instance are left as they are: the default cannot return a value of
  other type arguments than the one it was given, and the opt-out is
  recognised by identity, which a wrapper would break. An
  `InitialData.value` that is already exact stays the same instance; a
  narrower one is rebuilt once per `options()` call; an
  `InitialData.compute` is wrapped and a `null` seed passes through.
- *Outside it, each a test:* a per-use `copyWith(structuralSharing: …)` or
  `copyWith(initialData: …)` (limit 15), and a `structuralSharing` that
  arrives through the client's or a key's defaults, whose callbacks are
  typed `Object?` and not the definition's to wrap.
- *`update` on a missing entry passes `null`*, also when the definition's
  `initialData` would seed the entry it then creates. The raw call does
  the same, and the entry is seeded and then written.

**After the review of TQ0 (S0-3, TQ2): the normalisation is the infinite
definition's, and only its.** The decision above reads "typed `write`,
`update` and `updateAll` create or accept only an entry whose runtime type
argument is exactly `TCacheData`", and for an infinite definition it adds
the rebuilt value. The review asked what a plain
`QueryDefinition<InfiniteData<List<Device>, int>>` does with an
`InfiniteData<List<Thermostat>, int>`. Reproduced: the *entry* is exact
(`Query<InfiniteData<List<Device>, int>>`), the *value* in it keeps its own
type arguments, the next `copyWith` typed for the entry throws a
`TypeError` on the VM and dart2js default and completes at `-O3`/`-O4`,
and a read through an infinite definition on the same key hands the
narrower value back (`D5-infinite-7`, `-8`, and a test with the infinite
definition's write beside it as the control).

Options: (a) normalise in the plain definition too. It has one type
argument, `T`, and Dart cannot open `InfiniteData<P, Q>` out of a `T` to
name the page types the rebuilt value needs; a runtime-type comparison can
tell that the value is not exactly `T` and cannot build the exact one. (b)
Refuse the declaration: a debug assertion that `T` is not an
`InfiniteData`. It contradicts D3, which names that declaration among the
things nothing detects, and it would refuse the reads of a paged entry
some applications do through a plain reference. (c) Refuse the write: an
exactness check on the value for every plain write of an `InfiniteData`.
That is a rule for one data class inside the generic write path, and a
value of narrower type arguments is what every other generic class
(`List<Thermostat>` under `List<Device>`) is stored as without complaint.
(d) Narrow the promise: the entry is exact for every definition; the
written *value* is held to the declared page types by an infinite
definition only. Answer: (d), the product owner's. (b) and (c) are cheap
and are not built; they are named here in case the limit turns out to
bite.

### D6. Options, defaults and execution are reused, not rebuilt

**Options:** (a) a second options type for definitions; (b) `ref.options()`
returns the existing `QueryObserverOptions<TCacheData>`, selection goes
through the existing required `withSelect`, and `fetch` delegates to
`client.query`.

**Answer:** (b).

**Why:** the facade must not duplicate fetching, state, retries or
subscriptions, and ADR-0001's two shapes already anchor the output type.

- Selection yields `QuerySelectOptions<TCacheData, TSelected>` and never
  changes the typed key or cached value. No second optional output-type
  parameter.
- Overrides and definition defaults have one mechanism, and it is the
  existing one: the typed `copyWith` of the returned options. Each definition
  takes an optional `configure` callback typed for its kind and applied
  inside `options()`, which is where an input-dependent stale time or a
  per-input placeholder goes:
  - plain family: `QueryObserverOptions<T> Function(QueryObserverOptions<T>
    base, TInput input)`;
  - plain definition: the same without `input`;
  - infinite family and definition: the same over
    `InfiniteQueryObserverOptions<TPageData, TPageParam>`.
  A consumer overrides per use with `ref.options().copyWith(...)`. After
  `configure` the definition re-pins its key and fetcher with one more
  `copyWith`, so the definition path cannot change identity; a per-use
  `copyWith` still can, as a documented exit. A per-use `copyWith` cannot
  unset a definition default (null means "keep"), and the guide says so.
- **The cost, stated:** the plain side adds no field list. The infinite side
  does: `pageFn`, `initialPageParam` and `getNextPageParam` are required
  constructor parameters of the infinite options and must exist before
  `configure` receives a base, and they are often input-dependent (the
  max-pages screen starts from a cursor). So an infinite definition takes
  `pageFn`, `initialPageParam`, `getNextPageParam` and
  `getPreviousPageParam` as `(input, …)` functions of its own. That is a
  tenth place in CLAUDE.md's nine, for infinite-only fields; it is accepted
  because those four are the definition's identity-adjacent behaviour, not
  tunables, and a test fails if one is not passed through.
- Options that need the client (the task manager seeds a detail's
  `initialData` from the list caches and dates it from their state) stay
  with the consumer, who has a client: `QueryClientProvider.of(context)` or
  `useQueryClient()`, then `ref.options().copyWith(initialData: ...,
  initialDataUpdatedAt: ...)`. A definition holds no client (D1), and
  `InitialData.compute` receives none. The task manager therefore keeps a
  small `taskQuery(client, id)` wrapper shared by its two consumers; the
  migration example says so.
- Merge precedence: client defaults, matching key defaults in their existing
  order, definition options, per-use overrides. Null means unset. A
  definition's fetcher takes precedence over a generic default fetch function.
- A key-only definition (no fetcher; pre-seeded data or a default fetcher)
  names its output type explicitly. The untyped transport of a default
  fetcher is not statically validated by a typed key.
- `fetch` delegates to `client.query` with its freshness, deduplication,
  imperative retry defaults and `revalidateIfStale`; it does not promise a new
  request. Cancel, remove, reset, refetch and invalidate call the exact client
  operations.

**Phase 0:**

- `queryFn` is an optional parameter of `QueryFamily` and `QueryDefinition`:
  that is the key-only definition above. Its types then have no source, so
  they are written out; left out, the declaration infers `dynamic`, which
  `strict-inference` reports and the debug backstop refuses (D10). The
  infinite definitions keep `pageFn` required, as the infinite options do.
- `fetch(client, {revalidateIfStale = false})` on both reference kinds is
  `client.query` and `client.infiniteQuery` with their parameter and its
  default. Run: a family's reference, a zero-input definition, an infinite
  definition and an infinite family's reference each fetch through their
  definition's function and leave an entry of the declared type, and an
  observer made from `options()` sees it (`F-1` to `F-5`).
- The re-pin holds: a `configure` that returns options with another key and
  another fetcher produces options with the definition's key (`D5-16`).
- The signatures spell their function types out and add no public typedef.
  Options: (a) names such as `QueryFamilyFn<TInput, T>`; (b) inline types.
  Answer: (b). Nobody writes these types down (the closures are inferred
  from the constructor), so a name would be public surface with no user.
- No `isFetching` on a target: `client.isFetching(filters: x.filters())` is
  one call, and `filters()` (D7) is what every count and listener takes.

**Phase 1 (TQ1):** the re-pin is a `copyWith` over what `configure`
returned, and `copyWith` reads `null` as "keep". Two edges follow, both
tested.

- *`configure` may supply what the definition lacks*: a key-only
  definition's fetch function, an infinite definition's missing
  `getPreviousPageParam`. The definition has nothing there to pin, and the
  alternative is rebuilding the options field by field.
- *A first page param of `null`* (a cursor that starts at `null`) cannot
  be put back by a `copyWith`. Options: (a) let `configure`'s value stand,
  which silently breaks "the paging functions are the definition's"; (b)
  an assertion, absent from a release build; (c) rebuild the options field
  by field, one more place every option has to be written; (d) throw a
  `StateError` when the options are made, naming the key. Answer: (d). It
  is one comparison, the message says where the value belongs, and a
  `configure` that leaves the first page param alone is unaffected
  (limit 17).

**After the review of TQ0 (TQ2): the rule, and what `configure` returns.**

- *The rule, stated (S0-4).* **The definition pins what it declares; what
  it leaves unset, `configure` may set.** The review read the first edge
  above as a defect: a definition declared without a fetch function, or
  without a `getPreviousPageParam`, does not get its `null` back after a
  `configure` that sets one. Reproduced, and kept (the product owner's
  decision): the declared `null` means "not declared", and a definition
  has no way to say "declared absent" that a `copyWith` could restore.
  Both halves are tests on both kinds, and the constructors' dartdoc
  states the rule in these words.
- *`configure` returns options of the definition's own type (S0-2).* Its
  return type is `QueryObserverOptions<T>`, and options are covariant in
  their data type, so a `configure` on a `QueryDefinition<num>` may return
  a `QueryObserverOptions<int>`. Reproduced: on the VM the re-pin's
  `copyWith` then failed with a `TypeError` about the fetch function's
  type, which names neither the definition nor `configure`; at dart2js
  `-O4` nothing failed, `options()` returned the narrower options and a
  fetch stored `1.5` through them. Options: (a) a cast, which `-O4`
  compiles out; (b) an `is` test, which a narrower type passes; (c) rebuild
  the options field by field under the declared type, the field list D6
  refused; (d) compare `runtimeType` with the declared options type before
  any `copyWith` and throw. Answer: (d). Both options classes are `final`,
  so the runtime type of a value is exactly its type arguments' doing, and
  a `Type` comparison is not something an optimisation level removes: it
  is the technique the infinite normalisation already rests on. The error
  is a `StateError` naming the key and both types, the kind the `null`
  first page param already throws when the options are made;
  `QueryDataTypeError` is about what an entry holds, and `ArgumentError`
  about an argument of the call that throws. It is thrown by `options()`
  and by everything that makes options (`fetch`, a write that creates the
  entry), on a plain definition and family and on both infinite kinds,
  before a `copyWith` and before the `null`-param check. Run on all five
  runtimes (`D6-1` to `D6-5`): `StateError` each time, no entry after a
  write through such a definition, and options of the declared type that
  `configure` builds anew instead of copying pass (limit 19).

### D7. Exact for a reference, prefix for a family or namespace; bulk keeps the cache's check

**Options:** (a) typed family bulk reads and updates need a membership
mechanism that proves every entry under the prefix belongs to the family;
(b) a family's bulk operation is the prefix `[...namespace, name]`, and the
typed path checks `dataType == TCacheData` exactly on every matched entry
before reading or writing anything, then delegates; (c) no typed bulk
operations.

**Answer:** (b).

**Why:** (a) is the registry D3 declined, under another name. The write
side follows D5's one shape: preflight every matched entry with the exact
check, then hand the raw bulk update an updater wrapped with D2's `Object?`
check on its result and the infinite normalisation. The wrapping matters:
once every entry is exactly `TCacheData`, the raw `_holds` passes without
looking at the value, so at dart2js `-O4` an unwrapped updater returning a
`String` through a widened family wrote nothing and raised nothing (round 3).
(b) is what `getQueriesData` does today; `updateQueriesData` is lenient (an entry of
another type with no data, or a wider type, passes), so the typed family
adds the exact preflight for writes rather than inheriting it. Round 1 said
the raw bulk API already did this; round 2 reproduced that it does not. (c)
gives up the one bulk case users ask for (patch every cached detail after a
list write).

- Reference lifecycle operations are exact. Family operations select every
  input of the family. Namespace operations select the structural prefix,
  descendants included. Active/inactive filters, refetch type and cancellation
  pass through a typed filter adapter.
- Keys nested under a family's prefix (`['devices', 'detail', id, 'history']`)
  are not supported and are documented as such; a nested operation gets its
  own name. One of another type makes the bulk call throw; one of the same
  type is updated as a member and is not detectable. An authoring rule, not
  a check.
- Preparation order is the raw updater's: every updater runs and its result
  is validated before the first write. An updater that throws leaves the batch
  unwritten. Application callbacks that write re-entrantly are not rolled
  back; this is not a transaction.
- A namespace exposes invalidation and other non-data operations only.

**Phase 0 (names, shapes, and what ran):**

- The bulk operations are `family.readAll(client)` and
  `family.updateAll(client, updater, {updatedAt})`, on both family kinds,
  and both return `List<(TypedQueryKey<T>, T?)>`: the raw calls' list of
  key and value with the key typed, so a result can be read again without
  leaving the surface. Options for the names: `read` / `update` as on a
  reference (a family would then have a `read` that returns a list, and
  "a family has no `read`" would stop being a compile error for the
  commonest slip, a forgotten input); `readAll` / `updateAll`. Answer: the
  latter.
- The typed filter adapter is `QueryTarget.filters({type, stale,
  fetchStatus, status, predicate})` (D1): the key and its exactness are the
  target's, the rest narrows it, and the result is an ordinary
  `QueryFilters` for the client, `IsFetchingController`, `QueryListener`
  and the hooks' counts. The lifecycle operations take the parameters of
  the client calls they are (`invalidate(client, {refetchType,
  cancelRefetch})`, `cancel(client, {revert, silent})`, and so on).
- Run (`D7-1` to `D7-13`, the same on every runtime). With two details, a
  list and a lookup cached, `updateAll` returns and writes the two details
  and leaves the list and the lookup alone; the family's filters select 2
  entries, the namespace's 4, one reference's 1. With a key nested under
  one detail added, `invalidate` marks 1 of 5 entries on that detail's
  reference (not the nested one), 3 of 5 on the family (the nested one,
  not the list) and 5 of 5 on the namespace; `remove` on the family leaves
  the list and the lookup. A `Query<String>` without data under the
  prefix, and a raw `Query<Device?>` under it, each make `updateAll` throw
  `QueryDataTypeError` with every entry kept (`readAll` throws over the
  first as well), where the raw `updateQueriesData<Device>` completes and
  writes, the wider entry included. An updater that throws for the second
  entry leaves the first unwritten.
- The nested key in that run is invalidated and removed with the family,
  as the decision says: an authoring rule, not a check.

**Phase 1 (TQ1): the typed bulk update is its own pass, not the raw one
with a wrapped updater.** The answer above said "then delegates", and
Phase 1's list said to reuse the raw update's two passes. Reading
`updateQueriesData` against the exact shape showed three places where
delegating would let the leniency back in: its first pass accepts an entry
of another type that holds no data, its value check passes on type alone
once the entry is exact, and its second pass writes through the lenient
`setQueryData` into whatever entry the key has by then. A wrapped updater
also is not told which key it is called for, so the error could not name
it. Options: (a) delegate and accept the three; (b) add a key to the raw
updater's signature, which changes the raw API; (c) run the same order in
the typed library with the exact steps. Answer: (c). The order is the raw
one: every entry checked, every held value captured, every updater run,
every result checked and normalised, and only then the writes, inside one
`NotifyManager.batch`.

What that means for an updater that itself touches the cache, each line a
test:

- Every updater sees the data captured before the first one ran.
- An entry an updater removed is written again, **bare**: with the key
  alone, as the raw path does it. The family could build it with the
  input's options only by turning a key back into an input, which a
  `keyOf` does not allow.
- An entry an updater added is not part of the call.
- An entry swapped for one of a wider type makes its own write throw, and
  the writes made before it stay. The raw path writes into the wider
  entry. This is limit 16. (Narrowed in TQ2, below.)
- A cache listener and an observer hear each write as it is made; only a
  subscriber that schedules through the notify manager waits for the end
  of the batch. The raw call behaves the same, and the test compares the
  two event lists.

**TQ2: the entries are looked at once more before the first write.**
TQ1 left the swapped entry as an open point: `updateAll`'s dartdoc says
that nothing is written unless everything can be, and an updater that
replaced a *later* entry with one of another type broke that, because the
replacement was found at that entry's write, after the earlier ones.
Options: (a) leave it, a documented limit; (b) look every entry that is
about to be written up again, with the exact check, after the last updater
returned and before the batch; (c) write into the `Query` objects captured
in the first pass, which loses the write to a removed entry (D5's reason
for the second lookup). Answer: (b). It is one cache lookup per written
entry, it changes no result for a caller whose updaters leave the cache
alone, and it makes the sentence true for everything an updater can do:
the swap now throws `QueryDataTypeError` with **no** entry written. What
remains, and limit 16 now says only this: a cache listener or an observer
that reacts to one of the writes by replacing a later entry. That happens
inside the batch, between two writes, and the only way to exclude it is to
write without notifying, which is a different operation. Both are tests,
the listener's with the raw call beside it.

### D8. Infinite queries keep all three types

**Options:** (a) one `InfiniteQueryFamily<TInput, TPageData, TPageParam>`
whose cache type is `InfiniteData<TPageData, TPageParam>`; (b) a family per
page.

**Answer:** (a).

**Why:** the logical input identifies the entry; page parameters live inside
`InfiniteData`, as they do upstream and in the existing observer.

An infinite reference is an `InfiniteQueryRef<TPageData, TPageParam>`
(D1), whose `options()` returns `InfiniteQueryObserverOptions<TPageData,
TPageParam>`, which is what the infinite consumers take. A zero-input
`InfiniteQueryDefinition<TPageData, TPageParam>` exists beside the family;
its page functions take no input. The page function receives the typed
input plus the existing typed page context. Initial/next/previous page parameters, max pages, refetch direction,
retry, cancellation and observer paging actions are the existing ones.
Selected infinite options change the observer output only. Wrong page data,
wrong page parameters and wrongly typed `InfiniteData` writes are negative
analyzer cases. The raw path's refusal to widen `InfiniteData` on write
stays, and first writes with narrow literals are tested.

**Phase 0:** `positive/infinite.dart` holds the inferred types: the
reference, its options, an `InfiniteQueryObserver` of all three types from
the options alone, `read`, `fetch`, a `write` whose literal takes its type
arguments from the receiver, the selected shape, the family's `readAll`
and `updateAll`, and the declared types inside every callback of both
infinite definitions. `negative/definitions.dart` holds the refused
declarations (a page function returning other page data or using its
param as another type, an initial or a next page param of another type,
an infinite family's function that leaves out the input, a missing
required paging function) and `negative/surface_limits.dart` the refused
uses (an `InfiniteData` of other page data or other params written, a
list of pages written or returned by an updater, a wrong element in a
literal page, a read assigned to other types, a plain reference where an
infinite one is expected and the reverse, plain options handed to an
infinite observer). A zero-input infinite definition without type
arguments infers both types exactly, from `initialPageParam` and the page
function's return; an infinite family without them has D10's `Object?`
input.

### D9. Every consumer, no new state layer

The options a reference produces work with controllers, builders, mixins,
`context.query`, selectors, listeners and hooks without new ownership rules.
The four Flutter call styles stay equally documented. Inferred callback and
result types are verified at each public entry point, hook prefetch and
infinite helpers included. Heterogeneous composition keeps the existing typed
record combination (`combine`, `combineWith`). A list of references of two
data types handed to `QueriesObserver` or `useQueries` compiles, as a list of
raw options does, and infers `Object`, creating `Object` entries that every
exact typed read then rejects; that is outside the guarantee, the docs say so
(the hook's already do), and a compiling boundary fixture with a runtime
assertion pins it, apart from the analyzer-negative fixtures. Namespace and family filters also feed `IsFetchingController`,
`QueryListener` and the hooks' counts.

**Phase 0:** `boundary/mixed_list.dart` compiles on all three SDKs under
both option sets, and pins what is inferred: `[device.options(),
list.options()]` is a `List<QueryObserverOptions<Object>>` and the observer
over it a `QueriesObserver<Object, Object>`; two references of one data
type give `QueriesObserver<Device, Device>`. Run (`D9-1` to `D9-3`): the
mixed observer creates a `Query<Object>` under each key, after which the
references' own `read` and `write` throw `QueryDataTypeError`; the
same-type list creates a `Query<Device>` the reference reads. Only the
core's `QueriesObserver` ran here; the binding's and the hooks' lists are
Phase 3's.

One thing the fixture found that the plan had not asked: a list of the
*references* themselves, `[device, list]`, is not a
`List<QueryRef<Object>>` but a `List<QueryTarget>` (D1), because the
nearest common supertype of the two is the one without a data type. Its
elements can be invalidated and cannot be read or written
(`negative/surface_limits.dart`).

**Corrected after the review of TQ0 (S0-1, TQ2).** Phase 0 concluded from
that one case that "the hole is the options list and nothing wider". It is
wider. `[device, list]` is a family's reference and a definition: two
classes, whose nearest common supertype is the target. Two references of
**one** class meet at that class, at the common supertype of their data:

| Literal | Inferred (Dart 3.6, 3.10, 3.13) |
|---|---|
| `[ints('a'), strings('a')]`, two families' references | `List<QueryRef<Object>>` |
| `[device, lookup]`, data `Device` and `Device?` | `List<QueryRef<Device?>>` |
| two `QueryDefinition`s | `List<QueryDefinition<Object>>` |
| two infinite families' references | `List<InfiniteQueryRef<List<Object>, Object>>` |
| two families; two typed keys | `List<QueryFamily<String, Object>>`; `List<TypedQueryKey<Object>>` |
| a set, a map, a conditional expression of the first pair | `Set<QueryRef<Object>>`, `Map<String, QueryRef<Object>>`, `QueryRef<Object>` |
| a family's reference and a definition of another type; a plain and an infinite reference | `List<QueryTarget>` |

So: **a collection literal of references of different data types infers a
common supertype, `QueryRef<Object>` or `QueryEntryRef<Object>`; writes
through its elements are checked at runtime only; declare a heterogeneous
lifecycle list as `<QueryTarget>[…]`.** (`QueryEntryRef<Object>` is what
elements already typed as `QueryEntryRef` meet at; no literal of the
concrete kinds measured above infers it.) This is D2's widening, reached
without an upcast in the source, and it ends where D2's does: run on all
five runtimes (`D9-4` to `D9-11`), a `Temperature` written or returned by
an updater through the device's element, `null` through a non-nullable
one, an `int` through a list definition's, an `InfiniteData<List<Object>,
Object>` through an infinite one and a wrong `updateAll` result through a
family's are each refused before anything is written, by `TypeError` on
the VM and dart2js default and by `QueryDataTypeError` at `-O3`/`-O4`, and
no entry is created; the right value through each element is written.
What is lost is the compile-time refusal, not the cache's integrity.

Options: (a) make the two-class result hold for one class too, which
needs the references to stop sharing a generic class, that is `QueryRef`
invariant in `T`, and Dart has no declaration-site variance; (b) a lint;
(c) narrow the claim, pin the inference in a boundary fixture, give the
declared-target spelling a positive and a negative fixture, and say it in
the dartdoc where the limits are listed. Answer: (c), the product owner's.
`boundary/mixed_list.dart` pins every row above,
`positive/target_list.dart` shows `<QueryTarget>[…]` taking every kind of
target and every lifecycle operation, and `negative/surface_limits.dart`
refuses `write`, `update`, `read`, `state` and `key` on its elements.

Mutation definitions are outside this feature. Existing mutation callbacks
use typed references for cancellation, optimistic writes, snapshots, rollback,
server-response writes and family invalidation. Definitions do not solve
concurrent optimistic ordering or validate backend JSON; the example says so.

### D10. Explicit type arguments on a definition are a documented limit

**Options:** (a) rely on inference of `TInput` and `TCacheData` from the
`keyOf` and `queryFn` closures; (b) require explicit type arguments on
`QueryFamily` and `QueryDefinition` and say so.

**Answer:** (b).

**Why:** `QueryFamily(keyOf: (id) => [id], queryFn: (id, c) async =>
Device())` has no source for `TInput` but the closures' own parameters, which
take their type from the context; the result is `QueryFamily<Object?,
Device>`, not `dynamic`, and `strict-inference` reports nothing (round 2
measured this on Dart 3.6 language level, 3.11 and 3.13). `TCacheData` is
anchored by the fetcher's return. Explicit type arguments, a declared field
type or a typed closure parameter each anchor `TInput`; a `TInput` of
`Object?` then mostly fails downstream when the input meets a typed
repository parameter, but `keyOf` alone compiles. So: the examples write the
arguments, the guide says why, and every definition constructor
(`QueryFamily`, `QueryDefinition`, `InfiniteQueryFamily`,
`InfiniteQueryDefinition`) carries the binding's existing debug backstop,
`<Object?>[] is! List<T>`, which refuses `dynamic`, `Object?` and `void`
alike.
- On the output types (`TCacheData`, `TPageData`, `TPageParam`) it is
  ADR-0001's backstop and has no false refusal.
- On `TInput` it is new, and it refuses two legitimate declarations: `void`,
  which the zero-input definitions make unnecessary, and a deliberately
  top-typed nullable input. Accepted: the forgotten type argument it catches
  is the common case, the deliberate `Object?` input is rare, and its escape
  is `Object` or a sealed or nullable concrete type (`Object` and `String?`
  pass). The guide names the escape. Round 1 cited
[the inference research](../research/dynamic-inference-guards.md) here; that
research is about an optional output slot and does not establish this case.

**Phase 0 (Open-1, the record):** what a declaration without type arguments
infers, pinned by `expectStaticType` in `boundary/untyped_definition.dart`,
`positive/typed_inputs.dart`, `positive/infinite.dart` and
`positive/declaration_forms.dart`. Dart 3.6.2 (language 3.6), 3.10.7
(language 3.6 and 3.10) and 3.13.4 (language 3.6 and 3.13) infer the same
in every row.

| Declaration, no type arguments | Inferred | Analyzer, defaults | Analyzer, this repository's options |
|---|---|---|---|
| `QueryFamily(queryFn: (id, context) => …)`, the input unused | `QueryFamily<Object?, List<Device>>` | clean | clean |
| the same with `keyOf: (id) => [id]` | the same | clean | clean |
| `InfiniteQueryFamily(pageFn: (id, context) => …, …)` | `InfiniteQueryFamily<Object?, List<Device>, int>` | clean | clean |
| a key-only `QueryFamily(namespace: …, name: …)` | `QueryFamily<dynamic, dynamic>` | clean | `inference_failure_on_instance_creation` |
| a key-only `QueryDefinition(namespace: …, name: …)` | `QueryDefinition<dynamic>` | clean | `inference_failure_on_instance_creation` |
| `QueryDefinition(queryFn: (context) => …)` | `QueryDefinition<List<Device>>`, exact | clean | clean |
| `InfiniteQueryDefinition(pageFn: …, initialPageParam: 0, …)` | `InfiniteQueryDefinition<List<Device>, int>`, exact | clean | clean |
| `QueryFamily(queryFn: (String id, QueryFunctionContext context) => …)` | `QueryFamily<String, Device>`, exact | clean | clean |
| `final QueryFamily<String, Device> x = QueryFamily(…)` | exact | clean | clean |

So the decision is narrower than its heading, and better: **the limit is a
family's input slot.** A zero-input definition with a fetcher has no slot
that lacks a source, and it infers exactly; the examples may leave its type
arguments out, and the guide says a family's are written. The output types
are exact in every row that has a fetcher.

What an untyped family costs, measured:

- The ordinary one does not compile. Its fetcher hands the input to a typed
  parameter, and an `Object?` is not a `String`:
  `argument_type_not_assignable` inside the declaration, at the use of the
  input; using a member of the input is `unchecked_use_of_nullable_value`
  (it is `Object?`, not `dynamic`); assigning it where the typed family is
  expected is `invalid_assignment` (`negative/untyped_definition.dart`,
  five cases, an infinite family among them).
- The one that never looks at its input compiles, under the strict options
  as well, and then accepts `42`, `null` and a `Device` as inputs
  (`boundary/untyped_definition.dart`). That is the documented limit.
- The backstop is a debug assertion and nothing more (`D10-1` to `D10-8`).
  With assertions on, the untyped family, the key-only `dynamic` one,
  `QueryFamily<void, …>`, `QueryDefinition<Object?>`, the untyped infinite
  family and `InfiniteQueryDefinition` with a top page type or page-param
  type each throw `AssertionError` at construction, and
  `QueryFamily<Object, …>`, `QueryFamily<String?, …>` and
  `QueryDefinition<Object>` pass. Without assertions (the VM without them,
  dart2js at every level) every one of them is constructed. No compile
  error was promised here, and none is claimed: the guarantee is the
  explicit form, the limit is stated where definitions are introduced, and
  the assertion's message names the cure.

### D11. Showcase and versions

A new or changed showcase screen for the infinite flow follows the showcase's
five-artefact catalogue rule (`examples/showcase/README.md`, "The
catalogue"), and `catalogue_test.dart` must hold.

All three packages ship, because Phase 3 migrates a hook consumer and
Phase 4 updates every README, and the hooks README is fence-tested. Round 2's
"only if" was met by the plan itself.

| Package | Version | Why |
|---|---|---|
| core | `1.1.0` | additive API |
| binding | `1.2.0`, `query_kit: ^1.1.0` | it re-exports the whole core, so raising the floor makes the new API reachable through the binding's import: a feature, hence a minor under "Semantic versioning holds" |
| hooks | `0.1.3`, `query_kit_flutter: ^1.2.0` | it re-exports the binding; in 0.x a minor is the breaking bump (`docs/releasing.md`), so an addition is a patch |

Phase 0 corrected the hooks row: the plan said `0.1.1`, and `0.1.1` and
`0.1.2` have been published since it was written (tags
`query_kit_hooks-v0.1.1` and `-v0.1.2`; the pubspec is at `0.1.2`). Core
is at `1.0.4` and the binding at `1.1.4`, so `1.1.0` and `1.2.0` are still
the next minors. The numbers are the next free ones when Phase 4 bumps,
and are read off the pubspecs again then.

The shipped examples name the first release that has what they use (a
constraint names the oldest version that works, `docs/releasing.md`): the
binding's example `query_kit_flutter: ^1.2.0`, the hooks example
`query_kit_hooks: ^0.1.3`. Each is resolved without its workspace override
and at its lowest allowed dependency set (`pub downgrade`) before tagging,
because resolving the latest versions would not notice a floor that is too
low. Publish in dependency order: core, binding, hooks.

### D12. One declaration form: the constructors

Added in Phase 0. The product owner asked whether a declaration should be
spelled as a constructor that names its namespace
(`QueryFamily<String, Device>(namespace: devices, name: 'detail', …)`) or
as a factory method on the namespace
(`devices.family<String, Device>('detail', …)`), and for one documented
form.

**Options:** (a) constructors only; (b) factory methods only, the
constructors private; (c) both.

**Answer:** (a).

**Why:** the two were written side by side for all four definitions
(`support/namespace_factories.dart`, `positive/declaration_forms.dart`) and
no guarantee separates them.

- With type arguments both infer the same types and their callbacks see the
  same parameter types. Without, both infer `QueryFamily<Object?, …>`
  (`boundary/untyped_definition.dart`), both fail the same way when the
  fetcher uses its input (`negative/untyped_definition.dart`), both anchor a
  zero-input definition by its fetcher and a family by typed closure
  parameters, and both hit the same debug backstop (`D10-1`, `D10-2`). On
  all three SDKs.
- What the factory saves is the `namespace:` argument, one line per
  declaration.
- What it costs: `devices.query('list', …)` and
  `devices.infiniteQuery('feed', …)` would declare, one receiver away from
  `client.query(…)` and `client.infiniteQuery(…)`, which fetch. The
  constructor form is how every options object in the package is written,
  and the class name at the declaration is the word the reference, the
  search and the API index use.
- (c) is two spellings of one thing in every guide and every example,
  and a reader has to find out that they are one thing.
- (b) or (c) is not foreclosed for a user: the fixture's factory is an
  extension of some ninety lines over the public constructors, and needs
  nothing from the library.

### Open questions for Phase 0

**All three are answered (Phase 0, 2026-11-10):** Open-1 under D10 (the
record for a definition without type arguments), D8 and the positive
fixtures named in the [Phase 0](#phase-0--prove-the-dart-api-before-implementing-the-facade)
section; Open-2 under D1 (what the surface does not offer), D2 (the generic
setter) and D9 (the mixed list); Open-7 under D2. Nothing is open for an
analyzer any more.

Open-1's positive half, which has no decision of its own to sit under:
every shape below infers its exact type with no annotation and no type
argument at the call site, on Dart 3.6.2, 3.10.7 and 3.13.4, under the
analyzer's defaults and this repository's options. Each is pinned by
`expectStaticType`, which fails for a wider and for a narrower type.

| Shape | Inferred | Fixture |
|---|---|---|
| `detail('d1')`; its `options()`, `key`, `filters()` | `QueryRef<Device>`; `QueryObserverOptions<Device>`, `TypedQueryKey<Device>`, `QueryFilters` | `positive/plain_reference.dart` |
| `read`, `key.read`; `state`; `fetch`; `write`; `update` and its updater's parameter | `Device?`; `QueryState<Device>?`; `Future<Device>`; `Device`; `Device?` and `Device?` | the same |
| `QueryObserver(client, device.options())`, `client.observe`, `client.query`, a per-use `copyWith` | `QueryObserver<Device, Device>`, `Future<Device>`, `QueryObserverOptions<Device>` | the same |
| `device.options().withSelect((data) => data.name)` and its selector's parameter; the observer over it | `QuerySelectOptions<Device, String>`, `Device`; `QueryObserver<Device, String>` | `positive/selection_nullable_subtypes.dart` |
| a nullable definition's `read`, `state`, `write(null)`; a sealed base written with a variant and switched over exhaustively; an empty and a narrow collection literal written under the declared type; an updater declared with a wider parameter | exact | the same |
| inputs: a `String`, an enum, an `int`, a value object, a record with a named field, a nullable enum, `Object`, a list | a reference of the family's data type each | `positive/typed_inputs.dart` |
| the parameters of `keyOf`, `queryFn` and `configure` inside a declaration, inline and extracted | the declared types | the same |
| a family's `readAll` and `updateAll` | `List<(TypedQueryKey<Device>, Device?)>` | the same |
| an infinite definition, its `options()`, `read`, `fetch`, `pages`, `pageParams`, `write` of a literal, `update`, the observer, the selected shape, a family's reference, the parameters of every paging callback | exact in page data and page param | `positive/infinite.dart` |
| the sealed types in a `switch` | exhaustive without a default | `positive/reference_names.dart` |

The questions as they were asked:

Only these stay open; each needs an analyzer or a measurement, not a
decision. Round 1's Open-3 to Open-6 are closed: Open-3 by D2, Open-4 by D4,
Open-5 by D1 (a definition is a reference), Open-6 by reading the task
manager's keys, `['tasks', 'list', filters]` and `['tasks', 'byId', id]`,
which already fit `[namespace, name, ...input]` and need no adapter.

- **Open-1, inference:** which positive shapes infer exact types without
  annotations at the call site (reads, writes, updaters, selectors, page
  data) on Dart 3.6 and the CI SDK; and the record of what each SDK infers
  for a definition without type arguments (D10).
- **Open-2, negative fixtures:** that each listed misuse fails at the intended
  location with the intended diagnostic, including the unsafe generic setter
  of D2 as the control that shows why the receiver-anchored shape is needed.
  The mixed-type list of D9 compiles and is a separate boundary fixture with
  a runtime assertion, not an analyzer negative.
- **Open-7, `-O4`:** fixtures compiled with `dart compile js -O4` and run that
  show D2's explicit check firing where the covariance check is omitted, for
  a single `write`, a single `update` and a family bulk update (D7).

## Final surface (TQ0)

What Phase 1 implemented. These were the public signatures of the
prototype (`tool/typed_query_fixtures/prototype/typed_queries.dart`,
deleted by TQ1) and are now those of
`packages/query_kit/lib/src/query_definition.dart`, which every fixture
analyzes against; a signature that changes fails a fixture. Ten
types, no new typedef, no new top-level function, nothing added to
`QueryClient`. The names of the type parameters are not part of the
contract.

```dart
/// What a lifecycle operation is aimed at. No data type.
sealed class QueryTarget {
  QueryFilters filters({
    QueryTypeFilter? type,
    bool? stale,
    FetchStatus? fetchStatus,
    QueryStatus? status,
    bool Function(Query<Object?> query)? predicate,
  });
  Future<void> invalidate(QueryClient client,
      {RefetchType? refetchType, bool cancelRefetch = true});
  Future<void> refetch(QueryClient client, {bool cancelRefetch = true});
  Future<void> cancel(QueryClient client,
      {bool revert = true, bool silent = false});
  Future<void> reset(QueryClient client, {bool cancelRefetch = true});
  void remove(QueryClient client);
}

final class QueryNamespace extends QueryTarget {
  QueryNamespace(List<Object?> parts);
  final QueryKey rawKey;
}

/// No public constructor. `==` is the raw key and `T`.
final class TypedQueryKey<T> {
  final QueryKey rawKey;
  Type get dataType;
  T? read(QueryClient client);
  QueryState<T>? state(QueryClient client);
}

sealed class QueryEntryRef<T> extends QueryTarget {
  final TypedQueryKey<T> key;
  T? read(QueryClient client);
  QueryState<T>? state(QueryClient client);
  T write(QueryClient client, T value, {DateTime? updatedAt});
  T? update(QueryClient client, T? Function(T? previous) updater,
      {DateTime? updatedAt});
}

/// No public constructor. `==` is the kind and the typed key.
abstract final class QueryRef<T> extends QueryEntryRef<T> {
  QueryObserverOptions<T> options();
  Future<T> fetch(QueryClient client, {bool revalidateIfStale = false});
}

abstract final class InfiniteQueryRef<TPageData, TPageParam>
    extends QueryEntryRef<InfiniteData<TPageData, TPageParam>> {
  InfiniteQueryObserverOptions<TPageData, TPageParam> options();
  Future<InfiniteData<TPageData, TPageParam>> fetch(QueryClient client,
      {bool revalidateIfStale = false});
}

final class QueryDefinition<T> extends QueryRef<T> {
  QueryDefinition({
    required QueryNamespace namespace,
    required String name,
    FutureOr<T> Function(QueryFunctionContext context)? queryFn,
    QueryObserverOptions<T> Function(QueryObserverOptions<T> base)? configure,
  });
}

final class QueryFamily<TInput, T> extends QueryTarget {
  QueryFamily({
    required QueryNamespace namespace,
    required String name,
    List<Object?> Function(TInput input)? keyOf,
    FutureOr<T> Function(TInput input, QueryFunctionContext context)? queryFn,
    QueryObserverOptions<T> Function(
            QueryObserverOptions<T> base, TInput input)?
        configure,
  });
  final QueryKey rawKey;
  QueryRef<T> call(TInput input);
  List<(TypedQueryKey<T>, T?)> readAll(QueryClient client);
  List<(TypedQueryKey<T>, T?)> updateAll(
      QueryClient client, T? Function(T? previous) updater,
      {DateTime? updatedAt});
}

final class InfiniteQueryDefinition<TPageData, TPageParam>
    extends InfiniteQueryRef<TPageData, TPageParam> {
  InfiniteQueryDefinition({
    required QueryNamespace namespace,
    required String name,
    required FutureOr<TPageData> Function(
            InfinitePageContext<TPageParam> context)
        pageFn,
    required TPageParam initialPageParam,
    required TPageParam? Function(TPageData page, List<TPageData> pages,
            TPageParam pageParam, List<TPageParam> pageParams)
        getNextPageParam,
    TPageParam? Function(TPageData page, List<TPageData> pages,
            TPageParam pageParam, List<TPageParam> pageParams)?
        getPreviousPageParam,
    InfiniteQueryObserverOptions<TPageData, TPageParam> Function(
            InfiniteQueryObserverOptions<TPageData, TPageParam> base)?
        configure,
  });
}

final class InfiniteQueryFamily<TInput, TPageData, TPageParam>
    extends QueryTarget {
  InfiniteQueryFamily({
    required QueryNamespace namespace,
    required String name,
    List<Object?> Function(TInput input)? keyOf,
    required FutureOr<TPageData> Function(
            TInput input, InfinitePageContext<TPageParam> context)
        pageFn,
    required TPageParam Function(TInput input) initialPageParam,
    required TPageParam? Function(TInput input, TPageData page,
            List<TPageData> pages, TPageParam pageParam,
            List<TPageParam> pageParams)
        getNextPageParam,
    TPageParam? Function(TInput input, TPageData page, List<TPageData> pages,
            TPageParam pageParam, List<TPageParam> pageParams)?
        getPreviousPageParam,
    InfiniteQueryObserverOptions<TPageData, TPageParam> Function(
            InfiniteQueryObserverOptions<TPageData, TPageParam> base,
            TInput input)?
        configure,
  });
  final QueryKey rawKey;
  InfiniteQueryRef<TPageData, TPageParam> call(TInput input);
  List<(TypedQueryKey<InfiniteData<TPageData, TPageParam>>,
      InfiniteData<TPageData, TPageParam>?)> readAll(QueryClient client);
  List<(TypedQueryKey<InfiniteData<TPageData, TPageParam>>,
      InfiniteData<TPageData, TPageParam>?)> updateAll(
      QueryClient client,
      InfiniteData<TPageData, TPageParam>? Function(
              InfiniteData<TPageData, TPageParam>? previous)
          updater,
      {DateTime? updatedAt});
}
```

Behaviour that belongs to the signatures:

- A raw key is `[...namespace, name]` for a zero-input definition and
  `[...namespace, name, ...keyOf(input)]` for a family, `[...namespace,
  name, input]` without a `keyOf` (D3).
- `TypedQueryKey.==` is the raw key and `T`; a reference's `==` is its kind
  and its typed key; a family, a namespace and options have identity
  equality (D4).
- `write`, `update` and `updateAll` check the entry for the exact type
  first, then the value or every updater result through `Object?`, then
  write; they throw `QueryDataTypeError`. `call` checks the input the same
  way and throws `ArgumentError` (D2, D5, D7).
- Every definition constructor asserts that none of its type arguments is a
  top type, and the plain ones that the data type is not `Null` (D10, D5).
  Debug builds only.
- `options()` returns fresh options on every call, with the definition's
  key and functions pinned after `configure` (D4, D6). The definition pins
  what it declares; what it leaves unset, `configure` may set. Options of
  another runtime type than the definition's own are a `StateError` (D6,
  TQ2).
- `updateAll` looks every entry it is about to write up once more before
  the first write (D7, TQ2).
- Only the infinite definitions rebuild a written `InfiniteData` under
  the declared page types (D5, TQ2).

**The limits, stated.** Each is measured in Phase 0 unless it says
otherwise, and each belongs in the guide where the feature it limits is
introduced.

1. *Widening compiles.* A reference, a family or an updater upcast to a
   wider type argument, a raw type, `dynamic` and a cast are all accepted
   by the analyzer (three of them reported only under this repository's
   stricter options). The misuse is then refused at runtime before
   anything is written: by Dart's `TypeError` on the VM and dart2js at its
   default level, by `QueryDataTypeError` or `ArgumentError` at dart2js
   `-O3`/`-O4` (D2).
2. *dart2wasm at `-O3`/`-O4`* was not run in Phase 0; round 3's probe says
   it traps uncatchably there. Flutter's wasm default is `-O2`.
3. *No generic client-style setter*, because one widens (D2).
4. *A family without type arguments has an `Object?` input.* It fails to
   compile when its fetcher uses the input as a type, and compiles
   silently when it does not, under strict options too; the refusal is
   then a debug assertion and absent from a release build. The assertion
   also refuses a deliberate `Object?` or `void` input; `Object`, a
   nullable or a sealed type pass (D10).
5. *A key-only definition without type arguments is `dynamic`*; only
   `strict-inference` reports it, and the same debug assertion (D10).
6. *`QueryDefinition<Null>`* is refused by a debug assertion only (D5).
7. *A list of options of two data types* infers `Object`, and an observer
   over it creates `Object` entries the references then refuse (D9).
8. *A record input holding a collection needs a `keyOf`*, and nothing
   detects its absence; an input with identity equality is refused by
   `QueryKey`'s debug assertion only (D3).
9. *Two definitions of one raw key and one type* are one entry and give
   equal references, whatever their fetchers; a plain and an infinite
   definition of one key and one `InfiniteData` type share the entry and
   give unequal references (D3, D4).
10. *A key nested under a family's prefix* is a member of the family to
    its bulk and lifecycle operations when it has the family's type, and
    makes the typed bulk calls throw when it has another (D7).
11. *The exits are spelled and stay open:* `rawKey` handed to the raw
    client, a per-use `copyWith(queryKey: …)` or `copyWith(queryFn: …)`,
    and any raw call on the same key. The raw writes keep their leniency,
    so a raw first write still creates an entry of the value's own type,
    which a typed read then refuses (D5).
12. *`read` cannot tell a cached `null` from no data*; `state` can (D5).
13. *A per-use `copyWith` cannot unset a definition's default* (D6).
14. *Options carry no equality*, and each `options()` call makes a new
    fetcher closure (D4).
15. *A narrower `InfiniteData` supplied through a per-use `copyWith`* is
    outside the normalisation, and so is a `structuralSharing` from the
    client's or a key's defaults. The definition's own `structuralSharing`
    and `initialData` are inside it, built and tested by TQ1 (D5).
16. *A bulk update is not a transaction:* every result is validated, and
    every entry about to be written looked up again, before the first
    write, so nothing an updater does to the cache leaves it half-written
    (TQ2). The writes notify as they are made: a cache listener or an
    observer that answers one by replacing a later entry with one of
    another type makes that entry's write throw after the earlier ones, and
    nothing is rolled back (D7).
17. *A definition whose first page param is `null`* cannot have it changed
    by `configure`: making the options throws a `StateError` (D6, TQ1).
18. *A collection literal of references of different data types infers a
    common supertype*, `QueryRef<Object>` or `QueryEntryRef<Object>` (and
    `QueryDefinition<Object>`, `QueryFamily<String, Object>`,
    `TypedQueryKey<Object>`, `InfiniteQueryRef<List<Object>, Object>` for
    their kinds), not `QueryTarget`, whenever its elements are of one
    class; a set, a map and a conditional expression do the same. Writes
    through its elements are checked at runtime only, as in limit 1.
    Declare a heterogeneous lifecycle list as `<QueryTarget>[…]`, whose
    elements have no `write` (D9, TQ2).
19. *`configure` returns options of the definition's own type.* Options of
    a narrower data type satisfy its return type; making the options then
    throws a `StateError` naming the key and both types, on every runtime
    (D6, TQ2).
20. *A plain definition typed `InfiniteData<P, Q>` does not normalise.*
    Its entry is exact and the value it stores keeps the type arguments it
    came with; only an infinite definition rebuilds a narrower
    `InfiniteData` under the declared page types (D3, D5, TQ2).

## Implementation map

Paths are the baseline integration points; new file names are provisional.

- Core: introduce cohesive definition/reference/typed-key modules under
  [packages/query_kit/lib/src](../../packages/query_kit/lib/src/), exported by
  [query_kit.dart](../../packages/query_kit/lib/query_kit.dart).
  Phase 0: it is **one library**. `QueryTarget` and `QueryEntryRef` are
  sealed and `QueryRef` and `InfiniteQueryRef` are `abstract final`, and
  Dart wants every direct subtype of those in the library that declares
  them, so all ten types live together (the prototype was some 770 lines;
  since TQ1 it is `query_definition.dart`, some 1,350 with its dartdoc).
  Integrate with `query_client.dart`, `query_cache.dart`, `filters.dart`,
  `query_options.dart`, `query_state.dart` and `infinite_query.dart`.
  Inspect `query.dart`, both observer implementations and `queries_observer.dart`
  only where identity metadata or type preservation needs to cross a boundary.
- Flutter: exercise `query_controller.dart`, `query_builder.dart`,
  `query_mixin.dart`, `query_context.dart`, `queries_controller.dart`,
  `queries_builder.dart` and existing listeners under
  [query_kit_flutter/lib/src](../../packages/query_kit_flutter/lib/src/).
  Preserve `ReadEntry`/`ReadSet` key reuse and provider/client replacement.
  Avoid shadowing the internal `QueryScope` through the core barrel export.
- Hooks: exercise `use_query.dart`, `use_queries.dart`,
  `use_infinite_query.dart`, `use_prefetch.dart` and mutation integration under
  [query_kit_hooks/lib/src](../../packages/query_kit_hooks/lib/src/).
- Evidence: the analyzer fixtures and their runner exist since Phase 0
  (`tool/typed_query_fixtures/`, `tool/check_typed_query_fixtures.dart`),
  the intentional failures excluded from the repository's own analysis by
  `analysis_options.yaml`; extend core,
  Flutter and hooks tests, respecting the existing test organisation in
  [CONTRIBUTING](../../CONTRIBUTING.md). Feature-specific tests are separate
  from upstream cases; document the extension in
  [PORTING_NOTES](../../packages/query_kit/test/PORTING_NOTES.md).
- Consumer/docs: migrate one complete flow in
  [task_manager](../../examples/task_manager/) plus infinite behaviour in
  [showcase](../../examples/showcase/), and cover the hooks example. Update
  [doc_snippets](../../examples/doc_snippets/), the hook documentation fence
  tests, package READMEs and public API docs. Preserve the relevant raw examples
  as compatibility/advanced examples.

## Delivery sequence and exit criteria

### Phase 0 — Prove the Dart API before implementing the facade

Build small analyzer fixtures for the proposed definition, reference and typed
key shapes using the declared Dart 3.6 floor and the SDK used by current CI.
Run ordinary usage with a minimal consumer analyzer configuration as well as
the repository's strict settings. Separate language errors from optional lints.

Positive cases must prove exact inferred types without annotations on each
read/write call, including plain options, required selection, nullable data,
subtypes, typed inputs and infinite data. Negative fixtures must fail at the
intended location with the intended diagnostic, not merely exit nonzero due
to missing imports. Run valid counterparts as controls. Include the unsafe
generic client-style setter to demonstrate why the chosen shape is necessary.

Answer Open-1, Open-2 and Open-7 and record each answer under its decision.
Add one fixture that is not about types: two references built from equal
inputs of an equal definition are `==` (D4), and a reference holds no client.

**Exit:** executable positive/negative evidence on both SDKs, the `-O4`
fixture, a recorded final surface and explicit limits. If a desired syntax cannot uphold a guarantee,
revise the syntax or narrow the claim before proceeding; do not replace a
promised compile error with an undocumented debug assertion.

**Done (TQ0, 2026-11-10).** What exists:

| Path | What it is |
|---|---|
| `tool/check_typed_query_fixtures.dart` | the runner |
| `tool/typed_query_fixtures/surface.dart` | the one import every fixture takes the surface from: the package, plus the prototype |
| `…/prototype/typed_queries.dart` | a working prototype of the whole surface, written against the package's exported API only |
| `…/positive/` | six files that must analyze clean; every inferred type pinned by `expectStaticType`, which a wider or a narrower type fails |
| `…/negative/` | seven files, 114 marked lines: 105 misuses and nine self-tests of the type-pinning helper |
| `…/boundary/` | four files that must compile: the generic setter, the widened receivers, the untyped definitions, the mixed list; five lines carry a diagnostic that only this repository's stricter options produce |
| `…/support/` | the example domain, the type-pinning helper, the generic setter of D2's option (a), the namespace factories of D12's option (b) |
| `…/runtime/observations.dart` and three `.expect` files | 98 printed observations, and what each runtime must print |

```bash
dart run tool/check_typed_query_fixtures.dart              # everything
dart run tool/check_typed_query_fixtures.dart --no-runtime # the analyzer part
dart run tool/check_typed_query_fixtures.dart --record     # rewrite the .expect files
dart run tool/check_typed_query_fixtures.dart --keep       # keep the temporary package
```

The runner copies the fixtures into a temporary consumer package with a
path dependency on the core, and analyzes it once per language version (the
declared floor, and the running SDK's own when it is newer) and per option
set: **minimal**, no `analysis_options.yaml` at all, which is what a
consumer has before configuring anything, and **strict**, a copy of this
repository's. A line under `// EXPECT error <code>` must carry exactly that
diagnostic, as an error, in every configuration; a line under
`// EXPECT strict <code>` only under the strict set; anything else the
analyzer reports is a failure, and so is a marker nothing answers. That is
how language errors and optional lints stay apart: all 114 `error` markers
are errors of the language under the analyzer's defaults, and the five
`strict` ones are `strict-raw-types`, `strict-casts`, `strict-inference`
(twice) and the `avoid_dynamic_calls` lint. A negative file has to have at
least one marker and a positive file may have none, so a fixture cannot
pass by failing for another reason, or by not failing.

Then it runs `runtime/observations.dart` five ways, on the VM with and
without assertions and compiled by dart2js at its default level, at `-O3`
and at `-O4` under node, and compares each output with a recorded file
(`debug`, `release` for the VM without assertions and dart2js default,
`unchecked` for `-O3` and `-O4`).

It ran green on Dart 3.6.2 (the floor), 3.10.7 (CI) and 3.13.4 (stable at
the time): on each, 114 errors and 5 optional diagnostics where expected
and none elsewhere, per language version and option set, and 98
observations as recorded on each of the five runtimes. In CI it is a step
of `gates` (the CI SDK) and of `floors` (the floor), so the floor's own
analyzer and dart2js are covered, not only its test run. `latest-stable.yml`
does not run it yet.

**After the review of TQ0 (S0-5, TQ2): the runner can no longer pass
with less than it was committed with.** The review reduced the tree to
one positive file, no negative directory and an observation program that
prints nothing, recorded that, and got a green run. Reproduced on a copy
of that tree: `OK: 1 fixture files, 0 misuses refused`, exit code 0. The
rule above ("a negative file has to have at least one marker") is a rule
about a file that exists. Options: (a) minimum counts as constants in the
runner, which are stale the day a fixture is added and then let the new
one be deleted unseen; (b) an inventory file of minimum counts, the same
flaw one step removed; (c) an inventory that the tree must match
**exactly**, in both directions, written only by `--record`; (d) a hash
per file, which fails on every edit of a comment and teaches people to
record without reading. Answer: (c), over floors no inventory can lower.

- `tool/typed_query_fixtures/inventory.txt` lists every fixture file with
  its number of `error` and `strict` markers and every recorded output
  with its number of observations. A run compares it with the tree first
  and stops at a difference in either direction, naming the row.
- Floors in the runner's code, which hold whatever the inventory says:
  every fixture directory holds a file, the observation program exists,
  the tree refuses at least one misuse, every recorded output exists and
  is not empty, no fixture is an empty file.
- The output of each of the five runtimes is checked for itself before it
  is compared: at least one observation, every line an observation
  (`id | what | result`), no identifier twice.
- `--record` is the one way an inventory or a recorded output moves. It
  refuses to record an output that fails those checks, records the
  inventory only after a green run, and prints what is gone, changed and
  new, so the diff a reviewer reads says "gone: negative/definitions.dart"
  in so many words.
- `--self-test` breaks a copy of the tree in each of those ways, 31
  cases, and requires the failure and its message: the reviewer's tree
  among them, the same tree with the inventory deleted and re-recorded,
  and one end-to-end run that must exit with 1. CI runs it before the
  runner in `gates` and in `floors`.

What it does not hold: the inventory pins counts, not content. A misuse
replaced by another keeps its row; that is a reviewer's diff to read, and
the marker's diagnostic code still has to be the one the analyzer
reports.

The tree after TQ2: 24 files (seven positive, seven negative, four
boundary, four support, the surface and the program), 119 `error` markers
and 5 `strict` ones, 113 observations.

**Phase 1 points the fixtures at the real exports by deleting one line:**
`surface.dart`'s `export 'prototype/typed_queries.dart';`. Nothing else
imports the prototype. (Done by TQ1: `surface.dart` exports the package
and nothing else, `prototype/` is gone, and the runner no longer lists the
directory. The two table rows above describe TQ0's state.)

### Phase 1 — Ordinary definitions and cache operations

Implement namespaces, static definitions, families, references and typed keys.
Thread them into the existing cache with typed reads/state, writes/updates,
options, fetch and exact lifecycle operations. Identity is structural (D3):
no registry, no metadata. Preserve runtime checking and raw compatibility.

**Amended by Phase 0: Phase 1 lands the whole public surface, the infinite
definitions and the family bulk operations included.** The exit below asks
that all Phase 0 fixtures run against the real exports, the fixtures cover
the infinite and bulk signatures, and the hierarchy is sealed: a prototype
`InfiniteQueryRef` cannot extend the real `QueryEntryRef` from another
library, so there is no state in which the plain half is real and the
infinite half still the prototype. Options: (a) Phase 1 lands the plain
half and the runner learns to skip fixtures until Phase 2, which leaves
this exit unmet and the infinite signatures unguarded for a phase; (b)
Phase 1 lands the plain half and unseals the hierarchy for a phase, which
ships a weaker type than the one proven; (c) Phase 1 **promotes the
prototype** into `packages/query_kit/lib/src/` whole and Phase 2 adds
depth. Answer: (c). The prototype is working code for every signature and
ran on fifteen runtime configurations; what it lacks is the package's
internals and the package's tests, and Phase 1 supplies both:

- move `prototype/typed_queries.dart` into the core as one library and
  export its ten types; delete `prototype/` and the second export line of
  `surface.dart`;
- replace its two detours: build an entry only when it is absent and write
  through `Query.setData(manual: true)`, and reuse the raw bulk update's
  two passes instead of repeating them;
- drop its `ignore_for_file`, and rewrite its doc comments, which cite
  this plan's decision numbers (`tool/check_docs_jargon.dart` refuses
  those under `packages/*/lib`);
- tests for every member, the infinite and bulk ones too, so the core's
  line-coverage floor holds; the runtime observations stay as they are and
  become a second, cross-runtime proof;
- the public shape recorded as **ADR-0007** (`docs/adr/` already holds
  0005 and 0006, so the number the ticket was written with is taken).

**Exit:** core tests demonstrate same-key sharing between typed/raw consumers,
declared-type first writes, exact typed writes refusing a wider raw entry
(D5), nullable semantics, stable recreation, equal references from equal
inputs (D4), defaults, exact/prefix isolation and no extra
fetch/subscription merely from binding.
All Phase 0 fixtures run against the real public exports.

**Done (TQ1, 2026-11-10).** What exists:

| Path | What it is |
|---|---|
| `packages/query_kit/lib/src/query_definition.dart` | the ten types, one library, exported whole from the barrel; no `ignore_for_file`, no typedef, no top-level function, nothing added to `QueryClient` |
| `packages/query_kit/lib/query_kit.dart` | the export, and a "Typed query definitions" section in the library documentation with the five limits a user meets first |
| `packages/query_kit/dartdoc_options.yaml`, `doc/categories/typed-queries.md` | a "Typed queries" category in the API reference |
| `packages/query_kit/test/query_definition_test.dart` | 85 cases: the plain definitions, families, namespaces, lifecycle and bulk operations |
| `packages/query_kit/test/infinite_query_definition_test.dart` | 39 cases: the infinite definitions, the normalisation and the two wrappers |
| `packages/query_kit/test/barrel_test.dart` | one more case: the library exports ten types and nothing else public |
| `tool/typed_query_fixtures/surface.dart` | exports the package and nothing else; `prototype/` is deleted |
| [ADR-0007](../adr/0007-typed-query-definitions-are-values-over-the-client.md) | the parts of the shape a release makes permanent |

The surface is the [Final surface](#final-surface-tq0) with no signature
changed: the 23 fixture files and the 98 observations pass unedited
against the real exports on Dart 3.6.2, 3.10.7 and 3.13.4. The core's
suite went from 1175 to 1300 VM cases and from 1171 to 1295 in Chrome, no
existing case touched; line coverage is 3774 of 3780 (99.84 %, floor
99.8 %).

Where the implementation left the list above, each with its reason in the
[review record](#phase-1-tq1-2026-11-10):

- The bulk update is the typed library's own pass in the raw update's
  order, not the raw update with a wrapped updater (D7).
- The definition's own `structuralSharing` and `initialData` are wrapped
  here, not in Phase 2 (D5). The brief for the ticket asked for it, and
  the normalisation is not finished without it: a custom sharing function
  returning the narrower value undoes a normalised write.
- `update` looks the entry up a second time after the updater ran (D5).
- A definition with a `null` first page param refuses a `configure` that
  sets one (D6, limit 17).
- Two lines of the library cannot be reached on the VM: the `throw` of
  the value check and the `throw` of the input check. Dart's own
  covariance check throws a `TypeError` at the call before either runs,
  so they execute only where that check is compiled out. The proof that
  they work is the fixture runner's `-O3` and `-O4` runs
  (`runtime/observations.unchecked.expect`), which CI runs on two SDKs.
  Both checks go through one private function each, so the cost to the
  coverage floor is two lines, and no `coverage:ignore` hides them.

Left for Phase 2, beyond its own list: the infinite exit's runtime cases
that go further than Phase 1's tests (rollback with a request in flight),
and the mutation recipes. Nothing in `packages/query_kit_flutter` or
`packages/query_kit_hooks` changed; both suites run green over the new
core because the binding re-exports it and a name clash would fail them.

### Phase 2 — Families, infinite queries and mutation workflows

Implement family bulk operations as D7 says, infinite definitions,
typed filters and mutation recipes. Keep all fetching and paging in the current
client/observer machinery. Exercise cancellation and optimistic rollback with
an in-flight request and validate stored type and state after each transition.

**Amended by Phase 0:** the signatures of the bulk operations, the
infinite definitions and the filter adapter exist after Phase 1 (above).
Phase 2 is their depth: the definition's own `structuralSharing` and
`initialData` wrapped for the infinite normalisation (D5, which the
prototype does not do), the mutation recipes, and the runtime tests of
this exit, every one of which still applies.

**Amended by Phase 1:** the wrapping is done and tested (TQ1, D5). Of
this exit's cases TQ1's two test files already hold: the two kinds on one
key with different types and with the same `InfiniteData` type, sibling
and descendant isolation, the nested key of another type and the wider
raw entry each making the bulk call throw before any write, the narrower
`InfiniteData` normalised on write, stored null and absence. What remains
is rollback: cancellation and an optimistic write with a request in
flight, the stored type and state checked after each step, and the
mutation recipes around it.

**Exit:** page and input type fixtures pass; runtime tests cover an ordinary
and an infinite definition on one key with different types (the cache's own
type error) and with the same `InfiniteData` type (shared, documented),
sibling/descendant isolation, a nested key of another type under a family
prefix making the bulk call throw before any write, a wider raw entry under
a family prefix making the typed bulk update throw where the raw one writes,
an extracted narrower `InfiniteData` normalised on write, stored null,
absence and rollback. Runtime failures do not partially corrupt the cache.

**Done (TQ2, 2026-11-10).** What exists beyond TQ1:

| Path | What it is |
|---|---|
| `packages/query_kit/test/query_definition_mutation_test.dart` | 22 cases: the six mutation recipes, each a function a guide can lift, with a fetch in flight where it matters |
| `packages/query_kit/test/query_definition_test.dart` | 94 cases (85 after TQ1): what `configure` may return, the bulk update's second look, `reset(cancelRefetch:)` |
| `packages/query_kit/test/infinite_query_definition_test.dart` | 46 cases (39): the same for the infinite kinds, the pin rule without a previous-page function, the plain definition typed `InfiniteData` |
| `packages/query_kit/lib/src/query_definition.dart` | two changes of behaviour, no signature changed: options of another type than the definition's own are refused (D6), and a bulk update looks its entries up once more before the first write (D7) |
| `tool/check_typed_query_fixtures.dart`, `tool/typed_query_fixtures/inventory.txt` | the runner's inventory, floors, output checks and self-test (Phase 0, above) |
| `tool/typed_query_fixtures/positive/target_list.dart`, `boundary/mixed_list.dart`, `negative/surface_limits.dart`, `runtime/observations.dart` | the collection literal's inferred types pinned, the declared target list offered and refused, 15 more observations |

The core's suite went from 1300 to 1338 VM cases and from 1295 to 1333
in Chrome, no existing case rewritten; one TQ1 case was replaced, the
swap during a bulk update, whose expectation is the behaviour D7 changed
on purpose. Line coverage is 3786 of 3792 (99.84 %, floor 99.8 %).

**The recipes.** A mutation *definition* stays out of scope; each recipe
is a function that returns ordinary `MutationOptions` over typed
references, and the test file's own domain (`Device`, `DeviceQueries`,
`DeviceApi`) is what a guide would show.

| # | Recipe | What its cases hold |
|---|---|---|
| 1 | Optimistic write of one entry: `cancel`, `read`, `update`, write the old value back in `onError`, `invalidate` in `onSettled` | every step with a refetch in flight: the fetch is cancelled and its response never lands, the patch, the rollback, the refetch, with data, status, fetch status, timestamp and the entry's type after each; the control without the `cancel`, where the response in flight overwrites the patch; success; nothing cached |
| 2 | A snapshot of `state`, not of `read`, and a `restore` over it | no entry: removed again, exactly, a sibling untouched; an entry without data whose first fetch was in flight: reset and refetched; one nothing observes: reset, idle; a cached `null` on a nullable definition: written back as `null` with its timestamp; a value over a value and `null` over a value; and that `read` alone returns `null` for all three |
| 3 | The server's answer written into the detail and into its row of the list | no refetch; a detail never read is created with the declared type and a list never read is not; a refused write changes nothing |
| 4 | A list written, then its family invalidated | every cached detail marked, the observed ones refetched, an unrelated family untouched, and the mutation waits for the refetches |
| 5 | Every cached detail patched with `updateAll`, and put back by id | only the family's entries; a refusal restores the devices the mutation changed and keeps a neighbour's later write; with a detail's fetch in flight |
| 6 | The same as 1 and 2 over an infinite definition | cancel, prepend a row to the first page, fail, restore, refetch, with `InfiniteData<List<Event>, int>` as the stored type at every step; success; a feed nobody opened; a narrower optimistic value stored under the page types |

A last case runs every recipe against a refusing backend and compares
the cache before and after: entries, types and data.

**The exit, item by item.** Tests are named by group and case;
"definition", "infinite" and "mutation" are the three files above.

| Exit item | Covered by |
|---|---|
| page and input type fixtures | `positive/infinite.dart`, `positive/typed_inputs.dart`, `negative/definitions.dart`, `negative/reads_and_writes.dart`; the runner on three SDKs |
| ordinary and infinite on one key, different types | infinite, "a plain and an infinite definition on one key": "of different data types: the cache's own type error" |
| the same, one `InfiniteData` type: shared, documented | the same group: "of the same InfiniteData type: one entry, and nothing reports it"; limits 9 and 20; the barrel's limits list |
| sibling and descendant isolation | definition, "exact for a reference, prefix for a family and a namespace" (filters, invalidate, remove) and "updateAll writes every input and nothing beside the family"; infinite, "an infinite reference is exact, its family a prefix"; mutation, group 2 "no entry" (a sibling), group 4 (another family of the namespace), group 5 (the list beside the family) |
| a nested key of another type under a family prefix: the bulk call throws before any write | definition, "an entry of another type under the prefix: nothing runs or is written"; infinite, "an entry of other page types under the prefix: nothing is written" |
| a wider raw entry under a family prefix: the typed bulk update throws where the raw one writes | definition, "a wider entry under the prefix: refused where the client writes" |
| an extracted narrower `InfiniteData` normalised on write | infinite, "a written value is stored under the declared page types" (seven cases); mutation, group 6 "a narrower optimistic value is stored under the page types" |
| the same through a custom sharing callback (the ticket's wording) | infinite, "a hook that returns a narrower value: the commit is exact", "fetched pages go through it as well", "the family's hook is wrapped per input" |
| stored null, absence | definition, "absence, no data and a cached null" (seven cases); mutation, group 2 |
| rollback, with a request in flight, stored type and state after each step | mutation, group 1 and group 6 (their first cases), group 2 (its second case, a first fetch in flight); cancellation of a whole family's fetches before a patch: group 5 (its third case) |
| runtime failures do not partially corrupt the cache | definition, "an updater that throws for a later entry: no earlier one is written", "re-entrant updaters" (four cases), "through a widened family a wrong result is refused, nothing written", "write, update and read over a wider entry throw, and write nothing"; mutation, "every recipe, refused: entries, types and data as before"; observations `D9-4` to `D9-11` and `D6-2` on five runtimes |
| the filter adapter carries active/inactive, refetch type and cancellation (the ticket's build list) | definition, "filters carry the target's key and exactness, and every argument", "invalidate and refetch pass cancelRefetch on", "cancel passes revert and silent on", "reset passes cancelRefetch on" |
| `fetch` over `client.infiniteQuery`; the page functions are handed the input | infinite, "fetch is client.infiniteQuery: fresh, stale, joined", "a family hands every paging function its input" |

Nothing on the list was missing a case after the recipes were written;
the one line of it that had no case before TQ2 was rollback.

**TQ1's three open points, decided.**

- *A re-entrant swap during `updateAll`.* The entries are looked up
  again before the first write (D7, above). The listener's swap, which
  that cannot reach, is a test and limit 16.
- *`reset(cancelRefetch:)` had no behavioural case.* TQ1 recorded that
  the argument "cannot be observed", because a reset cancels what is in
  flight before it refetches. It can: for an entry the reset leaves with
  data (a seeded one), a fetch a cache listener starts as it hears the
  reset is in flight when the refetch arrives, and then `false` joins it
  (one fetch) and `true`, the default, replaces it (two). Three cases,
  one of them the client's own `resetQueries` over the same filters as
  the control. Checked by changing the library: with the argument
  dropped in a scratch copy of TQ1's code the "off" case fails.
- *Two lines the VM cannot reach* (the `throw` of the value check and of
  the input check, behind Dart's own covariance check). Options: (a) a
  `coverage:ignore` comment, which this repository has never used, so
  it would be the first hidden line in a count that is otherwise a plain
  count; (b) a test that reaches them through a private seam, which
  means a seam that exists for the test; (c) leave them counted as
  missed while the floor holds. Answer: (c). The library is at 260 of
  262 lines and the package at 99.84 % against a floor of 99.8 %, with
  the two new functions of TQ2 fully covered, and the lines are proven
  where they run: the `-O3` and `-O4` observations, which CI runs on two
  SDKs. The floor is not lowered; if a later change brings the package
  under it, that change has to cover something, not hide something.

### Phase 3 — Flutter, hooks and representative consumers

Integrate the options adapters through all supported consumers. Migrate one
end-to-end task-manager flow (detail/list, edit, cache update, invalidation and
failure/rollback), an infinite showcase flow (a screen under the five-artefact
catalogue rule, D11) and a hook consumer. Retain tests
using raw APIs so compatibility remains independently exercised.

**Exit:** binding/hook tests prove inference and lifecycle, including a
rebuild that hands in a recreated equal reference and starts no fetch and
restarts no timer (D4; `setOptions` still runs, as #84 needs), an
`Enabled.when` over outside state re-evaluated on such a rebuild, parameter
changes, identical recreated definitions, provider/client switches, unmount
and cancellation. Existing Playwright flows validate the migrated
user behaviour against their documented backends; a widget-only test is not
reported as backend/browser evidence.

### Phase 4 — Documentation, migration and release readiness

Lead new guides with definitions and typed references. Update
[query keys](../../website/docs/guides/query-keys.md),
[query options](../../website/docs/guides/query-options.md),
[Dart type safety](../../website/docs/dart-type-safety.md), filters, defaults,
infinite queries, mutation update/invalidation guides and hooks documentation.
Keep existing links stable. Publishable examples must have compiled twins under
the repository's documentation fence rules.

Explain direct key inference, explicit raw escape hatches, callback/upcast
limits, `select` versus cache type, null versus absence, and input identity.
Check the site's statements about TanStack's key typing: `dart-type-safety.md`
already credits `queryOptions()` and `DataTag`, and any page that says
TanStack cannot type keys is corrected (it supports global key registration
and query-options-associated data inference). State D10's limit, explicit
type arguments on a definition, where definitions are introduced.

**Exit:** migration examples and reference docs agree with the implemented API,
all validation gates below are green for the final feature commit, and a release
note accurately distinguishes compile-time guarantees from runtime checks.
The bumps are D11's table. Tags, package publishing and website
deployment are separate explicitly authorised actions.

## Acceptance and validation matrix

The following is future implementation acceptance, not results of writing this
plan. Phase 0 has since run the compile-time row, the widened receivers of
the runtime row and parts of the identity and filtering rows against the
prototype; they are acceptance again for the real module, and the same
fixtures are what checks them. Phase 1 has run them against the real
module, and its core tests cover the cache, identity, options and
filtering rows as far as the core alone can.

- **Compile-time:** wrong namespace/member, input shape, fetch return type,
  read assignment, write value, updater parameter/return, selector, page data
  and page parameter fail in focused analyzer fixtures. Positive controls
  demonstrate the expected inferred type. Test inline and extracted definitions,
  callbacks, collection inference and the minimum supported SDK.
- **Runtime types:** first write/seed uses the declared type, including nullable
  and sealed values. Conflicting raw entries fail with `QueryDataTypeError`
  before any write. Deliberately widened references, single and bulk, throw
  before any write: Dart's `TypeError` where Dart checks covariance (the VM,
  JIT and AOT, and dart2js at its default level, all at the call before the
  method body), `QueryDataTypeError` where dart2js `-O3`/`-O4` omits that
  check and D2's explicit check fires. A wrong input bound through a
  widened family is refused the same way, with `ArgumentError` at
  `-O3`/`-O4` (D2). dart2wasm at `-O3`/`-O4` is an unsound
  opt-in that traps uncatchably on the same misuse; Flutter's wasm default is
  `-O2`. That is a documented limit, and it rests on round 3's probe:
  Phase 0 did not run dart2wasm, and ran an AOT executable once by hand.
  No silent second cache entry created by a type token.
- **Identity:** same input/recreated definition shares data and in-flight work;
  different IDs/filters/tenants do not. Structural maps, value models, record
  limitations and mutable inputs have documented tested outcomes. Equal inputs
  of an equal definition give `==` references and `==` typed keys; options
  carry no equality promise (D4).
- **Filtering:** exact reference operations leave descendants alone; family
  operations include the intended inputs; namespace invalidation covers all
  descendants. A typed bulk read or update over a prefix holding an entry of
  another type, a wider type included, throws before any write (D7); the raw
  bulk update keeps writing into the wider one.
- **Semantics:** freshness, initial/placeholder data, select, retry, cancellation,
  background revalidation, structural sharing, timestamps and null/absence
  behave as the underlying client does. Infinite retries and pagination preserve
  the page/data relationship and cache type.
- **Lifecycle:** no client ownership inside reusable definitions, no eager
  fetches, leaked timers, duplicate observers or post-disposal
  notifications; a replaced repository is retained only until the next
  `setOptions` or the entry's collection, as with raw options (D4). No memo of references or closures anywhere
  (D4). Exercise two
  clients using the same definitions independently.
- **Integration:** core VM and Chrome suites, Flutter and hook VM/Chrome suites,
  affected examples and existing backend/Playwright flows. Use the repository
  clock/fake-async utilities for timing tests. Preserve upstream assertions and
  document actual divergences rather than weakening tests.
- **Repository gates:** follow current
  [CONTRIBUTING](../../CONTRIBUTING.md#the-gate) and
  [CI](../../.github/workflows/ci.yml): analyzer, formatter, test/coverage floors,
  doc snippets, dartdoc links, publish dry-runs, web builds, website checks and
  declared SDK-floor suites. Analyzer fixture execution is in both current and
  floor coverage since Phase 0 (`gates`, `floors`); the floor job's runtime
  tests alone are insufficient
  proof of static inference. Report local, CI and browser evidence separately.

For this plan-only commit, validate repository references, Markdown structure,
scope of the diff and `git diff --check`. No implementation tests or type-safety
proof are claimed, and no full application build is needed for this document.

## Migration and compatibility

Ship the capability additively. Keep raw `QueryKey`, client methods and existing
options constructors available with their current behaviour. Existing generic
calls must not break, and no major-version removal is part of this plan.

Migrate one operation at a time: move the existing key parts and fetch function
into a definition, confirm identical raw identity, then replace consumers and
cache writes with the typed reference. The task manager's keys already fit
the standard layout, so no migration adapter is needed for Phase 3. If a
later consumer has a legacy key shape the layout cannot express, an adapter
binds a real definition and is not a general-purpose unchecked
`TypedQueryKey<T>.fromRaw` constructor. Changing key layout intentionally is a cache identity
change and requires its own migration decision.

Raw and typed consumers can coexist when they agree on identity and exact data
type. Mixing them does not retroactively make the raw consumers statically safe.
A raw entry under a family's prefix with the family's exact type is simply
shared; one with another type, wider included, makes the family's typed bulk
calls throw (D7), and a typed single write to it throws too (D5).

A future opt-in analyzer rule can forbid raw key construction/access in a
consumer's application code, with deliberate allowlists for migrations and
library internals. It is not part of the initial runtime feature, and a library
cannot enable consumer lints automatically. No claim of project-wide enforcement
until that separate tool exists and is explicitly enabled.

## Principal risks and alternatives

- **Generic widening:** a prettier signature can weaken static checks. Use the
  analyzer proof as an API gate and retain runtime checks after deliberate erasure.
- **Facade duplication:** do not rebuild fetching, state, retries or subscriptions.
  Definition methods translate to existing operations with specified semantics.
- **Namespace ambiguity:** data prefixes, widget scopes and typed families
  are distinct. The provisional naming and D7's nesting rule make that
  distinction explicit.
- **Input omissions:** no Dart compiler can prove a hand-written `keyOf` includes
  every dependency, and the default, the input itself as the key part,
  includes all of it only when the input has value equality (D3: a record
  holding a collection does not). Central declarations, immutable inputs and targeted identity
  tests reduce this risk; backend schema validation remains separate.
- **Compatibility:** returning legacy options and exposing `rawKey` allow escape
  from the safe path. Document that boundary rather than claiming total lock-down
  or silently breaking the existing API.
- **Options churn, declined as a risk:** every call style runs `setOptions`
  per build already, by #84's design; a fresh closure per build adds one
  cache notification nobody subscribes to. Gating `setOptions` on equality
  would be the real regression (D4).
- **Web release builds:** dart2js `-O4` omits covariant parameter checks.
  D2 and D5 check explicitly; Open-7 proves it.
- **Lenient raw writes under a typed surface:** the raw `setQueryData` and
  `updateQueriesData` accept wider entries. The typed path checks exactly
  (D5, D7); a typed operation implemented by plain delegation would reopen
  the hole.
- **Undetected same-type collisions:** two definitions of one operation with
  different fetchers are indistinguishable to the cache and, as D3 argues, to
  any registry. The guide names it as an authoring rule.

Rejected as the primary design: only a string key factory (does not bind cache
data), only `QueryKey<T>` with a generic setter (does not prove write safety),
runtime assertions alone (too late and possibly debug-only), a definition
registry (D3) and compulsory code generation (unnecessary setup for the core
use case). An optional generator
and stricter project linting remain follow-ups.

## References

- [Query Key Factory](https://github.com/lukemorales/query-key-factory): central
  hierarchical declarations, colocated fetchers and prefix access.
- [tRPC TanStack integration](https://trpc.io/docs/client/tanstack-react-query/usage):
  typed procedure inputs, options and cache keys as the developer experience
  reference; this plan does not add a backend protocol or schema validation.
- [TanStack TypeScript support](https://tanstack.com/query/latest/docs/framework/react/typescript):
  registered key types and `queryOptions` data inference; heterogeneous bulk
  access has different typing requirements.
- [Dart unsafe variance diagnostic](https://dart.dev/tools/diagnostics/unsafe_variance):
  generic variance and runtime limitations; local fixtures must establish the
  guarantees of our chosen signatures on our supported SDKs.
- [Existing inference research](../research/dynamic-inference-guards.md) and
  [ADR-0001](../adr/0001-one-type-slot-for-plain-queries.md): preserve anchored
  output types and separate selection while extending the API.

## Review record

Three plan-review rounds, all on 2026-10-18, and then Phase 0's
measurements (2026-11-10), which changed the plan where the analyzer or a
run said otherwise. Every claim about the current code was
checked against the baseline before it was accepted, and round 2's findings
were each reproduced by the decider before the plan changed (the `-O4` case
by compiling with `dart compile js -O4` and running under node; the
inference case with `dart analyze`; the bulk and single-write leniency by
reading `_holds` and `_heldFor`).

### Round 1 (Fable, over `5edc932`)

| # | Finding | Reproduced | Outcome |
|---|---|---|---|
| R1 | The plan deferred its architecture to seven Phase 0 gates instead of deciding, against the AFK rule and the hooks plan's decision format | yes, by reading | §"Design decisions" became D1–D11 with options, answer and reason; six analyzer questions remain as Open-1 to Open-6 |
| R2 | A client-local definition registry for collision detection adds a lifetime for a check it cannot complete; the cache already throws on an exact-type mismatch | yes: `QueryCache.get` and the bulk operations throw `QueryDataTypeError` | D3 declines the registry; Phase 1 and the risk list changed with it |
| R3 | Typed family bulk operations need no membership mechanism: `getQueriesData` and `updateQueriesData` already check every entry under a prefix and throw before any write | yes, in `query_client.dart` | D7 adopts the existing semantics plus a documented no-nesting rule |
| R4 | No criterion for options equality: `DefaultedQueryOptions.==` compares `queryFn` by identity, so a fresh closure per build means `setOptions` per rebuild and churning hook keys | yes, `query_options.dart` line 1212 | D4, a Phase 0 fixture, Phase 1 and Phase 3 exits, the acceptance matrix and the risk list |
| R5 | Inference of a definition's type arguments from its closures yields `dynamic`, and the library cannot prevent it at the consumer | yes, by the earlier research | D10 requires explicit type arguments and documents the limit |
| R6 | A showcase infinite screen falls under the five-artefact catalogue rule | yes, showcase README | D11, Phase 3 |
| R7 | "Correct blanket statements that TanStack cannot type keys": the site already credits `queryOptions()`/`DataTag` | yes, `dart-type-safety.md` | Phase 4 item reworded as a check |
| R8 | The plan says "no major" but not which bump | yes | D11: minors |
| R9 | Whether `ref.options()` can be handed to `client.query` | yes: `QueryObserverOptionsBase` extends `QueryOptions` | Recorded under "Current behaviour"; no gate needed |

Round 2 found that R2, R3 and R4 above were only half right: the cache's
exact check covers reads, not writes (R2, R3), and options inequality costs
one notification, not a `setOptions` (R4). The rows stand as the record of
what round 1 believed; the decisions were rewritten.

### Round 2 (GPT-6-Astra via Codex CLI, and Opus 5.5, independently, over `cc18974`)

Both reviewers ran analyzer and runtime probes of their own (Astra on Dart
3.6.2, 3.10.7 and 3.13.5; Opus on 3.11.1 and 3.13.4 plus dart2js). Where
both found the same thing the row names both.

| # | Finding | Reproduced | Outcome |
|---|---|---|---|
| A1 / F1 | D4 would regress #84: every call style runs `setOptions` per build by design, hooks have no `keys`, `shouldFetchOptionally` runs regardless of equality; the Phase 3 "no `setOptions`" criterion could only be met by gating on equality | yes: `read_set.dart`, `controller_hook.dart`, `query_observer.dart` (`notifyObserverOptionsUpdated` is the only equality-dependent effect) | D4 rewritten: references and typed keys are values, options are not; Phase 3 exit and the risk list changed |
| A2 / F2 | D4's equality could not be delivered: `QueryOptions` has no `==` on purpose, closures are `==` only to themselves, a per-reference closure dies with the reference, a per-family memo grows per input, a shared memo would keep a stale fetcher | yes | D4 (b); no memo; Open-4 closed |
| A3 / F3 | The bulk-update claim was false: `updateQueriesData` uses `_heldFor`/`_holds` (value checks), so a wider entry or an empty foreign entry passes; a same-type descendant is updated | yes, `query_client.dart` | D7 adds the exact preflight to the typed path; R2/R3 marked half right |
| F4 | Single typed writes delegating to `setQueryData` land in a wider raw entry, then the reference's own read throws | yes, `_holds` | D5: typed writes exact |
| A4 | An extracted narrower `InfiniteData` passes `setQueryData<InfiniteData<num, int>>` and the next `copyWith` throws | yes, reading `_holds` and `InfiniteData.copyWith` | D5: infinite writes normalise to the declared type arguments |
| A5 / F11 | Ordinary and infinite definitions collide only when the types differ; the kind is never checked | yes, `query_cache.dart` | D3 names it as undetected |
| A6 | A mixed-type list for `QueriesObserver`/`useQueries` infers `Object` without an upcast | yes, `queries_observer.dart`, `use_queries.dart` | D9: outside the guarantee, a documented negative |
| A7 / F7 | Override surface, infinite options type and client/input-dependent options were API decisions left open; `QueryDefaults` erases callback types; the task manager seeds `initialData` from the client | yes, `queries.dart` | D6: `configure(base, input)` plus `copyWith`, client-dependent seeding stays with the consumer; D8: infinite options type |
| A8 / F10 | Dependency floors and the 0.x rule: hooks `0.2.0` is the breaking bump, the examples' constraints and the inter-package floors must move with the release | yes, `releasing.md`, the pubspecs | D11 rewritten |
| A9 / F5 | A widened receiver throws Dart's covariance `TypeError`, not the cache's error; dart2js `-O4` omits the check and the write passes; an explicit check through `Object?` fires | yes, compiled and run | D2 rewritten; Open-3 closed; Open-7 added |
| A10 / F6 | Without type arguments a family infers `Object?`, not `dynamic`; `strict-inference` is silent; a declared type anchors it; the cited research is about a different slot; the binding's debug backstop catches `Object?` | yes, `dart analyze` | D10 rewritten with the backstop |
| F8 | A family calling a sibling cannot be written in an initializer list (`implicit_this_reference_in_initializer`) | yes, by the language | The example uses `late final` |
| F9 | Open-5 and Open-6 were decidable now | yes | D1 (a definition is a reference); Open-6 closed by the task manager's keys |
| F11 | D3 cited a risk-list sentence from the first draft; `DefaultedQueryOptions.==` compares `queryFn` with `==`, not identity; hot reload re-runs no top-level initialiser; `QueryRef` beside `QueryObserverRef`; `TypedQueryKey` equality unspecified; `IsFetchingController`, `QueryListener` and the hooks' counts unnamed | yes | All worded in D1, D3, D9 and "Current behaviour" |
| F1 (detail) | A `QueryObserverOptionsUpdated` cache event | yes; this row first said "not by that name", which round 3 showed wrong (`query_cache.dart`, the public event class) | Named in D4, with its two subscribers |

Both reviewers confirmed D1's wrapper over the final `QueryKey`, D2's core
argument (the generic setter widens, the receiver-anchored calls reject),
D5's absence/null distinction, D6's reuse of `withSelect` and the defaults
order, D11's catalogue rule, and that `QueryObserverOptionsBase` extends
`QueryOptions`.

### Round 3 (GPT-6-Astra via Codex CLI, and Opus 5.5, independently, over `df889db`, scoped to round 2's diff)

Neither reviewer found a P1. Astra probed on Dart 3.6.2, 3.11.1 and 3.13.5
including dart2js `-O4`; Opus on 3.11.1 with dart2js at default and `-O4`
and dart2wasm at `-O2` to `-O4`. The decider checked each claim against the
source before changing the plan.

| # | Finding | Reproduced | Outcome |
|---|---|---|---|
| A-1 | Infinite normalisation before `setData` is undone by a custom `structuralSharing` returning the narrower value, and by narrow `initialData` | yes, `Query.setData` stores the sharing callback's result | D5: the definition wraps its own sharing and initial data; a per-use `copyWith` is outside |
| A-2 / O-P3-8 | D10's backstop on `TInput` refuses a deliberate `Object?` input and `void` | yes, probe: `void` and `Object?` refused, `Object` and `String?` pass | D10: kept, with the trade-off and the escape stated; `void` made unnecessary by zero-input definitions |
| A-3 / O-P3-2 | D11's example floors and the "only if" condition were wrong; Phase 4 still said "minors" | yes, the pubspecs and `releasing.md` | D11 rewritten as a table: all three ship, binding a minor because it re-exports the core, examples at the first supporting releases, `pub downgrade` before tagging |
| A-4 / O-P2-2 | The runtime acceptance row demanded `QueryDataTypeError` where the VM throws `TypeError` first; dart2wasm `-O3`/`-O4` traps | yes, D2's own text; the wasm trap taken from Opus's probe | Row rewritten |
| A-5 | The mixed list of D9 compiles, so it is not an analyzer negative | yes | Open-2 and D9: a boundary fixture with a runtime assertion |
| A-6 / O-P3-1 | D4 said nothing subscribes to the options event; `IsFetchingController` and `useIsFetching` recount on every event; the event class exists | yes | D4 wording, acceptance as parity with raw options; round 2's F1-detail row corrected |
| O-P2-1 | D7 delegating to the raw bulk update leaves updater results unchecked at `-O4`, because `_holds` passes on an exact entry type | yes, `_holds` | D5 and D7 share one shape with the updater wrapped; Open-7 covers single and bulk |
| O-P2-3 | D8 contradicted D1/D4/D6: an infinite reference cannot be a `QueryRef` overriding `options()` | yes, both options classes are `final` | D1: sealed `QueryEntryRef<T>`, `QueryRef<T>`, `InfiniteQueryRef<P, Q>` |
| O-P2-4 | No zero-input infinite definition, though every shipped infinite query is zero-input | yes, the three examples | `InfiniteQueryDefinition<P, Q>` in D1 and D8; D10 covers both infinite constructors |
| O-P3-3 | `configure` only fit a plain family; the infinite required fields are a tenth place; key and fetcher could be re-pinned; per-use `copyWith` cannot unset | yes, `infinite_query.dart` constructor | D6: `configure` per kind, re-pin, the cost stated and accepted |
| O-P3-4 | `peek` unnecessary; write and update lacked `updatedAt`; an entry created by a typed write used bare options | yes | D5's numbered shape |
| O-P3-5 | Normalisation details: unmodifiable copies, skip when exact, every updater result | yes, `InfiniteData` constructor and `==` | D5 |
| O-P3-6 | `context.client` is not public | yes, it is on the internal scope element | D6: `QueryClientProvider.of(context)` / `useQueryClient()`; the task manager keeps a wrapper |
| O-P3-7 | D4's parity test cannot fail because of D4; what D4 decides is untested; the lifecycle row contradicted D4 | yes | D4 adds the new-fetcher test; the lifecycle row qualified |

Both reviewers confirmed as answered: A1/F1, A2/F2 (no options equality, no
memo), A3/F3 and F4 for ordinary calls, A5, A6, A9/F5 in D2's text (the
explicit check survives `-O4` for values, updater results and nullable
`T`), A10/F6, F8, F9, F11. With round 3 the plan review stops: the open
questions are Open-1, Open-2 and Open-7, and Phase 0 answers them.

### Phase 0 (TQ0, 2026-11-10)

Every change Phase 0 made to this plan, with what showed it. "Run" means
the fixture runner on Dart 3.6.2, 3.10.7 and 3.13.4; the paths are under
`tool/typed_query_fixtures/`.

| # | What changed | Evidence | Where |
|---|---|---|---|
| P0-1 | `keyOf` is optional; without it the input is the one key part after the name. The product owner's amendment, kept because it holds | inference unchanged with and without (`boundary/untyped_definition.dart`); observations `K-1` to `K-8` | D3, the DX example, the surface |
| P0-2 | A new limit under P0-1: a record input holding a collection needs a `keyOf`, undetected | `K-6`: unequal without, equal with | D3, limit 8 |
| P0-3 | One declaration form, the constructors; no factory methods on the namespace. The product owner's question | both forms side by side infer the same and hit the same backstop (`positive/declaration_forms.dart`, `D10-1`, `D10-2`) | D12 (new) |
| P0-4 | `QueryRef` keeps its name | `positive/reference_names.dart`, an `invalid_assignment` between the two types | D1 |
| P0-5 | A tenth type, the sealed `QueryTarget`: the lifecycle operations and the filter adapter in one place | a list of a family's reference and a definition of another data type infers `List<QueryTarget>` (`boundary/mixed_list.dart`); an exhaustive switch (`positive/reference_names.dart`). The row first read "a list of references of two data types": true of two classes, false of one (S0-1) | D1, D7 |
| P0-6 | D2's claim narrowed: the generic *value* setter widens, a generic *updater* does not | `boundary/generic_setter.dart` compiles with `T = Object`; `negative/generic_setter.dart` refuses the updater | D2 |
| P0-7 | A family's `call` checks its input through `Object?` and throws `ArgumentError` | `O7-input-1`, `-2`: `TypeError` on the VM, `ArgumentError` at `-O3`/`-O4` | D2 |
| P0-8 | A reference's `==` is its kind and its typed key; namespace and name only through the raw key | `D4-8` to `D4-10` | D4 |
| P0-9 | `write` returns `T`, `update` returns `T?` | `positive/plain_reference.dart` | D5 |
| P0-10 | `queryFn` is optional on the plain definitions (the key-only definition is a parameter, not another class); no public typedef; no `isFetching` on a target | `positive/typed_inputs.dart` (`seeded`) | D6 |
| P0-11 | The bulk operations are named `readAll` and `updateAll` and return `List<(TypedQueryKey<T>, T?)>`; the filter adapter is `QueryTarget.filters()` | `positive/typed_inputs.dart`, `D7-1` to `D7-13` | D7 |
| P0-12 | D10 narrowed to a family's input: a zero-input definition with a fetcher infers exactly, plain and infinite. The backstop is recorded as debug-only, with what a release build does | the table under D10; `D10-1` to `D10-8` | D10 |
| P0-13 | The hooks release is `0.1.3`, its example `^0.1.3` | tags `query_kit_hooks-v0.1.1`, `-v0.1.2` | D11 |
| P0-14 | Phase 1 lands the whole surface by promoting the prototype; Phase 2 adds depth. Phase 1's decision record is ADR-0007 | the sealed hierarchy needs one library, and Phase 1's exit asks for every fixture against the real exports; `docs/adr/` holds 0005 and 0006 | Phase 1, Phase 2, the implementation map |
| P0-15 | The six refused DX lines carry their diagnostic codes; `detial` is `undefined_method`, not a getter | `negative/dx_misuses.dart` | the DX section |
| P0-16 | Two things recorded as not proven: the definition's own `structuralSharing` and `initialData` are not wrapped by the prototype, and dart2wasm was not run | the prototype's source | D5, limits 2 and 15, the acceptance matrix |

Three predictions made while writing the fixtures were wrong and are kept
here because a wrong prediction is a finding too: that a generic updater
would widen like the generic setter (it is refused, P0-6); that a list of
two references would be a `List<QueryRef<Object>>` (it is a
`List<QueryTarget>`, P0-5); and that node would run a dart2js program
with timers as it is (it ends silently, exit code 0, after the first
timer, because the compiled code reaches for `self`; the runner defines
it, and an empty run would have compared as a failure against the
recorded file either way).

Two of those sentences did not survive the review of TQ0. The second
prediction was right for the case it was made about and the correction
overreached: two references of one class *are* a `List<QueryRef<Object>>`
(S0-1). And "an empty run would have compared as a failure against the
recorded file" holds only while the recorded file is not empty too
(S0-5).

### Phase 1 (TQ1, 2026-11-10)

Where the implementation left this plan, or settled what it had not said.
Each row was a choice between named options; the options are under the
decision the last column names. "Test" means a case in
`packages/query_kit/test/query_definition_test.dart` or
`infinite_query_definition_test.dart`. No second reviewer has read this
phase: the rows are the implementer's own.

| # | What changed or was settled | Evidence | Where |
|---|---|---|---|
| P1-1 | The typed bulk update is its own pass in the raw update's order, not the raw update with a wrapped updater | reading `updateQueriesData`: an empty entry of another type passes its first pass, `_holds` passes on type alone, the second pass writes leniently; tests with the raw call as the control | D7, Phase 1 |
| P1-2 | What an updater that touches the cache does to a bulk update: captured data, a removed entry re-created bare, an added entry ignored, a swapped wider entry refused at its write (since TQ2 before the first write, P2-2) | tests, each beside the raw call | D7, limit 16 |
| P1-3 | A bulk update's writes are not held back for a cache listener or an observer; only a notify-manager subscriber waits for the batch. The dartdoc first said otherwise | a test that failed as first written, then rewritten as parity with the raw call | D7 |
| P1-4 | `update` resolves the entry again after the updater ran | tests: an updater that removes the entry, and one that swaps it | D5 |
| P1-5 | The definition's own `structuralSharing` and `initialData` are wrapped in Phase 1, not Phase 2; the default sharing and the opt-out instance are not wrapped; an exact `InitialData.value` keeps its instance | tests, with a raw definition as the control that the narrower value is otherwise stored | D5, limit 15, Phase 2 |
| P1-6 | A key's or the client's default `structuralSharing` is outside the normalisation | `QueryDefaults` types its callback `Object?`, and the client's check on what it returns is a subtype test, which a narrower `InfiniteData` passes; a test for both levels | D5, limit 15 |
| P1-7 | A `null` first page param cannot be changed by `configure`: `StateError` when the options are made. Options: silently keep the definition's (a `copyWith` reads `null` as "keep", so it would silently take `configure`'s instead); an assertion (absent in release); rebuild the options field by field (a tenth place per option); throw. Answer: throw | test | D6, limit 17 |
| P1-8 | `configure` may supply what a definition lacks: a key-only definition's fetch function, a missing `getPreviousPageParam` | tests | D6 |
| P1-9 | `QueryDataTypeError.actual` is the entry's type for an entry mismatch and the value's `runtimeType` for a value mismatch | tests for the first; the observations at `-O3`/`-O4` for the second | D5 |
| P1-10 | Two lines are unreachable on the VM (the two `throw`s behind Dart's covariance check) and are proven by the `-O3`/`-O4` observations; coverage 99.84 % with them counted as missed | `tool/check_coverage.dart` | Phase 1 |
| P1-11 | `reset`'s `cancelRefetch` is passed on and cannot be observed: a reset cancels the fetch in flight whatever it is given | a test that could not be written to fail. Wrong: TQ2 wrote it (P2-3) | D7 |
| P1-12 | The decision record is ADR-0007 and the ticket's "ADR-0005" is noted in it | `docs/adr/` | Phase 1 |
| P1-13 | No version or CHANGELOG change in Phase 1 | D11 puts the bumps in Phase 4 | D11 |

### Review of TQ0 (GPT-6.1-Sol, over `9aad67b`, worked in TQ2)

Five findings, each reproduced against the code before anything changed.
"Run" is the fixture runner on Dart 3.6.2, 3.10.7 and 3.13.4.

| # | Finding | Reproduced | Outcome |
|---|---|---|---|
| S0-1 (P1) | A list of references of two data types infers `List<QueryRef<Object>>`, not `List<QueryTarget>`; `refs.first.write(client, 'wrong')` compiles | yes. The analyzer's own answer, literal by literal (D9's table), on language 3.6 and 3.10: one class at two data types meets at that class, two classes at `QueryTarget`. The write throws `TypeError` on the VM and dart2js default and `QueryDataTypeError` at `-O3`/`-O4`, and creates no entry | The claim is narrowed (the product owner's decision), no code changed. D1, D9 and P0-5 corrected; limit 18; `boundary/mixed_list.dart` pins the inferred types; `positive/target_list.dart` and five lines of `negative/surface_limits.dart` hold the declared `<QueryTarget>[…]`; observations `D9-4` to `D9-11`; the barrel's limits list and `QueryTarget`'s dartdoc say it |
| S0-2 (P2) | `configure` may return options of a narrower data type | yes. VM: a `TypeError` from inside the re-pin's `copyWith`, naming a function type. dart2js `-O4`: no error, the narrower options handed out | Fixed: the runtime type of what `configure` returned is compared with the definition's options type before any `copyWith`; `StateError` with the key and both types. Nine tests on the four kinds, observations `D6-1` to `D6-5` identical on all five runtimes. D6, limit 19 |
| S0-3 (P2) | A plain definition typed `InfiniteData<P, Q>` bypasses the infinite normalisation | yes. The entry is exact, the stored value keeps its narrower type arguments, a `copyWith` typed for the entry throws on checked runtimes | The promise is narrowed (the product owner's decision), no code changed. D3, D5, limit 20; a test with the infinite definition as the control, observations `D5-infinite-7` and `-8`; the dartdoc of `QueryDefinition` and `InfiniteQueryRef`. No sound way to normalise from a plain definition exists (D5 names the two cheap refusals that were not built) |
| S0-4 (P2) | The re-pin does not restore a declared `null`: a `configure` can add a fetch function or a `getPreviousPageParam` the definition left out | yes, and it is what TQ1 built on purpose (P1-8) | Kept (the product owner's decision), no code changed. D6 states the rule: the definition pins what it declares; what it leaves unset, `configure` may set. The constructors' dartdoc says it; both halves are tests on the plain and the infinite kind, the zero-input and the family form |
| S0-5 (P2) | The fixture runner can pass vacuously: with the negative directory gone and an observation program that prints nothing, a re-record is green | yes: `OK: 1 fixture files, 0 misuses refused`, exit code 0, on a copy of the reviewer's tree | Fixed: an inventory the tree must match exactly, floors in the code, a check of every runtime's output, `--record` as the one path that moves a pin and that prints what moved, and `--self-test` (31 cases, the reviewer's tree among them) in CI before the runner. On that tree the runner now reports nine failures and exits with 1; `--record` there refuses and writes nothing. Phase 0's section |

What the review did not change: no signature, no existing fixture's
expectation, and no existing test except the one whose behaviour D7
changed on purpose in the same ticket (P2-2).

### Phase 2 (TQ2, 2026-11-10)

Where TQ2 left this plan or settled what it had not said, beyond the
five rows above. No second reviewer has read this phase: the rows are
the implementer's own, and the ticket ends in a review.

| # | What changed or was settled | Evidence | Where |
|---|---|---|---|
| P2-1 | The mutation recipes are six functions returning `MutationOptions`, in a test file of their own; no mutation definition, no helper added to the library | 22 cases | Phase 2 |
| P2-2 | A bulk update looks its entries up once more before the first write, so an updater's swap is refused with nothing written. TQ1's case for that swap asserted the earlier writes stayed; it now asserts none was made, and a new case holds what is left of the limit, a listener's swap, beside the raw call | tests | D7, limit 16 |
| P2-3 | `reset(cancelRefetch:)` is observable after all, for an entry the reset leaves with data, and has three cases. P1-11's "cannot be observed" was wrong | tests; the "off" case fails against a copy of the library that drops the argument | D7, Phase 2 |
| P2-4 | The two lines the VM cannot reach stay counted as missed; no `coverage:ignore`, no lowered floor | `tool/check_coverage.dart`: 3786 of 3792, 99.84 % | Phase 2 |
| P2-5 | A rollback that must tell absence, an entry without data and a stored `null` apart snapshots `state`, and restores an entry without data with `reset`, which is not the state it had: an error it held, or a fetch failure count, is gone. The exact restore needs the raw cache | the recipe's cases; reported to the product owner as a possible helper, not built | Phase 2, D5 |
| P2-6 | A snapshot taken with `readAll` cannot be written back by key: a `TypedQueryKey` has no `write`, and `updateAll`'s updater is not told which entry it is called for. The recipe restores through the data's own id | recipe 5; reported, not built | D7 |
| P2-7 | The first optimistic write of an entry whose rollback is a plain `write` gets a new timestamp on rollback; a rollback through the snapshot keeps the old one (`updatedAt:`) | recipe 2's cases assert the kept timestamp; the last case compares the cache without timestamps because recipe 1's rollback moves one | Phase 2 |
