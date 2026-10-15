# Changelog

## Unreleased

- A new library, `package:query_kit_flutter/adapter.dart`, exports
  `RebuildRule`: the decision every call style makes about whether a
  notification is worth a rebuild, for packages that read queries in a shape
  of their own, such as `query_kit_hooks`. It owns no controller and
  listens to nothing. `RebuildRule.of(controller)` is the rule the call
  styles use for one of the binding's controllers, and `BuildWhen`, the
  predicate it asks, is exported with it. Apps do not need the library, and
  the main library is unchanged.
- The four call styles now make that decision through `RebuildRule`. Their
  behaviour does not change, but for the fix below.
- Fixed: a `buildWhen` on an infinite query that declined a change of the
  result also held back a change of the paging flags made with it. A refetch
  that kept the data and found no next page left "Load more" on screen while
  `hasNextPage` was `false`. A move of the paging flags now rebuilds without
  asking `buildWhen`, whether the result moved with it or not, in
  `InfiniteQueryBuilder`, `context.infiniteQuery` and `watchInfiniteQuery`.
  `RebuildRule` takes that part as `beside`.

## 1.0.4

- `QueryBuilder`, `QuerySelectBuilder`, `InfiniteQueryBuilder`,
  `QueriesBuilder` and `MutationBuilder` apply new options, and a new
  `client`, in `build` instead of when their parent hands them a new widget.
  Options that throw while being applied — a new key whose
  `InitialData.compute` throws, say, or a `client` left with no
  `QueryClientProvider` above — used to leave the widget behind without
  disposing it, and its observer, with any `refetchInterval`, kept running
  after the screen was gone. Now the failure is an ordinary build error: the
  widget shows the error and, on the same client, keeps its observer, a
  refetch in flight and a running mutation, takes up the next options that
  apply, and releases everything when it goes. A change of client releases
  the old client's observer even when the new one cannot be made. `context.query` and `QueryMixin` always worked
  this way.
- The documentation of `QueryMixin` and `context.query` no longer promises
  that nothing a reader shows loses its subscription. A nested builder kept
  in a field — `late final` — and reading through the outer `State` or
  `context` is not re-run by that reader's own build that reads, so its key
  is released there while it is still shown, until it runs again and reads.
  A `build` that reads nothing releases nothing, and neither does a new
  widget from the parent on its own: the first read after it counts as the
  own build. The fix, now in the troubleshooting guide, is a widget of its
  own for the nested part.

## 1.0.3

No change to the code. The documentation site moved to its own address,
<https://query-kit.dualmeta.io/>; the package page's homepage and
documentation links, the README and the library's dartdoc name it, and the
former address redirects there. The README opens with a title a reader
searches for, "TanStack Query for Flutter | query_kit", instead of the package name,
which pub.dev's own heading above it already shows.

## 1.0.2

No change to the code. The package description on pub.dev read "AI- coded",
because its line was wrapped at the hyphen; it reads "AI-coded" again.

## 1.0.1

No change to the code. The package page now names the documentation site,
<https://dualmeta-gmbh.github.io/query_kit/>, as its homepage and
documentation, the README opens with a link to it, the quick start, the
examples and the API reference, and the description says what the package is:
TanStack Query for Flutter.

## 1.0.0

First release. `query_kit_flutter` is the Flutter binding for
[`query_kit`](https://pub.dev/packages/query_kit), a Dart port of TanStack
Query, and re-exports it. It depends on Flutter, `meta` and `query_kit` and
on nothing else. From here on, a breaking change is a major version.

query_kit is an entirely AI-coded project: all code, tests and documentation
were written by AI coding agents (Anthropic's Claude). A human maintainer set
the goals and reviews releases, but did not write the code. It is a community
port, not affiliated with or endorsed by TanStack.

**Setup**

- `QueryClientProvider` places a `QueryClient` above the tree and mounts it;
  `QueryClientProvider.create` builds and owns one. `of`, `read` and
  `maybeOf` find it.
- The app lifecycle drives the client's focus state, so queries refetch when
  the app returns to the foreground; `inactive` is read per platform and
  `isAppShown` overrides the mapping.
- Connectivity is opt-in through `OnlineStatus.fixed` or
  `OnlineStatus.stream`; nothing is installed by default.

**Four equal ways to read a query**

- `context.query(options)` and `context.selectQuery` in any widget.
- `QueryBuilder` and `QuerySelectBuilder`, the `StreamBuilder` shape.
- `QueryMixin` on a `State`: `watchQuery`, `watchSelectQuery`,
  `watchInfiniteQuery`, `watchMutation`.
- `QueryController`, a `ValueListenable<QueryResult<T>>` that works without
  widgets and with any package that reads a listenable.

**Infinite queries and mutations** in the same four shapes:
`context.infiniteQuery`, `InfiniteQueryBuilder`, `watchInfiniteQuery`,
`InfiniteQueryController` (with paging on the controller), and
`context.mutation`, `MutationBuilder`, `watchMutation`, `MutationController`
(with `mutate`, `mutateAsync`, `reset` and `cancel`).

**Rebuilds**

- A widget rebuilds when its result changes. `select` narrows the data it
  sees; `buildWhen`, taken by every builder and every read (`context.query`,
  `watchQuery`, …), decides when it rebuilds.
- Results that arrive during a build are delivered after the frame.

**Beside the four styles**

- `QueryListener`, `InfiniteQueryListener` and `MutationListener` for side
  effects (snackbars, navigation), with `listenWhen`.
- `QueriesBuilder` and `QueriesController` for a dynamic list of queries;
  the core's `combine` over results of different types, whichever call
  style read them.
- `MutationStateController` (and `.typed`) for cache-wide mutation state,
  `IsFetchingController` for a global loading indicator.

**Testing**

- Controllers are testable without widgets. A widget test ends with a short
  teardown — take the tree down, `clear()` the client — documented in the
  README and the testing guide; nothing test-only is exported.

Requires Flutter 3.27 or later.
