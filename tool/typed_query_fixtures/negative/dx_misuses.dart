/// Open-2: the six call sites the plan's developer-experience section says
/// are rejected statically, as it writes them (the last one `final`, which
/// the repository's own lints ask for and which changes nothing about it).
library;

import '../support/models.dart';
import '../surface.dart';

void misuses(QueryClient client) {
  final device = queries.devices.detail('d1');

  // A misspelled namespace.
  // EXPECT error undefined_getter
  queries.devces.detail('d1');

  // A misspelled operation.
  // EXPECT error undefined_method
  queries.devices.detial('d1');

  // A wrong input type.
  // EXPECT error argument_type_not_assignable
  queries.devices.detail(123);

  // A wrongly typed write.
  // EXPECT error argument_type_not_assignable
  device.write(client, 'not a device');

  // An updater returning the wrong type.
  // EXPECT error return_of_invalid_type_from_closure
  device.update(client, (_) => 42);

  // A read assigned to the wrong type, through the key.
  // EXPECT error invalid_assignment
  final String? wrongRead = device.key.read(client);

  _use(wrongRead);
}

void _use(Object? value) {}
