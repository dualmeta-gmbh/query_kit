---
status: accepted
date: 2026-10-18
ticket: https://github.com/dualmeta-gmbh/query_kit/issues/78
---

# The comparison page describes other packages and does not rank them

Readers who are choosing a TanStack-Query-like package for Flutter search for
exactly that, so the site needs a page that sets query_kit beside `fquery`,
`cached_query`, `flutter_query` and `query_stack`. Map #70 planned it as a
reputational one-way door: the project is an unaffiliated, AI-coded community
port, the other packages are maintained by people who did not ask to be
compared, and a page that is wrong or sour about them cannot be un-read. The
ticket planned the rule as "ADR-0004"; that number went to the hooks add-on
before the page was written, so the rule takes the next free one.

The rule has five parts, and the page follows all of them:

1. **Describe, do not rank.** The page says what each package is and does and
   where it may fit better than query_kit. It has no ordering, no score, no
   "winner" column and no checkmark grid that adds up to one.
2. **Date every claim, and name the version.** The page states the day its
   facts were gathered and the version each fact was read from. A fact about a
   package is a fact about a release; the page does not claim anything about
   the next one.
3. **Say only what a public source shows.** Each fact comes from the package's
   own pub.dev listing or API, its `pubspec.yaml`, its README, its changelog,
   its documentation site or its repository, and the page links the source.
   A feature the sources do not mention is reported as "not mentioned in its
   README", never as "missing". Nothing is inferred from how a package
   behaves in someone's app, and nothing from popularity numbers.
4. **No superlatives about this port.** query_kit's own claims are the ones
   the rest of the site already makes and can show: a test suite ported from
   upstream, the counts in [how fidelity is proven](../../website/docs/project/fidelity.md).
   The page lists what query_kit does not have next to what it does.
5. **Link their documentation, and invite correction.** Every package gets a
   link to its own docs, and the page says where to report a mistake about it.
   A correction is applied and the date moved only when every claim was
   checked again.

## Considered options

1. **No comparison page.** Nothing to get wrong, and nothing for a reader who
   searches for the comparison to find; the question would be answered by
   whoever writes the next blog post. The research notes already hold the
   comparison (`docs/research/competitor-deep-dive.md`), so staying silent
   leaves the better-sourced version unseen.
2. **A feature matrix with a column per package.** The usual form, and the one
   that most invites a ranking: every cell is a claim about someone else's
   package, a blank cell reads as "no", and the table is out of date the day
   any of them ships. Rejected.
3. **This** - prose per package, a short facts table with a source and a date
   for each cell, and an explicit "where another package may fit better".

## Consequences

- The page carries its date at the top and is edited with a date change,
  never silently. Rechecking it is manual, not a CI gate: the facts live on
  pub.dev, which a build cannot assert on without making the site's build
  depend on the network. The date tells a reader how old the page is.
- A package that is discontinued or replaced is reported as pub.dev reports
  it, with the listing as the source, and without a recommendation.
- The competitor study in `docs/research/` stays a dated working document. The
  page borrows its method, not its verdicts.
- If a maintainer of a listed package asks for a change to how they are
  described, it is made when the source supports it and the page says
  so when it does not.
