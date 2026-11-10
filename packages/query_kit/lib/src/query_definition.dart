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
/// client's, reached through the client each operation is handed. The one
/// thing remembered is a wrapper: an infinite definition finds the one it
/// made for a callback of its `configure` again by that callback, weakly,
/// so that its options are equal from call to call once defaulted.
library;

import 'dart:async';

import 'package:clock/clock.dart';

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
/// outside this package can be one.
///
/// To act on references of different data types together, declare the list
/// as one of targets: it has every operation above and no write.
///
/// ```dart
/// final stale = <QueryTarget>[devices.detail('d1'), rooms.detail('r1')];
/// ```
///
/// Left to inference the literal takes what its elements share, and two
/// references of one class share that class: `[ints('a'), strings('a')]`
/// is a `List<QueryRef<Object>>`, whose `write` compiles for any value and
/// is checked only when it runs.
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
/// A reference's [QueryEntryRef.key] is one, and a family's `readAll` and
/// `updateAll` return one for every entry they found. It reads and writes
/// the entry with the right type and no type argument, and it is a value:
/// two typed keys are equal when their raw keys and their data types are, so
/// it can be a map key or a member of a set.
///
/// ```dart
/// final key = devices.detail('d1').key; // TypedQueryKey<Device>
/// final Device? cached = key.read(client);
/// final QueryState<Device>? state = key.state(client);
/// key.write(client, updated);
/// ```
///
/// It is what puts back what a bulk read returned, the rollback of an
/// optimistic update over a whole family:
///
/// ```dart
/// final snapshot = devices.detail.readAll(client);
/// // ...patch every detail with updateAll; then, when the request fails:
/// for (final (key, data) in snapshot) {
///   if (data != null) key.write(client, data);
/// }
/// ```
///
/// That `null` means "no data" only for a non-null data type. For a
/// nullable one, a cached `null` reads as `null` too, and the snapshot
/// keeps each key's [state] instead; [QueryFamily.readAll] shows how.
///
/// A typed key knows the entry's key and its data type, and not the
/// definition. That shows in one place: an entry a [write] creates is
/// built from the key and the type alone, where a reference builds it with
/// the definition's options.
///
/// Only a definition or a reference makes one: there is no public
/// constructor and no conversion from a plain key, because the data type
/// would then be whatever the caller claimed.
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

  /// The value as the entry stores it. Identity, except for the key of an
  /// infinite reference.
  T _stored(T value) => value;

  /// The options of an entry made for this key alone: what the client's
  /// `setQueryData` builds one with, under the key's data type.
  QueryOptions<T> _bareOptions() => QueryOptions<T>(queryKey: rawKey);

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

  /// Writes [value] into the entry under this key and returns what the
  /// cache then holds: [QueryEntryRef.write], for a caller that holds the
  /// key and not the reference.
  ///
  /// ```dart
  /// for (final (key, data) in snapshot) {
  ///   if (data != null) key.write(client, data);
  /// }
  /// ```
  ///
  /// With a nullable data type that rollback skips a cached `null`, which
  /// reads as `null` as well; [QueryFamily.readAll] shows the snapshot
  /// that puts one back.
  ///
  /// An entry that exists is written as the reference writes it: it must
  /// hold exactly the key's data type, and the timestamp ([updatedAt],
  /// default: now), structural sharing and the notification are the same.
  /// A key that came from an infinite reference or an infinite family
  /// stores the value under the declared page types, as that reference
  /// does.
  ///
  /// An entry the write creates is where the two differ. The key has no
  /// definition to take options from, so the entry is built with the key
  /// and the data type and nothing else: the client's defaults and the
  /// key's own (`QueryClient.setQueryDefaults`) apply, as they do to an
  /// entry the client's `setQueryData` creates, and the definition's
  /// `gcTime`, `structuralSharing` and `initialData` do not. It has no
  /// fetch function either, until an observer of the reference's options,
  /// or a fetch through the reference that does fetch, brings the
  /// definition's: a refetch that reaches it before then fails it with
  /// [MissingQueryFunctionError] and keeps its data. That is a `refetch`
  /// over it, or an invalidation with a `refetchType` of `all` or
  /// `inactive`; a default invalidation refetches only the entries an
  /// observer reads, so it only marks this one stale. A fetch while the
  /// written data is fresh under the definition's `staleTime` returns that
  /// data and brings nothing, and a read through the reference only looks
  /// at the cache.
  /// Its type is the key's, whatever the value's own type is: a `Device`
  /// written through a `TypedQueryKey<Device?>` creates an entry of
  /// `Device?`. To create an entry with the definition's options, write
  /// through the reference.
  ///
  /// Throws [QueryDataTypeError], and writes nothing, when the entry holds
  /// another data type, or when [value] is not of the key's type, which
  /// only a key held under a wider type argument lets through the analyzer.
  /// And as on [QueryEntryRef.write], the value goes into the entry the
  /// cache holds when it is stored: an entry that a cache listener or its
  /// own `structuralSharing` removed or replaced in the middle of the
  /// write is a [StateError] or a [QueryDataTypeError], never a value
  /// returned and not stored.
  T write(QueryClient client, T value, {DateTime? updatedAt}) =>
      _writeEntry<T>(client, this, value, updatedAt, _bareOptions);

  /// Writes what [updater] returns for the data cached now, and returns
  /// what the cache then holds: [QueryEntryRef.update], for a caller that
  /// holds the key and not the reference.
  ///
  /// [updater] receives the current data, `null` when there is none, and
  /// returning `null` writes nothing and creates no entry. Otherwise as
  /// [write]: the same checks, and an entry it creates is built from the
  /// key and the data type alone.
  T? update(
    QueryClient client,
    T? Function(T? previous) updater, {
    DateTime? updatedAt,
  }) =>
      _updateEntry<T>(client, this, updater, updatedAt, _bareOptions);

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

/// The typed key an infinite reference and an infinite family hand out: a
/// [TypedQueryKey] that also knows the two page types, which is what a
/// write needs to store a value under them.
///
/// Nothing else is added. It holds the raw key and no function, so a key
/// kept in a snapshot keeps no fetch function and no repository alive, and
/// equality and `hashCode` are the base class's: the raw key and the data
/// type.
final class _InfiniteTypedQueryKey<TPageData, TPageParam>
    extends TypedQueryKey<InfiniteData<TPageData, TPageParam>> {
  const _InfiniteTypedQueryKey._(super.rawKey) : super._();

  @override
  InfiniteData<TPageData, TPageParam> _stored(
    InfiniteData<TPageData, TPageParam> value,
  ) =>
      _exactInfinite<TPageData, TPageParam>(value);
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
  QueryEntryRef._(this.key) : super._();

  /// The entry's key with its data type.
  final TypedQueryKey<T> key;

  @override
  QueryKey get _selector => key.rawKey;

  @override
  bool get _exact => true;

  /// The options an entry created by a write is built with.
  QueryOptions<T> _entryOptions();

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
  ///
  /// The value goes into the entry the cache holds under the key at the
  /// moment it is stored, and the call returns nothing it did not store
  /// there. Two pieces of the caller's code run before that moment: a
  /// cache listener hears of an entry the write creates, and the entry's
  /// `structuralSharing` is handed the value. Either may remove the entry
  /// or put another in its place, and the write then does not go into the
  /// entry that left the cache:
  ///
  /// * an entry of the same data type that a listener put there is the
  ///   one written;
  /// * an entry of another type in its place throws [QueryDataTypeError];
  /// * an entry a listener removed, and one that its own
  ///   `structuralSharing` removed or replaced with the same type, throws
  ///   a [StateError]. What sharing returned was shared against the entry
  ///   that is gone, so there is nothing left to store it in.
  ///
  /// The last two write nothing. A `Clock` installed with `withClock` is
  /// held to the same rule: without [updatedAt] the write asks it for the
  /// time before `structuralSharing` runs, and an entry the clock's code
  /// removed or replaced is treated as one `structuralSharing` removed or
  /// replaced. The `QuerySuccessAction` a cache listener hears then
  /// carries that time, where the client's `setQueryData` leaves it `null`.
  /// The stored `dataUpdatedAt` is therefore the time the write began, not
  /// the time sharing ended; the two differ only when time moves while
  /// `structuralSharing` runs.
  /// What a listener does once the value is stored, in answer to the
  /// write, comes after it: the call returns what it stored.
  T write(QueryClient client, T value, {DateTime? updatedAt}) =>
      _writeEntry<T>(client, key, value, updatedAt, _entryOptions);

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
  /// a mismatch throws [QueryDataTypeError] with nothing written. The
  /// entry is looked up again when [updater] has run, so one that
  /// [updater] itself removed is made again, and one it replaced is
  /// written when it has the same data type and refused when it has
  /// another.
  T? update(
    QueryClient client,
    T? Function(T? previous) updater, {
    DateTime? updatedAt,
  }) =>
      _updateEntry<T>(client, key, updater, updatedAt, _entryOptions);
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
  QueryRef._(QueryKey rawKey) : super._(TypedQueryKey<T>._(rawKey));

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
  ///
  /// Two calls never return `==` objects. What an observer compares is
  /// the options once the client has defaulted them, and whether those are
  /// equal depends on the definition. A [QueryDefinition] hands out the
  /// fetch function it was declared with, so the options of one that is
  /// held, in a top-level `final` or a field, are equal once defaulted,
  /// and an observer handed them again sees no change. A [QueryFamily]'s
  /// reference binds its input into a new fetch function on every call, so
  /// its options never equal the ones before, as options written inline
  /// with a closure do not: the observer takes them as changed, and starts
  /// no fetch for that alone. A family declared without a fetch function
  /// has nothing to bind, and its options are equal once defaulted. A
  /// `configure` that builds something new on every call, an
  /// `Enabled.when` over a closure say, makes either kind's options
  /// differ.
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
/// `copyWith` on the cached value takes a page of the declared type. That
/// is this reference's doing: it has the two page types to rebuild with. A
/// plain `QueryDefinition<InfiniteData<P, Q>>` has one type, the whole
/// value's, and stores what it is given, narrower type arguments included;
/// declare paged data as an infinite definition.
///
/// It is a value in the way a [QueryRef] is, and never equal to one.
///
/// {@category Typed queries}
abstract final class InfiniteQueryRef<TPageData, TPageParam>
    extends QueryEntryRef<InfiniteData<TPageData, TPageParam>> {
  InfiniteQueryRef._(QueryKey rawKey)
      : super._(_InfiniteTypedQueryKey<TPageData, TPageParam>._(rawKey));

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
  /// the declared page types. What one of the others returns is stored with
  /// the type arguments it was built with: an `InfiniteData<int, int>` in
  /// an `InfiniteData<num, num>` entry reads as the declared type, and a
  /// later `copyWith(pages: <num>[1.5])` on it throws a [TypeError].
  ///
  /// An [InfiniteQueryDefinition] hands out the paging functions it was
  /// declared with, so the options of one that is held are equal once
  /// defaulted, though two calls never return `==` objects; an
  /// [InfiniteQueryFamily]'s reference binds its input into new ones on
  /// every call. What that means to an observer is on [QueryRef.options].
  ///
  /// That holds with a `structuralSharing` or an `InitialData.compute`
  /// from `configure` when it is the same function every time `configure`
  /// runs: a top-level or static function, or one held in a field or a
  /// variable. The definition wraps such a function to hold the declared
  /// page types and hands out the same wrapper for the same function
  /// object. A closure written inside `configure` is a new one on every
  /// call, and so is a method torn off there (`repository.share`) on the
  /// Dart VM, where two such tear-offs are equal and not identical; the
  /// options then differ, as they do with any other option built anew.
  /// Tear the method off once, into a field, to have them equal.
  InfiniteQueryObserverOptions<TPageData, TPageParam> options();

  @override
  QueryOptions<InfiniteData<TPageData, TPageParam>> _entryOptions() =>
      options();

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
/// **Write the type argument out**, as on every definition. It says what
/// the entry holds where the query is declared, and a definition without a
/// fetch function, for an entry that is only ever written or that a
/// default fetch function serves, has nothing else to take the type from:
/// `QueryDefinition<Session?>(...)`.
///
/// Paged data belongs in an [InfiniteQueryDefinition]. A plain definition
/// whose data type is an `InfiniteData` works as any other type does, and
/// that is all: a written value is stored as it is, not rebuilt under the
/// page types as an [InfiniteQueryRef] rebuilds it.
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
  /// The definition pins what it declares: whatever [configure] returns,
  /// the options keep the definition's key and, when it has one, its fetch
  /// function. What the definition leaves unset, [configure] may set, so
  /// one declared without a [queryFn] takes the one [configure] gives it.
  ///
  /// [configure] must return options of the definition's own type, which
  /// the ones it is handed and any `copyWith` of them are. Options are
  /// covariant in their data type, so a `QueryObserverOptions<int>`
  /// satisfies the return type of a `QueryDefinition<num>`'s [configure];
  /// [options] refuses them with a [StateError] that names the key and
  /// both types.
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
        : _ownOptions<QueryObserverOptions<T>>(configure(base), key.rawKey)
            .copyWith(queryKey: key.rawKey, queryFn: _queryFn);
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
  /// them with its changes. The family pins what it declares: whatever
  /// [configure] returns, the options keep the family's key and, when it
  /// has one, its fetch function; a family declared without a [queryFn]
  /// takes the one [configure] sets. The options it returns must be of the
  /// family's own type, `QueryObserverOptions<T>` and not ones of a
  /// narrower data type, or making a reference's options throws a
  /// [StateError], as on [QueryDefinition].
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
        : _ownOptions<QueryObserverOptions<T>>(configure(base, input), key)
            .copyWith(queryKey: key, queryFn: bound);
  }

  /// The cached data of every input, each with its typed key; `null` where
  /// an entry holds no data yet.
  ///
  /// That `null` means "no data" only for a non-null `T`. For a nullable
  /// `T` a cached `null` reads as `null` too, so a rollback that writes
  /// back each non-null value leaves an overwritten cached `null`
  /// overwritten. Snapshot each key's state instead, whose `hasData` tells
  /// the two apart; for a `QueryFamily<String, Device?>` called `paired`:
  ///
  /// ```dart
  /// final snapshot = [
  ///   for (final (key, _) in paired.readAll(client)) (key, key.state(client)),
  /// ];
  /// // ...then, to roll back:
  /// for (final (key, state) in snapshot) {
  ///   if (state != null && state.hasData) key.write(client, state.data);
  /// }
  /// ```
  ///
  /// Throws [QueryDataTypeError] when an entry under the family's prefix
  /// holds another data type.
  List<(TypedQueryKey<T>, T?)> readAll(QueryClient client) =>
      _readAll<T>(client, filters(), TypedQueryKey<T>._);

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
  /// whatever another one returned. The entries are looked at once more
  /// when the updaters are done, so one that an updater itself replaced
  /// with an entry of another type refuses the call as well.
  ///
  /// That check covers the types and what the updaters return. It does not
  /// cover the writes, which then happen one after the other inside one
  /// `NotifyManager.batch`, each as [QueryEntryRef.write] makes it, and a
  /// write can still fail: an entry's `structuralSharing` may throw, and a
  /// cache listener that hears an earlier write may put an entry of
  /// another type in a later one's place. The call then throws at that
  /// entry with the earlier writes made and the later ones not, as
  /// [QueryClient.updateQueriesData] does. It is not a transaction, and
  /// nothing is rolled back.
  ///
  /// A cache listener that throws stops nothing: its error is reported to
  /// the zone and the writes go on. An entry removed since the updaters
  /// ran is created again by its write, and one replaced by an entry of
  /// the same data type is written. The family has only the key there,
  /// not the input, so an entry made again is built as a [TypedQueryKey]'s
  /// write builds one: with the key's bare options and no fetch function.
  /// A refetch of it then fails with [MissingQueryFunctionError] until an
  /// observer of the reference's options, or a fetch through the reference
  /// that does fetch, supplies the definition's.
  List<(TypedQueryKey<T>, T?)> updateAll(
    QueryClient client,
    T? Function(T? previous) updater, {
    DateTime? updatedAt,
  }) =>
      _updateAll<T>(
        client,
        filters(),
        updater,
        TypedQueryKey<T>._,
        updatedAt,
      );

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
/// `InfiniteQueryOptions` takes.
///
/// **Write the type arguments out.** Dart types the closures of one call
/// together, and the page type is what it loses. Without
/// `<List<Post>, int>`, a `getNextPageParam` that reads its page does not
/// compile, because the page is `Object?` there; and with a `configure`
/// the definition becomes an `InfiniteQueryDefinition<Object?, int>`
/// without a word from the analyzer, which a debug build then refuses
/// when it is made. A declared type on the field that holds the
/// definition works as well.
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
  /// and returns them with its changes. The definition pins what it
  /// declares: whatever [configure] returns, the options keep the
  /// definition's key and paging functions. What it leaves unset,
  /// [configure] may set, so a definition without a [getPreviousPageParam]
  /// takes the one [configure] sets. One edge: a definition whose
  /// [initialPageParam] is `null` cannot have it replaced there, so
  /// [options] throws a [StateError] when [configure] tries.
  ///
  /// [configure] must return options of the definition's own type,
  /// `InfiniteQueryObserverOptions<TPageData, TPageParam>`, which the ones
  /// it is handed and any `copyWith` of them are. Options of narrower page
  /// types satisfy its return type; [options] refuses them with a
  /// [StateError] that names the key and both types.
  ///
  /// A `structuralSharing` or an `initialData` that [configure] sets is
  /// held to the declared page types: what it produces is stored as an
  /// `InfiniteData<TPageData, TPageParam>` even when it was built with
  /// narrower type arguments. One from the client's defaults or from a
  /// per-use `copyWith` is not, as [InfiniteQueryRef.options] says.
  ///
  /// In a debug build the constructor refuses `dynamic`, `Object?` and
  /// `void` for either type argument, which is what a page type left to
  /// inference becomes beside a [configure].
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

  /// The wrappers [options] has put around the callbacks [_configure]
  /// returned, so that the same callback gets the same wrapper again and
  /// the options of two calls are equal. A family keeps none: its options
  /// differ from call to call by their paging functions already.
  late final _wrappers = _ExactWrappers<TPageData, TPageParam>();

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
    return configure == null
        ? base
        : _pinnedInfinite(base, configure(base), _wrappers);
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
/// nested keys holds here too: **write the type arguments out** (left to
/// inference the input is `Object?`, and the page type is lost as on
/// [InfiniteQueryDefinition]), and give a record input that holds a
/// collection a `keyOf`.
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
  /// the declared page types, and a missing [getPreviousPageParam], a
  /// `null` first page param or options of another type are treated as on
  /// [InfiniteQueryDefinition].
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
  /// where an entry holds no data yet. An `InfiniteData` is never `null`
  /// itself, so here `null` always means "no data".
  ///
  /// Throws [QueryDataTypeError] when an entry under the family's prefix
  /// holds another data type.
  List<
      (
        TypedQueryKey<InfiniteData<TPageData, TPageParam>>,
        InfiniteData<TPageData, TPageParam>?
      )> readAll(
          QueryClient client) =>
      _readAll<InfiniteData<TPageData, TPageParam>>(
        client,
        filters(),
        _InfiniteTypedQueryKey<TPageData, TPageParam>._,
      );

  /// Runs [updater] over the cached pages of every input and writes what
  /// it returns, as [QueryFamily.updateAll] does and with the same rules:
  /// nothing is written unless every entry and every result has the
  /// family's type, returning `null` leaves an entry as it is, a write
  /// that fails leaves the ones before it made, and an entry removed
  /// since the updaters ran is made again without the paging functions.
  /// Each result is stored under the declared page types.
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
        _InfiniteTypedQueryKey<TPageData, TPageParam>._,
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

/// A single typed write, the reference's and the typed key's alike: the
/// entry under [key] exact or absent, [value] a `T`, then the write.
///
/// The two callers differ in [optionsForNew] and in nothing else, which is
/// why they share this: what a missing entry is built with, the
/// definition's options for a reference and the key alone for a typed key.
T _writeEntry<T>(
  QueryClient client,
  TypedQueryKey<T> key,
  Object? value,
  DateTime? updatedAt,
  QueryOptions<T> Function() optionsForNew,
) {
  final rawKey = key.rawKey;
  // The entry before the value: of two mismatches the entry's is reported.
  client.queryCache.get<T>(rawKey);
  return _write<T>(
    client,
    rawKey,
    key._stored(_checked<T>(value, rawKey)),
    updatedAt,
    optionsForNew,
  );
}

/// A single typed update, shared as [_writeEntry] is: [updater] over what
/// the entry under [key] holds, and its result written unless it is `null`.
T? _updateEntry<T>(
  QueryClient client,
  TypedQueryKey<T> key,
  T? Function(T? previous) updater,
  DateTime? updatedAt,
  QueryOptions<T> Function() optionsForNew,
) {
  final rawKey = key.rawKey;
  final existing = client.queryCache.get<T>(rawKey);
  final previous =
      existing != null && existing.state.hasData ? existing.state.data : null;
  final Object? next = updater(previous);
  if (next == null) {
    return null;
  }
  final value = _checked<T>(next, rawKey);
  // [_write] looks the entry up again: the updater is the caller's code and
  // may have removed it, made it or put another in its place.
  return _write<T>(
      client, rawKey, key._stored(value), updatedAt, optionsForNew);
}

/// The one way a typed write reaches the cache: into the entry the cache
/// holds under [rawKey] when [value] is stored, or not at all.
///
/// The write is `Query.setData(manual: true)`, the call the client's
/// `setQueryData` ends in: sharing, timestamps and notifications are the
/// same. What differs is before it. The client's write takes any entry that
/// can hold the value, a `Device?` entry for a `Device`, which the
/// reference's own next read would then refuse; this one takes the entry of
/// exactly `T`, which is what `QueryCache.get<T>` returns or throws for.
///
/// It also differs in which entry that is. The entry is looked up here, by
/// key, after every piece of the caller's code that runs before it (an
/// updater, a bulk update's earlier writes and whoever heard them), and
/// three more pieces run between the lookup and the stored value:
///
/// * the cache's listeners hear `QueryAdded` for an entry made here, and
///   one may remove it or put another in its place: [_created] looks again;
/// * the clock dates the value when the caller gave no `updatedAt`, and a
///   `Clock` installed with `withClock` is code as well;
/// * the entry's `structuralSharing` is handed the value, and may do the
///   same to the entry it is running for.
///
/// `canCommit` is what `setData` asks after sharing, and nothing of the
/// caller's runs between it and the stored value.
///
/// Without those two a value went into an entry the cache had dropped and
/// was returned as stored, where the next read found nothing or an entry
/// of another type.
///
/// The clock is read here, and the time handed to `setData` as the
/// caller's own, because `setData` reads it after its guard, in the
/// reducer, where the client's `setQueryData` and a fetch read it as
/// upstream's do. A cache listener therefore hears the time in the action
/// where it hears `null` for a client's write without one. The entry's
/// `dataUpdatedAt` is the raw write's when the clock stands still during
/// `structuralSharing` (a fake clock, or `updatedAt` given); when time
/// moves while sharing runs, the typed write's is earlier by that much,
/// because it is read before sharing and the raw write's after.
T _write<T>(
  QueryClient client,
  QueryKey rawKey,
  T value,
  DateTime? updatedAt,
  QueryOptions<T> Function() optionsForNew,
) {
  final cache = client.queryCache;
  final query =
      cache.get<T>(rawKey) ?? _created<T>(client, rawKey, optionsForNew);
  final storedAt = updatedAt ?? clock.now();
  var held = true;
  final stored = query.setData(
    value,
    updatedAt: storedAt,
    manual: true,
    canCommit: () => held = identical(cache.peek(rawKey), query),
  );
  if (!held) {
    // What sharing returned was computed against the entry that is gone,
    // its previous value and its own callback, and a time the clock gave
    // for it: there is no entry left that it could be stored in.
    _gone<T>(cache, rawKey, 'structuralSharing or clock');
  }
  return stored;
}

/// The entry a write made under [rawKey], as the cache holds it once its
/// listeners have heard of it.
///
/// `build` looks the key up once more and creates the entry only when it
/// is still absent: resolving the options runs the caller's `configure`,
/// and constructing the entry an `InitialData.compute`. Adding it emits
/// `QueryAdded`, so the key is looked up a last time afterwards. An entry
/// of the same type that a listener put there is the one to write; one of
/// another type is the mismatch every other is; and an entry the listener
/// removed is not made a second time, because the listener would remove
/// that one too.
Query<T> _created<T>(
  QueryClient client,
  QueryKey rawKey,
  QueryOptions<T> Function() optionsForNew,
) {
  final cache = client.queryCache;
  cache.build<T>(client, client.defaultQueryOptions<T>(optionsForNew()));
  return cache.get<T>(rawKey) ?? _gone<T>(cache, rawKey, 'cache listener');
}

/// What a write throws when the entry it was about to store into left the
/// cache first: [QueryDataTypeError] when an entry of another type is in
/// its place, a [StateError] naming [culprit] otherwise.
Never _gone<T>(QueryCache cache, QueryKey rawKey, String culprit) {
  cache.get<T>(rawKey);
  throw StateError(
    'The entry of $rawKey was removed or replaced by a $culprit while a '
    'typed write was storing into it. Nothing was written.',
  );
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

/// [typedKey] makes the key each entry is returned under: the family's
/// kind of typed key, so that a write through it stores a value as a
/// reference of that family would.
List<(TypedQueryKey<T>, T?)> _readAll<T>(
  QueryClient client,
  QueryFilters filters,
  TypedQueryKey<T> Function(QueryKey rawKey) typedKey,
) =>
    [
      for (final (key, data) in client.getQueriesData<T>(filters: filters))
        (typedKey(key), data),
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
  TypedQueryKey<T> Function(QueryKey rawKey) typedKey,
  DateTime? updatedAt,
) {
  final entries = _exactEntries<T>(client, filters);
  final keys = [for (final query in entries) typedKey(query.queryKey)];
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
        final value => keys[i]._stored(_checked<T>(value, keys[i].rawKey)),
      },
  ];
  // Every entry about to be written, looked up once more before the first
  // write. An updater is the caller's code: one that swapped an entry for
  // one of another type would otherwise be found out at that entry's
  // write, after the writes before it.
  for (var i = 0; i < entries.length; i++) {
    if (next[i] != null) {
      client.queryCache.get<T>(keys[i].rawKey);
    }
  }
  return client.notifyManager.batch(
    () => [
      for (var i = 0; i < entries.length; i++)
        (
          keys[i],
          switch (next[i]) {
            null => null,
            // By key, as the client's bulk update writes: an entry removed
            // since the first pass is made again, with the key's bare
            // options, because a family cannot tell the input from the
            // key.
            final T value => _write<T>(
                client,
                keys[i].rawKey,
                value,
                updatedAt,
                keys[i]._bareOptions,
              ),
          },
        ),
    ],
  );
}

/// [value] as a `T`, or [QueryDataTypeError] for the entry under [key].
///
/// The parameter is `Object?` and the test an explicit `is`, on purpose.
/// A reference held as `QueryEntryRef<Object?>`, or a typed key held as
/// `TypedQueryKey<Object?>`, accepts any value statically. The VM refuses
/// it at the call, but a JavaScript build
/// compiled with `-O3` or `-O4` (Flutter's web release mode) omits that
/// check, and omits casts as well. An `is` test is kept at every level, so
/// this is the line such a build stops at, and no other runtime reaches.
T _checked<T>(Object? value, QueryKey key) {
  if (value is! T) {
    throw QueryDataTypeError(key, T, value.runtimeType);
  }
  return value;
}

// ------------------------------------------------ what configure returned

/// [configured], which a definition's `configure` returned for the query
/// under [key], when it is options of exactly the definition's own type
/// [TOptions]; a [StateError] otherwise.
///
/// `configure` is typed to return the definition's options, and options of
/// a narrower data type are a subtype of those, so the analyzer accepts
/// `QueryObserverOptions<int>` from the `configure` of a definition of
/// `num`. Such options cannot take the definition's fetch function back:
/// the `copyWith` that pins it throws a `TypeError` about a parameter the
/// caller never wrote, and a JavaScript build compiled with `-O3` or `-O4`
/// omits that check and hands the narrower options on. Both options
/// classes are final, so comparing the runtime type is comparing the type
/// arguments, and that comparison is kept at every level.
TOptions _ownOptions<TOptions extends Object>(
  TOptions configured,
  QueryKey key,
) {
  if (configured.runtimeType != _typeOf<TOptions>()) {
    throw StateError(
      'configure returned ${configured.runtimeType} for $key, whose '
      'definition makes ${_typeOf<TOptions>()}. Return options of the '
      'definition\'s own type: the ones configure is handed, changed with '
      'copyWith.',
    );
  }
  return configured;
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
  InfiniteQueryObserverOptions<TPageData, TPageParam> configured, [
  _ExactWrappers<TPageData, TPageParam>? wrappers,
]) {
  _ownOptions<InfiniteQueryObserverOptions<TPageData, TPageParam>>(
    configured,
    base.queryKey,
  );
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
    structuralSharing: _exactSharing(configured.structuralSharing, wrappers),
    initialData: _exactInitialData(configured.initialData, wrappers),
  );
}

/// The wrappers one [InfiniteQueryDefinition] made, each found again by
/// the callback it wraps.
///
/// Both tables are weak and keyed by identity. A wrapper holds its
/// callback, and nothing but the options it went into holds the wrapper,
/// so this keeps alive nothing the definition's `configure` does not
/// already: a callback made anew on every call is collected with its
/// wrapper once the options that carry them are.
final class _ExactWrappers<TPageData, TPageParam> {
  final sharing =
      Expando<StructuralSharing<InfiniteData<TPageData, TPageParam>>>();
  final compute = Expando<InfiniteData<TPageData, TPageParam>? Function()>();
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
///
/// With [wrappers], the wrapper made for [sharing] before is returned
/// again; without, a new one every time.
StructuralSharing<InfiniteData<TPageData, TPageParam>>?
    _exactSharing<TPageData, TPageParam>(
  StructuralSharing<InfiniteData<TPageData, TPageParam>>? sharing,
  _ExactWrappers<TPageData, TPageParam>? wrappers,
) {
  if (sharing == null || isNoStructuralSharing(sharing)) return null;
  InfiniteData<TPageData, TPageParam> exact(
    InfiniteData<TPageData, TPageParam>? previous,
    InfiniteData<TPageData, TPageParam> next,
  ) =>
      _exactInfinite<TPageData, TPageParam>(sharing(previous, next));
  return wrappers == null ? exact : wrappers.sharing[sharing] ??= exact;
}

/// [initialData] with its seed under the declared page types, or `null` to
/// keep it as it is: a seed is written into the cache as fetched data is.
/// [wrappers] as on [_exactSharing], for a seed that is computed.
InitialData<InfiniteData<TPageData, TPageParam>>?
    _exactInitialData<TPageData, TPageParam>(
  InitialData<InfiniteData<TPageData, TPageParam>>? initialData,
  _ExactWrappers<TPageData, TPageParam>? wrappers,
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
      InfiniteData<TPageData, TPageParam>? exact() {
        final seed = compute();
        return seed == null
            ? null
            : _exactInfinite<TPageData, TPageParam>(seed);
      }
      // Two computed seeds are equal when their functions are.
      return InitialData<InfiniteData<TPageData, TPageParam>>.compute(
        wrappers == null ? exact : wrappers.compute[compute] ??= exact,
      );
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
