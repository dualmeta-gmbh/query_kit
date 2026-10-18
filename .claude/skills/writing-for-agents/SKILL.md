---
name: writing-for-agents
description: Writing documents an agent consumes. Use when creating or editing a skill under .claude/skills, or when modifying CLAUDE.md, CONTRIBUTING.md's agent-facing parts, or docs/agents/.
---

# Writing for agents

Reference for any document an agent reads: a skill, `CLAUDE.md`, a doc reached by a pointer. The packaging differs; the writing does not. The levers below make the agent take the same process every run.

When the document is a skill, also read [SKILL-MECHANICS.md](SKILL-MECHANICS.md) for frontmatter, the invocation choice and this repository's skill set.

## Context pointers

A **context pointer** is a line in the agent's context that names out-of-context material and encodes the condition for reaching it: a skill's description, a `CLAUDE.md` line naming a file. The wording of the pointer, not its target, decides whether the agent gets there. A must-have target behind a weak pointer is a variance bug: sharpen the wording first; inline the material only if that fails.

A pointer does two jobs: say what the material is, and list the **branches** that should trigger reaching it. Every word of an always-loaded pointer costs on every turn:

- Front-load the leading word.
- One trigger per branch; synonyms for one branch are one branch written twice.
- Cut identity the body already carries.

`CLAUDE.md`'s pointer to PORTING_NOTES is a good one: "the first thing to read before touching a ported suite" names the material and the branch in one line.

## The two loads

- **Context load**: always-loaded material on the agent's window, spent whether or not it fires. `CLAUDE.md` is 444 lines; every line is paid for on every turn of every session.
- **Cognitive load**: what the human must remember exists. Not a cost to minimise everywhere; spend it where human judgement matters.

Material behind a pointer escapes context load for the pointer's line; material with no pointer rides on cognitive load alone.

## Information hierarchy

Two content types: **steps** (what the agent does, in order) and **reference** (rules and facts consulted on demand). Place each piece on a ladder by how immediately it is needed:

1. **In-file step**: the primary tier.
2. **In-file reference**: consulted on demand; a flat set of rules on one rung is fine.
3. **Disclosed reference**: a separate file behind a pointer, loaded when the pointer fires.

**Progressive disclosure** is the move down the ladder so the top stays legible. The test is branching: inline what every branch needs; push behind a pointer what only some branches reach. **Co-location** is the within-file companion: a concept's definition, rules and caveats under one heading. **Sprawl** is the failure: a document too long even when every line is live.

## Steps and completion criteria

Every step ends on a **completion criterion**. Two properties:

- **Clarity**: can the agent tell done from not done? "Understanding reached" invites stopping early; "every reader shape in the table green" does not.
- **Demand**: how much it requires. "Every modified option field in `value_semantics_test.dart`" forces legwork that "add tests" does not.

The strongest criteria are checkable and exhaustive. This repository's are: red before, green after, pasted; the gate run; the PORTING_NOTES row written.

## Leading words

A **leading word** is a compact concept the model already holds, repeated as a token so it anchors behaviour: *seam*, *frontier*, *red*, *AFK*, *twin*. This repository has good ones: *call style*, *own build*, *additive*, *divergence*, *port-only*, *the pin*. Hunt for restatements a leading word retires: "fast, deterministic, low-overhead" is *tight*.

**Negation** is the trap beside this lever: a prohibition drags the forbidden behaviour into context. State the target ("time goes through `clock.now()`") and let the ban ride on it; keep a bare prohibition only as a guardrail you cannot phrase positively.

## Pruning

- **Single source of truth.** One meaning, one place. The environment is a source too: `ci.yml` is the truth about the gate, `pubspec.yaml` about the version, `git tag` about what shipped. A document restating them is a **cache**, worth keeping only when the lookup is expensive. Cache what cannot be looked up: the unwritten convention, the reason, the gotcha.
- **Relevance.** Does the line still change what the agent does? History that explains how the code got here is not an instruction; it belongs in PORTING_NOTES or `docs/history/`, with a pointer. Without pruning the default is **sediment**: layers that settle because adding feels safe and removing feels risky.
- **No-ops.** An instruction the model already follows by default pays load to say nothing. Delete the sentence, not words from it. A leading word too weak to beat the default is a no-op too; the fix is a stronger word.

## Applying this to CLAUDE.md

The file's job is to change what an agent does in this repository. Check each paragraph against that:

- **History versus instruction.** The first 120 lines narrate review rounds by date and ID. The instruction inside them (reproduce before changing; a structural row is a hypothesis; fixes introduce defects, so a fresh pass follows) survives in a few lines; the narrative is a cache of PORTING_NOTES' sections and goes behind one pointer.
- **Caches that went stale.** Test counts, versions, the `tool/` listing and the layout table are environment lookups. Before editing, measure: `git tag`, the package's own test command run in its directory with the full output and exit status kept, `ls tool`, `git ls-files docs`. Then either delete the cached number or replace it with the command.
- **Rules that are not written anywhere else stay.** The AFK rule, `--repo dualmeta-gmbh/query_kit`, the five-step teardown's reason, the nine places of an option field, port-don't-rewrite, the upstream pin and why it is load-bearing. These are the file's real content. The skills' copy of the design constraints is `codebase-design`'s [REPOSITORY.md](../codebase-design/REPOSITORY.md); it routes to `CLAUDE.md`, so a rule moved out of `CLAUDE.md` must land where REPOSITORY.md points.
- **Pointers, not copies.** Each skill in `.claude/skills/` and each doc under `docs/agents/` gets one line naming it and its branch.
- **The rule inventory.** Before the rewrite, list every rule in the old file: each sentence that changes what an agent does, one line each, with its old line number. After the rewrite, check each off against the new file, or write beside it the file and section it moved to. A rule with neither a tick nor a new home was lost, and the rewrite is not done. A tick means the rule survived with its scope, its modality (must, may, never), its exceptions and its trigger; a rule kept as a weaker sentence is a loss too. Then walk three real requests through the new file (an AFK ticket, an API cleanup, a docs edit) and check each reaches the rules it needs; a contradiction between two sources it points at is reported, not left for the reader.

Completion criterion for a `CLAUDE.md` edit: every rule in the old inventory is ticked or has a named new home, every remaining line either changes behaviour or points at a file that does, every number in it was produced by a command in the same session, and the gate commands match `.github/workflows/ci.yml`.
