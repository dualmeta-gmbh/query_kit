/// Open-1's record for D10: what a definition **without type arguments**
/// infers. All of it compiles. The input type has no source but the
/// closures' own parameters, which take their type from the context, so it
/// comes out as `Object?`; the data type is anchored by the fetcher's
/// return.
///
/// An infinite definition's page type has the same weakness once a
/// `configure` is written: the page type then comes out as `Object?`, with
/// no diagnostic under the analyzer's defaults and none under the
/// repository's strict settings (there is no marker on it, and an
/// unexpected diagnostic fails the run). A plain definition with a fetcher and a
/// `configure` infers exactly; that is measured here and is not the
/// documented form. The documented form writes the type arguments on every
/// definition (`positive/written_type_arguments.dart`).
///
/// The two declaration forms (constructor, namespace factory) infer the
/// same. What refuses these declarations at runtime is the debug backstop,
/// `runtime/observations.dart`; what makes most of them fail earlier is in
/// `negative/untyped_definition.dart`.
library;

import '../support/models.dart';
import '../support/namespace_factories.dart';
import '../support/static_type.dart';
import '../surface.dart';

final _devices = QueryNamespace(['devices']);
const _repository = DeviceRepository();

// A fetcher that never uses its input.
final untyped = QueryFamily(
  namespace: _devices,
  name: 'untyped',
  queryFn: (id, context) => _repository.devices(),
);

// An explicit `keyOf` names no type either.
final untypedWithKey = QueryFamily(
  namespace: _devices,
  name: 'untypedWithKey',
  keyOf: (id) => [id],
  queryFn: (id, context) => _repository.devices(),
);

// The factory form.
final untypedFactory = _devices.family(
  'untypedFactory',
  queryFn: (id, context) => _repository.devices(),
);

// The infinite family.
final untypedInfinite = InfiniteQueryFamily(
  namespace: _devices,
  name: 'untypedInfinite',
  pageFn: (id, context) => _repository.page(context.pageParam),
  initialPageParam: (id) => 0,
  getNextPageParam: (id, page, pages, pageParam, pageParams) => pageParam + 1,
);

// A key-only family names nothing at all.
// EXPECT strict inference_failure_on_instance_creation
final bare = QueryFamily(namespace: _devices, name: 'bare');

// EXPECT strict inference_failure_on_instance_creation
final bareDefinition = QueryDefinition(namespace: _devices, name: 'bare');

// An infinite definition whose page functions never read the page: exact
// without a `configure` ...
final untypedFeed = InfiniteQueryDefinition(
  namespace: _devices,
  name: 'untypedFeed',
  pageFn: (context) => _repository.page(context.pageParam),
  initialPageParam: 0,
  getNextPageParam: (page, pages, pageParam, pageParams) => pageParam + 1,
);

// ... and with one, the page type is lost: `Object?`.
final untypedFeedConfigured = InfiniteQueryDefinition(
  namespace: _devices,
  name: 'untypedFeedConfigured',
  pageFn: (context) => _repository.page(context.pageParam),
  initialPageParam: 0,
  getNextPageParam: (page, pages, pageParam, pageParams) => pageParam + 1,
  configure: (base) => base.copyWith(maxPages: 3),
);

// An infinite family loses its page type the same way, with its input.
final untypedInfiniteConfigured = InfiniteQueryFamily(
  namespace: _devices,
  name: 'untypedInfiniteConfigured',
  pageFn: (id, context) => _repository.page(context.pageParam),
  initialPageParam: (id) => 0,
  getNextPageParam: (id, page, pages, pageParam, pageParams) => pageParam + 1,
  configure: (base, id) => base.copyWith(maxPages: 3),
);

// A plain definition with a fetcher keeps its data type beside a
// `configure`, whatever the `configure` does.
final untypedListConfigured = QueryDefinition(
  namespace: _devices,
  name: 'untypedListConfigured',
  queryFn: (context) => _repository.devices(),
  configure: (base) => base.copyWith(
    staleTime: StaleTime.infinite,
    initialData: InitialData.compute(() => const [Device('d1')]),
  ),
);

// A family's data type too; its input is `Object?` as before.
final untypedConfigured = QueryFamily(
  namespace: _devices,
  name: 'untypedConfigured',
  queryFn: (id, context) => _repository.devices(),
  configure: (base, id) => base.copyWith(staleTime: StaleTime.infinite),
);

// A key-only definition with a `configure` names nothing.
final bareConfigured = QueryDefinition(
  namespace: _devices,
  name: 'bareConfigured',
  configure: (base) => base.copyWith(staleTime: StaleTime.infinite),
);

void untypedDefinitions(QueryClient client) {
  untypedFeed
      .expectStaticType<Exactly<InfiniteQueryDefinition<List<Device>, int>>>();
  untypedFeedConfigured
      .expectStaticType<Exactly<InfiniteQueryDefinition<Object?, int>>>();
  untypedInfiniteConfigured
      .expectStaticType<Exactly<InfiniteQueryFamily<Object?, Object?, int>>>();
  untypedListConfigured
      .expectStaticType<Exactly<QueryDefinition<List<Device>>>>();
  untypedConfigured
      .expectStaticType<Exactly<QueryFamily<Object?, List<Device>>>>();
  bareConfigured.expectStaticType<Exactly<QueryDefinition<Object?>>>();

  // What was lost is lost at every use: the pages are `Object?`, and any
  // paged data is accepted.
  untypedFeedConfigured
      .read(client)
      .expectStaticType<Exactly<InfiniteData<Object?, int>?>>();
  untypedFeedConfigured.write(
    client,
    InfiniteData(pages: const ['not a page'], pageParams: const [0]),
  );

  untyped.expectStaticType<Exactly<QueryFamily<Object?, List<Device>>>>();
  untypedWithKey
      .expectStaticType<Exactly<QueryFamily<Object?, List<Device>>>>();
  untypedFactory
      .expectStaticType<Exactly<QueryFamily<Object?, List<Device>>>>();
  untypedInfinite.expectStaticType<
      Exactly<InfiniteQueryFamily<Object?, List<Device>, int>>>();
  bare.expectStaticType<Exactly<QueryFamily<dynamic, dynamic>>>();
  bareDefinition.expectStaticType<Exactly<QueryDefinition<dynamic>>>();

  // The data type is exact all the same.
  untyped('d1').expectStaticType<Exactly<QueryRef<List<Device>>>>();
  untyped('d1').read(client).expectStaticType<Exactly<List<Device>?>>();

  // And any input is accepted, which is the limit.
  untyped(42);
  untyped(null);
  untyped(const Device('d1'));
}
