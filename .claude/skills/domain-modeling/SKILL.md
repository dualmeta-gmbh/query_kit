---
name: domain-modeling
description: Build and sharpen query_kit's domain model. Use when a term is being defined or challenged, when writing or editing CONTEXT.md (the glossary), or when recording or editing an ADR under docs/adr/.
---

# Domain modeling

Actively build and sharpen the project's domain model while designing: challenge terms, invent edge-case scenarios, and write the glossary and the decisions down the moment they crystallise. Merely reading `CONTEXT.md` for vocabulary is not this skill; `docs/agents/domain.md` tells every skill to do that before exploring. This skill is for changing the model.

## Where the model lives

This repository uses `CONTEXT.md`, not `GLOSSARY.md` (`docs/agents/domain.md`):

```
/
├── CONTEXT.md                 the glossary, one context
├── docs/adr/                  0001-… 0002-… 0003-…
└── docs/decisions/            one older decision, binding-api-shape.md
```

A `CONTEXT-MAP.md` at the root would mean several contexts; there is none, and the two packages share one language. `docs/decisions/binding-api-shape.md` is a decision record that predates the ADR directory: read it as an ADR when the topic is the binding's API shape or dependencies; do not move or renumber anything.

Create nothing speculatively. Both files exist; add to them when a term or decision is resolved.

## During the session

### Challenge against the glossary

When a term conflicts with `CONTEXT.md`, say so at once. "`CONTEXT.md` defines a *call style* as one of four equal ways the binding reads a query; `QueriesBuilder` is not one of them (PORTING_NOTES, C49). Which do you mean?"

### Sharpen fuzzy language

Propose the precise canonical term. "Observer options come in two *shapes*, plain and select; 'the options type' names neither."

### Discuss concrete scenarios

Stress-test relationships with specific sequences. The repository's scenarios are sequences of events on a cache: a key change during a fetch, a dropped mutation's callbacks a microtask after `clear()`, a `LayoutBuilder` re-running its builder without its parent. Invent the one that forces the term's edge.

### Cross-reference with code and with upstream

When someone states how something works, check the code, and check upstream at the pin (`codebase-design`'s [REPOSITORY.md](../codebase-design/REPOSITORY.md), "The upstream pin"). A contradiction with the code is a finding; a contradiction with upstream is faithful, a decided divergence, a defect or an unresolved claim, and the divergence table in PORTING_NOTES says which.

### Update CONTEXT.md inline

When a term is resolved, add or correct it there and then, in the shape of [CONTEXT-FORMAT.md](CONTEXT-FORMAT.md). Do not batch.

`CONTEXT.md` holds terms, not implementation. A step list belongs there only when the steps are the term, as *teardown* is.

### Published identifiers are not renamed by a glossary cleanup

The glossary picks the word for a concept; it does not rename the Dart identifier that carries it. `QueryObserverOptions`, `withSelect`, `StructurallyShareable` and every other export are part of the 1.0.0 surface, and a rename is a major (REPOSITORY.md, "The public surface since 1.0.0"). When the glossary's word and the identifier differ, the entry names the identifier as the spelling in code; a rename, if wanted, is its own decision with its own record, never a side effect of sharpening a term.

### Offer ADRs sparingly

Write an ADR only when all three hold:

1. **Hard to reverse.** Here that includes anything in the major class of REPOSITORY.md's public-surface rule: a public type, an export, a wire shape of a key.
2. **Surprising without context.** A future reader will ask why.
3. **A real trade-off.** There were alternatives and one was picked for reasons.

Use [ADR-FORMAT.md](ADR-FORMAT.md). AFK is the default (REPOSITORY.md, "Who decides"): do not ask whether to write it; write it when the three hold, and cite its number in the ticket's resolution comment. When the task may not write to the repository, return the entry (glossary bullet or ADR, with its intended number) as proposed text in the report. A mismatch between the glossary and the code is a finding to resolve against the code and the pinned upstream, not permission to redefine the term.

## Terms the glossary does not have yet

`CONTEXT.md` defines five terms. The code and PORTING_NOTES use many more as if defined: *reader*, *own build*, *generation* and *additive read* (the binding's release rule, `packages/query_kit_flutter/lib/src/read_set.dart`), *keyless read*, *speaker* (a provider that sets the online verdict), *fact group* and *control* (the showcase's `lib/shared/`), *scope* (a mutation's), *structural sharing*, *divergence*, *port-only*. When a session uses one of these precisely, that is the moment to add it.
