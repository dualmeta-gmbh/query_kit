---
name: thermonuclear-review
description: Structural code-quality review of a module, package or the whole of query_kit, not only a branch diff. Strict on abstraction quality, spaghetti growth, seams and tests; reconciled with the port's upstream twins and the 1.0.0 public surface.
disable-model-invocation: true
---

# Thermonuclear review

An unusually strict review of implementation quality over a **target**: a path (`packages/query_kit/lib/src/mutation.dart`), a package, or both packages. The default target is whatever the user named; with none, both `lib/` trees, and the coverage ledger says so. A branch diff is a target too, but the sweep is the point: the structural findings that outlived the release review (AR-06, AR-10) came from reading the library line by line against upstream (`CLAUDE.md`, the 2026-09-23 release review), not from a diff.

Be ambitious. Look for the restructuring that preserves behaviour while making the implementation markedly smaller and more direct, where whole branches, modes or layers disappear. Do not stop at "this could be a bit cleaner". Call the Skill tool with "codebase-design" for the words (module, interface, seam, deep, shallow, deletion test) and use them.

## Before reading code

1. `codebase-design`'s [REPOSITORY.md](../codebase-design/REPOSITORY.md): the pin and how to verify it, the ported-test rule, the public surface and its three classes, the decisions already made, the known-item lists, the measurement rule. These standing contracts and the triage of known items are read first, so a finding already recorded there as decided or known is not a new finding; an item shown to be worse than rated is.
2. `CLAUDE.md`, "Conventions the port runs on": `clock.now()` never `DateTime.now()`; `.ignore()` on every held future; sealed value types for options with an "off" value; `Defaulted*Options` as distinct types; the nine-place option-field transcription, explored and kept (#62). These are rules, not findings.
3. The PORTING_NOTES rows for the modules in the target, divergence rows included. What looks odd next to upstream is often decided.
4. `docs/adr/0003-core-operation-lifetimes.md` when the target runs operations: identity fields that look redundant may be the contract.
5. The upstream twin at the pin, `query/packages/query-core/src/<name>.ts`. Structure the port kept from upstream is a fidelity choice; structure the port added is yours to judge.

What waits until your own pass is written: other reviewers' conclusions about the same target (an earlier agent's report, a candidate finding someone handed you). Agreement with them is a lead, not proof; a claim the inspected code does not bear out is reported as not reproduced, and a finding only you made stands if its evidence does.

## The file-size rule, reconciled

The original rule, "no file may cross 1000 lines", does not fit a port whose files deliberately mirror upstream files. Replace it with three measurements, each reported with its command. They are cues to ask what the excess is, not acceptance budgets:

- **A lib file with an upstream twin** is measured against the twin: `wc -l` both. Dart carries types, dartdoc and sealed classes upstream spells as unions, so up to about 1.5× the twin is the port's price. Today: `query_client.dart` 1573 against `queryClient.ts` 1087 (1.45×), `query.dart` 1328 against 973 (1.36×), `query_observer.dart` 1091 against 902 (1.21×), `mutation.dart` 1063 against `mutation.ts` 535 (1.99×). Above 1.5×, ask what the excess is: dartdoc is free, ADR-0003 ownership is decided, anything else is a candidate.
- **A lib file with no twin** (`query_options.dart` 1410, the binding's files) is measured against 1000 lines with the original rule, except that `query_options.dart`'s size is the nine-place transcription (#62) and a finding there must propose something #62 did not consider.
- **A test file that ports an upstream suite** is one file by rule and is never a size finding. A **port-only** test file is: `port_specifics_test.dart` (4807 lines) and `review_regressions_test.dart` (4350) may be split by subject, provided every PORTING_NOTES pointer to a case name still resolves (the notes name cases, not line numbers) and no case is dropped.

## Lenses

Apply the ones that fit; a lens that does not apply is not written up.

1. **Code judo.** Can the model change so that conditionals disappear rather than move? Apply the deletion test to every helper and wrapper. A pass-through, an identity wrapper or a one-caller helper is a finding; `ListenerRegistry`, `NotifyGate`, `ControllerLifetime`, `ReadSet`/`ReadEntry`, `QueryCacheRef` and `_RefetchRules` are the canonical homes already built, so a near-duplicate of one is a finding too.
2. **Spaghetti growth.** Ad-hoc conditionals, one-off booleans, special cases inserted into unrelated flows. In this repository the review rounds are where they came from: a fix "proven on the shape its finding named" that added a branch for that shape (`packages/query_kit_flutter/test/reader_shapes_test.dart`, header). Ask whether a set of fix branches is one rule written five times; a rule fixed per case is a missing module.
3. **Types and seams.** The analyzer runs with `strict-casts`, `strict-inference` and `strict-raw-types` (`analysis_options.yaml`), so a cast is visible: question each one, each `Object?` where a sealed type exists, each nullable that means two things. A silent fallback papering over an unclear invariant is a seam that should be explicit.
4. **Canonical layer.** Feature logic leaking into shared paths; the showcase's `lib/shared/` rules apply there (`examples/showcase/README.md`: one subject, more than one caller, a single-caller member belongs with its caller). In the core, a `Query` reaching the cache two ways was C54.
5. **Seams and tests.** Is the module tested through its interface? A regression that needed a private seam (a `@visibleForTesting`, an internal event order) is a shape complaint about the module. Is there a table where there are cases (a rule with N shapes tested on one)? Does the test's assertion still pin the failure its finding named (read the assertion, and the PORTING_NOTES row that says what was wrong)? Is a port-only case sitting where a ported suite should hold it, or the reverse?
6. **Orchestration and atomicity.** Sequential work that is independent; related updates that can leave state half-applied. The ownership contract is ADR-0003; the known spread of identities is AR-06. Delivery order is part of the interface here: direct subscriptions and cache listeners are synchronous per dispatch and only a `batch` defers (`packages/query_kit/lib/src/notify_manager.dart`, the class doc), so moving a notification into or out of a batch, or across an `await`, is a behaviour change.

## What correctness work belongs here

Only this much, because the repository's own rule is that a finding is reproduced before anything is changed (`CLAUDE.md`, "A review's finding is verified by reproducing it"):

- Trace a suspected side effect end to end before writing it up. Never present unfinished research ("if the observer handles X this is fine" when you can read the observer).
- Do not misreport priority. This skill's definitions: P1 is wrong data or a crash on a realistic path; P2 a defect on a reachable path; P3 contract, cost or polish. They match how the backlog uses the labels, which has no scale of its own. State impact apart from evidence: a confirmed P3 outranks a hypothetical P1 in the table.
- A correctness finding is handed to the `blast-radius` skill, which owns the proof ladder and the fix. This review stops at the reproduction recipe.

## Evidence

Every structural claim carries the command that measured it (REPOSITORY.md, "Measurement"). Every row also carries one evidence label, earned rather than chosen:

- **confirmed defect**: reproduced by a test, or by a path you traced end to end;
- **measured structural concern**: a count or a shape produced by a command in this session;
- **hypothesis**: a claim with neither a measurement nor a reproduction;
- **decided trade-off**: already recorded in an ADR, a divergence row or the backlog; reported only because the review argues for reopening it;
- **not reproduced**: a claim from an earlier review or report that the inspected code does not bear out.

Every proposed change names its public-surface class (internal, compatible addition, major), its cost to the ported suites and to diffability against the upstream twin, and what else it could break.

## Output

A table in the shape PORTING_NOTES uses for a review, so it can be pasted there when worked:

```md
| ID | Where | What (lens) | Evidence | Measured by | Proposed change (class, cost) | Priority |
```

Order by: confirmed behaviour failures; structural regressions and missed simplifications; spaghetti and branching; seams, types and tests; file size; legibility. Fewer high-conviction rows beat a long list. "No findings in the inspected scope" is a valid result; a review whose rows are all nits says the target is fine.

Below the table:

- **Coverage ledger**: per area of the target, what was read (files, line ranges), what was traced (callers and dependencies followed to their end), what was run (suites, with the command and the counts) and the gaps, including what the target excluded (examples, tests, docs, tooling) and anything noticed there in passing. The ledger bounds the verdict: a review certifies the scope its ledger shows and nothing wider, and a partial run certifies nothing about the whole library or a release.
- **Known**: backlog and PORTING_NOTES IDs seen and left.
- **Cleared**: what was checked and is fine, one line each.
- **Hand-offs**: behaviour findings to `blast-radius`, structural candidates to `improve-codebase-architecture` or a wayfinder map.

## Approval bar

Approve nothing on "behaviour seems correct". Presumptive blockers, each carrying a confirmed-defect or measured label (a hypothesis never blocks): a reachable restructuring that deletes a category of complexity left untaken; a lib file above its twin cue with non-dartdoc excess unexplained; new ad-hoc branching in a flow a rule could own; a near-duplicate of a canonical helper; a cast or `Object?` where a sealed type is one line away; a test that reaches past the interface it could test through. A finding that contradicts an ADR or a divergence row names it and argues for reopening, or is dropped. The verdict is scoped to the coverage ledger.
