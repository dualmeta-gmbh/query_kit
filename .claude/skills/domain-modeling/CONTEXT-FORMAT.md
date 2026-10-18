# CONTEXT.md format

The shape the file already has (`CONTEXT.md` at the repository root); keep it.

## Structure

```md
# Context: query_kit

A glossary of the terms this repository uses precisely. Implementation lives
in the packages; decisions live in [`docs/adr/`](docs/adr/).

## Terms

- **Query options** — what the cache layer needs to run a query: key, function,
  staleness, retry, network mode. One type argument: the query's data type.
- **Observer options** — query options plus what only an observer cares about.
  Come in two **shapes**:
  - **Plain** — no `select`; one type argument.
  - **Select** — a required `select` projects the data; two type arguments.
```

One bullet per term, the term in bold, the existing separator, then one or two sentences. A term with named sub-cases nests them as sub-bullets, as *shape* does. A term that is settled by an ADR names it in the entry (`(ADR-0002)`), and the ADR number is the cross-reference, never a restated decision.

## Rules

- **Be opinionated.** When several words exist for one concept, pick one. Where the repository has words to avoid, say so in the entry: "_Avoid_: boundary (say seam)". The existing entries do not carry an avoid line; add one only when a wrong word is actually in use.
- **Define what it is, not what it does.** One or two sentences.
- **Only terms specific to this project.** `Timer`, microtask, `InheritedWidget` are Dart and Flutter, not glossary entries. *Own build* and *additive read* are glossary entries: Flutter has no such terms, the binding does.
- **Upstream's words are a tiebreaker, not a rule.** A TanStack term is kept when the port kept the concept (*stale*, *invalidate*, *observer*); where the port diverged, the entry uses the port's word and the divergence table in PORTING_NOTES holds the mapping.
- **No implementation in the glossary.** Line numbers, private names and counts belong in PORTING_NOTES or dartdoc.
- Group under subheadings only when clusters emerge; the file is flat today and five terms do not need headings.

## What the glossary is not

Not a spec, not a scratch pad, not a decision log. A decision goes to `docs/adr/`; a port fact goes to PORTING_NOTES; a user-facing definition goes to the site (`website/docs/`), which has its own jargon guard (`tool/check_docs_jargon.dart`) and must not carry ticket numbers or review IDs the glossary may.
