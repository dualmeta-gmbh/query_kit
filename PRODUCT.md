# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

Flutter developers looking for a data-fetching and caching package. They land
on the site from pub.dev, GitHub or a search, and want to see within seconds
what it does, how reading a query looks in a widget, and whether it is serious
enough to build on. Secondary: developers who know TanStack Query (React Query)
and want to know how faithful the port is.

## Product Purpose

query_kit fetches, caches and updates the server data of a Dart or Flutter app
and keeps it fresh. Two packages on pub.dev: `query_kit` (the pure-Dart core:
staleness, background refetching, retries, cancellation, mutations, infinite
queries) and `query_kit_flutter` (the binding: provider, controllers, builder
widgets, a `State` mixin and `context.query(...)`). The site is its
documentation: a landing page, guides, a cookbook, live examples and an API
reference. Success: a visitor installs it and finds the answer to their next
question in the docs.

## Positioning

A port of TanStack Query's `query-core`, proven by porting upstream's own test
suite case for case under upstream's test names; every omission and divergence
is written down. The Flutter binding needs nothing but Flutter (no hooks,
signals or connectivity package), and offers four equal ways to read a query —
none is presented as the default.

## Operating Context

Read on desktop next to an editor while building, and on a phone when
evaluating. Every Dart sample on the site is compiled and analysed in CI
(`examples/doc_snippets/`); the landing sample is compiled too. Live demos are
the showcase and task-manager Flutter web builds, embedded on demand
(`<LiveDemo>`), running against an in-memory backend. Every doc page is also
served as Markdown for AI agents (`llms.txt`).

## Capabilities and Constraints

- Docusaurus 3 site under `website/`, deployed to GitHub Pages at
  https://query-kit.dualmeta.io/ on a release tag.
- URLs, slugs, heading anchors and the sidebar structure are stable; the build
  fails on a broken link or anchor.
- Light and dark mode, following the system preference, with a toggle.
- Code samples must stay byte-identical to their compiled twins.

## Brand Commitments

- Name: `query_kit` (lowercase, underscore), packages `query_kit` and
  `query_kit_flutter`. Publisher dualmeta.io.
- **AI disclosure, fixed wording, wherever a reader can land first** (hero,
  announcement bar, footer, overview): "query_kit is an entirely AI-coded
  project: all code, tests and documentation were written by AI coding agents
  (Anthropic's Claude). A human maintainer set the goals and reviews releases,
  but did not write the code."
- **Non-affiliation** with TanStack, Tanner Linsley and the TanStack
  organisation, stated plainly, with gratitude and the MIT credit.
- Voice: dry, exact, plain-spoken, British spelling. No hype.
- The four call styles are equal alternatives; no default is shown as preferred.

## Evidence on Hand

- Compiled landing sample (`examples/doc_snippets/lib/landing.dart`).
- Live demos: 30 showcase screens and the task-manager app (Flutter web).
- Fidelity record: `packages/query_kit/test/PORTING_NOTES.md`; the ported test
  suites. Counts change per release; take them from the repo, do not invent.
- No users, testimonials, benchmarks or download counts to show. Do not
  fabricate any.

## Product Principles

1. Show the code doing the work before describing it.
2. Every claim is checkable: link it to the test, the source or the page.
3. Honest about what it is: AI-coded, a port, not TanStack's.
4. Nothing but Flutter: no dependency, no preferred style imposed.
