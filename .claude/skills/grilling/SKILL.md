---
name: grilling
description: Grill a plan, decision or idea relentlessly as a design tree of rounds. Use when the user wants their thinking stress-tested, says "grill", or when a wayfinder:grilling ticket or another skill needs a decision walked to a shared understanding. Runs with or without a human in the loop.
---

# Grilling

Interview until a shared understanding is reached. Map the subject as a **design tree**: every decision branches into the decisions that hang off it.

Work the tree in **rounds**. The **frontier** is every decision whose prerequisites are settled: the questions askable now without guessing at answers not yet heard. Ask the whole frontier in one round, numbered, each with a recommended answer. Word each question so "yes" accepts the recommendation.

```
Q1 - <title>: <body, with the choices>
-> <recommended answer, and why it beats the others>

---

Q2 - <title>: <body>
-> <recommended answer>
```

Each answered round reshapes the tree: settled decisions push the frontier out and unblock what depended on them. A question whose answer depends on another question still open this round belongs to a later round.

**Facts are yours to find, never the user's.** When a question needs a fact from the repository (a line, a count, whether a test exists, what upstream does at the pin), look it up or dispatch a sub-agent; only the questions downstream of that lookup wait, the rest of the frontier is asked now. A count is measured by a command, not remembered (`codebase-design`'s [REPOSITORY.md](../codebase-design/REPOSITORY.md), "Measurement"). A fact that cannot be found stays a named gap; a decision that rests on it keeps the current contract and says so.

The session is done when every in-scope branch is decided, deferred with a reason, or blocked on a named fact. Nothing is silently assumed.

## Who answers

REPOSITORY.md, "Who decides", applies; state the mode in the first round:

- **AFK** (the default; a `wayfinder:grilling` ticket, a skill calling this one, or any run where the conversation did not ask for an interview): answer each frontier question with your recommended answer and move to the next round. Never ask which option to take, never stop for an answer. The record replaces the live exchange: the resolution comment states, per question, the options, the answer and why it beats the alternatives. Decide, then build: production Dart lands once the decisions covering it are closed.
- **A human asked to be interviewed** in the current conversation, or reserved a decision: put those decisions to them and wait; decide and record the rest. Confirmation is needed only for what they reserved or for work the task did not authorise.

In both modes the ticket is read and written with `gh ... --repo dualmeta-gmbh/query_kit`.

## What the tree must cover in this repository

Beyond the subject's own branches, a decision about `packages/` always has these nodes, one per constraint in REPOSITORY.md; ask them when they are on the frontier:

- Which public-surface class is it: internal, a compatible addition, or a major? If major, is there an additive spelling, and is the break its own decision?
- Does it change behaviour a ported suite asserts? Then either upstream at the pin is matched, or a divergence row is added.
- Does it touch a decision already made (an ADR, `docs/decisions/binding-api-shape.md`, a convention)? Reopen it explicitly or stay inside it.
- Does it add an option field? That is nine places and a row in `value_semantics_test.dart`.
- Does it add a dependency to a published package?
- Is it already a known item? Then it is triaged, and the question is whether the rating still holds.

When a term is sharpened or a decision is hard to reverse, call the Skill tool with "domain-modeling" to update `CONTEXT.md` or write the ADR as the answer lands, not afterwards (or, in a read-only task, to draft the entry for the report).
