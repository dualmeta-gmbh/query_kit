---
name: improve-codebase-architecture
description: Scan query_kit for deepening opportunities, write them up as a report, then grill through the chosen one and chart it as work.
disable-model-invocation: true
---

# Improve codebase architecture

Surface architectural friction and propose **deepening opportunities**: refactors that turn shallow modules into deep ones, for testability and navigability. Nothing is built here; the output is a report and, when one candidate is picked, a decided plan.

Call the Skill tool with "codebase-design" first and use its words exactly (module, interface, depth, seam, adapter, leverage, locality) and its principles (the deletion test, the interface is the test surface, one adapter is a hypothetical seam, a rule fixed per case is a missing module). Use `CONTEXT.md`'s words for the domain. The constraints every candidate is classified against are in its [REPOSITORY.md](../codebase-design/REPOSITORY.md): known items are cited by ID, not re-found; ported suites stay unchanged; each candidate's public-surface class (internal, compatible addition, major) goes on its card; a conflict with a decision already made is shown only with a reason to reopen it; every count has its command; AFK is the default and the task's write boundary holds.

## Process

### 1. Explore

Scope before scanning. If the user named a direction, take it. Otherwise walk `git log --oneline` back a good stretch for hot spots, the files that keep coming up, and let those pull attention first; the fixes of every review round landed in `query.dart`, `query_observer.dart`, `query_client.dart`, `read_set.dart` and `query_client_provider.dart`, so expect them. A hot spot is a lead, not a finding: a file changes often because it owns a lot, too.

Read `CONTEXT.md`, the ADRs in the area, the backlog's "Structure (next wayfinder map)" section, and the PORTING_NOTES sections for the modules in scope. Then spawn a sub-agent to walk the code and note friction, not to apply a checklist (without delegation, make the pass yourself and say so in the report):

- Where does understanding one concept require bouncing between several small modules?
- Where is a module shallow, its interface nearly as complex as its implementation?
- Where has something been extracted for testability while the bugs hide in how it is called (no locality)? The port's own history says where: four of the first five review bugs sat exactly where the port differs from upstream (PORTING_NOTES, "Regressions found by review").
- Where was the same rule fixed, moved and fixed again? The "Regressions found by review" and "Release review 2026-09-23" sections, read by subject rather than by date, show which invariants had no home.
- Where do modules leak across their seams (a `Query` reaching through `client.queryCache` was C54)?
- What is hard to test through its interface? The 4807-line `port_specifics_test.dart` and 4350-line `review_regressions_test.dart` are where to look: a regression that needed a private seam is a shape complaint, and tests organised by the round that found the bug rather than by module often mirror low locality in the code.

Apply the deletion test to anything suspected shallow. "Deleting it concentrates complexity" is the signal. Zero candidates is a valid result; say what was scanned and found sound.

### 2. Present candidates as a report

Write the report to the OS temp directory, never into the repository: `$TMPDIR` (or `/tmp`), `architecture-review-<timestamp>.md`, in the shape of [CARD-FORMAT.md](CARD-FORMAT.md). Tell the user the absolute path. Markdown, not HTML: the report's next life is the body of a wayfinder map issue or a file under `docs/research/`, and both are Markdown.

Do not propose interfaces yet.

### 3. Who picks, then the grilling loop

REPOSITORY.md, "Who decides", applies: the report's top recommendation is the pick, and the record (options, choice, why) replaces the exchange. Only when the current conversation explicitly asked for an interview or reserved the choice do you ask "Which of these would you like to explore?" and wait.

For the picked candidate, call the Skill tool with "grilling" (it knows both modes) to walk the design tree: constraints, dependencies, the shape of the deepened module, what sits behind the seam, which tests survive and which are replaced (codebase-design's DEEPENING.md), which exports change and so which public-surface class the design is in. Keeping the current design is one of the answers.

Side effects happen inline, as decisions crystallise, when the task may write to the repository; in a review-only task the same entries go into the report as proposed text:

- A deepened module named after a concept missing from `CONTEXT.md`, or a term sharpened in passing: call the Skill tool with "domain-modeling" and add it now.
- The candidate is rejected for a load-bearing reason a future scan would need: write the ADR (domain-modeling's ADR-FORMAT.md) rather than offering one; in AFK there is nobody to offer it to.
- Alternatives worth seeing side by side: codebase-design's DESIGN-IT-TWICE.md.

### 4. Chart it

In a task that may write to the tracker, a decided candidate becomes work the way every piece of work here does: a new wayfinder map issue with its tickets, per `docs/agents/issue-tracker.md` ("Wayfinding operations"), created with `gh ... --repo dualmeta-gmbh/query_kit`. Never reopen a closed map. The first ticket is one reversible slice, not the whole deepening. A candidate in the major class gets its own decision ticket before any build ticket. Each ticket's build runs through the `blast-radius` skill before its first production edit, because most rounds of fixes here introduced defects the next round found (`docs/plans/post-release-backlog.md`, "Why the review stopped where it did").

In a review-only task, the plan (tickets, order, the first slice) is the last section of the report instead.
