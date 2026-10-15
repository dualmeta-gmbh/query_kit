---
status: accepted
date: 2026-10-15
ticket: https://github.com/dualmeta-gmbh/query_kit/issues/94
---

# Hooks are an add-on package over an adapter library

#21 ruled that the binding requires no third-party package, `flutter_hooks`
included, and that hooks may come later as an opt-in package. Map #92 builds
that package, `query_kit_hooks`, and two things had to be decided before it
could be: what a package outside the binding may use of the binding's
internals, and whether hooks join the four call styles the binding promises
are equal. The plan is `docs/plans/hooks-package.md` (D4 and D15); the spike
that measured both is `docs/research/hooks-spike.md`.

## The seam: `RebuildRule`, alone, in `package:query_kit_flutter/adapter.dart`

Every call style rebuilds a reader only for a notification carrying something
it is not already showing, and asks `buildWhen` only when the value moved.
That decision is where most of the binding's review findings hung (C49,
V-B-1 to V5). A hook owes its reader the same guarantee, so it must make the
same decision.

The binding exports it as one class that owns nothing: `RebuildRule<T>`
takes two closures — the controller's value and the state observed beside it
— and answers `read()` and `shouldRebuild(buildWhen)`. The binding's
internal `ReadEntry` keeps the subscription and the controller's ownership,
and delegates the decision to that class. There is one rule, not a copy per
package.

It lives in a library of its own, `adapter.dart`, not in the barrel. An app
never needs it; an adapter package does, and its dartdoc says so.

### Considered options

1. **Public API only.** The hooks package rebuilds the rule. The spike ran
   this way and proved it works, but two copies of the binding's most-reviewed
   decision drift apart.
2. **Export `ReadEntry`, `ObservedState` and `observedStateOf`.** Unsound
   (Astra, H-06): `ReadEntry` accepts any `ValueListenable` but casts it to
   `ChangeNotifier` and disposes it, so a valid listenable of one's own fails
   late, with a cast error, and the binding's private convention "handing
   over is handing over ownership" becomes an API obligation. The spike also
   showed no hook needs `ObservedState` or `observedStateOf`.
3. **This** — an ownership-free rule. Subscription, controller and disposal
   stay with the caller; the decision is in one place because `ReadEntry`
   uses it rather than containing it.
4. **Move the rule into the core.** Pulls Flutter's notion of a rebuild into
   a core that has no Flutter, and changes the core for no defect.

## Hooks are not a fifth call style

The four styles are equal by promise and by proof (C49): every one takes a
`buildWhen`, none rebuilds for nothing, and the showcase's
`catalogue_test.dart` holds them level. Hooks are a separate package with its
own documentation page, its own example app and its own ported suite. They
get no showcase screen and no catalogue column — the showcase could not even
depend on them without breaking #21 — and the documentation recommends them
over the four styles no more than it recommends one style over another.

The hooks package's documentation samples are compiled inside the hooks
package, by a twin of the binding's `site_fences_test.dart` that reads the
hooks page and the package README. `examples/doc_snippets` stays at two
packages: adding the third would pull `flutter_hooks` into an example, which
#21 rules out for everything built on top.

## Consequences

- `adapter.dart` is under semantic versioning. A change to `RebuildRule` is a
  major version of `query_kit_flutter`.
- Because of that, the binding version that first exports it, 1.1.0, is
  released together with `query_kit_hooks` 0.1.0, after that package's review
  round has read the exported surface — not before.
- The binding's behaviour does not change. Its suite stays green with no case
  rewritten, and a test that imports only `adapter.dart` holds the rule's
  branches.
- An adapter for another reading shape — signals, a state-management
  package — has the same seam, and owes its readers the same guarantee.
