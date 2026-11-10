/// Open-2, the acceptance matrix's "input shape, fetch return type, page
/// data and page parameter": a declaration that contradicts its own type
/// arguments is an error in the declaration, and a call with the wrong
/// input shape is an error at the call.
library;

import '../support/models.dart';
import '../surface.dart';

final _devices = QueryNamespace(['devices']);
const _repository = DeviceRepository();

Future<String> _fetchName(String id, QueryFunctionContext context) async => id;

// The fetcher returns another type than the definition declares.
final wrongReturn = QueryFamily<String, Device>(
  namespace: _devices,
  name: 'wrongReturn',
  // EXPECT error return_of_invalid_type_from_closure
  queryFn: (id, context) => 'a name',
);

// An extracted fetcher of another type.
final wrongTearOff = QueryFamily<String, Device>(
  namespace: _devices,
  name: 'wrongTearOff',
  // EXPECT error argument_type_not_assignable
  queryFn: _fetchName,
);

// The fetcher uses its input as another type than the family declares.
final wrongInputUse = QueryFamily<int, Device>(
  namespace: _devices,
  name: 'wrongInputUse',
  // EXPECT error argument_type_not_assignable
  queryFn: (id, context) => _repository.device(id),
);

// A zero-input definition's fetcher returns another type.
final wrongStatic = QueryDefinition<List<Device>>(
  namespace: _devices,
  name: 'wrongStatic',
  // EXPECT error return_of_invalid_type_from_closure
  queryFn: (context) => _repository.device('d1'),
);

// `keyOf` returns key parts, not one part.
final wrongKeyOf = QueryFamily<String, Device>(
  namespace: _devices,
  name: 'wrongKeyOf',
  // EXPECT error return_of_invalid_type_from_closure
  keyOf: (id) => id,
);

// `keyOf` is typed by the family's input.
final wrongKeyOfInput = QueryFamily<String, Device>(
  namespace: _devices,
  name: 'wrongKeyOfInput',
  // EXPECT error argument_type_not_assignable
  keyOf: (int id) => [id],
);

// `configure` returns options of the definition's data type.
final wrongConfigure = QueryFamily<String, Device>(
  namespace: _devices,
  name: 'wrongConfigure',
  configure: (base, id) =>
      // EXPECT error return_of_invalid_type_from_closure
      QueryObserverOptions<String>(queryKey: base.queryKey),
);

// A name is a string.
final wrongName = QueryFamily<String, Device>(
  namespace: _devices,
  // EXPECT error argument_type_not_assignable
  name: 42,
);

// The page function returns another page type.
final wrongPage = InfiniteQueryDefinition<List<Device>, int>(
  namespace: _devices,
  name: 'wrongPage',
  // EXPECT error return_of_invalid_type_from_closure
  pageFn: (context) => 'a page',
  initialPageParam: 0,
  getNextPageParam: (page, pages, pageParam, pageParams) => null,
);

// The initial page param is another type.
final wrongInitialParam = InfiniteQueryDefinition<List<Device>, int>(
  namespace: _devices,
  name: 'wrongInitialParam',
  pageFn: (context) => _repository.page(context.pageParam),
  // EXPECT error argument_type_not_assignable
  initialPageParam: 'first',
  getNextPageParam: (page, pages, pageParam, pageParams) => null,
);

// The next page param is another type.
final wrongNextParam = InfiniteQueryDefinition<List<Device>, int>(
  namespace: _devices,
  name: 'wrongNextParam',
  pageFn: (context) => _repository.page(context.pageParam),
  initialPageParam: 0,
  // EXPECT error return_of_invalid_type_from_closure
  getNextPageParam: (page, pages, pageParam, pageParams) => 'next',
);

// The page function uses its param as another type.
final wrongParamUse = InfiniteQueryDefinition<List<Device>, String>(
  namespace: _devices,
  name: 'wrongParamUse',
  // EXPECT error argument_type_not_assignable
  pageFn: (context) => _repository.page(context.pageParam),
  initialPageParam: 'first',
  getNextPageParam: (page, pages, pageParam, pageParams) => null,
);

// An infinite family's functions take the input first.
final wrongFamilyPage = InfiniteQueryFamily<String, List<DeviceEvent>, int>(
  namespace: _devices,
  name: 'wrongFamilyPage',
  // EXPECT error argument_type_not_assignable
  pageFn: (context) => _repository.events('d1', cursor: 0),
  // EXPECT error argument_type_not_assignable
  initialPageParam: 0,
  getNextPageParam: (id, page, pages, pageParam, pageParams) => null,
);

// An infinite definition needs its paging functions.
// EXPECT error missing_required_argument
// EXPECT error missing_required_argument
// EXPECT error missing_required_argument
final missingPaging = InfiniteQueryDefinition<List<Device>, int>(
  namespace: _devices,
  name: 'missingPaging',
);

void inputShapes(QueryClient client) {
  // No input where one is declared.
  // EXPECT error not_enough_positional_arguments
  queries.devices.detail();

  // Two inputs where one is declared.
  // EXPECT error extra_positional_arguments
  queries.devices.detail('d1', 'd2');

  // A nullable input where the declared one is not.
  // EXPECT error argument_type_not_assignable
  queries.devices.detail(null);

  // A record with a missing field.
  // EXPECT error argument_type_not_assignable
  queries.devices.inRoom((room: Room.hall));

  // A record with a misspelled field.
  // EXPECT error argument_type_not_assignable
  queries.devices.inRoom((room: Room.hall, onlyOnn: true));

  // A record with a wrongly typed field.
  // EXPECT error argument_type_not_assignable
  queries.devices.inRoom((room: 'hall', onlyOn: true));

  // A value object's field is checked where the object is built.
  // EXPECT error argument_type_not_assignable
  queries.devices.filtered(DeviceFilter(room: 'hall'));

  // A zero-input definition is a reference, not a function.
  // EXPECT error invocation_of_non_function_expression
  queries.devices.list('d1');

  // An infinite family's input is typed as a plain family's is.
  // EXPECT error argument_type_not_assignable
  queries.devices.history(1);
}
