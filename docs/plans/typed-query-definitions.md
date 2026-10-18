# Plan: native typed query definitions

Status: proposed implementation plan; no feature code or type-safety spike has
been implemented or validated by this document.

Date: 2026-10-18. Repository baseline: `a5afe7d` (`main`).

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
- Imperative fetching is `client.query(...)` / `client.infiniteQuery(...)`,
  not an existing `fetchQuery` / `ensureQueryData` API. Freshness, background
  revalidation, cancellation and retry semantics must survive the new facade.
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

## Design decisions and boundaries

### 1. Definition, identity, reference and namespace are different things

- `QueryFamily<TInput, TCacheData>` owns one operation path, its input-to-key
  mapping and its typed fetch function. Calling it binds an input and returns
  `QueryRef<TCacheData>`.
- `QueryDefinition<TCacheData>` covers an operation without varying inputs.
- `QueryRef<TCacheData>` binds a definition and input, carries executable
  options, and exposes operations whose data type comes from that reference.
  It does not retain a client, mount observers, fetch or register timers merely
  because it was constructed.
- `TypedQueryKey<TCacheData>` wraps the existing raw `QueryKey` and retains the
  cache type for key-only reads and state access. Initially expose creation
  through definitions/references, not a public arbitrary `fromRaw<T>` cast.
- `QueryNamespace` selects entries by prefix without claiming a data type.
  It supports lifecycle operations and filters, not typed data reads/writes.

Keep `QueryKey` and its equality/hashing unchanged. It is final, so use
composition rather than subclassing it. Do not add `T`, closure identity or
definition instance identity to cache equality: that would hide a collision
behind a second cache entry and break raw/typed interoperability. An explicit
`rawKey` escape hatch must document the loss of static guarantees.

### 2. Anchor writes to the receiver's type

Do not treat a signature such as
`setData<T>(TypedQueryKey<T> key, T value)` as sufficient proof. Dart can infer
a common wider type from the two arguments; simply making keys generic does
not establish the intended compile-time guarantee.

Prefer `ref.write(client, TCacheData value)` and
`ref.update(client, TCacheData? Function(TCacheData?) updater)` with no new data
type parameter on each operation. Key-only reads may live on the typed key;
mutation operations live on the reference to keep one authoritative write API.
Any additional client-style convenience must pass the same negative analyzer
tests before being added. Do not widen existing raw client methods to `Object`
or `dynamic` to simulate overloads.

This does not make Dart generics invariant. Explicit upcasts, raw generics,
`dynamic`, dishonest casts and deliberately incorrect definitions remain
boundaries. Keep production runtime checks and test widened receivers as well
as natural calls. The acceptance claim is precisely the tested typed surface,
not that every expressible Dart program fails statically.

### 3. Define stable identity and its limits

The default raw identity is namespace parts, operation name, then the frozen
parts returned by `keyOf(input)`. Use explicit stable names; do not derive
identity from closure identity, `runtimeType.toString()`, construction order or
a random token. Recreating definitions with the same schema must address the
same entries, including widget rebuilds and hot reload.

Every value that changes the result belongs in the identity or in a deliberately
separate client: IDs, tenant/account, locale, filters and backend environment
where relevant. A captured repository object is a dependency, not an automatic
identity component. Switching accounts must not reuse another account's data.

`keyOf` is explicit for general inputs: Dart cannot generically inspect record
fields or prove that arbitrary closure dependencies are included. Primitive
inputs are straightforward; records and custom models need documented value
equality or explicit conversion to supported parts. Freeze collection key
parts once when binding. Require immutable input values or an explicit snapshot
adapter so a retained input cannot change what is fetched after its key was
computed. Do not claim `keyOf` freezing clones a user model or captured input.

Definitions with the same logical operation must be reused. Establish a
schema/registration contract in Phase 0 that rejects distinguishable conflicts
(duplicate declarations within a namespace, ordinary versus infinite kind,
incompatible cache types) before a typed operation mutates or fetches. Raw
entries with the same compatible key and type must remain adoptable.

Function identity is not a reliable conflict check: recreated closures can be
equivalent, and the same closure can depend on mutable external state. A registry
cannot prove that two same-named, same-typed fetchers have the same meaning.
Document this authoring boundary explicitly. If metadata registration is needed,
keep it client-local, bound its lifetime, and define its behaviour on remove,
clear and disposal; no process-global definition registry or retained repositories.
Do not silently promise detection of all same-type function collisions.

Structural identity is not a portable serialisation format. Preserve current
key semantics and debug rendering. Persistence, hydration codecs and cross-process
schema migrations are separate features, not accidental promises of this API.

### 4. Preserve declared cache types, absence and null

Every typed read uses the definition's exact cache type. Every first typed write
or seed establishes that declared type, including a sealed base type receiving
a concrete variant, `List<Device>` receiving a narrow literal, and `Device?`
receiving a non-null `Device`. Do not infer the entry type afresh from the value.
Reject an existing incompatible raw entry before changing it.

`ref.read(client)` returns `TCacheData?` for compatibility: for nullable queries
it cannot distinguish an absent value from a cached null. Provide typed
`state(client)` exposing the existing state and `hasData` for that distinction.
`QuerySuccess<T>.data` is `T`; it can be null when `T` itself is nullable.

Keep current update semantics: returning null from `update` skips the write.
Use `ref.write(client, null)` on a nullable definition to deliberately cache
null, invoking the declared nullable type rather than inferring `Null`.
Use exact removal for restoring absence. A snapshot/rollback recipe must
distinguish absent entry, existing entry without data, and stored null; do not
convert every absent snapshot into a stored null. Decide how the degenerate
`TCacheData == Null` case is handled in Phase 0 rather than silently changing
the raw client's intentional `Null`-write no-op.

Writes retain structural sharing, timestamps and synchronous notification
behaviour. Runtime mismatches must use the existing diagnostic contract where
possible and identify the key, expected type and actual type.

### 5. Reuse options, defaults and execution

`ref.options()` produces `QueryObserverOptions<TCacheData>`; selection uses
the existing required `withSelect` shape and yields
`QuerySelectOptions<TCacheData, TSelected>`. Selection never changes the typed
key or cached value. Avoid adding a second optional output-type parameter.

Definition defaults and per-use options may set behaviour such as freshness,
retry, enabled, placeholder/initial data and refetch rules, all with appropriate
data types. Safe overrides must not accept a replacement key, fetch function,
input or arbitrary fetch behaviour. Returning existing options exposes their
legacy `copyWith`; classify using it to replace identity/function as an explicit
exit from the safe definition path, not an enforced immutable contract.

Merge precedence must be specified and tested: client defaults, matching key
defaults in their existing order, definition options, then per-use overrides.
Null still means unset for option fields. Existing typed definition fetchers
take precedence over a generic default fetch function.

Support a deliberately named key-only definition path when a typed observer
uses pre-seeded data or an existing default fetcher. Require an explicit output
type where no function provides inference. Preserve missing-function failures
and runtime checks on generic default functions. Do not claim their untyped
transport is statically validated merely because a typed key was supplied.

`fetch` delegates to `client.query`, including freshness/deduplication,
imperative retry defaults and `revalidateIfStale`. It is not a guarantee of a
new network request. Keep any prefetch and ensure-data conveniences thin and
document their errors and staleness; no second fetch lifecycle. Reuse exact
client operations for cancel, remove, reset and refetch as well as invalidate.

### 6. Make the exact/prefix boundary explicit

Reference lifecycle operations are exact by default. Family operations select
all input instances; namespace operations select the structural prefix,
including descendants. Preserve active/inactive filters, refetch type and
cancellation controls through a typed filter adapter.

A family can expose typed bulk reads and updates only when membership is known
to be homogeneous. A raw prefix alone does not prove that: a detail operation
may have nested queries with another type or an incompatible legacy entry.
Phase 0 must choose a membership mechanism or decline the typed bulk operation;
do not claim safety based only on the first prefix match. Prefer explicit
definition membership plus exact cache-type verification for every selected
entry. Unowned legacy matches require an explicit adoption policy.

Typed bulk operations must preflight all selected entry types, compute updater
results and validate those results before writing, preserving the raw bulk
updater's preparation order. An updater throwing during preparation must leave
the batch unwritten. This does not roll back side effects or reentrant writes
performed by application callbacks and is not a database transaction. A
heterogeneous namespace exposes invalidation and non-data operations only;
existing raw bulk APIs stay available with their current runtime obligations.

### 7. Infinite queries retain all three types

Provide `InfiniteQueryFamily<TInput, TPageData, TPageParam>` and a bound infinite
reference. Its typed cache key and read/write/update operations use
`InfiniteData<TPageData, TPageParam>`, not just one page. The page function
receives typed input plus the existing typed page context and cancellation.

The logical query input determines the entry key; individual page parameters
belong inside `InfiniteData` and must not split one infinite query into one
entry per page. Preserve initial/next/previous page parameters, max pages,
refetch direction, retry, cancellation and observer paging actions. Reject
ordinary/infinite identity conflicts; use distinct operation names by default.

Selected infinite options change the observer output only. Wrong page data,
wrong page parameters and wrongly typed `InfiniteData` writes are negative
analyzer cases. Retain current runtime protection against unsafe widening of
`InfiniteData` and test first writes with narrow literals.

### 8. Integrate every consumer without another state layer

Generated existing options should work with controllers, builders, mixins,
`context.query`, selectors, listeners and hooks without new ownership rules.
Keep the four base Flutter styles equally documented. Verify inferred callback
and result types at each public entry point, including hook prefetch and
infinite helpers. Heterogeneous result composition retains existing typed record
combination; homogeneous `useQueries`/`QueriesObserver` collections must not
erase types merely to accept mixed definitions.

Mutation definitions themselves are outside the initial feature. Existing
mutation callbacks must be able to use typed references for cancellation,
optimistic writes, snapshots, rollback, server-response writes and family
invalidation. Query definitions do not solve concurrent optimistic mutation
ordering or automatically validate backend JSON. Show an example that preserves
the existing concurrency contract and states its assumptions.

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

Resolve and record these design gates before freezing the public API:

- Constructor inference and zero-input declarations; no accidental `dynamic`.
- Covariance/upcast behaviour, including returning callback fields versus
  methods and the original declared type on a widened reference.
- Typed-key reads without arbitrary public retagging or unsafe overloads.
- Definition metadata, collision diagnostics, adoption of raw entries and
  cleanup, without closure-identity-dependent keys.
- Family membership for typed bulk operations and descendant exclusion.
- Safe behaviour overrides, nullable writes/updates and the `Null` type case.
- Input immutability/snapshot rules and all default/query-only entry points.

**Exit:** executable positive/negative evidence on both SDKs, a recorded final
surface and explicit limits. If a desired syntax cannot uphold a guarantee,
revise the syntax or narrow the claim before proceeding; do not replace a
promised compile error with an undocumented debug assertion.

### Phase 1 — Ordinary definitions and cache operations

Implement namespaces, static definitions, families, references and typed keys.
Thread them into the existing cache with typed reads/state, writes/updates,
options, fetch and exact lifecycle operations. Implement the Phase 0 identity
and collision contract. Preserve runtime checking and raw compatibility.

**Exit:** core tests demonstrate same-key sharing between typed/raw consumers,
declared-type first writes, nullable semantics, stable recreation, defaults,
exact/prefix isolation and no extra fetch/subscription merely from binding.
All Phase 0 fixtures run against the real public exports.

### Phase 2 — Families, infinite queries and mutation workflows

Implement the chosen homogeneous-family bulk contract, infinite definitions,
typed filters and mutation recipes. Keep all fetching and paging in the current
client/observer machinery. Exercise cancellation and optimistic rollback with
an in-flight request and validate stored type and state after each transition.

**Exit:** page and input type fixtures pass; runtime tests cover ordinary versus
infinite conflicts, sibling/descendant isolation, bulk preflight, stored null,
absence and rollback. Runtime failures do not partially corrupt the cache.

### Phase 3 — Flutter, hooks and representative consumers

Integrate the options adapters through all supported consumers. Migrate one
end-to-end task-manager flow (detail/list, edit, cache update, invalidation and
failure/rollback), an infinite showcase flow and a hook consumer. Retain tests
using raw APIs so compatibility remains independently exercised.

**Exit:** binding/hook tests prove inference and lifecycle, including rebuilds,
parameter changes, identical recreated definitions, provider/client switches,
unmount and cancellation. Existing Playwright flows validate the migrated
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
Correct blanket statements that TanStack cannot type keys: it supports global
key registration and query-options-associated data inference.

**Exit:** migration examples and reference docs agree with the implemented API,
all validation gates below are green for the final feature commit, and a release
note accurately distinguishes compile-time guarantees from runtime checks.
Version bumps, tags, package publishing and website deployment are separate
explicitly authorised actions.

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
  limitations and mutable inputs have documented tested outcomes. Diagnostics
  cover detectable schema conflicts without relying on closure equality.
- **Filtering:** exact reference operations leave descendants alone; family
  operations include the intended inputs; namespace invalidation covers all
  descendants. Typed bulk reads/updates exclude or reject incompatible members
  according to the declared membership policy before writes occur.
- **Semantics:** freshness, initial/placeholder data, select, retry, cancellation,
  background revalidation, structural sharing, timestamps and null/absence
  behave as the underlying client does. Infinite retries and pagination preserve
  the page/data relationship and cache type.
- **Lifecycle:** no client ownership inside reusable definitions, no eager
  fetches, leaked timers, registry growth after cleanup, stale repository
  retention, duplicate observers or post-disposal notifications. Exercise two
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
Avoid adding legacy entries to a typed family solely because their prefix matches.

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
- **Namespace ambiguity:** data prefixes, widget scopes and typed homogeneous
  families are distinct. The provisional naming and membership gate make that
  distinction explicit.
- **Input omissions:** no Dart compiler can prove a hand-written `keyOf` includes
  every dependency. Central declarations, immutable inputs and targeted identity
  tests reduce this risk; backend schema validation remains separate.
- **Compatibility:** returning legacy options and exposing `rawKey` allow escape
  from the safe path. Document that boundary rather than claiming total lock-down
  or silently breaking the existing API.
- **Cost of metadata:** any membership/collision registry needs measured cleanup
  and lookup behaviour. Avoid a second cache and global declaration ownership.

Rejected as the primary design: only a string key factory (does not bind cache
data), only `QueryKey<T>` with a generic setter (does not prove write safety),
runtime assertions alone (too late and possibly debug-only), and compulsory
code generation (unnecessary setup for the core use case). An optional generator
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
