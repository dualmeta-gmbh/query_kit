---
title: Design notes
description: Why query_kit is shaped the way it is. The decision records, the research behind them, the plans and the porting notes live in the repository; this page says which one answers which question.
---

# Design notes

The reasons behind query_kit's shape are written down in the repository, next
to the code. This page is a signpost: it says what each folder holds and which
question it answers, and links the documents on GitHub. Nothing is copied
here, so the documents stay the single source.

Two cautions. The documents are working papers written for the people
building the packages, not for users, and several are in German. And they
carry the project's internal bookkeeping, such as ticket numbers and review
labels, which the rest of this site leaves out.

## Decision records

[`docs/adr/`](https://github.com/dualmeta-gmbh/query_kit/tree/main/docs/adr)
holds the decisions that are hard to reverse, each with the options that were
considered and why one won.

| Record | Decides |
|---|---|
| [One type slot for a plain query](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/adr/0001-one-type-slot-for-plain-queries.md) | Why a query without `select` has one type argument and one with it has two, so the data type can never silently become `dynamic`. See [type safety in Dart](../dart-type-safety.md). |
| [The widget-test teardown is a snippet](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/adr/0002-widget-test-teardown-is-a-documented-snippet.md) | Why the binding does not export a test helper and no `flutter_test` dependency reaches your app. See [testing](../guides/testing.md). |
| [Core operations own their state](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/adr/0003-core-operation-lifetimes.md) | Which fetch or mutation may write to a query, when a mutation scope passes on, and what a cancelled operation may no longer do. |
| [Hooks are an add-on](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/adr/0004-hooks-are-an-add-on-over-an-adapter-library.md) | Why `query_kit_hooks` is a separate package over a small public seam of the binding, and why hooks are not a fifth call style. See [hooks](../guides/hooks.md). |
| [The comparison page describes and does not rank](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/adr/0005-the-comparison-page-describes-and-does-not-rank.md) | The rules [other Dart libraries](../reference/other-dart-libraries.md) follows when it writes about other people's packages. |

## Research

[`docs/research/`](https://github.com/dualmeta-gmbh/query_kit/tree/main/docs/research)
holds the findings the decisions rest on. Each says what was read and when.

**About TanStack Query**

- [Upstream `query-core` inventory](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/research/upstream-query-core-inventory.md):
  every module and test file of the version this port follows, and what moved
  since an earlier one.
- [The adapter contract](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/research/adapter-contract.md):
  what TanStack Query's own framework bindings need from the core.
- [Inventory of React Query's hook tests](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/research/react-query-hook-tests-inventory.md):
  case by case, which can be ported to hooks.

**About Dart and Flutter**

- [Runtime facts](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/research/dart-flutter-runtime-facts.md):
  timers, microtasks, error zones and lifecycle events, the guarantees the
  timing model depends on.
- [Guards against `dynamic` inference](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/research/dynamic-inference-guards.md):
  what Dart offers and what comparable libraries do. Behind the first
  decision record above.
- [Shipping a widget-test helper](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/research/test-helper-packaging.md):
  behind the second.
- [Hooks spike](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/research/hooks-spike.md):
  the measurements behind the hooks add-on.

**About other packages and naming**

- [Survey of Dart and Flutter query libraries](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/research/dart-query-libraries-survey.md)
  and [a deeper comparison](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/research/competitor-deep-dive.md),
  both from September 2026. They are planning papers for the project itself,
  and they name defects found by reading other packages' code. The sourced
  public version is [other Dart libraries](../reference/other-dart-libraries.md).
- [Package names and affiliation](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/research/package-naming-and-affiliation.md):
  which names were free on pub.dev, and what TanStack has said about
  community ports. See [credits](credits.md).

**About how well it works**

- [The first real integration](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/research/br64-integration-findings.md):
  an app using the packages unmodified reported fourteen findings. Each was
  checked against the code and against upstream before anything changed.
- [Core confidence assessment](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/research/core-confidence-assessment.md)
  and a [test follow-up](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/research/release-test-follow-up.md),
  both in German.

## The API shape of the binding

[`docs/decisions/binding-api-shape.md`](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/decisions/binding-api-shape.md)
records why the Flutter binding offers four call styles that behave the same,
why it has no required third-party package, and why this documentation shows
no default among them.

## Plans

[`docs/plans/`](https://github.com/dualmeta-gmbh/query_kit/tree/main/docs/plans)
holds the plans the bigger pieces of work followed, in German:
[the hooks package](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/plans/hooks-package.md),
[functional improvements](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/plans/functional-improvements.md)
and [what was left for after the first release](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/plans/post-release-backlog.md)
(in English).

## The porting notes

The audit trail of the whole port is
[`PORTING_NOTES.md`](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit/test/PORTING_NOTES.md)
in the core package's tests, with the hooks add-on's own
[beside it](https://github.com/dualmeta-gmbh/query_kit/blob/main/packages/query_kit_hooks/test/PORTING_NOTES.md).
They list every upstream test that was ported, adapted or left out and why,
every bug a review found, and the table of deliberate divergences that
[differences from TanStack Query](../reference/differences-from-tanstack.md)
unpacks. [How fidelity is proven](fidelity.md) explains how to read them.
