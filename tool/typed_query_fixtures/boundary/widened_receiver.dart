/// D2's boundaries: what leaves the typed surface on purpose **compiles**.
/// Dart's generics are covariant, so a reference can be widened, and then
/// any value is accepted statically. What happens when these lines run is
/// `runtime/observations.dart` (Open-7): Dart's own `TypeError` where Dart
/// checks covariance, the surface's explicit check where it does not.
///
/// Under the repository's strict settings three of them are reported; the
/// markers say which, and that they are optional diagnostics, not language
/// errors.
library;

import '../support/models.dart';
import '../surface.dart';

void upcasts(QueryClient client) {
  final device = queries.devices.detail('d1');

  // A reference widened by an ordinary assignment.
  final QueryRef<Object?> widened = device;
  widened.write(client, 'not a device');
  widened.update(client, (previous) => 42);

  // The same through the shared supertype.
  final QueryEntryRef<Object?> entry = device;
  entry.write(client, 42);

  // A widened family takes any input and any updater.
  final QueryFamily<Object?, Object?> family = queries.devices.detail;
  family(42);
  family.updateAll(client, (previous) => 'renamed');

  // A widened infinite reference takes any paged data.
  final InfiniteQueryRef<Object?, Object?> feed = queries.devices.feed;
  feed.write(
    client,
    InfiniteData<String, String>(pages: const [], pageParams: const []),
  );

  // A widened typed key reads as the wider type.
  final TypedQueryKey<Object?> key = device.key;
  key.read(client);
}

void rawGenerics(QueryClient client) {
  // A raw type is the same widening, unannounced.
  // EXPECT strict strict_raw_type
  final QueryRef raw = queries.devices.detail('d1');
  raw.write(client, 'not a device');
}

void dynamicValues(QueryClient client, dynamic value) {
  final device = queries.devices.detail('d1');

  // A `dynamic` value is assignable to anything.
  // EXPECT strict argument_type_not_assignable
  device.write(client, value);

  // A `dynamic` receiver checks nothing.
  final dynamic untyped = device;
  // EXPECT strict avoid_dynamic_calls
  untyped.write(client, 'not a device');
}

void dishonestCasts(QueryClient client, Object value) {
  final device = queries.devices.detail('d1');

  // A cast is a promise the analyzer takes at its word.
  device.write(client, value as Device);
  device.update(client, (previous) => value as Device?);
}

void rawKeys(QueryClient client) {
  final device = queries.devices.detail('d1');

  // `rawKey` is the documented exit: the raw client takes any type argument.
  client.setQueryData<String>(device.key.rawKey, 'not a device');
  client.getQueryData<String>(device.key.rawKey);

  // And a per-use `copyWith` can move the key.
  device.options().copyWith(queryKey: QueryKey(const ['elsewhere']));
}
