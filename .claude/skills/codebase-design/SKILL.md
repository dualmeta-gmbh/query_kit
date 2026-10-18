---
name: codebase-design
description: Shared vocabulary for designing deep modules in query_kit (module, interface, seam, adapter, depth, leverage, locality). Use when designing or improving a module's interface, deciding where a seam goes, making code testable through its interface, or when another skill needs this vocabulary.
---

# Codebase design

Design **deep modules**: a lot of behaviour behind a small interface, placed at a clean seam, tested through that interface. Use these words wherever code in `packages/query_kit` or `packages/query_kit_flutter` is designed or restructured.

The constraints every design sits under (the upstream pin, ported tests unchanged, the 1.0.0 surface and its internal / compatible addition / major classification, the decisions already made, known items, measurement, who decides) are stated once in [REPOSITORY.md](REPOSITORY.md). A proposal classifies itself against them; it does not restate them. Deepening may move code between Dart files freely; it may not change what a ported case asserts or what a barrel exports without saying so.

## Glossary

Use these terms exactly. Do not substitute "component", "service", "API" or "boundary".

**Module**: anything with an interface and an implementation. Scale-agnostic: a function, a class, a Dart library, a package. `ReadSet` is a module; so is `packages/query_kit`.

**Interface**: everything a caller must know to use the module correctly: the signature, plus invariants, ordering, error modes, required configuration, cost. `QueryClient.clear()`'s interface includes that a dropped mutation's callbacks run a microtask later and may write to the cache (the five-step teardown in `CONTEXT.md`). _Avoid_: API, signature.

**Implementation**: what is inside the module. Distinct from **adapter**: a thing can be a small adapter with a large implementation (the showcase's express server under `examples/showcase/server/`) or a large adapter with a small one (its dio fake).

**Depth**: leverage at the interface. How much behaviour a caller or test exercises per unit of interface learned. **Deep**: much behaviour, small interface. **Shallow**: an interface nearly as complex as the implementation.

**Seam** _(Feathers)_: a place where behaviour can be altered without editing in that place; where a module's interface lives. Placing the seam is a decision separate from what goes behind it. _Avoid_: boundary.

**Adapter**: a concrete thing that satisfies an interface at a seam. Names the role, not the substance.

**Leverage**: what callers get from depth. One implementation pays back across N call sites and M tests.

**Locality**: what maintainers get from depth. Change, bugs, knowledge and verification concentrate in one place.

## Deep and shallow, in this repository

Deep modules the binding already has, each written up in its library doc:

- `packages/query_kit_flutter/lib/src/read_set.dart`: two constructor arguments (how a reader is told to rebuild, what a debug message calls it); identity tuples, entries, epoch and release are implementation. Its doc also lists what deliberately stayed outside and why.
- `packages/query_kit_flutter/lib/src/notify_gate.dart`: one check ("does this notification carry what the listeners already saw") that makes "nothing rebuilds for nothing" true in all four call styles.
- `packages/query_kit_flutter/lib/src/controller_lifetime.dart`: the subscribe-while-listened dance, once, with four guards a separate copy would get wrong.
- `packages/query_kit/lib/src/listener_registry.dart`: the listener list five core modules keep, as a field rather than a base class because Dart has no declaration-site variance.

A shallow interface that was really an incomplete one: `QueryCacheRef` had four members where its twin `MutationCacheRef` had ten, and `Query` reached around it through `client.queryCache` for the missing two (PORTING_NOTES, "C54"). The fix was to complete the interface, not to delete the seam.

When designing an interface, ask: can the number of members go down, can the parameters get simpler, can more go inside.

## Principles

- **Depth is a property of the interface, not the implementation.** A deep module may be composed of small swappable parts; they are not part of the interface. A module can have **internal seams** (private, used by its own tests) and one **external seam**.
- **The deletion test.** Imagine deleting the module. If complexity vanishes, it was a pass-through. If it reappears across N callers, it was earning its keep. `ControllerLifetime` passes: delete it and every controller holding one (five sites today: `grep -rn "ControllerLifetime<" packages/query_kit_flutter/lib/src`) regrows the nested-subscribe guard.
- **The interface is the test surface.** Ported suites test each module through its own interface, most through the barrel and four through `src/` imports (REPOSITORY.md, "Ported tests stay as ported"), which is why deepening behind those interfaces leaves them green and moving a file can still break an import. A port-only regression that reaches past an interface (a private field, an event order nobody outside observes) is testing the wrong shape; see DEEPENING.md.
- **One adapter means a hypothetical seam. Two adapters means a real one.** `QueryObserverRef` is implementable but its doc says implementing it is unsupported (`packages/query_kit/lib/src/query.dart`, the interface's doc; backlog item API-16): one adapter, a hypothetical seam. The clock has two: `package:clock`'s real clock and `fake_async`'s, which is why `clock.now()` is a rule in `CLAUDE.md`.
- **A rule fixed per case is a missing module.** When the same invariant has been patched at several call sites, or moved several times, it has no single home. The binding's release edge for element-bound reads moved three times across the 2026-09-23 passes before `read_set.dart` held it as one rule and `reader_shapes_test.dart` held the rule as a table (`CLAUDE.md`, the V3 and V4 passes). Give the invariant one home before fixing its next case.

## Designing for testability

1. **Accept dependencies, do not create them.** `QueryClient` takes its `QueryCache`, `MutationCache`, `AppFocusManager`, `OnlineManager` and `NotifyManager` (`packages/query_kit/lib/src/query_client.dart:433`); the managers are instances the client owns rather than module-level singletons (divergence row "module-level managers", #19). Time is accepted through the zone: `clock.now()` and `Timer`, never `DateTime.now()`.

   ```dart
   // Testable: the seam is a constructor argument.
   final client = QueryClient(queryCache: cache);

   // Hard to test: the collaborator is made inside.
   class Client { final _cache = QueryCache(); }
   ```

2. **Return results, do not produce side effects.** `QueryState` is reduced by actions and `QueryResult` is a sealed value with `==`; a test compares values instead of watching mutation. `StructuralSharing` returns the shared value rather than patching the previous one in place.

   ```dart
   // Testable: a value in, a value out (the sealed QueryAction family,
   // packages/query_kit/lib/src/query.dart:241).
   QueryState<T> reduce(QueryState<T> state, QueryAction action) { ... }

   // Hard to test
   void apply(QueryAction action) { _state = ...; notify(); }
   ```

3. **Small surface.** Fewer members, fewer tests to write; fewer parameters, simpler setup. Each option field here costs nine places and about forty lines (`CLAUDE.md`, "An option field costs about forty lines"), so a new field is a surface decision, not a detail.

## Relationships

- A module has exactly one interface.
- Depth is measured against that interface.
- A seam is where the interface lives; an adapter sits at a seam and satisfies the interface.
- Depth produces leverage for callers and locality for maintainers.

## Rejected framings

- **Depth as a line-count ratio** (Ousterhout): rewards padding. Use depth as leverage.
- **Interface as the public members only**: too narrow; every fact a caller must know counts.
- **"Boundary"**: overloaded with DDD's bounded context. Say seam or interface.

## Going deeper

- The repository's standing constraints, stated once for every skill: [REPOSITORY.md](REPOSITORY.md).
- Deepening a cluster given its dependencies, with the fidelity rule for tests: [DEEPENING.md](DEEPENING.md).
- Exploring several interfaces for one candidate with parallel sub-agents, and deciding without a human: [DESIGN-IT-TWICE.md](DESIGN-IT-TWICE.md).
