---
name: unslop
description: Cut AI tells and internal bookkeeping from query_kit's prose. Use when writing or editing user-facing text (website/docs, package READMEs, the top CHANGELOG entry, dartdoc), CLAUDE.md or CONTRIBUTING.md, or a writeup another skill hands back.
---

# Unslop

Edit text to remove AI patterns. Scan for the patterns below, rewrite, keep the meaning and the intended tone. Rule numbers are stable ids other skills cite; a removed rule leaves a gap.

## What counts as user-facing here

The project is published as AI-coded (`README.md`, the disclosure paragraph) and says what stands in for a human author is checking. Prose that reads as generated undercuts that claim. The surfaces a user reads, and the ones `tool/check_docs_jargon.dart` scans: `website/docs/**`, each package's `README.md`, the top entry of each `CHANGELOG.md`, every `///` line under `packages/*/lib`, and the example sources the site shows whole (`examples/showcase/lib`, `examples/task_manager/lib`, `packages/query_kit_flutter/example/lib`).

### 0. Internal bookkeeping (this repository's rule)

User-facing text carries no review rounds, no dates of the form `2026-xx-xx`, no finding IDs (`C12`, `LIB-3`, `V-B-1`), no `map #N`, no `ADR-N`, no issue links or `(#N)`, no upstream pin `50680b98c`. The guard is blocking in CI (`.github/workflows/ci.yml`, "docs jargon"). Rewrite to say what the thing does now. A line that must keep a reference carries `<!-- jargon-ok -->` (Markdown), `{/* jargon-ok */}` (MDX) or `// jargon-ok` (dartdoc); use it for a reason, not to pass. PORTING_NOTES, `docs/`, `CLAUDE.md` and test comments are internal and may carry all of it.

Three things to leave as they are:

- The AI-coded disclosure paragraph is repeated word for word across the READMEs, changelogs, library docs, examples and the site (eighteen tracked files today: `git grep -l 'entirely AI-coded project'`; commit `1c735ca` made the announcement bar match). Do not rephrase it anywhere.
- A fenced Dart sample on the site or in the two package READMEs declares its guarantee in its marker (`site_fences_test.dart`): an exact twin under `examples/doc_snippets/`, an excerpt with a visible `…`, or prose-only with a reason. Keep the marker; edit the prose around the fence; edit an exact twin only together with its sample.
- A number (test counts, coverage, cases ported) is measured by a command, not remembered; the site's numbers were once "remembered, not measured" (PORTING_NOTES, "Phase 0"). Keep the number only if you re-ran the command (`codebase-design`'s [REPOSITORY.md](../codebase-design/REPOSITORY.md), "Measurement").
- A Dart identifier in prose is the published spelling; a rewrite that prefers another word for the concept changes the prose, not the identifier (REPOSITORY.md, "The public surface since 1.0.0").

## Patterns to detect and fix

### Content

3. **Superficial -ing phrases.** "ensuring…", "highlighting…", "showcasing…". Delete or expand with the fact.
5. **Vague attributions.** "Experts believe". Name the source or delete.

### Language

7. **AI vocabulary.** Additionally, crucial, delve, enduring, enhance, fostering, garner, interplay, intricate, landscape, pivotal, robust, seamless, showcase, tapestry, testament, underscore, vibrant. Plain words.
8. **Fancy ways to say "is".** "serves as", "stands as", "boasts", "features". Say "is" or "has".
9. **"Not just X, but Y."** State the point.
10. **Rule of three.** Use the natural number of items.
11. **Synonym cycling.** Pick one word for a thing and repeat it. In this repository that word is usually in `CONTEXT.md`.
12. **False ranges.** "from X to Y" where X and Y are not on a scale. List them.

### Style

13. **Em dashes.** Write none in new text. When rewriting a passage, replace the ones in it with a period, a comma or a colon before a list; not with an en dash, a hyphen or parentheses standing in for the dash. Do not sweep a file only to remove dashes: the repository's existing prose is full of them and a dash-only diff buries real edits.
14. **Colon as a connector.** Fine before a list or an example, not mid-sentence. Let the point stand.
15. **Boldface overuse.** Not every noun or acronym.
16. **Inline-header lists.** A bold label plus colon that restates the line is a tell; a bold lead-in ending in a period followed by new detail is fine.
17. **Title case headings.** Sentence case; the site already uses it.
18. **Decorative emojis.** Remove.
19. **Curly quotes.** Straight quotes.

### Communication artifacts

20. **Chatbot phrases.** "I hope this helps", "Let me know if", "Certainly". Remove.
22. **Sycophancy.** "Great question". Respond directly.

### Filler

23. **Filler phrases.** "In order to" is "To"; delete "It is important to note that".
24. **Excessive hedging.** "could potentially possibly" is "may".
25. **Generic conclusions.** State the plan or the fact.

### Jargon

26. **Abstract metaphor nouns.** Substrate, wedge, vector, locus, nexus, primitive (as a noun), harness (as a metaphor; `test/harness.dart` is a file and stays), surface as in "API surface", bedrock, scaffolding, paradigm, north star, flywheel. Pick the concrete word. The repository's own words are seam, interface, module (the `codebase-design` skill).

### Plain speech

27. **Say what it does, not how it feels.** "types that follow your schema" names a feeling; "a column rename fails the build" names a mechanism. If a sentence could appear unchanged in another project's docs, it says nothing about this one. Cut it.
28. **Shorten or split dense sentences.** One idea per sentence. The internal docs here chain clauses with semicolons and dashes for a dozen lines (`CLAUDE.md`, the opening paragraphs); user-facing text does not.
29. **Active voice.** Name the actor: "the compiler rejects" over "is rejected".
30. **Adverbs.** "significantly faster" is the measured delta or nothing.
31. **The plain word.** "use" over "utilize" or "leverage" (in prose; *leverage* is a `codebase-design` term in architecture writeups and stays there).
32. **Mannered prose.** Aphorisms, personified code ("the plan holds it"), figurative verbs. Say what you mean.
33. **Over-compression.** Dropped articles, arrows, fragments. Whole sentences, abbreviations spelled out.

## Procedure

1. Name the surface (user-facing, internal, or a skill) and the rules that apply to it.
2. Run `dart run tool/check_docs_jargon.dart` when the surface is user-facing; its hits come first.
3. Rewrite, keeping fenced samples and the disclosure untouched. On an internal surface (PORTING_NOTES, the ADRs, `docs/`) every fact survives: finding IDs, commit hashes, paths, dates, counts, quoted upstream text and test names; tighten the wording, drop no claim. On any surface keep commands, anchors, fence markers and qualifiers such as "VM only", "planned" or "not reproduced"; a rewrite that reads stronger than the evidence is wrong, and a claim without evidence is flagged, not polished.
4. Compare the old and new text claim by claim: same meaning, same scope. Then ask what still reads as machine-written, and fix that too.
5. Re-run the guard; for the site, `(cd website && npm ci && npm run build)` catches a broken anchor (`CLAUDE.md`).
