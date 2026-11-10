/// Open-2, the acceptance matrix's "read assignment, write value, updater
/// parameter/return, selector": each wrong use is an error where it is
/// written.
library;

import '../support/models.dart';
import '../surface.dart';

Future<void> reads(QueryClient client) async {
  final device = queries.devices.detail('d1');

  // EXPECT error invalid_assignment
  final String? fromReference = device.read(client);

  // `read` is nullable: nothing may be cached.
  // EXPECT error invalid_assignment
  final Device notNull = device.read(client);

  // EXPECT error invalid_assignment
  final String fetched = await device.fetch(client);

  // EXPECT error invalid_assignment
  final QueryState<String>? state = device.state(client);

  // EXPECT error invalid_assignment
  final TypedQueryKey<String> key = device.key;

  // A reference of one data type is not a reference of another.
  // EXPECT error invalid_assignment
  final QueryRef<Thermostat> narrower = device;

  // EXPECT error invalid_assignment
  final QueryObserverOptions<String> options = device.options();

  // A list of devices is not a device.
  // EXPECT error invalid_assignment
  final Device? one = queries.devices.list.read(client);

  _use([fromReference, notNull, fetched, state, key, narrower, options, one]);
}

void writes(QueryClient client, Object anything) {
  final device = queries.devices.detail('d1');
  final list = queries.devices.list;
  final lookup = queries.devices.lookup('d1');

  // A null where the declared type is not nullable.
  // EXPECT error argument_type_not_assignable
  device.write(client, null);

  // A supertype is not a value of the type.
  // EXPECT error argument_type_not_assignable
  device.write(client, anything);

  // A nullable value where the declared type is not nullable.
  // EXPECT error argument_type_not_assignable
  device.write(client, lookup.read(client));

  // A wrong element in a collection literal.
  // EXPECT error list_element_type_not_assignable
  list.write(client, ['d1']);

  // A list of the wrong element type.
  // EXPECT error argument_type_not_assignable
  list.write(client, <String>['d1']);

  // One device where a list is declared.
  // EXPECT error argument_type_not_assignable
  list.write(client, const Device('d1'));
}

String? _rename(String? previous) => previous;

void updates(QueryClient client) {
  final device = queries.devices.detail('d1');
  final list = queries.devices.list;

  // An updater whose parameter is another type.
  // EXPECT error argument_type_not_assignable
  device.update(client, (String? previous) => null);

  // An extracted updater of another type.
  // EXPECT error argument_type_not_assignable
  device.update(client, _rename);

  // The inferred parameter is the declared type: it has no such member.
  // EXPECT error undefined_getter
  device.update(client, (previous) => previous?.length);

  // The parameter is nullable: nothing may be cached.
  // EXPECT error unchecked_use_of_nullable_value
  device.update(client, (previous) => previous.copyWith(isOn: true));

  // A wrong element in the returned collection.
  // EXPECT error list_element_type_not_assignable
  list.update(client, (previous) => [...?previous, 'd3']);

  // A family's bulk update is held to the same types.
  // EXPECT error return_of_invalid_type_from_closure
  queries.devices.detail.updateAll(client, (previous) => 'renamed');
}

void selectors(QueryClient client) {
  final device = queries.devices.detail('d1');

  // The selector's parameter is the cache type.
  // EXPECT error undefined_getter
  device.options().withSelect((data) => data.celsius);

  // EXPECT error argument_type_not_assignable
  device.options().withSelect<int>((String data) => data.length);

  // What a selection reports is what its selector returns.
  final QuerySelectOptions<Device, int> count =
      // EXPECT error return_of_invalid_type_from_closure
      device.options().withSelect((data) => data.name);

  _use([count]);
}

void _use(List<Object?> values) {}
