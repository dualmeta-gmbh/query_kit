/// D10, the other half of `boundary/untyped_definition.dart`: a definition
/// without type arguments has an `Object?` input, so the ordinary one, whose
/// fetcher hands its input to a typed repository, does not compile. The
/// error is in the declaration, at the use of the input.
library;

import '../support/models.dart';
import '../support/namespace_factories.dart';
import '../surface.dart';

final _devices = QueryNamespace(['devices']);
const _repository = DeviceRepository();

// The input meets a `String` parameter.
final usesInput = QueryFamily(
  namespace: _devices,
  name: 'usesInput',
  // EXPECT error argument_type_not_assignable
  queryFn: (id, context) => _repository.device(id),
);

// The same in the factory form.
final usesInputFactory = _devices.family(
  'usesInputFactory',
  // EXPECT error argument_type_not_assignable
  queryFn: (id, context) => _repository.device(id),
);

// The input's members are not there: it is `Object?`, not `dynamic`.
final usesMember = QueryFamily(
  namespace: _devices,
  name: 'usesMember',
  // EXPECT error unchecked_use_of_nullable_value
  keyOf: (filter) => [filter.room],
  queryFn: (filter, context) => _repository.devices(),
);

// An untyped family is not the typed family it was meant to be.
// EXPECT error invalid_assignment
final QueryFamily<String, List<Device>> assigned = _untyped;

final _untyped = QueryFamily(
  namespace: _devices,
  name: 'untyped',
  queryFn: (id, context) => _repository.devices(),
);

// An infinite family whose page function uses its input.
final usesInputInfinite = InfiniteQueryFamily(
  namespace: _devices,
  name: 'usesInputInfinite',
  pageFn: (id, context) =>
      // EXPECT error argument_type_not_assignable
      _repository.events(id, cursor: context.pageParam),
  initialPageParam: (id) => 0,
  getNextPageParam: (id, page, pages, pageParam, pageParams) => pageParam + 1,
);
