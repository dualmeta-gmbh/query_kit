/// Prototype of the typed query definition surface: the public signatures
/// the plan's Phase 0 proves (`docs/plans/typed-query-definitions.md`,
/// "Final surface (TQ0)").
///
/// It is written against the *exported* API of `package:query_kit` only, so
/// it runs unchanged outside the package. That costs it two detours a module
/// inside `lib/src` does not need: an entry a typed write creates is built
/// through `QueryCache.build` and then written through `setQueryData`
/// (`Query.setData` is internal), and the family's bulk update repeats the
/// raw bulk update's two passes instead of reusing them.
///
/// The signatures are what the fixtures hold. The bodies are prototype
/// grade: enough for the analyzer and for the runtime observations (D2, D4,
/// D5, D7, D10), tested by nothing else.
// A private field set from a named parameter cannot be an initializing
// formal at the declared floor (language 3.6); the runner also analyzes
// this file at the running SDK's own language version, where the lint asks
// for one.
// ignore_for_file: prefer_initializing_formals
library;

import 'dart:async';

import 'package:query_kit/query_kit.dart';

/// What a lifecycle operation is aimed at: one cache entry (a reference),
/// every input of one operation (a family) or everything under a prefix (a
/// namespace). D7: exact for a reference, prefix for a family or namespace.
///
/// It names no data type, so it offers no read and no write.
sealed class QueryTarget {
  QueryTarget._();

  QueryKey get _selector;

  bool get _exact;

  /// The filters that select this target, for everything that takes
  /// [QueryFilters]: the client's bulk operations, `IsFetchingController`,
  /// `QueryListener`, the hooks' counts. The key and its exactness are the
  /// target's; the rest narrows it.
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

  /// [QueryClient.invalidateQueries] over this target.
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

  /// [QueryClient.refetchQueries] over this target.
  Future<void> refetch(QueryClient client, {bool cancelRefetch = true}) =>
      client.refetchQueries(filters: filters(), cancelRefetch: cancelRefetch);

  /// [QueryClient.cancelQueries] over this target.
  Future<void> cancel(
    QueryClient client, {
    bool revert = true,
    bool silent = false,
  }) =>
      client.cancelQueries(filters: filters(), revert: revert, silent: silent);

  /// [QueryClient.resetQueries] over this target.
  Future<void> reset(QueryClient client, {bool cancelRefetch = true}) =>
      client.resetQueries(filters: filters(), cancelRefetch: cancelRefetch);

  /// [QueryClient.removeQueries] over this target.
  void remove(QueryClient client) => client.removeQueries(filters: filters());
}

/// A key prefix that groups operations and claims no data type (D1).
final class QueryNamespace extends QueryTarget {
  /// The namespace whose entries all start with [parts].
  QueryNamespace(List<Object?> parts)
      : rawKey = QueryKey(parts),
        super._();

  /// The prefix, as the raw key filters take.
  final QueryKey rawKey;

  @override
  QueryKey get _selector => rawKey;

  @override
  bool get _exact => false;

  @override
  String toString() => 'QueryNamespace(${rawKey.debugString})';
}

/// A raw [QueryKey] that remembers the data type cached under it (D1).
///
/// Only a definition or a reference makes one: there is no public
/// constructor and no cast from a raw key.
final class TypedQueryKey<T> {
  const TypedQueryKey._(this.rawKey);

  /// The key the cache compares. Using it leaves the typed surface.
  final QueryKey rawKey;

  /// The data type the entry under [rawKey] holds, exactly.
  Type get dataType => T;

  /// The cached data, or `null` when there is none.
  T? read(QueryClient client) => client.getQueryData<T>(rawKey);

  /// The entry's state, which tells a cached `null` from no data.
  QueryState<T>? state(QueryClient client) => client.getQueryState<T>(rawKey);

  /// The raw key and the data type (D4).
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

/// One cache entry and the data type it holds: what [QueryRef] and
/// [InfiniteQueryRef] share. It has no `options()`, because the two options
/// types have no common subtype (D1).
sealed class QueryEntryRef<T> extends QueryTarget {
  QueryEntryRef._(QueryKey rawKey)
      : key = TypedQueryKey<T>._(rawKey),
        super._();

  /// The typed key of the entry.
  final TypedQueryKey<T> key;

  @override
  QueryKey get _selector => key.rawKey;

  @override
  bool get _exact => true;

  /// The options an entry this reference creates is built with (D5, step 4).
  QueryOptions<T> _entryOptions();

  /// The value as the entry stores it. Identity except for paged data.
  T _normalise(T value) => value;

  /// The cached data, or `null` when there is none.
  T? read(QueryClient client) => key.read(client);

  /// The entry's state, which tells a cached `null` from no data.
  QueryState<T>? state(QueryClient client) => key.state(client);

  /// Writes [value] under the declared type and returns what the cache holds.
  ///
  /// A method with no type parameter of its own (D2): the receiver fixes the
  /// type before the argument is seen.
  T write(QueryClient client, T value, {DateTime? updatedAt}) {
    client.queryCache.get<T>(key.rawKey);
    return _commit(client, value, updatedAt);
  }

  /// Writes what [updater] returns for the current data; `null` writes
  /// nothing.
  T? update(
    QueryClient client,
    T? Function(T? previous) updater, {
    DateTime? updatedAt,
  }) {
    final existing = client.queryCache.get<T>(key.rawKey);
    final previous =
        existing != null && existing.state.hasData ? existing.state.data : null;
    final Object? next = updater(previous);
    return next == null ? null : _commit(client, next, updatedAt);
  }

  T _commit(QueryClient client, Object? value, DateTime? updatedAt) {
    // Through `Object?`, not through the parameter's own type: a receiver
    // widened to `QueryEntryRef<Object?>` accepts any value statically, and
    // dart2js at -O3/-O4 omits the covariance check that would refuse it at
    // the call. An explicit `is` test survives those levels.
    if (value is! T) {
      throw QueryDataTypeError(key.rawKey, T, value.runtimeType);
    }
    final stored = _normalise(value);
    // The entry is built with the reference's own options, so a first write
    // creates it under the declared type with the definition's `gcTime` and
    // `structuralSharing`.
    client.queryCache.build<T>(
      client,
      client.defaultQueryOptions<T>(_entryOptions()),
    );
    return client.setQueryData<T>(key.rawKey, stored, updatedAt: updatedAt);
  }
}

/// A plain query: a definition bound to its input (D1).
///
/// It is a value. It holds no client, and making one fetches nothing.
abstract final class QueryRef<T> extends QueryEntryRef<T> {
  QueryRef._(super.rawKey) : super._();

  /// Fresh options for this entry, to hand to an observer, a controller, a
  /// builder, `context.query` or a hook. Nothing memoises them (D4).
  QueryObserverOptions<T> options();

  @override
  QueryOptions<T> _entryOptions() => options();

  /// [QueryClient.query] with these options.
  Future<T> fetch(QueryClient client, {bool revalidateIfStale = false}) =>
      client.query<T>(options(), revalidateIfStale: revalidateIfStale);

  /// The kind, the data type and the raw key (D4). The fetcher is not part
  /// of it.
  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is QueryRef<Object?> && other.key == key;

  @override
  int get hashCode => Object.hash(QueryRef, key);

  @override
  String toString() => 'QueryRef<$T>(${key.rawKey.debugString})';
}

/// An infinite query: a definition bound to its input (D1, D8).
abstract final class InfiniteQueryRef<TPageData, TPageParam>
    extends QueryEntryRef<InfiniteData<TPageData, TPageParam>> {
  InfiniteQueryRef._(super.rawKey) : super._();

  /// Fresh options for this entry, for the infinite consumers.
  InfiniteQueryObserverOptions<TPageData, TPageParam> options();

  @override
  QueryOptions<InfiniteData<TPageData, TPageParam>> _entryOptions() =>
      options();

  @override
  InfiniteData<TPageData, TPageParam> _normalise(
    InfiniteData<TPageData, TPageParam> value,
  ) =>
      _normaliseInfinite<TPageData, TPageParam>(value);

  /// [QueryClient.infiniteQuery] with these options.
  Future<InfiniteData<TPageData, TPageParam>> fetch(
    QueryClient client, {
    bool revalidateIfStale = false,
  }) =>
      client.infiniteQuery<TPageData, TPageParam>(
        options(),
        revalidateIfStale: revalidateIfStale,
      );

  /// The kind, the data type and the raw key (D4).
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

/// A plain query with no varying input: the definition is the reference.
final class QueryDefinition<T> extends QueryRef<T> {
  /// The entry `[...namespace, name]`.
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
    // Re-pinned after `configure`, so a definition cannot move its own key
    // or swap its own fetcher.
    return (_configure?.call(base) ?? base)
        .copyWith(queryKey: key.rawKey, queryFn: _queryFn);
  }
}

/// One operation over a varying input (D1). Calling it binds an input.
final class QueryFamily<TInput, T> extends QueryTarget {
  /// The entries `[...namespace, name, ...keyOf(input)]`.
  ///
  /// Without [keyOf] the input is the one key part after the name, which is
  /// what a raw key would hold: `[...namespace, name, input]`.
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

  /// The family's prefix, as the raw key filters take.
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

  /// The reference for [input].
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
    return (_configure?.call(base, input) ?? base)
        .copyWith(queryKey: key, queryFn: bound);
  }

  /// The cached data of every input, `null` where an entry holds none.
  /// Throws [QueryDataTypeError] when an entry under the prefix holds
  /// another type.
  List<(TypedQueryKey<T>, T?)> readAll(QueryClient client) =>
      _readAll<T>(client, filters());

  /// Runs [updater] over every input's entry. Every entry is checked for
  /// the exact type and every result is validated before the first write
  /// (D7).
  List<(TypedQueryKey<T>, T?)> updateAll(
    QueryClient client,
    T? Function(T? previous) updater, {
    DateTime? updatedAt,
  }) =>
      _updateAll<T>(client, filters(), updater, (value) => value, updatedAt);

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

/// An infinite query with no varying input: the definition is the reference
/// (D1, D8). Its page functions are the existing ones.
final class InfiniteQueryDefinition<TPageData, TPageParam>
    extends InfiniteQueryRef<TPageData, TPageParam> {
  /// The entry `[...namespace, name]`.
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
    return (_configure?.call(base) ?? base).copyWith(
      queryKey: key.rawKey,
      pageFn: _pageFn,
      initialPageParam: _initialPageParam,
      getNextPageParam: _getNextPageParam,
      getPreviousPageParam: _getPreviousPageParam,
    );
  }
}

/// One paged operation over a varying input (D8). The input identifies the
/// entry; the page params live inside its [InfiniteData].
final class InfiniteQueryFamily<TInput, TPageData, TPageParam>
    extends QueryTarget {
  /// The entries `[...namespace, name, ...keyOf(input)]`; without [keyOf],
  /// `[...namespace, name, input]`.
  ///
  /// The four paging functions take the input first: they are required
  /// before `configure` has a base to work on, and they often depend on the
  /// input (D6).
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

  /// The family's prefix, as the raw key filters take.
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

  /// The reference for [input].
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
    FutureOr<TPageData> pageFn(InfinitePageContext<TPageParam> context) =>
        _pageFn(input, context);
    TPageParam? next(
      TPageData page,
      List<TPageData> pages,
      TPageParam pageParam,
      List<TPageParam> pageParams,
    ) =>
        _getNextPageParam(input, page, pages, pageParam, pageParams);
    final PageParamFn<TPageData, TPageParam>? previous = getPrevious == null
        ? null
        : (page, pages, pageParam, pageParams) =>
            getPrevious(input, page, pages, pageParam, pageParams);
    final initial = _initialPageParam(input);
    final base = InfiniteQueryObserverOptions<TPageData, TPageParam>(
      queryKey: key,
      pageFn: pageFn,
      initialPageParam: initial,
      getNextPageParam: next,
      getPreviousPageParam: previous,
    );
    return (_configure?.call(base, input) ?? base).copyWith(
      queryKey: key,
      pageFn: pageFn,
      initialPageParam: initial,
      getNextPageParam: next,
      getPreviousPageParam: previous,
    );
  }

  /// The cached pages of every input, `null` where an entry holds none.
  List<
      (
        TypedQueryKey<InfiniteData<TPageData, TPageParam>>,
        InfiniteData<TPageData, TPageParam>?
      )> readAll(
          QueryClient client) =>
      _readAll<InfiniteData<TPageData, TPageParam>>(client, filters());

  /// Runs [updater] over every input's entry, as [QueryFamily.updateAll]
  /// does, and stores each result under the declared page types.
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
        _normaliseInfinite<TPageData, TPageParam>,
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

/// D5: an [InfiniteData] narrower in its type arguments than the entry is
/// rebuilt under the declared ones; an exact one is kept as it is.
InfiniteData<TPageData, TPageParam> _normaliseInfinite<TPageData, TPageParam>(
  InfiniteData<TPageData, TPageParam> value,
) =>
    value.runtimeType == _typeOf<InfiniteData<TPageData, TPageParam>>()
        ? value
        : InfiniteData<TPageData, TPageParam>(
            pages: List<TPageData>.unmodifiable(value.pages),
            pageParams: List<TPageParam>.unmodifiable(value.pageParams),
          );

Type _typeOf<X>() => X;

/// D2 for the input: a family widened to `QueryFamily<Object?, …>` accepts
/// any input statically, and dart2js at -O3/-O4 omits the covariance check
/// that would refuse it at the call. Without this the wrong input would
/// become a key part and reach the fetcher as a `TInput`.
void _checkInput<TInput>(Object? input, Object family) {
  if (input is! TInput) {
    throw ArgumentError.value(input, 'input', 'Not an input of $family');
  }
}

/// D7's preflight: every matched entry holds exactly `T`, or nothing is
/// read and nothing is written.
List<Query<Object?>> _exactEntries<T>(
    QueryClient client, QueryFilters filters) {
  final queries = client.queryCache.findAll(filters: filters);
  for (final query in queries) {
    if (query.dataType != T) {
      throw QueryDataTypeError(query.queryKey, T, query.dataType);
    }
  }
  return queries;
}

List<(TypedQueryKey<T>, T?)> _readAll<T>(
  QueryClient client,
  QueryFilters filters,
) =>
    [
      for (final query in _exactEntries<T>(client, filters))
        (
          TypedQueryKey<T>._(query.queryKey),
          query.state.hasData ? query.state.data as T : null,
        ),
    ];

List<(TypedQueryKey<T>, T?)> _updateAll<T>(
  QueryClient client,
  QueryFilters filters,
  T? Function(T? previous) updater,
  T Function(T value) normalise,
  DateTime? updatedAt,
) {
  final queries = _exactEntries<T>(client, filters);
  // Every updater runs and every result is validated before the first
  // write, as the raw bulk update prepares its batch.
  final next = <T?>[];
  for (final query in queries) {
    final Object? value =
        updater(query.state.hasData ? query.state.data as T : null);
    // Through `Object?`, for the reason `QueryEntryRef._commit` gives. A
    // `null` writes nothing, whatever `T` is.
    if (value is T) {
      next.add(value == null ? null : normalise(value));
    } else if (value == null) {
      next.add(null);
    } else {
      throw QueryDataTypeError(query.queryKey, T, value.runtimeType);
    }
  }
  return client.notifyManager.batch(
    () => [
      for (var i = 0; i < queries.length; i++)
        (
          TypedQueryKey<T>._(queries[i].queryKey),
          switch (next[i]) {
            null => null,
            final T value => client.setQueryData<T>(
                queries[i].queryKey,
                value,
                updatedAt: updatedAt,
              ),
          },
        ),
    ],
  );
}

/// D10's backstop, the binding's own: `List<Object?>` is a `List<X>` exactly
/// for the top types, so it refuses `dynamic`, `Object?` and `void` alike.
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
