/// Open-2's control, D2's option (a): a client-style setter whose data type
/// is a type parameter of the operation **compiles** with a wrong value.
/// Dart solves `T` from both arguments and widens it to their common
/// supertype, so the typed key constrains nothing.
///
/// Everything in this file analyzes cleanly. The same calls on the
/// reference are errors: `negative/dx_misuses.dart`. Where the generic
/// shape does hold (an updater, an explicit type argument) is
/// `negative/generic_setter.dart`.
library;

import '../support/client_style_setter.dart';
import '../support/models.dart';
import '../support/static_type.dart';
import '../surface.dart';

void genericSetter(QueryClient client) {
  final device = queries.devices.detail('d1');

  // A string under a device's key: `T` is `Object`, and the result says so.
  setData(client, device.key, 'not a device')
      .expectStaticType<Exactly<Object>>();

  // The same as a method of the client.
  client
      .setTyped(device.key, 'not a device')
      .expectStaticType<Exactly<Object>>();

  // A nullable key and a wrong value.
  final lookup = queries.devices.lookup('d1');
  setData(client, lookup.key, 42).expectStaticType<Exactly<Object?>>();

  // Paged data under a wrong page type.
  setData(
    client,
    queries.devices.feed.key,
    InfiniteData<String, String>(pages: const [], pageParams: const []),
  ).expectStaticType<Exactly<InfiniteData<Object, Object>>>();

  // The honest call still infers the declared type, which is why the shape
  // looks safe in a demo.
  setData(client, device.key, const Device('d1'))
      .expectStaticType<Exactly<Device>>();
}
