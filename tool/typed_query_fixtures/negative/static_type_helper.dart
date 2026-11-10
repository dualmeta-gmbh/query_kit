/// The control of the controls: `expectStaticType` refuses a wider type, a
/// narrower type and a differently nullable type. Without this file a
/// positive fixture would prove no more than "it compiles".
library;

import '../support/models.dart';
import '../support/static_type.dart';
import '../surface.dart';

void helper(QueryClient client) {
  final device = queries.devices.detail('d1');

  // The control: the exact type passes.
  device.expectStaticType<Exactly<QueryRef<Device>>>();

  // A wider claim than the static type.
  // EXPECT error type_argument_not_matching_bounds
  device.expectStaticType<Exactly<QueryRef<Object?>>>();
  // EXPECT error type_argument_not_matching_bounds
  device.expectStaticType<Exactly<QueryEntryRef<Device>>>();
  // EXPECT error type_argument_not_matching_bounds
  device.expectStaticType<Exactly<Object>>();

  // A narrower claim than the static type.
  // EXPECT error type_argument_not_matching_bounds
  device.expectStaticType<Exactly<QueryRef<Thermostat>>>();
  // EXPECT error type_argument_not_matching_bounds
  device.expectStaticType<Exactly<QueryDefinition<Device>>>();

  // Nullability counts, both ways.
  // EXPECT error type_argument_not_matching_bounds
  device.read(client).expectStaticType<Exactly<Device>>();
  // EXPECT error type_argument_not_matching_bounds
  device.expectStaticType<Exactly<QueryRef<Device>?>>();
  // EXPECT error type_argument_not_matching_bounds
  device.expectStaticType<Exactly<QueryRef<Device?>>>();

  // A wider static type is seen as wider.
  final QueryRef<Object?> widened = device;
  // EXPECT error type_argument_not_matching_bounds
  widened.expectStaticType<Exactly<QueryRef<Device>>>();
}
