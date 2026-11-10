/// The other half of `boundary/generic_setter.dart`: where the client-style
/// generic shape *does* refuse a wrong value. An explicit type argument
/// pins `T`, and so does a closure, because Dart solves `T` from the
/// non-closure arguments (the typed key) before it looks at the closure.
///
/// So D2's widening is a property of the value setter alone. It is still
/// the reason for the receiver-anchored shape: `write` is the operation an
/// optimistic update and a server-response write use.
library;

import '../support/client_style_setter.dart';
import '../support/models.dart';
import '../surface.dart';

void pinned(QueryClient client) {
  final device = queries.devices.detail('d1');

  // The type argument written out.
  // EXPECT error argument_type_not_assignable
  setData<Device>(client, device.key, 'not a device');

  // An updater: `T` is `Device` before the closure is inferred.
  // EXPECT error return_of_invalid_type_from_closure
  updateData(client, device.key, (previous) => 42);

  // A key of another type than the type argument.
  // EXPECT error argument_type_not_assignable
  setData<String>(client, device.key, 'not a device');
}
