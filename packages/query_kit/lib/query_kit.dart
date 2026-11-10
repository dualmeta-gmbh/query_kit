/// Asynchronous state management for Dart: fetching, caching, refetching,
/// invalidation and mutations of server data — a port of TanStack Query's
/// `query-core` that runs anywhere Dart runs, no Flutter needed.
///
/// > query_kit is an entirely AI-coded project: all code, tests and
/// > documentation were written by AI coding agents (Anthropic's Claude). A
/// > human maintainer set the goals and reviews releases, but did not write
/// > the code.
///
/// query_kit is an independent community port and is not affiliated with or
/// endorsed by TanStack. For Flutter widgets on top of it, see the
/// `query_kit_flutter` package.
///
/// ## Quick start
///
/// A [QueryClient] owns the cache. Describe a query with [QueryOptions] — a
/// [QueryKey] that identifies it and a query function that fetches it —
/// then fetch it imperatively with [QueryClient.query], or follow it with a
/// [QueryObserver], which fetches on subscribe, refetches when the data is
/// stale and something happens (focus, reconnect, invalidation), and reports
/// every change as a sealed [QueryResult].
///
/// ```dart
/// import 'package:query_kit/query_kit.dart';
///
/// Future<void> main() async {
///   final client = QueryClient()..mount();
///   final todosKey = QueryKey(['todos']);
///
///   // Fetch once and cache.
///   final todos = await client.query(QueryOptions<List<String>>(
///     queryKey: todosKey,
///     queryFn: (context) => fetchTodos(),
///     staleTime: const StaleTime.duration(Duration(seconds: 30)),
///   ));
///   print(todos);
///
///   // Observe: every change to the entry, as a sealed result.
///   final observer = QueryObserver(
///     client,
///     QueryObserverOptions<List<String>>(
///       queryKey: todosKey,
///       queryFn: (context) => fetchTodos(),
///     ),
///   );
///   final unsubscribe = observer.subscribe((result) {
///     switch (result) {
///       case QueryPending():
///         print('loading');
///       case QuerySuccess(:final data):
///         print('todos: $data');
///       case QueryError(:final error):
///         print('failed: $error');
///     }
///   });
///
///   // Mark stale and refetch what is observed.
///   await client.invalidateQueries(filters: QueryFilters(queryKey: todosKey));
///
///   unsubscribe();
///   client.unmount();
///   client.clear();
/// }
///
/// Future<List<String>> fetchTodos() async => ['Buy milk', 'Walk the dog'];
/// ```
///
/// ## Where to go next
///
/// The API is grouped into categories:
///
/// * **Client** — [QueryClient] and its defaults.
/// * **Queries**, **Options**, **Option values** — [QueryKey], [QueryOptions]
///   and the sealed option values such as [StaleTime], [RetryPolicy] and
///   [RefetchInterval].
/// * **Results** and **Combining results** — [QueryResult] and
///   [CombinedResult].
/// * **Observers** — [QueryObserver], [InfiniteQueryObserver],
///   [MutationObserver], [QueriesObserver], [MutationStateObserver].
/// * **Mutations** and **Infinite queries** — [MutationOptions],
///   [InfiniteQueryOptions] and friends.
/// * **Caches**, **Filters**, **Structural sharing**, **Errors**, **Managers**
///   — [QueryCache], [MutationCache], [QueryFilters], [replaceEqualDeep],
///   [AppFocusManager], [OnlineManager], [NotifyManager].
/// * **Typed queries** — [QueryDefinition], [QueryFamily] and their infinite
///   twins: a query declared once, see below.
/// * **Advanced** — the plumbing: cache events, actions, fetch behaviours.
///
/// ## Typed query definitions
///
/// A key and its data type meet at every call: `getQueryData<Device>(key)`
/// is right only as long as each caller repeats the type the fetch function
/// returns. A definition states both once, and hands out references that
/// carry the type.
///
/// ```dart
/// final devices = QueryNamespace(['devices']);
///
/// final deviceList = QueryDefinition<List<Device>>(
///   namespace: devices,
///   name: 'list',
///   queryFn: (context) => api.devices(),
/// );
///
/// final deviceDetail = QueryFamily<String, Device>(
///   namespace: devices,
///   name: 'detail',
///   queryFn: (id, context) => api.device(id),
/// );
///
/// final device = deviceDetail('d1'); // QueryRef<Device>
/// final observer = QueryObserver(client, device.options());
/// final Device? cached = device.read(client);
/// device.write(client, updated);
/// await deviceDetail.invalidate(client); // every detail
/// await devices.invalidate(client); // everything under ['devices']
/// ```
///
/// Four things, each with its own job:
///
/// * A **definition** declares a query: [QueryDefinition] for one without
///   an input, [QueryFamily] for one per input, and
///   [InfiniteQueryDefinition] and [InfiniteQueryFamily] for paged data.
///   It is declared once and holds no client and no state.
/// * A **reference** is a definition bound to its input, one cache entry:
///   a [QueryRef] or an [InfiniteQueryRef], both a [QueryEntryRef]. It
///   gives the options for an observer, fetches, reads and writes with the
///   declared type. A definition without an input is its own reference.
/// * A **typed key**, [TypedQueryKey], is a reference's key with its data
///   type: a value for a map or a set that can still read and write its
///   entry. A family's `readAll` returns one per entry, which is how a
///   snapshot of many entries is put back.
/// * A **namespace**, [QueryNamespace], is the key prefix a group of
///   definitions shares. It claims no data type, so it invalidates and
///   removes, and neither reads nor writes.
///
/// A definition, a reference and a namespace are each a [QueryTarget],
/// the argument of everything that needs no data type: `invalidate`,
/// `refetch`, `cancel`, `reset`, `remove`, `filters`. A typed key is not
/// one. It reads and writes its entry and has none of those operations;
/// the reference it came from has them.
///
/// They sit on top of the client and change nothing about it. A typed
/// reference and a plain [QueryKey] with the same parts are the same cache
/// entry, so an application can move one query at a time.
///
/// What they cannot do for you:
///
/// * **Write the type arguments on every definition**:
///   `QueryDefinition<List<Device>>(...)`, `QueryFamily<String, Device>(...)`,
///   `InfiniteQueryDefinition<List<Post>, int>(...)`. Nothing tells Dart a
///   family's input type, and an infinite definition left to inference
///   loses its page type: a `getNextPageParam` that reads its page does
///   not compile, and with a `configure` the page type becomes `Object?`
///   without a diagnostic. A debug build refuses a definition whose type
///   argument was left to become `dynamic` or `Object?`.
/// * **A reference assigned to a wider type is checked when it runs.**
///   Through a `QueryRef<Object?>` a write of the wrong type compiles; it
///   throws before anything is written, a `TypeError` from the language
///   or, in a build that compiles that check out, a [QueryDataTypeError].
/// * **A collection literal widens without being asked.** Two references
///   of one class and two data types, `[ints('a'), strings('a')]`, are a
///   `List<QueryRef<Object>>`, and a write through an element is checked
///   when it runs, as above. For a list that is only invalidated,
///   refetched or removed, say `<QueryTarget>[...]`: a target has no
///   write.
/// * **`configure` returns options of the definition's own type**, the
///   ones it is handed or a `copyWith` of them. Options of a narrower data
///   type satisfy its return type and are refused with a `StateError` when
///   the options are made.
/// * **Only an infinite definition holds a written `InfiniteData` to its
///   page types.** A plain `QueryDefinition<InfiniteData<P, Q>>` stores
///   the value it is given.
/// * **A plain key leaves the typed surface.** `rawKey` is there for an
///   API that takes a [QueryKey]; with `client.setQueryData(ref.key.rawKey,
///   ...)` the type argument is yours to get right again.
/// * **A typed key knows the type, not the definition.** An entry its
///   `write` creates has the key's data type and the client's defaults,
///   and none of the definition's options, its fetch function included,
///   until an observer of the reference's options, or a fetch through the
///   reference that does fetch, brings them.
///   Write through the reference to create an entry with them.
/// * **A family's reference makes new options every time.** It binds its
///   input into a new fetch function per `options()` call, so an observer
///   handed them again takes them as changed options, as it does options
///   written inline. A definition without an input hands out the function
///   it was declared with, and its options are equal once defaulted,
///   which is what an observer compares, unless its `configure` builds
///   something new each time it runs.
/// * **Nothing registers definitions.** Two that share a namespace and a
///   name with different data types are found at the first read or write
///   of the second type, with a [QueryDataTypeError]. Two with the same
///   data type and different fetch functions are one cache entry, and
///   nothing reports it.
/// * **A record input that holds a list, a map or a set needs a `keyOf`.**
///   A record compares its fields with `==` and a list is equal only to
///   itself, so two equal inputs would be two entries.
///
/// Guides, recipes and live examples are on the documentation site:
/// https://query-kit.dev/
library;

// Export policy (maintainer note): what is exported is the public surface,
// close to TanStack's `index.ts`. The plumbing between the pieces — the
// cache-side interfaces (`*CacheRef`), the retryer — is not, so that it can
// change without a major version. What a public signature names *is*
// exported, so that every field can be typed by its reader: the
// `QueryAction` and `MutationAction` families, the `*ObserverRef`
// interfaces, and `FetchBehavior`/`FetchContext`, the type of
// `QueryOptions.behavior`. They are read-only from outside; dispatching an
// action, implementing a ref or building a fetch context is not public API,
// and the refs' members are `@internal`.

export 'src/cancel_token.dart';
export 'src/combined_result.dart';
export 'src/filters.dart' hide describeFilters;
export 'src/focus_manager.dart';
export 'src/infinite_query.dart'
    hide
        InfiniteQueryBehavior,
        addToEnd,
        addToStart,
        hasNextPage,
        hasPreviousPage,
        nextPageParam,
        previousPageParam;
export 'src/infinite_query_observer.dart' hide hasNextPageOf, hasPreviousPageOf;
export 'src/mutation.dart' hide MutationCacheRef;
export 'src/mutation_cache.dart';
export 'src/mutation_observer.dart';
export 'src/mutation_options.dart';
export 'src/mutation_result.dart';
export 'src/mutation_state_observer.dart';
export 'src/notify_manager.dart';
export 'src/online_manager.dart';
export 'src/option_values.dart';
export 'src/queries_observer.dart';
export 'src/query.dart' hide QueryCacheRef;
export 'src/query_cache.dart';
export 'src/query_client.dart';
export 'src/query_definition.dart';
export 'src/query_key.dart';
export 'src/query_observer.dart';
export 'src/query_options.dart' hide isNoStructuralSharing;
export 'src/query_result.dart';
export 'src/query_state.dart';
export 'src/structural_sharing.dart' hide sharingBucketOf;
