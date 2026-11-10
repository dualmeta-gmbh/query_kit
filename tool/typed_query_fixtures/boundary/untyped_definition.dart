/// Open-1's record for D10: what a definition **without type arguments**
/// infers. All of it compiles. The input type has no source but the
/// closures' own parameters, which take their type from the context, so it
/// comes out as `Object?`; the data type is anchored by the fetcher's
/// return.
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

void untypedDefinitions(QueryClient client) {
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
