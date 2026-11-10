/// The two ways a declaration could be spelled, side by side: the
/// definitions' constructors (the plan's form) and factory methods on the
/// namespace (`support/namespace_factories.dart`).
///
/// With type arguments both infer the same types, and the callbacks see the
/// same parameter types. What they infer *without* type arguments is in
/// `boundary/untyped_definition.dart`, and it is the same there too.
library;

import '../support/models.dart';
import '../support/namespace_factories.dart';
import '../support/static_type.dart';
import '../surface.dart';

final _devices = QueryNamespace(['devices']);
const _repository = DeviceRepository();

// --- a family ---------------------------------------------------------------

final constructorFamily = QueryFamily<String, Device>(
  namespace: _devices,
  name: 'detail',
  queryFn: (id, context) => _repository.device(id, signal: context.signal),
);

final factoryFamily = _devices.family<String, Device>(
  'detail',
  queryFn: (id, context) => _repository.device(id, signal: context.signal),
);

// --- a zero-input definition ------------------------------------------------

final constructorList = QueryDefinition<List<Device>>(
  namespace: _devices,
  name: 'list',
  queryFn: (context) => _repository.devices(),
);

final factoryList = _devices.query<List<Device>>(
  'list',
  queryFn: (context) => _repository.devices(),
);

// --- the infinite twins -----------------------------------------------------

final constructorFeed = InfiniteQueryDefinition<List<Device>, int>(
  namespace: _devices,
  name: 'feed',
  pageFn: (context) => _repository.page(context.pageParam),
  initialPageParam: 0,
  getNextPageParam: (page, pages, pageParam, pageParams) => pageParam + 1,
);

final factoryFeed = _devices.infiniteQuery<List<Device>, int>(
  'feed',
  pageFn: (context) => _repository.page(context.pageParam),
  initialPageParam: 0,
  getNextPageParam: (page, pages, pageParam, pageParams) => pageParam + 1,
);

final constructorHistory = InfiniteQueryFamily<String, List<DeviceEvent>, int>(
  namespace: _devices,
  name: 'history',
  pageFn: (id, context) => _repository.events(id, cursor: context.pageParam),
  initialPageParam: (id) => 0,
  getNextPageParam: (id, page, pages, pageParam, pageParams) => pageParam + 1,
);

final factoryHistory = _devices.infiniteFamily<String, List<DeviceEvent>, int>(
  'history',
  pageFn: (id, context) => _repository.events(id, cursor: context.pageParam),
  initialPageParam: (id) => 0,
  getNextPageParam: (id, page, pages, pageParam, pageParams) => pageParam + 1,
);

void declarationForms() {
  constructorFamily.expectStaticType<Exactly<QueryFamily<String, Device>>>();
  factoryFamily.expectStaticType<Exactly<QueryFamily<String, Device>>>();

  constructorList.expectStaticType<Exactly<QueryDefinition<List<Device>>>>();
  factoryList.expectStaticType<Exactly<QueryDefinition<List<Device>>>>();

  constructorFeed
      .expectStaticType<Exactly<InfiniteQueryDefinition<List<Device>, int>>>();
  factoryFeed
      .expectStaticType<Exactly<InfiniteQueryDefinition<List<Device>, int>>>();

  constructorHistory.expectStaticType<
      Exactly<InfiniteQueryFamily<String, List<DeviceEvent>, int>>>();
  factoryHistory.expectStaticType<
      Exactly<InfiniteQueryFamily<String, List<DeviceEvent>, int>>>();

  // Both forms anchor a zero-input definition by its fetcher alone.
  QueryDefinition(
    namespace: _devices,
    name: 'inferred',
    queryFn: (context) => _repository.devices(),
  ).expectStaticType<Exactly<QueryDefinition<List<Device>>>>();
  _devices
      .query('inferred', queryFn: (context) => _repository.devices())
      .expectStaticType<Exactly<QueryDefinition<List<Device>>>>();

  // Both forms anchor a family by typed closure parameters.
  QueryFamily(
    namespace: _devices,
    name: 'typed',
    queryFn: (String id, QueryFunctionContext context) =>
        _repository.device(id),
  ).expectStaticType<Exactly<QueryFamily<String, Device>>>();
  _devices
      .family(
        'typed',
        queryFn: (String id, QueryFunctionContext context) =>
            _repository.device(id),
      )
      .expectStaticType<Exactly<QueryFamily<String, Device>>>();
}
