---
title: "TanStack Query for Flutter: query_kit, fquery, cached_query and flutter_query compared"
sidebar_label: Other Dart libraries
description: How query_kit compares with the other TanStack-Query-like packages for Dart and Flutter (fquery, cached_query, flutter_query and query_stack), read from each package's own pub.dev listing, README and changelog on 18 October 2026.
---

# Other Dart libraries like TanStack Query

If you are choosing a TanStack-Query-like package for Flutter, query_kit is
one of several. This page describes the others as their own listings,
READMEs and changelogs describe them, and says where each may fit your
project better than query_kit does. It does not rank them.

**All facts here were read on 18 October 2026**, from the versions named in
each section. Packages move; if this page is old when you read it, check the
links. It is written by the people who write query_kit, so check their
documentation before you decide, and
[tell us](https://github.com/dualmeta-gmbh/query_kit/issues) if a description
of theirs is wrong. The rules this page follows are written down in the
repository's [decision
record](https://github.com/dualmeta-gmbh/query_kit/blob/main/docs/adr/0005-the-comparison-page-describes-and-does-not-rank.md).

## At a glance

Facts only, from pub.dev (its API and package pages) and each package's
`pubspec.yaml`. "Dependencies" lists what the pubspec names besides the Dart
and Flutter SDKs.

| Package | Release read | First published | Publisher on pub.dev | Licence | Dependencies |
|---|---|---|---|---|---|
| [`query_kit`](https://pub.dev/packages/query_kit) | 1.0.3, 16 Oct 2026 | 23 Sep 2026 | dualmeta.io | MIT | `clock`, `meta` |
| [`query_kit_flutter`](https://pub.dev/packages/query_kit_flutter) | 1.1.0, 16 Oct 2026 | 23 Sep 2026 | dualmeta.io | MIT | `query_kit`, `meta`, `clock` |
| [`query_kit_hooks`](https://pub.dev/packages/query_kit_hooks) | 0.1.0, 16 Oct 2026 | 16 Oct 2026 | dualmeta.io | MIT | `query_kit_flutter`, `flutter_hooks` |
| [`fquery`](https://pub.dev/packages/fquery) | 3.1.0, 25 Jun 2026 | 2 Jul 2022 | none shown | MIT | `fquery_core`, `flutter_hooks`, `freezed`, `freezed_annotation`, `collection` |
| [`cached_query`](https://pub.dev/packages/cached_query) | 3.7.0, 17 May 2026 | 26 Jun 2022 | cachedquery.dev | MIT | `rxdart`, `meta` |
| [`cached_query_flutter`](https://pub.dev/packages/cached_query_flutter) | 3.4.0, 17 May 2026 | 26 Jun 2022 | cachedquery.dev | MIT | `cached_query`, `connectivity_plus` |
| [`cached_storage`](https://pub.dev/packages/cached_storage) | 3.3.0, 17 May 2026 | 26 Jun 2022 | cachedquery.dev | MIT | `cached_query`, `sqflite`, `path` |
| [`flutter_query`](https://pub.dev/packages/flutter_query) | 0.11.1, 14 Jul 2026 | name on pub.dev since 30 Sep 2020; the current changelog starts at 0.4.0, 8 Jan 2026 | flutterquery.com | MIT | `flutter_hooks`, `clock`, `collection`, `meta` |
| [`query_stack`](https://pub.dev/packages/query_stack) | 1.0.5, 30 May 2023 | 31 Mar 2023 | jc.kodel.com.br | BSD-3-Clause | `rxdart`, `collection` |

## query_kit

[query_kit](../overview.md) is a port of TanStack Query's `query-core` to
Dart, with a Flutter binding on top and an optional hooks add-on. The core
(`query_kit`) is pure Dart. The binding (`query_kit_flutter`) offers four call
styles that behave the same: builder widgets, listenable controllers, a
`State` mixin and `context.query(...)`. The add-on (`query_kit_hooks`) gives
React Query's hook names to apps written with `flutter_hooks`; see
[hooks](../guides/hooks.md).

What it is aimed at: the behaviour of TanStack Query, checked by porting
TanStack Query's own test suites. **414 of the 536** core cases and **269 of
the 305** hook cases are ported, and every case left out is listed with its
reason ([how fidelity is proven](../project/fidelity.md)). Where it differs
on purpose, [that is listed too](differences-from-tanstack.md).

What it gives you less of, and what to weigh:

- **Age.** The first release was on 23 September 2026. `fquery` and `cached_query` have
  been published since 2022.
- **No persistence and no devtools.** There is no built-in persister;
  [offline first and persistence](../cookbook/offline-first-and-persistence.md)
  wires one by hand. Debugging uses the cache's events and an on-screen
  strip, see [debugging](../guides/debugging.md).
- **It is AI-coded.** All code, tests and documentation were written by AI
  coding agents. [Credits](../project/credits.md) says what that means.
- **It follows TanStack Query's shape.** If you do not know that library,
  none of the names (`staleTime`, `gcTime`, `invalidateQueries`) will be
  familiar, and a package that was designed for Flutter first may read more
  naturally.

## fquery

Release read: `fquery` 3.1.0 and `fquery_core` 3.1.0, 25 June 2026.
Documentation: the [README on
GitHub](https://github.com/41y08h/fquery/tree/main/packages/fquery) and the
[API docs on pub.dev](https://pub.dev/documentation/fquery/latest/).

Its pub.dev listing calls it a "simple yet powerful async state management
solution with in-built caching", and its README says the goal is to make
async state management "as easy as instantiating a sync variable". The
README lists automatic caching and garbage collection, re-fetching of stale
data, invalidation, manual updates, dependent, parallel and infinite queries,
and mutations.

How it is shaped, from the README:

- Widgets and hooks over one cache: `QueryBuilder`, `InfiniteQueryBuilder`,
  `QueriesBuilder`, `MutationBuilder` and `IsFetchingBuilder`, and with
  `flutter_hooks` `useQuery`, `useInfiniteQuery`, `useQueries`, `useMutation`
  and `useIsFetching`.
- A `CacheProvider` holds a `QueryCache`. Its changelog says that since 3.0.0
  the `QueryClient` methods live on `QueryCache`.
- Its own option names: `cacheDuration`, `staleDuration`, `refetchOnMount`,
  `refetchInterval`, `retryCount` and `retryDelay`.
- The error type is a type argument of the builder, as in
  `QueryBuilder<List<Todo>, Exception>`.
- Its pubspec lists `flutter_hooks`, `freezed` and `freezed_annotation` as
  dependencies, so they come with the package whichever call style you use.
- The README links a Discord community.

Where it may fit better: you want builders and hooks from one package with an
option set that has its own names rather than TanStack Query's, or you
already use `flutter_hooks` and `freezed` throughout the app.

## cached_query

Release read: `cached_query` 3.7.0, `cached_query_flutter` 3.4.0 and
`cached_storage` 3.3.0, all 17 May 2026. Documentation:
[cachedquery.dev](https://cachedquery.dev/) and the [repository's
README](https://github.com/D-James-GH/cached_query).

Its README describes "a small collection of dart and flutter libraries
inspired by tools such as SWR, RTKQuery, React Query, Urql and apollo", so it
is a library in the same family and not a port. It is split in three:

- **`cached_query`** has no Flutter dependency and can be used in any Dart
  project. A `Query(key:, queryFn:)` is an object you create anywhere; you
  `await query.result` or listen to `query.stream`, built on `rxdart`.
  Configuration is global, through `CachedQuery.instance.config(...)`. The
  README documents `InfiniteQuery`, a `Mutation` with `invalidateQueries`,
  optimistic updates, and a devtools extension. Its changelog lists retrying
  for queries in 3.7.0.
- **`cached_query_flutter`** adds `QueryBuilder` and `MutationBuilder`,
  refetching when the connection returns (through `connectivity_plus`) and
  when the app resumes. Its README has a section on using it with
  `flutter_bloc`.
- **`cached_storage`** is a storage add-on built on `sqflite`. The README
  describes the persistent cache as "flutter ios/android only", or you
  implement your own `StorageInterface`.

Where it may fit better: you need a persisted cache or the devtools
extension today, your app is organised around streams or `flutter_bloc`, or
you want the same cache library in a Dart server or command-line tool and in
the Flutter app. query_kit's core can also run without Flutter, but it has
neither persistence nor devtools.

## flutter_query

Release read: `flutter_query` 0.11.1, 14 July 2026. Documentation:
[flutterquery.com](https://flutterquery.com), its [coming from TanStack
Query](https://flutterquery.com/docs/coming-from-tanstack-query) page, and the
[repository](https://github.com/jezsung/query/tree/main/packages/flutter_query).

Its pub.dev description is "Fetch, cache, and sync server data with automatic
state management and background updates, inspired by TanStack Query." This is
a different package from query_kit with a similar name; the
`flutter_query` name on pub.dev goes back to 2020, and the changelog covers
the line that starts at 0.4.0.

How it is shaped, from the README and changelog:

- Hooks on `flutter_hooks`: `useQuery`, `useMutation`, `useInfiniteQuery`,
  `useQueryClient`, `useIsFetching`, `useIsMutating` and `useMutationState`.
  Its README lists no builder widgets.
- A `QueryClient` and a `QueryClientProvider`. Its changelog describes sealed
  snapshot results, graduated from an experimental library in 0.11.0, and
  `seed` and `placeholder` options that take sealed values.
- Names that differ from TanStack Query on purpose, which its comparison
  page explains: `Duration`-based `staleDuration` and `gcDuration`, `seed`
  for `initialData`, `placeholder` for `placeholderData`, and a single
  `retry` callback in place of `retry` and `retryDelay`.
- Offline behaviour, as its changelog describes it, needs a
  `connectivityChanges` stream passed to the `QueryClient`.
- It is on 0.x, and its README says that before 1.0.0 a minor version may
  include breaking changes; its changelog marks several. Its pubspec asks
  for Flutter 3.32 or later.

Where it may fit better: you write your screens with hooks and want a
package built around that from the start, with a documented list of where it
leaves TanStack Query behind. `query_kit_hooks` also offers hooks, with
React Query's own names and option types and with React Query's hook tests
ported; the two are alternatives, not companions.

## query_stack

Release read: `query_stack` 1.0.5, 30 May 2023. Documentation: its
[README on GitHub](https://github.com/JCKodel/query_stack).

Its pub.dev listing is marked discontinued, with `streamline` named as the
replacement. The listing for `streamline` describes it as a "CQRS/Mediator
Pattern library". The `query_stack` README says it is "inspired by" TanStack
Query and that the package has three parts: dependency injection through
environments, stream builders and future builders.

## Others on pub.dev

These two turned up while checking and were not examined beyond their
listings. Both are young: their first versions are from 2026.

- [`tanquery`](https://pub.dev/packages/tanquery) 0.8.0, 23 May 2026:
  "TanStack Query for Dart", described as pure Dart with no Flutter
  dependency.
- [`swrly`](https://pub.dev/packages/swrly) 0.4.0, 22 September 2026:
  "A TanStack Query for Flutter", with deduplication, caching by query key
  and stale-while-revalidate.

## Choosing

None of this is a verdict. Questions that separate these packages in
practice, each answered by the packages' own documentation:

- **Do you need a persisted cache or devtools now?** `cached_query` documents
  both.
- **Do you write with `flutter_hooks`?** `fquery`, `flutter_query` and
  `query_kit_hooks` all have hooks; they differ in names, in option types and
  in what they depend on.
- **Do you want TanStack Query's names and behaviour, or a design of its
  own?** query_kit aims at the first. The others chose their own vocabulary,
  to different degrees.
- **How long a track record do you want?** `fquery` and `cached_query` have
  been on pub.dev since 2022; query_kit since September 2026.

For a name-by-name map from TanStack Query to query_kit, see [coming from
React Query](../coming-from-react-query.md).
