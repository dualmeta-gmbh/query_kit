/// D10's positive half: the documented form writes the type arguments on
/// every definition, and then every closure sees the declared types,
/// whatever it reads and whether or not there is a `configure`.
///
/// Below it, what else was measured to cure the two failures of an
/// infinite definition without type arguments
/// (`negative/untyped_definition.dart`, `boundary/untyped_definition.dart`):
/// a type written on the right closure parameter, a named page function, a
/// declared field type. They are the record of why the rule is the type
/// arguments and not one of them: which parameter has to be typed depends
/// on which failure it is.
library;

import '../support/models.dart';
import '../support/static_type.dart';
import '../surface.dart';

final _devices = QueryNamespace(['devices']);
const _repository = DeviceRepository();

// --- the documented form ----------------------------------------------------

final list = QueryDefinition<List<Device>>(
  namespace: _devices,
  name: 'list',
  queryFn: (context) => _repository.devices(),
  configure: (base) => base.copyWith(staleTime: StaleTime.infinite),
);

final detail = QueryFamily<String, Device>(
  namespace: _devices,
  name: 'detail',
  queryFn: (id, context) => _repository.device(id),
  configure: (base, id) => base.copyWith(meta: id.length),
);

// Reads its page and its pages, and configures.
final feed = InfiniteQueryDefinition<List<Device>, int>(
  namespace: _devices,
  name: 'feed',
  pageFn: (context) => _repository.page(context.pageParam),
  initialPageParam: 0,
  getNextPageParam: (page, pages, pageParam, pageParams) {
    page.expectStaticType<Exactly<List<Device>>>();
    pages.expectStaticType<Exactly<List<List<Device>>>>();
    return page.isEmpty || pages.last.isEmpty ? null : pageParam + 1;
  },
  getPreviousPageParam: (page, pages, pageParam, pageParams) =>
      page.isEmpty ? null : pageParam - 1,
  configure: (base) {
    base.expectStaticType<
        Exactly<InfiniteQueryObserverOptions<List<Device>, int>>>();
    return base.copyWith(maxPages: 3);
  },
);

final history = InfiniteQueryFamily<String, List<DeviceEvent>, int>(
  namespace: _devices,
  name: 'history',
  pageFn: (id, context) => _repository.events(id, cursor: context.pageParam),
  initialPageParam: (id) => 0,
  getNextPageParam: (id, page, pages, pageParam, pageParams) =>
      page.isEmpty ? null : pageParam + 1,
  configure: (base, id) => base.copyWith(maxPages: id.length),
);

// --- what else cures a page that is read ------------------------------------

// The page parameter typed where it is read.
final typedPage = InfiniteQueryDefinition(
  namespace: _devices,
  name: 'typedPage',
  pageFn: (context) => _repository.page(context.pageParam),
  initialPageParam: 0,
  getNextPageParam: (List<Device> page, pages, pageParam, pageParams) =>
      page.isEmpty ? null : pageParam + 1,
);

// The page function's own parameter typed.
final typedContext = InfiniteQueryDefinition(
  namespace: _devices,
  name: 'typedContext',
  pageFn: (InfinitePageContext<int> context) =>
      _repository.page(context.pageParam),
  initialPageParam: 0,
  getNextPageParam: (page, pages, pageParam, pageParams) =>
      page.isEmpty ? null : pageParam + 1,
);

// A named page function.
Future<List<Device>> _page(InfinitePageContext<int> context) =>
    _repository.page(context.pageParam);

final namedPageFunction = InfiniteQueryDefinition(
  namespace: _devices,
  name: 'namedPageFunction',
  pageFn: _page,
  initialPageParam: 0,
  getNextPageParam: (page, pages, pageParam, pageParams) =>
      page.isEmpty ? null : pageParam + 1,
);

// --- what else cures a `configure` ------------------------------------------

// The `configure` parameter typed. (Typing the page parameter instead does
// not: `negative/untyped_definition.dart`.)
final typedConfigure = InfiniteQueryDefinition(
  namespace: _devices,
  name: 'typedConfigure',
  pageFn: (context) => _repository.page(context.pageParam),
  initialPageParam: 0,
  getNextPageParam: (page, pages, pageParam, pageParams) => pageParam + 1,
  configure: (InfiniteQueryObserverOptions<List<Device>, int> base) =>
      base.copyWith(maxPages: 3),
);

// The page function's own parameter typed, which cures both at once.
final typedContextConfigured = InfiniteQueryDefinition(
  namespace: _devices,
  name: 'typedContextConfigured',
  pageFn: (InfinitePageContext<int> context) =>
      _repository.page(context.pageParam),
  initialPageParam: 0,
  getNextPageParam: (page, pages, pageParam, pageParams) =>
      page.isEmpty ? null : pageParam + 1,
  configure: (base) => base.copyWith(maxPages: 3),
);

// A named page function, the same.
final namedPageFunctionConfigured = InfiniteQueryDefinition(
  namespace: _devices,
  name: 'namedPageFunctionConfigured',
  pageFn: _page,
  initialPageParam: 0,
  getNextPageParam: (page, pages, pageParam, pageParams) =>
      page.isEmpty ? null : pageParam + 1,
  configure: (base) => base.copyWith(maxPages: 3),
);

// A declared type on the field is the type arguments, written elsewhere.
final InfiniteQueryDefinition<List<Device>, int> declaredField =
    InfiniteQueryDefinition(
  namespace: _devices,
  name: 'declaredField',
  pageFn: (context) => _repository.page(context.pageParam),
  initialPageParam: 0,
  getNextPageParam: (page, pages, pageParam, pageParams) =>
      page.isEmpty ? null : pageParam + 1,
  configure: (base) => base.copyWith(maxPages: 3),
);

// A family with its closure parameters typed infers its input, with or
// without a `configure`.
final typedInput = QueryFamily(
  namespace: _devices,
  name: 'typedInput',
  queryFn: (String id, QueryFunctionContext context) => _repository.device(id),
  configure: (base, id) => base.copyWith(meta: id.length),
);

void writtenTypeArguments() {
  list.expectStaticType<Exactly<QueryDefinition<List<Device>>>>();
  detail.expectStaticType<Exactly<QueryFamily<String, Device>>>();
  feed.expectStaticType<Exactly<InfiniteQueryDefinition<List<Device>, int>>>();
  history.expectStaticType<
      Exactly<InfiniteQueryFamily<String, List<DeviceEvent>, int>>>();

  typedPage
      .expectStaticType<Exactly<InfiniteQueryDefinition<List<Device>, int>>>();
  typedContext
      .expectStaticType<Exactly<InfiniteQueryDefinition<List<Device>, int>>>();
  namedPageFunction
      .expectStaticType<Exactly<InfiniteQueryDefinition<List<Device>, int>>>();
  typedConfigure
      .expectStaticType<Exactly<InfiniteQueryDefinition<List<Device>, int>>>();
  typedContextConfigured
      .expectStaticType<Exactly<InfiniteQueryDefinition<List<Device>, int>>>();
  namedPageFunctionConfigured
      .expectStaticType<Exactly<InfiniteQueryDefinition<List<Device>, int>>>();
  declaredField
      .expectStaticType<Exactly<InfiniteQueryDefinition<List<Device>, int>>>();
  typedInput.expectStaticType<Exactly<QueryFamily<String, Device>>>();
}
