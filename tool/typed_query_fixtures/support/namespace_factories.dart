/// The declaration form the plan did *not* choose, written out so the
/// fixtures can compare the two: factory methods on the namespace instead of
/// the definitions' constructors.
///
/// It is an extension over the public constructors and nothing more, which
/// is the first piece of evidence: an application that prefers this form
/// writes these lines itself, and the library gives up nothing by not
/// shipping them.
library;

import 'dart:async';

import '../surface.dart';

extension NamespaceFactories on QueryNamespace {
  QueryFamily<TInput, T> family<TInput, T>(
    String name, {
    List<Object?> Function(TInput input)? keyOf,
    FutureOr<T> Function(TInput input, QueryFunctionContext context)? queryFn,
    QueryObserverOptions<T> Function(
      QueryObserverOptions<T> base,
      TInput input,
    )? configure,
  }) =>
      QueryFamily<TInput, T>(
        namespace: this,
        name: name,
        keyOf: keyOf,
        queryFn: queryFn,
        configure: configure,
      );

  QueryDefinition<T> query<T>(
    String name, {
    FutureOr<T> Function(QueryFunctionContext context)? queryFn,
    QueryObserverOptions<T> Function(QueryObserverOptions<T> base)? configure,
  }) =>
      QueryDefinition<T>(
        namespace: this,
        name: name,
        queryFn: queryFn,
        configure: configure,
      );

  InfiniteQueryDefinition<TPageData, TPageParam>
      infiniteQuery<TPageData, TPageParam>(
    String name, {
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
  }) =>
          InfiniteQueryDefinition<TPageData, TPageParam>(
            namespace: this,
            name: name,
            pageFn: pageFn,
            initialPageParam: initialPageParam,
            getNextPageParam: getNextPageParam,
          );

  InfiniteQueryFamily<TInput, TPageData, TPageParam>
      infiniteFamily<TInput, TPageData, TPageParam>(
    String name, {
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
  }) =>
          InfiniteQueryFamily<TInput, TPageData, TPageParam>(
            namespace: this,
            name: name,
            pageFn: pageFn,
            initialPageParam: initialPageParam,
            getNextPageParam: getNextPageParam,
          );
}
