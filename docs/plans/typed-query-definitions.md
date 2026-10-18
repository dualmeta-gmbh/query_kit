# Plan: native typed query definitions

Status: proposed implementation plan, revised after one review (Fable,
2026-10-18; the [review record](#review-record) at the end says what each
finding became). No feature code or type-safety spike has been implemented or
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

The current task delivers this plan only. Implementation, issue creation,
publishing, deployment and a generator are outside this task. Before feature
implementation, record the API decision in the wayfinder described by
[CONTRIBUTING](../../CONTRIBUTING.md#where-the-plan-lives); no new issue or
accepted ADR is implied by this local plan.

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
- The bulk reads and updates (`getQueriesData`, `updateQueriesData`) already
  check every entry under a prefix against the exact requested type and throw
  `QueryDataTypeError` before anything is written. A prefix spanning two data
  types is therefore loud today, not silent.
- `DefaultedQueryOptions.==` compares `queryFn` by identity
  (`query_options.dart`, the `==` near line 1212). Options that carry a fresh
  closure on every build are unequal on every build; the binding's controllers
  and the hooks' `keys` then see a change each time. Hand-written inline
  `queryFn`s have this problem today.
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
  DeviceQueries(DeviceRepository repository)
      : detail = QueryFamily<String, Device>(
          namespace: namespace,
          name: 'detail',
          keyOf: (id) => [id],
          queryFn: (id, context) =>
              repository.device(id, signal: context.signal),
        );

  static final namespace = QueryNamespace(['devices']);
  final QueryFamily<String, Device> detail;

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
- `QueryRef<TCacheData>` binds a definition and input, carries executable
  options, and exposes operations whose data type comes from that reference.
  It does not retain a client, mount observers, fetch or register timers merely
  because it was constructed.
- `TypedQueryKey<TCacheData>` wraps the existing raw `QueryKey` and retains the
  cache type for key-only reads and state access. Creation goes through
  definitions and references, not a public arbitrary `fromRaw<T>` cast.
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
reference and fails at runtime with the cache's existing type error. Explicit
upcasts, raw generics, `dynamic` and dishonest casts remain boundaries; the
production runtime checks stay, and the fixtures test widened receivers as
well as natural calls. The acceptance claim is the tested typed surface, not
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

**Why:** the cache already enforces one exact data type per key and throws
`QueryDataTypeError` for the reads and writes a conflicting definition would
make, and `InfiniteData` is a type like any other, so an ordinary and an
infinite definition on the same key collide there too. A registry would add a
lifetime (remove, clear, dispose, two clients, hot reload) and lookup cost
for a check it cannot complete: two same-named, same-typed fetchers with
different meaning are indistinguishable to it, and recreated closures are
equivalent but not identical. The plan's own risk list named that cost. (c)
breaks recreation and hot reload, and hides a collision as a second entry.

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

### D4. A reference and its options are values

**Options:** (a) `ref.options()` builds fresh options with a fresh `queryFn`
closure on every call; (b) a family creates the input-bound `queryFn` once per
reference, caches the reference's base options, and `QueryRef` has `==` and
`hashCode` over its definition and typed key, so an equal input yields equal
options and equal references across builds.

**Answer:** (b).

**Why:** `DefaultedQueryOptions.==` compares `queryFn` by identity. With (a)
every rebuild hands the controller unequal options; `setOptions` runs and the
observer re-evaluates `shouldFetchOptionally` each time, and a hook keyed on
the options or the reference re-subscribes on every build. Inline `queryFn`s
have this cost today; a definition is the first place the library can remove
it, and the plan treats that as a requirement rather than a nicety.

Consequences: `QueryFamily.call(input)` returns a reference whose options,
reached through `options()`, are `==` to those of another reference built
from an equal input of an equal definition. Two definitions are equal when
their namespace, name, kind and cache type are equal; the fetch function is
not compared, so two definitions of one operation with different fetchers
produce equal references and the last `setOptions` wins, as with raw options
today. The exact mechanism (a per-family memo keyed by the typed key, or a
closure created in `call` and held by the reference) is Open-4.

### D5. Declared cache types, absence and null

**Options:** (a) infer the entry type afresh from each written value, as the
raw `setQueryData` does for an entry it creates; (b) every typed write or seed
uses the definition's declared type.

**Answer:** (b).

**Why:** the raw path infers narrowly because it has no other source; a
definition has one. A sealed base type receiving a concrete variant,
`List<Device>` receiving a narrow literal and `Device?` receiving a `Device`
must create an entry of the declared type, or the next typed read throws.

- Every typed read uses the exact declared type. An existing incompatible raw
  entry is rejected with the existing `QueryDataTypeError`, not changed.
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
- Definition defaults and per-use overrides set behaviour (freshness, retry,
  enabled, placeholder/initial data, refetch rules) with the data type of the
  definition. Overrides take no replacement key, fetch function or input. The
  returned options still expose `copyWith`; using it to replace identity or
  function is a documented exit from the safe path, not a prevented one.
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
(b) a family's bulk operation is the prefix `[...namespace, name]` with the
existing `getQueriesData` / `updateQueriesData` semantics: every selected
entry is checked against the exact cache type and the whole call throws
before any write; (c) no typed bulk operations.

**Answer:** (b).

**Why:** (a) is the registry D3 declined, under another name. (b) is already
the behaviour of the raw bulk API, so the typed family adds a type to it and
nothing else. (c) gives up the one bulk case users ask for (patch every
cached detail after a list write).

- Reference lifecycle operations are exact. Family operations select every
  input of the family. Namespace operations select the structural prefix,
  descendants included. Active/inactive filters, refetch type and cancellation
  pass through a typed filter adapter.
- Keys nested under a family's prefix (`['devices', 'detail', id, 'history']`)
  are not supported and are documented as such; a nested operation gets its
  own name. If one exists anyway, the bulk call throws, as it does today.
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

The page function receives the typed input plus the existing typed page
context. Initial/next/previous page parameters, max pages, refetch direction,
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
record combination; homogeneous `useQueries`/`QueriesObserver` collections do
not erase types to accept mixed definitions.

Mutation definitions are outside this feature. Existing mutation callbacks
use typed references for cancellation, optimistic writes, snapshots, rollback,
server-response writes and family invalidation. Definitions do not solve
concurrent optimistic ordering or validate backend JSON; the example says so.

### D10. Explicit type arguments on a definition are a documented limit

**Options:** (a) rely on inference of `TInput` and `TCacheData` from the
`keyOf` and `queryFn` closures; (b) require explicit type arguments on
`QueryFamily` and `QueryDefinition` and say so.

**Answer:** (b).

**Why:** `QueryFamily(keyOf: (id) => [id], queryFn: (id, c) => ...)` has no
source for `TInput` but the closures' own parameters, which take their type
from the context; the result is `dynamic`, and the only diagnostic that
catches it is the `strict-inference` analyzer mode, which is off by default
and scoped to the consumer's own package
([research](../research/dynamic-inference-guards.md)). A library cannot
enforce it. The examples write the arguments; the guide says why; a Phase 0
fixture records what each SDK infers without them, so the claim is measured.

### D11. Showcase and versions

A new or changed showcase screen for the infinite flow follows the showcase's
five-artefact catalogue rule (`examples/showcase/README.md`, "The
catalogue"), and `catalogue_test.dart` must hold. The feature is additive, so
it ships as a minor: core `1.1.0`, binding `1.2.0`, hooks `0.2.0`, each with
its changelog entry; no major and no removal.

### Open questions for Phase 0

Only these stay open; each needs an analyzer or a measurement, not a
decision.

- **Open-1, inference:** which positive shapes infer exact types without
  annotations at the call site (reads, writes, updaters, selectors, page
  data) on Dart 3.6 and the CI SDK, and what each infers without the type
  arguments D10 requires.
- **Open-2, negative fixtures:** that each listed misuse fails at the intended
  location with the intended diagnostic, including the unsafe generic setter
  of D2 as the control that shows why the receiver-anchored shape is needed.
- **Open-3, widened receivers:** the exact runtime failure of `write` on a
  `QueryRef<Object?>` and whether a callback field versus a method changes
  what the analyzer reports.
- **Open-4, equality mechanism (D4):** per-family memo keyed by the typed key
  versus a closure created in `call` and held by the reference; measured by
  the options-equality fixture and by a check that no reference retains a
  client.
- **Open-5, zero-input declarations:** the `QueryDefinition<T>` constructor
  shape that avoids `null` or `dynamic` arguments at call sites.
- **Open-6, migration adapter:** whether the selected task-manager flow needs
  a legacy key layout the standard namespace layout cannot express.

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

Answer Open-1 to Open-6 and record each answer under its decision. Add one
fixture that is not about types: two references built from equal inputs of
an equal definition produce `==` options and `==` references (D4), and a
reference holds no client.

**Exit:** executable positive/negative evidence on both SDKs, the
options-equality fixture, a recorded final surface and explicit limits. If a desired syntax cannot uphold a guarantee,
revise the syntax or narrow the claim before proceeding; do not replace a
promised compile error with an undocumented debug assertion.

### Phase 1 — Ordinary definitions and cache operations

Implement namespaces, static definitions, families, references and typed keys.
Thread them into the existing cache with typed reads/state, writes/updates,
options, fetch and exact lifecycle operations. Identity is structural (D3):
no registry, no metadata. Preserve runtime checking and raw compatibility.

**Exit:** core tests demonstrate same-key sharing between typed/raw consumers,
declared-type first writes, nullable semantics, stable recreation, equal
options and references from equal inputs (D4), defaults, exact/prefix
isolation and no extra fetch/subscription merely from binding.
All Phase 0 fixtures run against the real public exports.

### Phase 2 — Families, infinite queries and mutation workflows

Implement family bulk operations as D7 says, infinite definitions,
typed filters and mutation recipes. Keep all fetching and paging in the current
client/observer machinery. Exercise cancellation and optimistic rollback with
an in-flight request and validate stored type and state after each transition.

**Exit:** page and input type fixtures pass; runtime tests cover an ordinary
and an infinite definition on one key (the cache's own type error),
sibling/descendant isolation, a nested key under a family prefix making the
bulk call throw before any write, stored null, absence and rollback. Runtime failures do not partially corrupt the cache.

### Phase 3 — Flutter, hooks and representative consumers

Integrate the options adapters through all supported consumers. Migrate one
end-to-end task-manager flow (detail/list, edit, cache update, invalidation and
failure/rollback), an infinite showcase flow (a screen under the five-artefact
catalogue rule, D11) and a hook consumer. Retain tests
using raw APIs so compatibility remains independently exercised.

**Exit:** binding/hook tests prove inference and lifecycle, including rebuilds
that hand in a recreated reference without a `setOptions` call reaching the
observer, parameter changes, identical recreated definitions, provider/client
switches, unmount and cancellation. Existing Playwright flows validate the migrated
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
The bumps are the minors of D11. Tags, package publishing and website
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
  and sealed values. Conflicting raw entries, deliberately widened references,
  generic defaults and `dynamic` misuse fail safely in release builds as well
  as debug. No silent second cache entry created by a type token.
- **Identity:** same input/recreated definition shares data and in-flight work;
  different IDs/filters/tenants do not. Structural maps, value models, record
  limitations and mutable inputs have documented tested outcomes. Equal inputs
  of an equal definition give `==` references and `==` options; a different
  fetcher does not make them unequal (D4).
- **Filtering:** exact reference operations leave descendants alone; family
  operations include the intended inputs; namespace invalidation covers all
  descendants. A typed bulk read or update over a prefix holding an entry of
  another type throws before any write (D7).
- **Semantics:** freshness, initial/placeholder data, select, retry, cancellation,
  background revalidation, structural sharing, timestamps and null/absence
  behave as the underlying client does. Infinite retries and pagination preserve
  the page/data relationship and cache type.
- **Lifecycle:** no client ownership inside reusable definitions, no eager
  fetches, leaked timers, stale repository retention, duplicate observers or
  post-disposal notifications. A per-family memo, if Open-4 chooses one, is
  measured for growth across many inputs. Exercise two
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
cache writes with the typed reference. Support an explicit migration adapter
for legacy key shapes if the standard namespace layout cannot preserve them;
the adapter binds a real definition and must not be a general-purpose unchecked
`TypedQueryKey<T>.fromRaw` constructor. Prove the adapter in Phase 0 if needed
by the selected consumer. Changing key layout intentionally is a cache identity
change and requires its own migration decision.

Raw and typed consumers can coexist when they agree on identity and exact data
type. Mixing them does not retroactively make the raw consumers statically safe.
A raw entry under a family's prefix with the family's type is simply shared;
one with another type makes the family's bulk calls throw (D7).

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
- **Options churn:** a facade that builds a fresh closure per build would
  cost every consumer a `setOptions` per rebuild. D4 makes equality a
  requirement and Phase 0 measures it.
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

One review so far (Fable, 2026-10-18, over commit `5edc932`). Every claim
about the current code was checked against the baseline before it was
accepted; the five substantive findings were all confirmed and worked in, and
the smaller ones are listed with what became of them.

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
