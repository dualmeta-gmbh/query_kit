# Plan: native typed query definitions

Status: proposed implementation plan, revised after three review rounds
(Fable, then GPT-6-Astra and Opus 5.5 independently twice, all 2026-10-18;
the [review record](#review-record) at the end says what each finding
became). Round 2 found that three decisions of round 1 rested on wrong claims
about the current code; round 3, scoped to round 2's diff, found no P1 and
closed the gaps round 2's fixes left. Further plan reviews were judged to
give diminishing returns; the remaining questions are Phase 0's. No feature code or type-safety spike has been implemented or
validated by this document.

Date: 2026-10-18. Repository baseline: `a5afe7d` (`main`).

Decider: the agent, under the AFK rule of map
[#1](https://github.com/dualmeta-gmbh/query_kit/issues/1). Every decision
below names the options, the answer and the reason, so it can be reopened
from this document alone. Only what needs an analyzer to answer stays open
for Phase 0, and the [open questions](#open-questions-for-phase-0) list says
which those are.

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

All names and Dart examples below describe a proposed API, not working code.
Phase 0 must settle signatures and prove inference before these examples become
public documentation.

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
    keyOf: (id) => [id],
    queryFn: (id, context) =>
        _repository.device(id, signal: context.signal),
  );

  Future<void> invalidate(QueryClient client) => namespace.invalidate(client);
}

final queries = (devices: DeviceQueries(repository));
final device = queries.devices.detail('d1'); // QueryRef<Device>
```

The definition above produces the structural raw key
`['devices', 'detail', 'd1']`. Namespace and operation strings occur in the
definition, not throughout the application. Static queries need an equally
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

These ordinary call sites must be rejected statically:

```dart
queries.devces.detail('d1');
queries.devices.detial('d1');
queries.devices.detail(123);
device.write(client, 'not a device');
device.update(client, (_) => 42);
String? wrongRead = device.key.read(client);
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
  - `InfiniteQueryRef<TPageData, TPageParam>` implements
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
  which. Renaming is Phase 0's call if the fixtures read badly.
- `QueryNamespace` selects entries by prefix without claiming a data type.
  It supports lifecycle operations and filters, not typed data reads/writes.

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

### D3. Identity is structural, and nothing else

**Options:** (a) raw identity from namespace parts, operation name and the
frozen parts of `keyOf(input)`, with no metadata; (b) the same identity plus a
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

Consequences: explicit stable names; no identity from closure identity,
`runtimeType.toString()`, construction order or a random token. Recreating a
definition with the same schema addresses the same entries, across widget
rebuilds and hot reload, because nothing but the parts is compared. Every
value that changes the result belongs in the identity or in a separate client:
IDs, tenant/account, locale, filters, backend environment. A captured
repository object is a dependency, not an identity component. Switching
accounts must not reuse another account's data.

`keyOf` is explicit for general inputs: Dart cannot inspect record fields
generically or prove that captured dependencies are included. Primitive inputs
are straightforward; records and custom models need documented value equality
or explicit conversion to supported parts. Collection key parts are frozen once
when binding. Inputs must be immutable, or the caller takes a snapshot; a
retained input must not change what is fetched after its key was computed.
`keyOf` freezing does not clone a user model.

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
  that are references) is namespace, name, kind, the cache type and the raw key;
  `TypedQueryKey.==` is the raw key and `TCacheData`. A hook or a user may
  key on a reference. The fetcher is not part of it, so two definitions of
  one operation with different fetchers produce equal references, and the
  observer takes the fetcher it was last handed.
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
| hooks | `0.1.1`, `query_kit_flutter: ^1.2.0` | it re-exports the binding; in 0.x a minor is the breaking bump (`docs/releasing.md`), so an addition is a patch |

The shipped examples name the first release that has what they use (a
constraint names the oldest version that works, `docs/releasing.md`): the
binding's example `query_kit_flutter: ^1.2.0`, the hooks example
`query_kit_hooks: ^0.1.1`. Each is resolved without its workspace override
and at its lowest allowed dependency set (`pub downgrade`) before tagging,
because resolving the latest versions would not notice a floor that is too
low. Publish in dependency order: core, binding, hooks.

### Open questions for Phase 0

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

## Implementation map

Paths are the baseline integration points; new file names are provisional.

- Core: introduce cohesive definition/reference/typed-key modules under
  [packages/query_kit/lib/src](../../packages/query_kit/lib/src/), exported by
  [query_kit.dart](../../packages/query_kit/lib/query_kit.dart).
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
- Evidence: add analyzer fixtures and a focused runner under `tool/` with
  intentional failures kept outside ordinary analyzed Dart source; extend core,
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

### Phase 1 — Ordinary definitions and cache operations

Implement namespaces, static definitions, families, references and typed keys.
Thread them into the existing cache with typed reads/state, writes/updates,
options, fetch and exact lifecycle operations. Identity is structural (D3):
no registry, no metadata. Preserve runtime checking and raw compatibility.

**Exit:** core tests demonstrate same-key sharing between typed/raw consumers,
declared-type first writes, exact typed writes refusing a wider raw entry
(D5), nullable semantics, stable recreation, equal references from equal
inputs (D4), defaults, exact/prefix isolation and no extra
fetch/subscription merely from binding.
All Phase 0 fixtures run against the real public exports.

### Phase 2 — Families, infinite queries and mutation workflows

Implement family bulk operations as D7 says, infinite definitions,
typed filters and mutation recipes. Keep all fetching and paging in the current
client/observer machinery. Exercise cancellation and optimistic rollback with
an in-flight request and validate stored type and state after each transition.

**Exit:** page and input type fixtures pass; runtime tests cover an ordinary
and an infinite definition on one key with different types (the cache's own
type error) and with the same `InfiniteData` type (shared, documented),
sibling/descendant isolation, a nested key of another type under a family
prefix making the bulk call throw before any write, a wider raw entry under
a family prefix making the typed bulk update throw where the raw one writes,
an extracted narrower `InfiniteData` normalised on write, stored null,
absence and rollback. Runtime failures do not partially corrupt the cache.

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
plan.

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
  check and D2's explicit check fires. dart2wasm at `-O3`/`-O4` is an unsound
  opt-in that traps uncatchably on the same misuse; Flutter's wasm default is
  `-O2`. That is a documented limit. No silent second cache entry created by
  a type token.
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
  declared SDK-floor suites. Add analyzer fixture execution to both current and
  floor coverage; the current floor job's runtime tests alone are insufficient
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
  every dependency. Central declarations, immutable inputs and targeted identity
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

Two rounds so far, all on 2026-10-18. Every claim about the current code was
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
