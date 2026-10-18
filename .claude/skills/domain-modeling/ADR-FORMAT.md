# ADR format

ADRs live in `docs/adr/`, numbered `0001-slug.md`, `0002-slug.md`. Three exist; they are cited by number in `CLAUDE.md`, in PORTING_NOTES rows and in dartdoc, so a number is permanent. Scan the directory for the highest number and add one.

## Template

Two shapes exist. ADR-0001 and ADR-0002 record one choice and share this one:

```md
---
status: proposed
date: YYYY-MM-DD
ticket: https://github.com/dualmeta-gmbh/query_kit/issues/NN
---

# {Title: the decision as a sentence}

{One paragraph: the context, what was decided, and why. Name the research
or the review finding that drove it, with a relative link.}

## Considered options

1. **{Option}.** {Why it loses.}
2. **This** — {the chosen option}. {Why it wins.}
3. **{Option}.** {Why it loses.}

## Consequences

- {A downstream effect a reader would not guess: what is now breaking,
  what a later change must keep, what became moot.}
```

ADR-0003 records a set of rules rather than one choice, and its shape is the one to copy for that: "Ownership rules", a contract table, "Relationship to the pinned upstream", "Release acceptance". It has no `ticket` and no "Considered options".

Frontmatter: `status` is `proposed | accepted | deprecated | superseded by ADR-NNNN`; `date` is the real date the decision was taken, never a copied one; `ticket` only when a real wayfinder ticket decided it, with that ticket's number. `accepted` means the choice is resolved and recorded, not that the code implements it or that tests prove it; what is planned rather than done is said so in the text. "Considered options" is kept for a single choice because the AFK rule requires the options and the reason to be in the record (`CLAUDE.md`, "the resolution comment states the options, the answer, and why it beats the alternatives"). "Consequences" only when non-obvious. When an ADR supersedes another, the old one keeps its text and gains the `superseded by` status; its reasoning is not deleted.

## When to write one

All three must hold:

1. **Hard to reverse.** Since 1.0.0 that includes every supported public contract (REPOSITORY.md, "The public surface since 1.0.0": an incompatible change is a major), the widget-test teardown shape users have copied (ADR-0002), and the ownership rules tests pin (ADR-0003).
2. **Surprising without context.** The next reader would "fix" it. ADR-0002 exists because the README's "no dependency beyond Flutter" would otherwise look like an oversight to someone adding `flutter_test` back.
3. **A real trade-off.** ADR-0001 lists four options; a decision with one sane option is a comment in the code.

What qualifies here: the shape of the public API; a deliberate divergence from upstream that is not just a row (a row in PORTING_NOTES' divergence table is enough for most); a dependency ruling; a test-packaging choice; a scope lock (ADR-0003 locks a scheduling framework out). What does not: a refactor inside `lib/src` that no export sees; a review fix with a regression test (that is a PORTING_NOTES row).

## Relationship to the other records

- A decision that changes ported behaviour also needs its divergence row in `packages/query_kit/test/PORTING_NOTES.md`; the ADR says why, the row says what.
- A decision made on a ticket is also the ticket's resolution comment; the ADR is the durable copy and links the ticket in its frontmatter.
- `docs/decisions/binding-api-shape.md` is the one decision outside this directory. Leave it where it is and link it when an ADR builds on it.
- In a task that may not write to the repository, the ADR is returned as proposed text in the report, with its intended number, and nothing is created.
