---
title: How the examples are built
description: How the examples are built and tested — the one-file tour, the showcase against a real backend, the acceptance demo, and the hooks add-on's example.
---

# How the examples are built

Three, of increasing size, and a fourth for the optional hooks add-on.
[Examples](../examples/index.md) lists what each showcase screen shows and
which guide it belongs to; this page is about how they are built and proven.

## The one-file tour

`packages/query_kit_flutter/example/` — a provider, one query read two ways
and a mutation that invalidates it, with no server at all. `flutter run` in
that directory. It is what pub.dev shows on the package page.

## The showcase

`examples/showcase/` — **every feature of the library as its own screen**, 30
of them, against a dummy backend built for the purpose, each with widget tests
and Playwright end-to-end tests in a real browser. The app is the catalogue;
the tests are the proof.

```bash
cd examples/showcase/server && npm install && npm run dev
```

```bash
cd examples/showcase && flutter run -d chrome
```

Each feature lives in `lib/features/<id>/`, imports only the package and
`lib/shared/`, and says at the top of its file what it shows, which TanStack Query
example it mirrors, and how it is proven.

| Reading | Paging | Writing | Runtime |
|---|---|---|---|
| `simple` | `pagination` | `mutations` | `auto-refetching` |
| `basic` | `load-more` | `optimistic-updates` | `retry` |
| `default-query-function` | `max-pages` | `mutation-state` | `cancellation` |
| `dependent-queries` | | `playground` | `offline` |
| `parallel-queries` | | `invalidation-and-filters` | `focus-refetch` |
| `query-collections` | | `global-callbacks` | `four-call-styles` |
| `combine` | | `mutation-cancel` | |
| `prefetching` | | | `cache-inspector` |
| `select-and-sharing` | | | `diagnostics` |
| `build-when` | | | |
| `initial-and-placeholder` | | | |
| `stale-and-gc` | | | |

**No screen presents one of the four call styles as the default**; across the
catalogue each is used in its turn.

### How it is tested

Three layers and nothing else:

- **Widget tests** run the real app against a `dio` `HttpClientAdapter` that
  mirrors the server route for route and loads the same seed file.
- **A contract test** runs one list of cases against the fake *and*, with the
  server up, against the server. That is what makes the fake trustworthy.
- **End-to-end tests** drive the real web build in Chromium against the real
  backend. Every test gets a backend scenario of its own, so the suite runs
  fully parallel and nothing one test does is visible to another.

Nothing in the browser suite asserts on a clock. To prove something shows
*before* the backend answers, the test holds the request in the browser and
releases it after the assertion; a poll is proven to stop by sampling a request
count, waiting, and sampling again. Flutter web paints to a canvas, so the
tests read the **semantics tree** — the same tree a screen reader gets.

### What building it found

Two library bugs that no ported test could reach; see [how fidelity is
proven](fidelity.md#what-the-examples-found).

## The acceptance demo

`examples/task_manager/` — a small to-do app against a deliberately slow
backend with scripted failures: renaming to `fail` is rejected, every second
delete fails, and a reminder is *accepted* before it is *confirmed*, so a poll
has to survive a confirmation window without stomping the value the user asked
for.

Where the showcase is a catalogue — one screen per feature, so you can look a
feature up — this is the other kind of example: one ordinary app that needs six
of them at once, so you can see how they compose. It was also the library's
acceptance bar, and that checklist is in the app's README, one widget test per
row.

It is also where the four call styles are each used once, in the place each one
genuinely fits — a controller for the list two siblings share, `context.query`
per row, the mixin on the already-stateful detail screen, a select builder for
the header badge.

## The hooks example

`packages/query_kit_hooks/example/` — a small app of posts, todos and
projects on the optional [hooks add-on](../guides/hooks.md). It calls every
hook the package exports, each where an app would call it, and its README
has a table of which hook is used where.

It ships in the package archive, and there it runs against an in-memory
backend in the app's own process: the same requests, 300 ms each, so the
loading states are there to see. The archive holds no platform folders, so
create the ones you want first:

```bash
flutter create . --platforms=web,android,ios
flutter run
```

Its widget tests walk every tab against the in-memory backend on a fake
clock, and a contract test checks that backend against the real one.

In the repository the app also runs against the showcase's server, and two
end-to-end suites, which are not in the archive, prove every hook against
it:

- **Playwright** in Chromium, Firefox and WebKit against the web build, each
  test with a backend scenario of its own.
- **`integration_test`** on a device — an iOS simulator, an Android
  emulator, macOS, Linux or Chrome — with real frames and a real trip to the
  background and back.
