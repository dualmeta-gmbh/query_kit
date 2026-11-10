/// Typed query definitions: a query declared once, with its input, its key
/// and its fetch function, and the references that carry its data type to
/// every read, write and invalidation.
///
/// One library, because the hierarchy is closed: [QueryTarget] and
/// [QueryEntryRef] are sealed and [QueryRef] and [InfiniteQueryRef] cannot
/// be extended elsewhere, so every type that is one of them lives here.
///
/// Nothing here owns state. A definition, a reference and a typed key hold
/// a key and functions; the cache, the observers and the fetches are the
/// client's, reached through the client each operation is handed.
library;

import 'dart:async';

import 'filters.dart';
import 'infinite_query.dart';
import 'query.dart';
import 'query_cache.dart';
import 'query_client.dart';
import 'query_key.dart';
import 'query_options.dart';
import 'query_state.dart';

/// What a cache operation is aimed at: one entry (a [QueryRef] or an
/// [InfiniteQueryRef]), every input of one operation (a [QueryFamily] or an
/// [InfiniteQueryFamily]) or everything under a key prefix (a
/// [QueryNamespace]).
///
/// It names no data type, so it offers the operations that need none:
/// [invalidate], [refetch], [cancel], [reset], [remove] and [filters]. A
/// reference acts on exactly its own entry; a family and a namespace act on
/// every entry whose key starts with theirs.
///
/// ```dart
/// Future<void> refresh(QueryClient client, QueryTarget target) =>
///     target.invalidate(client);
///
/// await refresh(client, devices.detail('d1')); // one entry
/// await refresh(client, devices.detail); // every detail
/// await refresh(client, devices.namespace); // everything under 'devices'
/// ```
///
/// The type is sealed: a `switch` over a target is exhaustive, and nothing
/// outside this package can be one. A list of references of different data
/// types is a `List<QueryTarget>`, which can be invalidated and not written.
///
/// {@category Typed queries}
sealed class QueryTarget {
  QueryTarget._();

  QueryKey get _selector;

  bool get _exact;

  /// The filters that select this target, for everything that takes
  /// [QueryFilters]: the client's bulk operations, `QueryClient.isFetching`,
  /// a cache listener.
  ///
  /// The key and whether it matches exactly are the target's own. The
  /// arguments narrow the selection further, as they do on [QueryFilters].
  ///
  /// ```dart
  /// final loading = client.isFetching(filters: devices.detail.filters());
  /// final stale = devices.namespace.filters(stale: true);
  /// ```
  QueryFilters filters({
    QueryTypeFilter? type,
    bool? stale,
    FetchStatus? fetchStatus,
    QueryStatus? status,
    bool Function(Query<Object?> query)? predicate,
  }) =>
      QueryFilters(
        queryKey: _selector,
        exact: _exact,
        type: type,
        stale: stale,
        fetchStatus: fetchStatus,
        status: status,
        predicate: predicate,
      );

  /// Marks every selected entry stale and refetches the ones in use:
  /// [QueryClient.invalidateQueries] over this target, with its parameters.
  Future<void> invalidate(
    QueryClient client, {
    RefetchType? refetchType,
    bool cancelRefetch = true,
  }) =>
      client.invalidateQueries(
        filters: filters(),
        refetchType: refetchType,
        cancelRefetch: cancelRefetch,
      );

  /// Refetches every selected entry that can fetch:
  /// [QueryClient.refetchQueries] over this target.
  Future<void> refetch(QueryClient client, {bool cancelRefetch = true}) =>
      client.refetchQueries(filters: filters(), cancelRefetch: cancelRefetch);

  /// Cancels the fetches in flight for the selected entries:
  /// [QueryClient.cancelQueries] over this target. An optimistic update
  /// calls this first, so that a response on its way cannot overwrite the
  /// value it is about to write.
  Future<void> cancel(
    QueryClient client, {
    bool revert = true,
    bool silent = false,
  }) =>
      client.cancelQueries(filters: filters(), revert: revert, silent: silent);

  /// Puts every selected entry back to its initial state and refetches the
  /// ones in use: [QueryClient.resetQueries] over this target.
  Future<void> reset(QueryClient client, {bool cancelRefetch = true}) =>
      client.resetQueries(filters: filters(), cancelRefetch: cancelRefetch);

  /// Removes every selected entry from the cache:
  /// [QueryClient.removeQueries] over this target. Removing a reference's
  /// entry is how a rollback restores "nothing was cached".
  void remove(QueryClient client) => client.removeQueries(filters: filters());
}

/// A key prefix that groups query definitions, such as everything about
/// devices.
///
/// A namespace claims no data type: the entries under it may hold anything.
/// So it can invalidate, refetch, cancel, reset and remove them, and it has
/// no read and no write. Each definition is given the namespace it belongs
/// to, and its keys start with the namespace's parts.
///
/// ```dart
/// final devices = QueryNamespace(['devices']);
///
/// final detail = QueryFamily<String, Device>(
///   namespace: devices,
///   name: 'detail',
///   queryFn: (id, context) => api.device(id),
/// );
///
/// await devices.invalidate(client); // every entry under ['devices']
/// ```
///
/// Whatever changes what a query returns belongs in its key, and a
/// namespace is a natural place for the part that is the same for a whole
/// group: `QueryNamespace(['tenant', tenantId, 'devices'])`.
///
/// {@category Typed queries}
final class QueryNamespace extends QueryTarget {
  /// The namespace of every key that starts with [parts]. The parts follow
  /// [QueryKey]'s rules: collections are frozen, and an object needs value
  /// equality.
  QueryNamespace(List<Object?> parts)
      : rawKey = QueryKey(parts),
        super._();

  /// The prefix as a plain [QueryKey], for an API that takes one.
  final QueryKey rawKey;

  @override
  QueryKey get _selector => rawKey;

  @override
  bool get _exact => false;

  @override
  String toString() => 'QueryNamespace(${rawKey.debugString})';
}

/// A [QueryKey] that remembers the data type cached under it.
///
/// A reference's [QueryEntryRef.key] is one. It reads the entry and its
/// state with the right type and no type argument, and it is a value: two
/// typed keys are equal when their raw keys and their data types are, so it
/// can be a map key or a member of a set.
///
/// ```dart
/// final key = devices.detail('d1').key; // TypedQueryKey<Device>
/// final Device? cached = key.read(client);
/// final QueryState<Device>? state = key.state(client);
/// ```
///
/// Only a definition or a reference makes one: there is no public
/// constructor and no conversion from a plain key, because the data type
/// would then be whatever the caller claimed. It has no write either; a
/// write goes through the reference, which knows how to create the entry.
///
/// {@category Typed queries}
final class TypedQueryKey<T> {
  const TypedQueryKey._(this.rawKey);

  /// The key the cache compares. Handing it to the client's own methods
  /// (`getQueryData`, `setQueryData`, a [QueryFilters]) leaves the typed
  /// surface: the type argument is then the caller's to get right.
  final QueryKey rawKey;

  /// The data type the entry under [rawKey] holds, exactly.
  Type get dataType => T;

  /// The cached data, or `null` when there is none: [QueryClient.getQueryData]
  /// with the key's data type. Throws [QueryDataTypeError] when the entry
  /// holds another type.
  ///
  /// With a nullable data type a cached `null` and no data read the same
  /// here; [state] tells them apart.
  T? read(QueryClient client) => client.getQueryData<T>(rawKey);

  /// The entry's state, or `null` when there is no entry:
  /// [QueryClient.getQueryState] with the key's data type. Its
  /// `hasData` is what tells a cached `null` from no data.
  QueryState<T>? state(QueryClient client) => client.getQueryState<T>(rawKey);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TypedQueryKey<Object?> &&
          other.dataType == T &&
          other.rawKey == rawKey;

  @override
  int get hashCode => Object.hash(T, rawKey);

  @override
  String toString() => 'TypedQueryKey<$T>(${rawKey.debugString})';
}

/// One cache entry and the data type it holds: what a [QueryRef] and an
/// [InfiniteQueryRef] have in common.
///
/// It reads and writes the entry with the declared type, and acts on
/// exactly that entry as a [QueryTarget]. It has no `options()`, because a
/// plain and an infinite query take different options; a function that
/// needs only the cache takes this type and works for both.
///
/// ```dart
/// T? optimistic<T>(QueryClient client, QueryEntryRef<T> entry, T value) {
///   final previous = entry.read(client);
///   entry.write(client, value);
///   return previous;
/// }
/// ```
///
/// {@category Typed queries}
sealed class QueryEntryRef<T> extends QueryTarget {
  QueryEntryRef._(QueryKey rawKey)
      : key = TypedQueryKey<T>._(rawKey),
        super._();

  /// The entry's key with its data type.
  final TypedQueryKey<T> key;

  @override
  QueryKey get _selector => key.rawKey;

  @override
  bool get _exact => true;

  /// The options an entry created by a write is built with.
  QueryOptions<T> _entryOptions();

  /// The value as the entry stores it. Identity except for paged data.
  T _normalise(T value) => value;

  /// The cached data, or `null` when there is none. A plain read: it
  /// neither fetches nor subscribes. Throws [QueryDataTypeError] when the
  /// entry holds another type.
  ///
  /// With a nullable data type a cached `null` and no data read the same
  /// here; [state] tells them apart.
  T? read(QueryClient client) => key.read(client);

  /// The entry's state, or `null` when there is no entry. Its `hasData` is
  /// what tells a cached `null` from no data.
  QueryState<T>? state(QueryClient client) => key.state(client);

  /// Writes [value] into the cache and returns what the cache then holds
  /// (after structural sharing, that may be the instance already cached).
  ///
  /// The tool for an optimistic update and for putting a mutation's
  /// response into the cache. Every observer of the entry sees the value at
  /// once, and the entry counts as fetched at [updatedAt] (default: now).
  ///
  /// ```dart
  /// final device = devices.detail('d1');
  /// device.write(client, updated);
  /// ```
  ///
  /// The entry has the reference's data type, whatever the value's own type
  /// is: a `Thermostat` written through a `QueryRef<Device>` creates an
  /// entry of `Device`, and `null` written through a `QueryRef<Device?>` is
  /// stored as a cached `null`. An entry the write creates is built with
  /// the definition's options, so its `gcTime` and `structuralSharing`
  /// apply from this first write.
  ///
  /// Throws [QueryDataTypeError], and writes nothing, when the entry
  /// already exists with another data type (a `Device?` entry made through
  /// the client's `setQueryData` is another type than `Device`), or when
  /// [value] is not of the reference's type, which only a reference held
  /// under a wider type argument lets through the analyzer.
  T write(QueryClient client, T value, {DateTime? updatedAt}) {
    final rawKey = key.rawKey;
    final existing = client.queryCache.get<T>(rawKey);
    return _store(client, existing, _checked<T>(value, rawKey), updatedAt);
  }

  /// Writes what [updater] returns for the data cached now, and returns
  /// what the cache then holds.
  ///
  /// [updater] receives the current data, `null` when there is none, and
  /// returning `null` writes nothing: the call then returns `null` and
  /// creates no entry. To store `null` under a nullable type, use [write].
  ///
  /// ```dart
  /// device.update(client, (previous) => previous?.copyWith(isOn: true));
  /// ```
  ///
  /// Otherwise as [write]: the entry keeps the reference's data type, and
  /// a mismatch throws [QueryDataTypeError] with nothing written.
  T? update(
    QueryClient client,
    T? Function(T? previous) updater, {
    DateTime? updatedAt,
  }) {
    final rawKey = key.rawKey;
    final existing = client.queryCache.get<T>(rawKey);
    final previous =
        existing != null && existing.state.hasData ? existing.state.data : null;
    final Object? next = updater(previous);
    if (next == null) {
      return null;
    }
    final value = _checked<T>(next, rawKey);
    // Looked up again: the updater is the caller's code and may have
    // removed the entry, or made it.
    return _store(client, client.queryCache.get<T>(rawKey), value, updatedAt);
  }

  T _store(
    QueryClient client,
    Query<T>? existing,
    T value,
    DateTime? updatedAt,
  ) =>
      _write<T>(
        client,
        existing,
        _normalise(value),
        updatedAt,
        _entryOptions,
      );
}

/// A reference to one cache entry of a plain query: a definition bound to
/// its input.
///
/// Calling a [QueryFamily] returns one, and a [QueryDefinition] is one. It
/// is what an application passes around instead of a key and a type
/// argument:
///
/// ```dart
/// final device = devices.detail('d1'); // QueryRef<Device>
///
/// final observer = QueryObserver(client, device.options());
/// final Device fetched = await device.fetch(client);
/// final Device? cached = device.read(client);
/// device.write(client, updated);
/// await device.invalidate(client);
/// ```
///
/// A reference is a value. It holds no client, so it can be a constant of
/// the application and be used with any client, and making one fetches
/// nothing, creates no cache entry and starts no timer. Two references are
/// equal when they address the same entry with the same data type, whichever
/// definition instance made them; the fetch function is not compared. A
/// plain and an infinite reference are never equal.
///
/// A reference can be assigned to a wider type, `QueryRef<Object?>`. A
/// write through it of a value that is not of the real data type then
/// compiles, and is refused when it runs, before anything is written.
///
/// {@category Typed queries}
abstract final class QueryRef<T> extends QueryEntryRef<T> {
  QueryRef._(super.rawKey) : super._();

  /// The options of this query, for an observer, [QueryClient.query] or
  /// any other consumer of [QueryObserverOptions].
  ///
  /// Each call returns new options: the definition's key and fetch
  /// function, with what its `configure` set. Change them for one use with
  /// `copyWith`, and select from the data with `withSelect`:
  ///
  /// ```dart
  /// final options = device.options().copyWith(
  ///   staleTime: const StaleTime.duration(Duration(minutes: 1)),
  /// );
  /// final name = device.options().withSelect((device) => device.name);
  /// ```
  ///
  /// A `copyWith` cannot unset what the definition set (`null` means "keep"),
  /// and a `copyWith(queryKey: ...)` or `copyWith(queryFn: ...)` leaves the
  /// definition behind: the options then describe another query.
  QueryObserverOptions<T> options();

  @override
  QueryOptions<T> _entryOptions() => options();

  /// Fetches the query and completes with its data: [QueryClient.query]
  /// with [options].
  ///
  /// It does not always make a request. Data that is still fresh by the
  /// definition's `staleTime` is returned as it is, and a fetch already in
  /// flight is joined. With [revalidateIfStale], stale data is returned at
  /// once while it refreshes in the background.
  Future<T> fetch(QueryClient client, {bool revalidateIfStale = false}) =>
      client.query<T>(options(), revalidateIfStale: revalidateIfStale);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is QueryRef<Object?> && other.key == key;

  @override
  int get hashCode => Object.hash(QueryRef, key);

  @override
  String toString() => 'QueryRef<$T>(${key.rawKey.debugString})';
}

/// A reference to one cache entry of an infinite query: an infinite
/// definition bound to its input.
///
/// Calling an [InfiniteQueryFamily] returns one, and an
/// [InfiniteQueryDefinition] is one. The entry holds an
/// `InfiniteData<TPageData, TPageParam>`, and the reference reads, writes
/// and fetches it as a [QueryRef] does a plain value:
///
/// ```dart
/// final feed = posts.feed; // InfiniteQueryRef<List<Post>, int>
///
/// final observer = InfiniteQueryObserver(client, feed.options());
/// final pages = feed.read(client)?.pages;
/// feed.update(
///   client,
///   (data) => data?.copyWith(pages: [
///     for (final page in data.pages) page.where((post) => post.id != id).toList(),
///   ]),
/// );
/// ```
///
/// A written value is stored under the declared page types. An
/// `InfiniteData` built elsewhere with narrower type arguments, say of
/// `List<Never>` pages, is rebuilt from its pages, so that a later
/// `copyWith` on the cached value takes a page of the declared type.
///
/// It is a value in the way a [QueryRef] is, and never equal to one.
///
/// {@category Typed queries}
abstract final class InfiniteQueryRef<TPageData, TPageParam>
    extends QueryEntryRef<InfiniteData<TPageData, TPageParam>> {
  InfiniteQueryRef._(super.rawKey) : super._();

  /// The options of this query, for an `InfiniteQueryObserver`,
  /// [QueryClient.infiniteQuery] or any other consumer of
  /// [InfiniteQueryObserverOptions].
  ///
  /// Each call returns new options: the definition's key and paging
  /// functions, with what its `configure` set. `copyWith` changes them for
  /// one use and `withSelect` selects from the pages, as on
  /// [QueryRef.options]. A `structuralSharing` or an `initialData` given
  /// through such a `copyWith` is used as it is, and so is a
  /// `structuralSharing` from the client's defaults or from
  /// [QueryClient.setQueryDefaults]; only the definition's own are held to
  /// the declared page types.
  InfiniteQueryObserverOptions<TPageData, TPageParam> options();

  @override
  QueryOptions<InfiniteData<TPageData, TPageParam>> _entryOptions() =>
      options();

  @override
  InfiniteData<TPageData, TPageParam> _normalise(
    InfiniteData<TPageData, TPageParam> value,
  ) =>
      _exactInfinite<TPageData, TPageParam>(value);

  /// Fetches the query and completes with its pages:
  /// [QueryClient.infiniteQuery] with [options]. Fresh data is returned as
  /// it is and a fetch in flight is joined, as [QueryRef.fetch] does.
  Future<InfiniteData<TPageData, TPageParam>> fetch(
    QueryClient client, {
    bool revalidateIfStale = false,
  }) =>
      client.infiniteQuery<TPageData, TPageParam>(
        options(),
        revalidateIfStale: revalidateIfStale,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InfiniteQueryRef<Object?, Object?> && other.key == key;

  @override
  int get hashCode => Object.hash(InfiniteQueryRef, key);

  @override
  String toString() =>
      'InfiniteQueryRef<$TPageData, $TPageParam>(${key.rawKey.debugString})';
}

/// A plain query with no varying input, such as "all devices": the
/// definition is itself the [QueryRef].
///
/// ```dart
/// final devices = QueryNamespace(['devices']);
///
/// final list = QueryDefinition<List<Device>>(
///   namespace: devices,
///   name: 'list',
///   queryFn: (context) => api.devices(signal: context.signal),
/// );
///
/// final all = await list.fetch(client);
/// list.update(client, (devices) => [...?devices, created]);
/// ```
///
/// Its key is the namespace's parts followed by the name:
/// `['devices', 'list']`. Declare it once, as a top-level `final` or as a
/// field of a class that holds the repository it fetches from.
///
/// With a fetch function the data type is inferred from what it returns.
/// Without one, for an entry that is only ever written or that a default
/// fetch function serves, write the type argument out:
/// `QueryDefinition<Session?>(...)`.
///
/// {@category Typed queries}
final class QueryDefinition<T> extends QueryRef<T> {
  /// The query stored under `[...namespace, name]`.
  ///
  /// [queryFn] fetches the data. [configure] sets the definition's other
  /// options: it receives options holding the key and the fetch function
  /// and returns them with its changes, usually a `copyWith`.
  ///
  /// ```dart
  /// QueryDefinition<List<Device>>(
  ///   namespace: devices,
  ///   name: 'list',
  ///   queryFn: (context) => api.devices(),
  ///   configure: (base) => base.copyWith(
  ///     staleTime: const StaleTime.duration(Duration(minutes: 5)),
  ///   ),
  /// );
  /// ```
  ///
  /// Whatever [configure] returns, the options keep the definition's key
  /// and, when it has one, its fetch function.
  ///
  /// The data type must be a real one. In a debug build the constructor
  /// refuses `dynamic`, `Object?` and `void`, which is what a forgotten
  /// type argument infers on a definition without a fetch function, and
  /// `Null`; name the nullable type the entry holds instead.
  QueryDefinition({
    required QueryNamespace namespace,
    required String name,
    FutureOr<T> Function(QueryFunctionContext context)? queryFn,
    QueryObserverOptions<T> Function(QueryObserverOptions<T> base)? configure,
  })  : assert(_debugAnchored<T>(), _unanchored('QueryDefinition', 'T', T)),
        assert(T != Null, _nullData('QueryDefinition')),
        _queryFn = queryFn,
        _configure = configure,
        super._(namespace.rawKey.append([name]));

  final FutureOr<T> Function(QueryFunctionContext context)? _queryFn;
  final QueryObserverOptions<T> Function(QueryObserverOptions<T> base)?
      _configure;

  @override
  QueryObserverOptions<T> options() {
    final base = QueryObserverOptions<T>(
      queryKey: key.rawKey,
      queryFn: _queryFn,
    );
    final configure = _configure;
    // Pinned again after `configure`, so a definition cannot move its own
    // key or swap its own fetch function.
    return configure == null
        ? base
        : configure(base).copyWith(queryKey: key.rawKey, queryFn: _queryFn);
  }
}

/// One query over a varying input, such as "the device with this id".
/// Calling it with an input returns the [QueryRef] of that input's entry.
///
/// ```dart
/// final devices = QueryNamespace(['devices']);
///
/// final detail = QueryFamily<String, Device>(
///   namespace: devices,
///   name: 'detail',
///   queryFn: (id, context) => api.device(id, signal: context.signal),
/// );
///
/// final device = detail('d1'); // QueryRef<Device>, key ['devices', 'detail', 'd1']
/// await detail.invalidate(client); // every detail, whatever its id
/// ```
///
/// **Write the type arguments out.** Dart infers the data type from the
/// fetch function, but nothing tells it the input type: without
/// `<String, Device>` the input is `Object?`, and `detail(42)` compiles.
/// A declared type on the field that holds the family, or typed closure
/// parameters, work as well.
///
/// The input is part of the key, so equal inputs address the same entry
/// and their references are equal. Without a `keyOf` the input is the one
/// key part after the name, and it follows [QueryKey]'s rules: a string, a
/// number, an enum, a list, a map and a record of those are compared by
/// value, and an object of your own needs `==` and `hashCode`. **A record
/// that holds a list, a map or a set needs a `keyOf`**: a record compares
/// its fields with `==`, a list is equal only to itself, and two equal
/// inputs would silently be two entries.
///
/// As a [QueryTarget] a family selects every input's entry, by the prefix
/// `[...namespace, name]`. A key nested under that prefix is selected too;
/// give a nested operation a name of its own beside the family instead.
///
/// {@category Typed queries}
final class QueryFamily<TInput, T> extends QueryTarget {
  /// The queries stored under `[...namespace, name, input]`.
  ///
  /// [queryFn] fetches the data for an input. Without it the family
  /// describes entries that are only written, or that a default fetch
  /// function serves.
  ///
  /// [keyOf] turns an input into the key parts after the name, when the
  /// input itself is not what the key should hold: to spread it over
  /// several parts so that a prefix selects a subset, to convert an input
  /// without value equality, or to leave a field out of the identity.
  ///
  /// ```dart
  /// QueryFamily<({String room, List<String> tags}), List<Device>>(
  ///   namespace: devices,
  ///   name: 'search',
  ///   keyOf: (input) => [input.room, input.tags],
  ///   queryFn: (input, context) => api.search(input.room, input.tags),
  /// );
  /// ```
  ///
  /// [configure] sets the other options, per input: it receives options
  /// holding the key and the fetch function, and the input, and returns
  /// them with its changes. Whatever it returns, the options keep the
  /// family's key and, when it has one, its fetch function.
  ///
  /// In a debug build the constructor refuses `dynamic`, `Object?` and
  /// `void` for either type argument, which is what a forgotten one
  /// infers, and `Null` as the data type. An input that really can be
  /// anything is declared as `Object`, or as a nullable or sealed type.
  QueryFamily({
    required QueryNamespace namespace,
    required String name,
    List<Object?> Function(TInput input)? keyOf,
    FutureOr<T> Function(TInput input, QueryFunctionContext context)? queryFn,
    QueryObserverOptions<T> Function(
      QueryObserverOptions<T> base,
      TInput input,
    )? configure,
  })  : assert(
          _debugAnchored<TInput>(),
          _unanchored('QueryFamily', 'TInput', TInput),
        ),
        assert(_debugAnchored<T>(), _unanchored('QueryFamily', 'T', T)),
        assert(T != Null, _nullData('QueryFamily')),
        rawKey = namespace.rawKey.append([name]),
        _keyOf = keyOf,
        _queryFn = queryFn,
        _configure = configure,
        super._();

  /// The prefix every input's key starts with, `[...namespace, name]`, as
  /// a plain [QueryKey].
  final QueryKey rawKey;

  final List<Object?> Function(TInput input)? _keyOf;
  final FutureOr<T> Function(TInput input, QueryFunctionContext context)?
      _queryFn;
  final QueryObserverOptions<T> Function(
    QueryObserverOptions<T> base,
    TInput input,
  )? _configure;

  @override
  QueryKey get _selector => rawKey;

  @override
  bool get _exact => false;

  /// The reference of [input]'s entry.
  ///
  /// Binding fetches nothing and creates no entry. The key is computed
  /// here, once: a collection in the input is copied into it, so changing
  /// the caller's list afterwards does not move the reference. The fetch
  /// function is handed the input itself, which should therefore be
  /// immutable.
  ///
  /// Throws [ArgumentError] for an input that is not a `TInput`, which
  /// only a family held under a wider type argument lets through the
  /// analyzer.
  QueryRef<T> call(TInput input) {
    _checkInput<TInput>(input, this);
    return _FamilyQueryRef<TInput, T>._(
      this,
      input,
      rawKey.append(_keyOf?.call(input) ?? <Object?>[input]),
    );
  }

  QueryObserverOptions<T> _optionsFor(TInput input, QueryKey key) {
    final queryFn = _queryFn;
    final bound = queryFn == null
        ? null
        : (QueryFunctionContext context) => queryFn(input, context);
    final base = QueryObserverOptions<T>(queryKey: key, queryFn: bound);
    final configure = _configure;
    return configure == null
        ? base
        : configure(base, input).copyWith(queryKey: key, queryFn: bound);
  }

  /// The cached data of every input, each with its typed key; `null` where
  /// an entry holds no data yet.
  ///
  /// Throws [QueryDataTypeError] when an entry under the family's prefix
  /// holds another data type.
  List<(TypedQueryKey<T>, T?)> readAll(QueryClient client) =>
      _readAll<T>(client, filters());

  /// Runs [updater] over the cached data of every input and writes what it
  /// returns; returns each typed key with what its entry then holds.
  ///
  /// The tool for patching every cached detail after a write elsewhere.
  /// [updater] is called once per entry with its data, `null` when it
  /// holds none, and returning `null` leaves that entry as it is.
  ///
  /// ```dart
  /// detail.updateAll(
  ///   client,
  ///   (device) => device?.room == oldName
  ///       ? device!.copyWith(room: newName)
  ///       : null,
  /// );
  /// ```
  ///
  /// Nothing is written unless everything can be: every entry under the
  /// prefix must hold exactly the family's data type, every updater runs,
  /// and every result must be of that type, or the call throws (a
  /// [QueryDataTypeError] for a type, or what an updater threw) with the
  /// cache as it was. Every updater sees the data from before the call,
  /// whatever another one returned.
  ///
  /// The writes then happen one after the other, inside one
  /// `NotifyManager.batch`. It is not a transaction: a cache listener hears
  /// each write as it is made, and one that reacts by changing the cache
  /// is not undone. An entry removed while the updaters ran is created
  /// again by its write.
  List<(TypedQueryKey<T>, T?)> updateAll(
    QueryClient client,
    T? Function(T? previous) updater, {
    DateTime? updatedAt,
  }) =>
      _updateAll<T>(client, filters(), updater, _asIs, updatedAt);

  @override
  String toString() => 'QueryFamily<$TInput, $T>(${rawKey.debugString})';
}

final class _FamilyQueryRef<TInput, T> extends QueryRef<T> {
  _FamilyQueryRef._(this._family, this._input, super.rawKey) : super._();

  final QueryFamily<TInput, T> _family;
  final TInput _input;

  @override
  QueryObserverOptions<T> options() => _family._optionsFor(_input, key.rawKey);
}

/// An infinite query with no varying input, such as "the feed": the
/// definition is itself the [InfiniteQueryRef].
///
/// ```dart
/// final posts = QueryNamespace(['posts']);
///
/// final feed = InfiniteQueryDefinition<List<Post>, int>(
///   namespace: posts,
///   name: 'feed',
///   pageFn: (context) => api.feed(offset: context.pageParam),
///   initialPageParam: 0,
///   getNextPageParam: (page, pages, pageParam, pageParams) =>
///       page.isEmpty ? null : pageParam + page.length,
/// );
///
/// final observer = InfiniteQueryObserver(client, feed.options());
/// ```
///
/// Its key is `[...namespace, name]`. The paging functions are the ones
/// `InfiniteQueryOptions` takes, and both type arguments are inferred from
/// them: the page type from what [pageFn] returns, the page param type
/// from [initialPageParam].
///
/// {@category Typed queries}
final class InfiniteQueryDefinition<TPageData, TPageParam>
    extends InfiniteQueryRef<TPageData, TPageParam> {
  /// The infinite query stored under `[...namespace, name]`.
  ///
  /// [pageFn], [initialPageParam], [getNextPageParam] and
  /// [getPreviousPageParam] are `InfiniteQueryOptions`' fields of the same
  /// names. [configure] sets the other options (`maxPages`, `staleTime`,
  /// ...): it receives options holding the key and the paging functions
  /// and returns them with its changes. Whatever it returns, the options
  /// keep the definition's key and paging functions. Two edges: a
  /// definition without a [getPreviousPageParam] takes the one [configure]
  /// sets, and a definition whose [initialPageParam] is `null` cannot have
  /// it replaced there, so [options] throws a [StateError] when
  /// [configure] tries.
  ///
  /// A `structuralSharing` or an `initialData` that [configure] sets is
  /// held to the declared page types: what it produces is stored as an
  /// `InfiniteData<TPageData, TPageParam>` even when it was built with
  /// narrower type arguments.
  ///
  /// In a debug build the constructor refuses `dynamic`, `Object?` and
  /// `void` for either type argument.
  InfiniteQueryDefinition({
    required QueryNamespace namespace,
    required String name,
    required FutureOr<TPageData> Function(
      InfinitePageContext<TPageParam> context,
    ) pageFn,
    required TPageParam initialPageParam,
    required TPageParam? Function(
      TPageData page,
      List<TPageData> pages,
      TPageParam pageParam,
      List<TPageParam> pageParams,
    ) getNextPageParam,
    TPageParam? Function(
      TPageData page,
      List<TPageData> pages,
      TPageParam pageParam,
      List<TPageParam> pageParams,
    )? getPreviousPageParam,
    InfiniteQueryObserverOptions<TPageData, TPageParam> Function(
      InfiniteQueryObserverOptions<TPageData, TPageParam> base,
    )? configure,
  })  : assert(
          _debugAnchored<TPageData>(),
          _unanchored('InfiniteQueryDefinition', 'TPageData', TPageData),
        ),
        assert(
          _debugAnchored<TPageParam>(),
          _unanchored('InfiniteQueryDefinition', 'TPageParam', TPageParam),
        ),
        _pageFn = pageFn,
        _initialPageParam = initialPageParam,
        _getNextPageParam = getNextPageParam,
        _getPreviousPageParam = getPreviousPageParam,
        _configure = configure,
        super._(namespace.rawKey.append([name]));

  final InfinitePageFn<TPageData, TPageParam> _pageFn;
  final TPageParam _initialPageParam;
  final PageParamFn<TPageData, TPageParam> _getNextPageParam;
  final PageParamFn<TPageData, TPageParam>? _getPreviousPageParam;
  final InfiniteQueryObserverOptions<TPageData, TPageParam> Function(
    InfiniteQueryObserverOptions<TPageData, TPageParam> base,
  )? _configure;

  @override
  InfiniteQueryObserverOptions<TPageData, TPageParam> options() {
    final base = InfiniteQueryObserverOptions<TPageData, TPageParam>(
      queryKey: key.rawKey,
      pageFn: _pageFn,
      initialPageParam: _initialPageParam,
      getNextPageParam: _getNextPageParam,
      getPreviousPageParam: _getPreviousPageParam,
    );
    final configure = _configure;
    return configure == null ? base : _pinnedInfinite(base, configure(base));
  }
}

/// One infinite query over a varying input, such as "the posts of this
/// author". Calling it with an input returns the [InfiniteQueryRef] of that
/// input's entry.
///
/// ```dart
/// final byAuthor = InfiniteQueryFamily<String, List<Post>, int>(
///   namespace: posts,
///   name: 'byAuthor',
///   pageFn: (author, context) =>
///       api.posts(author: author, offset: context.pageParam),
///   initialPageParam: (author) => 0,
///   getNextPageParam: (author, page, pages, pageParam, pageParams) =>
///       page.isEmpty ? null : pageParam + page.length,
/// );
///
/// final mine = byAuthor('ada'); // InfiniteQueryRef<List<Post>, int>
/// ```
///
/// The input identifies the entry; the page params live inside its
/// `InfiniteData`. Each paging function takes the input first, because
/// where the first page starts and how the next is found often depend on
/// it.
///
/// What [QueryFamily] says about type arguments, inputs, `keyOf` and
/// nested keys holds here too: **write the type arguments out**, and give
/// a record input that holds a collection a `keyOf`.
///
/// {@category Typed queries}
final class InfiniteQueryFamily<TInput, TPageData, TPageParam>
    extends QueryTarget {
  /// The infinite queries stored under `[...namespace, name, input]`, or
  /// under `[...namespace, name, ...keyOf(input)]` with a [keyOf].
  ///
  /// [pageFn], [initialPageParam], [getNextPageParam] and
  /// [getPreviousPageParam] are `InfiniteQueryOptions`' fields of the same
  /// names with the input in front; the first page param is a function of
  /// the input. [configure] sets the other options per input, and the
  /// options keep the family's key and paging functions whatever it
  /// returns. A `structuralSharing` or an `initialData` it sets is held to
  /// the declared page types, and a missing [getPreviousPageParam] or a
  /// `null` first page param is treated, as on [InfiniteQueryDefinition].
  ///
  /// In a debug build the constructor refuses `dynamic`, `Object?` and
  /// `void` for any type argument, which is what a forgotten input type
  /// infers. An input that really can be anything is declared as `Object`,
  /// or as a nullable or sealed type.
  InfiniteQueryFamily({
    required QueryNamespace namespace,
    required String name,
    List<Object?> Function(TInput input)? keyOf,
    required FutureOr<TPageData> Function(
      TInput input,
      InfinitePageContext<TPageParam> context,
    ) pageFn,
    required TPageParam Function(TInput input) initialPageParam,
    required TPageParam? Function(
      TInput input,
      TPageData page,
      List<TPageData> pages,
      TPageParam pageParam,
      List<TPageParam> pageParams,
    ) getNextPageParam,
    TPageParam? Function(
      TInput input,
      TPageData page,
      List<TPageData> pages,
      TPageParam pageParam,
      List<TPageParam> pageParams,
    )? getPreviousPageParam,
    InfiniteQueryObserverOptions<TPageData, TPageParam> Function(
      InfiniteQueryObserverOptions<TPageData, TPageParam> base,
      TInput input,
    )? configure,
  })  : assert(
          _debugAnchored<TInput>(),
          _unanchored('InfiniteQueryFamily', 'TInput', TInput),
        ),
        assert(
          _debugAnchored<TPageData>(),
          _unanchored('InfiniteQueryFamily', 'TPageData', TPageData),
        ),
        assert(
          _debugAnchored<TPageParam>(),
          _unanchored('InfiniteQueryFamily', 'TPageParam', TPageParam),
        ),
        rawKey = namespace.rawKey.append([name]),
        _keyOf = keyOf,
        _pageFn = pageFn,
        _initialPageParam = initialPageParam,
        _getNextPageParam = getNextPageParam,
        _getPreviousPageParam = getPreviousPageParam,
        _configure = configure,
        super._();

  /// The prefix every input's key starts with, `[...namespace, name]`, as
  /// a plain [QueryKey].
  final QueryKey rawKey;

  final List<Object?> Function(TInput input)? _keyOf;
  final FutureOr<TPageData> Function(
    TInput input,
    InfinitePageContext<TPageParam> context,
  ) _pageFn;
  final TPageParam Function(TInput input) _initialPageParam;
  final TPageParam? Function(
    TInput input,
    TPageData page,
    List<TPageData> pages,
    TPageParam pageParam,
    List<TPageParam> pageParams,
  ) _getNextPageParam;
  final TPageParam? Function(
    TInput input,
    TPageData page,
    List<TPageData> pages,
    TPageParam pageParam,
    List<TPageParam> pageParams,
  )? _getPreviousPageParam;
  final InfiniteQueryObserverOptions<TPageData, TPageParam> Function(
    InfiniteQueryObserverOptions<TPageData, TPageParam> base,
    TInput input,
  )? _configure;

  @override
  QueryKey get _selector => rawKey;

  @override
  bool get _exact => false;

  /// The reference of [input]'s entry. Binding fetches nothing and creates
  /// no entry; the key is computed here, once, as [QueryFamily.call] does.
  ///
  /// Throws [ArgumentError] for an input that is not a `TInput`, which
  /// only a family held under a wider type argument lets through the
  /// analyzer.
  InfiniteQueryRef<TPageData, TPageParam> call(TInput input) {
    _checkInput<TInput>(input, this);
    return _FamilyInfiniteQueryRef<TInput, TPageData, TPageParam>._(
      this,
      input,
      rawKey.append(_keyOf?.call(input) ?? <Object?>[input]),
    );
  }

  InfiniteQueryObserverOptions<TPageData, TPageParam> _optionsFor(
    TInput input,
    QueryKey key,
  ) {
    final getPrevious = _getPreviousPageParam;
    final base = InfiniteQueryObserverOptions<TPageData, TPageParam>(
      queryKey: key,
      pageFn: (context) => _pageFn(input, context),
      initialPageParam: _initialPageParam(input),
      getNextPageParam: (page, pages, pageParam, pageParams) =>
          _getNextPageParam(input, page, pages, pageParam, pageParams),
      getPreviousPageParam: getPrevious == null
          ? null
          : (page, pages, pageParam, pageParams) =>
              getPrevious(input, page, pages, pageParam, pageParams),
    );
    final configure = _configure;
    return configure == null
        ? base
        : _pinnedInfinite(base, configure(base, input));
  }

  /// The cached pages of every input, each with its typed key; `null`
  /// where an entry holds no data yet.
  ///
  /// Throws [QueryDataTypeError] when an entry under the family's prefix
  /// holds another data type.
  List<
      (
        TypedQueryKey<InfiniteData<TPageData, TPageParam>>,
        InfiniteData<TPageData, TPageParam>?
      )> readAll(
          QueryClient client) =>
      _readAll<InfiniteData<TPageData, TPageParam>>(client, filters());

  /// Runs [updater] over the cached pages of every input and writes what
  /// it returns, as [QueryFamily.updateAll] does and with the same rules:
  /// nothing is written unless every entry and every result has the
  /// family's type, and returning `null` leaves an entry as it is. Each
  /// result is stored under the declared page types.
  List<
      (
        TypedQueryKey<InfiniteData<TPageData, TPageParam>>,
        InfiniteData<TPageData, TPageParam>?
      )> updateAll(
    QueryClient client,
    InfiniteData<TPageData, TPageParam>? Function(
      InfiniteData<TPageData, TPageParam>? previous,
    ) updater, {
    DateTime? updatedAt,
  }) =>
      _updateAll<InfiniteData<TPageData, TPageParam>>(
        client,
        filters(),
        updater,
        _exactInfinite<TPageData, TPageParam>,
        updatedAt,
      );

  @override
  String toString() => 'InfiniteQueryFamily<$TInput, $TPageData, $TPageParam>'
      '(${rawKey.debugString})';
}

final class _FamilyInfiniteQueryRef<TInput, TPageData, TPageParam>
    extends InfiniteQueryRef<TPageData, TPageParam> {
  _FamilyInfiniteQueryRef._(this._family, this._input, super.rawKey)
      : super._();

  final InfiniteQueryFamily<TInput, TPageData, TPageParam> _family;
  final TInput _input;

  @override
  InfiniteQueryObserverOptions<TPageData, TPageParam> options() =>
      _family._optionsFor(_input, key.rawKey);
}

// ------------------------------------------------------------ the writes

/// The one way a typed write reaches the cache: into [existing], or into an
/// entry built for the key of [optionsForNew] when there is none.
///
/// [existing] is what `QueryCache.get<T>` returned, so it holds exactly `T`,
/// and the write is `Query.setData(manual: true)`, the call the client's
/// `setQueryData` ends in: sharing, timestamps and notifications are the
/// same. What differs is before it. The client's write takes any entry that
/// can hold the value, a `Device?` entry for a `Device`, which the
/// reference's own next read would then refuse.
T _write<T>(
  QueryClient client,
  Query<T>? existing,
  T value,
  DateTime? updatedAt,
  QueryOptions<T> Function() optionsForNew,
) {
  // `build` looks the key up once more and creates the entry only when it
  // is still absent: resolving the options runs the caller's `configure`,
  // and constructing the entry an `InitialData.compute`.
  final query = existing ??
      client.queryCache.build<T>(
        client,
        client.defaultQueryOptions<T>(optionsForNew()),
      );
  return query.setData(value, updatedAt: updatedAt, manual: true);
}

/// Every entry [filters] selects, each holding exactly `T`; or nothing is
/// read and nothing written.
List<Query<T>> _exactEntries<T>(QueryClient client, QueryFilters filters) {
  final entries = <Query<T>>[];
  for (final query in client.queryCache.findAll(filters: filters)) {
    // The `is` test adds nothing to the comparison; it is what hands the
    // loop a `Query<T>` without a cast.
    if (query.dataType != T || query is! Query<T>) {
      throw QueryDataTypeError(query.queryKey, T, query.dataType);
    }
    entries.add(query);
  }
  return entries;
}

List<(TypedQueryKey<T>, T?)> _readAll<T>(
  QueryClient client,
  QueryFilters filters,
) =>
    [
      for (final (key, data) in client.getQueriesData<T>(filters: filters))
        (TypedQueryKey<T>._(key), data),
    ];

/// A family's bulk update, in the order of the client's `updateQueriesData`:
/// what every entry holds, then every updater, then every result checked,
/// then the writes in one batch.
///
/// It does not call that method, because each of its three steps is
/// lenient where a typed write is exact: it takes an entry of another type
/// that holds no data, it asks whether the entry can hold the result, and
/// it writes into whatever entry the key has by then.
List<(TypedQueryKey<T>, T?)> _updateAll<T>(
  QueryClient client,
  QueryFilters filters,
  T? Function(T? previous) updater,
  T Function(T value) normalise,
  DateTime? updatedAt,
) {
  final entries = _exactEntries<T>(client, filters);
  final previous = [
    for (final query in entries) query.state.hasData ? query.state.data : null,
  ];
  // Through `Object?`, which is what [_checked] needs.
  final results = <Object?>[for (final held in previous) updater(held)];
  final next = <T?>[
    for (var i = 0; i < entries.length; i++)
      switch (results[i]) {
        // A `null` writes nothing, whatever `T` is.
        null => null,
        final value => normalise(_checked<T>(value, entries[i].queryKey)),
      },
  ];
  return client.notifyManager.batch(
    () => [
      for (var i = 0; i < entries.length; i++)
        (
          TypedQueryKey<T>._(entries[i].queryKey),
          switch (next[i]) {
            null => null,
            // Looked up by key, as the client's bulk update does: an entry
            // removed since the first pass is made again, with plain
            // options, because a family cannot tell the input from the key.
            final T value => _write<T>(
                client,
                client.queryCache.get<T>(entries[i].queryKey),
                value,
                updatedAt,
                () => QueryOptions<T>(queryKey: entries[i].queryKey),
              ),
          },
        ),
    ],
  );
}

T _asIs<T>(T value) => value;

/// [value] as a `T`, or [QueryDataTypeError] for the entry under [key].
///
/// The parameter is `Object?` and the test an explicit `is`, on purpose.
/// A reference held as `QueryEntryRef<Object?>` accepts any value
/// statically. The VM refuses it at the call, but a JavaScript build
/// compiled with `-O3` or `-O4` (Flutter's web release mode) omits that
/// check, and omits casts as well. An `is` test is kept at every level, so
/// this is the line such a build stops at, and no other runtime reaches.
T _checked<T>(Object? value, QueryKey key) {
  if (value is! T) {
    throw QueryDataTypeError(key, T, value.runtimeType);
  }
  return value;
}

// ------------------------------------------------- the declared page types

/// [value] under exactly the declared page types.
///
/// An `InfiniteData` inferred from narrower literals, of `List<Never>`
/// pages say, is a valid `InfiniteData<TPageData, TPageParam>` and a trap
/// once cached: the next `copyWith` typed for the entry hands its lists a
/// `TPageData` they cannot take. Rebuilt from its pages it loses nothing,
/// since the class is final and holds the two lists and nothing else, and
/// it becomes shareable again: structural sharing keeps the incoming value
/// whenever the runtime types differ. An exact value is kept as it is,
/// instance included.
InfiniteData<TPageData, TPageParam> _exactInfinite<TPageData, TPageParam>(
  InfiniteData<TPageData, TPageParam> value,
) =>
    value.runtimeType == _typeOf<InfiniteData<TPageData, TPageParam>>()
        ? value
        : InfiniteData<TPageData, TPageParam>(
            pages: List<TPageData>.unmodifiable(value.pages),
            pageParams: List<TPageParam>.unmodifiable(value.pageParams),
          );

Type _typeOf<X>() => X;

/// What an infinite definition's `configure` returned, as the options the
/// definition hands out: the key and the paging functions of [base] again,
/// and the two options that can put a value into the cache held to the
/// declared page types.
InfiniteQueryObserverOptions<TPageData, TPageParam>
    _pinnedInfinite<TPageData, TPageParam>(
  InfiniteQueryObserverOptions<TPageData, TPageParam> base,
  InfiniteQueryObserverOptions<TPageData, TPageParam> configured,
) {
  final initialPageParam = base.initialPageParam;
  if (initialPageParam == null && configured.initialPageParam != null) {
    // `copyWith` reads `null` as "keep", so a first page param of `null`
    // is the one thing that cannot be put back.
    throw StateError(
      'configure changed initialPageParam of ${base.queryKey}. The first '
      'page param belongs to the definition; set it there.',
    );
  }
  return configured.copyWith(
    queryKey: base.queryKey,
    pageFn: base.pageFn,
    initialPageParam: initialPageParam,
    getNextPageParam: base.getNextPageParam,
    getPreviousPageParam: base.getPreviousPageParam,
    structuralSharing: _exactSharing(configured.structuralSharing),
    initialData: _exactInitialData(configured.initialData),
  );
}

/// [sharing] with its result under the declared page types, or `null` to
/// keep it as it is.
///
/// Sharing has the last word on what a write stores, so a hook that
/// returns a narrower value, the previous one a plain `setQueryData` put
/// there for instance, would undo what the write prepared. The default
/// walk and the opt-out need no wrapper: both return the incoming value or
/// one of its exact type. The opt-out must not get one, because it is
/// recognised by identity.
StructuralSharing<InfiniteData<TPageData, TPageParam>>?
    _exactSharing<TPageData, TPageParam>(
  StructuralSharing<InfiniteData<TPageData, TPageParam>>? sharing,
) =>
        sharing == null || isNoStructuralSharing(sharing)
            ? null
            : (previous, next) => _exactInfinite<TPageData, TPageParam>(
                  sharing(previous, next),
                );

/// [initialData] with its seed under the declared page types, or `null` to
/// keep it as it is: a seed is written into the cache as fetched data is.
InitialData<InfiniteData<TPageData, TPageParam>>?
    _exactInitialData<TPageData, TPageParam>(
  InitialData<InfiniteData<TPageData, TPageParam>>? initialData,
) {
  switch (initialData) {
    case null:
      return null;
    case InitialDataValue<InfiniteData<TPageData, TPageParam>>(:final data):
      final exact = _exactInfinite<TPageData, TPageParam>(data);
      return identical(exact, data)
          ? null
          : InitialData<InfiniteData<TPageData, TPageParam>>.value(exact);
    case InitialDataCompute<InfiniteData<TPageData, TPageParam>>(
        :final compute
      ):
      return InitialData<InfiniteData<TPageData, TPageParam>>.compute(() {
        final seed = compute();
        return seed == null
            ? null
            : _exactInfinite<TPageData, TPageParam>(seed);
      });
  }
}

// ------------------------------------------------------------- the checks

/// [input] as a `TInput`, or [ArgumentError]: the check `QueryEntryRef`
/// makes for a written value, for a family's input. Without it a family
/// held as `QueryFamily<Object?, ...>` would, in a JavaScript release
/// build, put a wrong input into a key and hand it to the fetch function.
void _checkInput<TInput>(Object? input, Object family) {
  if (input is! TInput) {
    throw ArgumentError.value(input, 'input', 'Not an input of $family');
  }
}

/// Whether [X] is a type an argument was written or inferred for, and not
/// one of the top types a missing argument falls back to: `List<Object?>`
/// is a `List<X>` exactly for `dynamic`, `Object?` and `void`.
bool _debugAnchored<X>() => <Object?>[] is! List<X>;

String _unanchored(String definition, String slot, Type type) =>
    '$definition: the type argument $slot is a top type ($type). A '
    'definition does not infer its type arguments from untyped closures: '
    'write them out ($definition<…>(…)), or declare the type of the field '
    'that holds it. An input that really can be anything is declared as '
    'Object, or as a nullable or sealed type.';

String _nullData(String definition) =>
    '$definition: the data type is Null. Name the nullable type the entry '
    'holds ($definition<Device?>(…)).';
