# Changelog

## 0.1.3

- Requires query_kit_flutter 1.2.0, which brings query_kit's typed query
  definitions through this package's import. No hook changed: a
  reference's `options()` go into `useQuery`, `useInfiniteQuery`,
  `useQueries`, `useCombinedQueries` and the prefetch hooks as
  hand-written options do, and into `useSelectQuery` through
  `withSelect`. The result has the data type the definition declared.
- The README and the hooks guide on the site declare their queries as typed
  definitions and read them through the hooks. The guide says what the
  analyzer still lets through: a helper typed `QueryObserverOptions<Object>`
  creates an `Object` entry that the reference then refuses, and an
  `onMutate` parameter written without a type is an `Object?`.
- The example's todo list and its projects are typed definitions, and the
  todo writes go through the list's reference. Their keys are now
  `['todos', 'list']` and `['projects', 'list']` instead of `['todos']` and
  `['projects']`. A raw call on the old prefix still covers them; code
  copied from the example that names the old key exactly needs the new
  one. The posts keep the raw form, so the example shows both.

## 0.1.2

- Move the documentation to https://query-kit.dev/. Update homepage,
  documentation and README links. No API or behavior changes.

## 0.1.1

- Link the package's documentation directly to the hooks guide.
  No API or behavior changes.

## 0.1.0

First release. `query_kit_hooks` is React Query's hooks on
[`flutter_hooks`](https://pub.dev/packages/flutter_hooks), over
[`query_kit_flutter`](https://pub.dev/packages/query_kit_flutter), the
Flutter binding of query_kit, a Dart port of TanStack Query. It re-exports the
binding. It depends on Flutter, `flutter_hooks` and `query_kit_flutter` 1.1.0
or later, and on nothing else. It is an optional add-on for apps whose widgets
are `HookWidget`s: the binding's four call styles do the same job without it.

query_kit is an entirely AI-coded project: all code, tests and documentation
were written by AI coding agents (Anthropic's Claude). A human maintainer set
the goals and reviews releases, but did not write the code. It is a community
port, not affiliated with or endorsed by TanStack.

**Thirteen hooks**

- `useQuery` and `useSelectQuery` for one query, without and with `select`.
- `useInfiniteQuery` for a paged query, as an `InfiniteQueryController`.
- `useMutation` for a mutation, as a `MutationController`.
- `useQueries` for a list of queries, and `useCombinedQueries` for a list
  combined into one `CombinedResult`.
- `useIsFetching` and `useIsMutating` for how many queries are fetching and
  how many mutations are pending.
- `useMutationState` and `useTypedMutationState` for a selection over the
  mutation cache, untyped or typed.
- `usePrefetchQuery` and `usePrefetchInfiniteQuery` to start a fetch without
  reading it.
- `useQueryClient` for the client of the nearest `QueryClientProvider`.

**The binding's rules**

- The hooks read the same cache, by the same rules, as the binding's call
  styles: they are built on its controllers and its rebuild rule.
- No hook rebuilds for a notification carrying what the widget already
  shows. The hooks that read one result take a `buildWhen`.

**Proven by React Query's tests**

React Query's hook suites are ported case by case and run against these
hooks: 269 of 305 upstream cases. Every case left out is listed with its
reason in `test/PORTING_NOTES.md`.

**The example** is a small app of posts, todos and projects that calls every
hook where an app would. It runs against an in-memory backend.

In 0.x, a breaking change is a minor version (0.1 to 0.2).
