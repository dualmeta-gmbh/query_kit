# Candidate card format

The scan's output is one Markdown file in the OS temp directory. It must read as a document someone can paste into a wayfinder map issue or save under `docs/research/` without rewriting, so GitHub-flavoured Markdown only: tables, fenced code, Mermaid fences (GitHub renders them), no HTML, no CDN.

## Header

```md
# Architecture review: query_kit

Commit `<git rev-parse --short HEAD>`, upstream `<git -C query rev-parse --short HEAD>`, <date>, mode: AFK | interview.
Scope: <what was scanned, per area>; excluded: <what was not>; not measured: <counts a read-only run could not produce>.
Known items consulted: docs/plans/post-release-backlog.md, PORTING_NOTES "Structural work after the ninth review".
```

No introduction. Straight into the candidates, or into one line saying none were found and what was read.

## Candidate card

One `##` section per candidate:

```md
## <Short title naming the deepening, e.g. "One run token per Query">

**Strength:** Strong | Worth exploring | Speculative
**Dependencies:** in-process | local-substitutable | remote but owned | true external
**Known as:** AR-06 (backlog) | new

**Files**
- `packages/query_kit/lib/src/query.dart` (1328 lines; upstream twin `query.ts` 973)
- …

**Problem.** One sentence. What hurts, in glossary terms.

**Solution.** One sentence. What changes.

**Cost.** Migration (which imports, port-only tests and call sites move) and the cheapest test that would show the candidate is wrong.

**Wins**
- locality: run ownership checked in one place
- leverage: one guard, four observers
- delete: three identity fields

**Before / after**
<two short diagrams side by side as two fenced blocks, or one Mermaid flowchart with the deep module drawn as one node>

**Constraints**
| Ported suites touched | Public surface | Decision touched | Option-field cost |
|---|---|---|---|
| none | internal \| compatible addition \| major (which exports) | inside ADR-0003's ownership rules | none |

**Measured by**
- line counts: `wc -l packages/query_kit/lib/src/query.dart`
- callers: `grep -rn "_fetchGeneration" packages/query_kit/lib`
```

Rules for the card:

- The constraints table is mandatory; the questions are REPOSITORY.md's. "Ported suites touched" is the fidelity question; "Public surface" is the 1.0.0 class (internal, compatible addition, or major with the exports named); a conflict with a decision is stated as "contradicts ADR-000N, worth reopening because …" or not at all. A candidate in the major class is rated at most "Worth exploring".
- Every number has a command under "Measured by". A count without one is a hypothesis and is labelled so.
- Wins are six words or fewer, each starting with a glossary noun (locality, leverage, interface, delete). Not "cleaner", not "easier to maintain".
- Prose is sparse. If the diagram needs a paragraph, redraw the diagram.

## Diagrams

Pick per candidate; vary them.

- **Mermaid flowchart** for call flow and dependencies. Draw a leak as a dashed edge labelled `leak`.
- **Mass diagram** as two fenced text blocks: a tall interface box over a thin implementation (shallow) beside a short interface box over a deep implementation.
- **Cross-section** for layered shallowness: stacked bands a call passes through, before and after.
- **Call-graph collapse**: nested boxes before, one box with faded internals after.

Keep each diagram under about twenty lines so before and after sit together.

## Top recommendation

One section at the end: the candidate to take first, one sentence why, a link to its card. In an AFK run this is the pick.

## Tone

Plain, concise, the architectural nouns from `codebase-design` and the domain nouns from `CONTEXT.md`. Use exactly: module, interface, implementation, depth, deep, shallow, seam, adapter, leverage, locality. Never: component, service, unit, API, signature, boundary, layer, wrapper. No hedging, no throat-clearing. A sentence that could be a bullet is a bullet; a bullet that could be cut is cut.
