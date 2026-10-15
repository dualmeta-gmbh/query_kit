# Repository constraints

The constraints every design, review, proof and decision in query_kit sits under. This is the one place they are stated; the other skills point here instead of restating them. Paths are relative to the repository root. `CLAUDE.md`, `CONTEXT.md` and `docs/adr/` are the authority; this file routes to them, and where two of them disagree it says which one is current.

## The upstream pin

- The reference is `query/packages/query-core/src/` at `50680b98c` (`CLAUDE.md`, "Repository layout"). Verify it before comparing: `git -C query rev-parse --short HEAD`. If the checkout is missing or at another revision and the task may not change it, compare against a separate reference checkout of that revision, or report the gap; never compare against upstream `main` silently.
- A difference from upstream is one of four things: faithful (upstream does the same), a decided divergence (a row in the table "Deliberate divergences that will show up in later suites", `packages/query_kit/test/PORTING_NOTES.md`), a defect, or an unresolved claim. Say which. Upstream is evidence, not permission to undo a stronger Dart contract: closeness is a tiebreaker, and a better Dart or Flutter result needs its reason recorded (`CLAUDE.md`, "What the map settles").

## Ported tests stay as ported

- One Dart test file maps to one upstream test file; each case keeps its upstream name; an assertion changes only with a PORTING_NOTES entry saying why (`CLAUDE.md`, "When porting a test, port it"). A suite is never rewritten to fit a refactor (map #49's rule).
- Whole files with no upstream counterpart are the port-only files (PORTING_NOTES, "The port-only files, and what each is for"): `smoke_test.dart`, `port_specifics_test.dart`, the `release_*_regressions_test.dart` files in the core, `review_regressions_test.dart` in the binding. A clearly named Dart-only case that belongs beside its ported neighbours may stay in the ported file (PORTING_NOTES, "What 'Cases' counts"). A regression test is named after its finding ID.
- Four ported suites import `src/` directly (`subscribable_test.dart`, `removable_test.dart`, `retryer_test.dart`, `utils_test.dart`): moving an internal file can break a ported import without changing behaviour. An import adaptation is recorded; a renamed case or a changed assertion is not an adaptation.
- When a ported case goes red, the port is wrong until proven otherwise.

## The public surface since 1.0.0

Both packages reached 1.0.0 on 2026-09-23 (`CLAUDE.md`, "Where the work stands"); the current versions are in each `pubspec.yaml`. A breaking change is a major, whether or not a caller exists in this repository. The surface is what the barrel files export: `packages/query_kit/lib/query_kit.dart` and `packages/query_kit_flutter/lib/query_kit_flutter.dart`. The core barrel's export policy (the maintainer note at line 91) says what is and is not a contract: the `*CacheRef` interfaces and the retryer are not exported and may change freely; the `QueryAction` and `MutationAction` families, the `*ObserverRef` interfaces and `FetchBehavior`/`FetchContext` are exported so their fields can be typed, but dispatching an action, implementing a ref or building a fetch context is not public API. The core barrel is pinned by `packages/query_kit/test/barrel_test.dart`; the binding's hidden names by the "C23.7" group of `packages/query_kit_flutter/test/review_regressions_test.dart`.

Classify every proposed change as one of three:

1. **Internal**: no supported contract changes, in name, signature, inferred type, default, observable order or error. Free.
2. **Compatible addition**: a new export, member or optional parameter; existing spellings keep compiling and behaving. Say what was added.
3. **Major**: a supported existing contract becomes incompatible. An intentional break is a separate decision with its own record, never a side effect of a refactor or a glossary cleanup.

Check all of: exports, constructors, type inference at call sites (the `setQueryData` P2 of the 2026-09-18 review was an inferred type argument), defaults, observable order, thrown errors.

## Decisions already made

Not re-litigated inside a design or a review. A proposal that conflicts with one names it and argues for reopening, or stays inside it.

| Topic | Record |
|---|---|
| Plain and select options, one type slot for plain queries | `docs/adr/0001-one-type-slot-for-plain-queries.md`; `CONTEXT.md` |
| Widget-test teardown is a documented snippet; `flutter_test` stays a dev dependency | `docs/adr/0002-widget-test-teardown-is-a-documented-snippet.md`. Its text describes three steps; the current teardown is the five steps in `CONTEXT.md` ("Teardown") and `packages/query_kit_flutter/test/harness.dart`, which win |
| Fetch identity, scope ownership, re-entrancy, cancellation, settlement | `docs/adr/0003-core-operation-lifetimes.md` |
| The binding's API shape: four equal call styles, no default call style in the docs, no hooks, signals or connectivity package required | `docs/decisions/binding-api-shape.md`; `CLAUDE.md`, "What the map settles" |
| Null means unset; sealed "off" values; `Defaulted*Options` as distinct types; an option field written out in nine places | `CLAUDE.md`, "Conventions the port runs on"; PORTING_NOTES, C52; #62 |

The dependency rule is about integrations: neither published package requires a hooks, signals or connectivity package, and none is added. The dependencies each `pubspec.yaml` declares today (`clock` and `meta` in the core, `meta` in the binding) stay as declared; the rule does not ask for their removal.

## Known items are not findings

- `docs/plans/post-release-backlog.md` holds what the release review triaged and left: its "Structure (next wayfinder map)" section names AR-06, AR-10 and AR-13 to AR-18; its other sections carry the API-* and the remaining IDs. Cite the ID; do not re-find it. Showing an item is worse than rated, or finding one on no list, is a finding.
- PORTING_NOTES' "Structural work after the ninth review (C47–C59)" is what the last structural map already did; its "Regressions found by review" and the three "Release review 2026-09-23" sections, each with a "Second pass", are the record of what was found and what the fixes then broke. These records are kept: a historical regression test is not deleted because a newer test covers the same lines.

## Measurement

A count is produced by a command in the same session (`wc -l`, `grep -c`, `dart test` totals) and the command is written next to the number. Map #49 re-measured every finding it worked and most counts were wrong (`CLAUDE.md`, "a structural row is a hypothesis, not a measurement"). A number without a command is a hypothesis and is labelled so. Historical counts in `CLAUDE.md` and PORTING_NOTES are context, not current evidence; a count that cannot be measured in a read-only task is reported as a gap, not reused.

## Who decides

AFK is the default. `CLAUDE.md`, "AFK: nobody is in the loop": every decision, grilling ones included, is made by the agent; never ask which option to take, never stop for an answer. Take the recommended answer and record, per decision, the options, the choice and why it beats the alternatives, so it can be reopened from the record alone (`docs/agents/issue-tracker.md`, "Resolve"). Invoking a skill by name does not switch this off.

Interactive mode applies only when the current conversation explicitly asks for it: a request for an interview, a question put to the person, or a decision they reserved for themselves. Then ask only the unresolved decisions and wait for those answers; everything else is still decided and recorded.

Either way, deciding does not widen the task: a review does not become an implementation, a proof does not become a release, and the current task's write boundary holds. A skill that would write to the repository (a glossary entry, an ADR, a ticket) does so only when the task allows it; otherwise it returns the proposed entry in its report. Tickets are read and written with `gh ... --repo dualmeta-gmbh/query_kit`, always: `CLAUDE.md`, "Issue tracker", overrides `docs/agents/issue-tracker.md`'s "infer the repo", because the nested `query/` clone makes `gh` infer the wrong one. Closed maps keep their decisions.

## Gates

The test, analyzer and formatter commands, each runnable from the repository root, are in the `blast-radius` skill, step 6, with their preconditions. `.github/workflows/ci.yml` is the truth about what CI runs beyond them (browser runs, coverage floors, the docs jargon guard, the Flutter floor, the site, end-to-end suites); copy a command from the workflow when running it, never guess a flag. Passing the local block is not CI acceptance, and a green build or publish dry-run is not permission to publish.
