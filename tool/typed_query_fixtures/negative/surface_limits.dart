/// Open-2: what the surface deliberately does not offer is absent, not
/// merely discouraged. A namespace has no data type (D1, D7), a typed key
/// has no public constructor and is not a raw key (D1), the reference types
/// cannot be forged outside the library, and paged data is held to both of
/// its types (D8).
library;

import '../support/models.dart';
import '../surface.dart';

void namespaces(QueryClient client) {
  final namespace = DeviceQueries.namespace;

  // A namespace selects by prefix and claims no data type: no read, no
  // state, no write, no update, no options.
  // EXPECT error undefined_method
  namespace.read(client);
  // EXPECT error undefined_method
  namespace.state(client);
  // EXPECT error undefined_method
  namespace.write(client, const Device('d1'));
  // EXPECT error undefined_method
  namespace.update(client, (Device? previous) => previous);
  // EXPECT error undefined_method
  namespace.options();
  // EXPECT error undefined_getter
  namespace.key;
}

void families(QueryClient client) {
  final family = queries.devices.detail;

  // A family is not one entry: single reads and writes need an input.
  // EXPECT error undefined_method
  family.read(client);
  // EXPECT error undefined_method
  family.write(client, const Device('d1'));
  // EXPECT error undefined_method
  family.options();
  // EXPECT error undefined_method
  family.fetch(client);
  // EXPECT error undefined_getter
  family.key;

  // A family is not a reference, and a reference is not a family.
  // EXPECT error invalid_assignment
  final QueryRef<Device> reference = family;
  // EXPECT error invocation_of_non_function_expression
  family('d1')('d2');

  _use([reference]);
}

void entries(QueryClient client) {
  // What plain and infinite references share has no `options()` and no
  // `fetch`: the two options types have no common subtype (D1).
  final QueryEntryRef<Device> entry = queries.devices.detail('d1');
  // EXPECT error undefined_method
  entry.options();
  // EXPECT error undefined_method
  entry.fetch(client);

  // The two kinds do not convert into each other.
  // EXPECT error invalid_assignment
  final QueryRef<InfiniteData<List<Device>, int>> plain = queries.devices.feed;
  // EXPECT error invalid_assignment
  final InfiniteQueryRef<List<Device>, int> paged = queries.devices.list;

  // `QueryRef` and the existing `QueryObserverRef` are unrelated types.
  // EXPECT error invalid_assignment
  final QueryObserverRef observer = queries.devices.detail('d1');

  _use([plain, paged, observer]);

  // A list of a family's reference and a definition is a list of targets:
  // it can be invalidated, and it cannot be read or written.
  final mixed = [queries.devices.detail('d1'), queries.devices.list];
  // EXPECT error undefined_method
  mixed.first.write(client, const Device('d1'));
  // EXPECT error undefined_method
  mixed.first.read(client);

  // Two references of one class are a list of references, whose write
  // compiles (`boundary/mixed_list.dart`). Declared as a list of targets
  // it is the same list without one.
  final lifecycle = <QueryTarget>[
    queries.devices.detail('d1'),
    queries.devices.reading('d1'),
  ];
  // EXPECT error undefined_method
  lifecycle.first.write(client, const Temperature(21));
  // EXPECT error undefined_method
  lifecycle.first.update(client, (previous) => const Temperature(21));
  // EXPECT error undefined_method
  lifecycle.first.read(client);
  // EXPECT error undefined_method
  lifecycle.first.state(client);
  // EXPECT error undefined_getter
  lifecycle.first.key;
}

void typedKeys(QueryClient client) {
  final key = queries.devices.detail('d1').key;

  // No public constructor and no cast from a raw key.
  // EXPECT error new_with_undefined_constructor_default
  final forged = TypedQueryKey<String>(key.rawKey);
  // EXPECT error undefined_method
  final cast = TypedQueryKey.fromRaw<String>(key.rawKey);
  // EXPECT error invalid_assignment
  final TypedQueryKey<String> assigned = key.rawKey;

  // A typed key is not a raw key: leaving the typed surface is spelled
  // `rawKey`, and reads as that.
  // EXPECT error argument_type_not_assignable
  client.getQueryData<String>(key);
  // EXPECT error argument_type_not_assignable
  client.setQueryData<String>(key, 'a name');
  // EXPECT error argument_type_not_assignable
  client.invalidateQueries(filters: QueryFilters(queryKey: key));

  // A typed key reads and tells the state; it does not write.
  // EXPECT error undefined_method
  key.write(client, const Device('d1'));

  // A reference has no public constructor either.
  // EXPECT error new_with_undefined_constructor_default
  final reference = QueryRef<Device>();

  _use([forged, cast, assigned, reference]);
}

// The reference types cannot be implemented or extended elsewhere, so every
// reference comes from a definition.
// EXPECT error invalid_use_of_type_outside_library
class ForgedEntry implements QueryEntryRef<Device> {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// EXPECT error invalid_use_of_type_outside_library
class ForgedReference implements QueryRef<Device> {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// EXPECT error invalid_use_of_type_outside_library
class ForgedKey implements TypedQueryKey<Device> {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// EXPECT error invalid_use_of_type_outside_library
class ForgedTarget implements QueryTarget {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void infiniteData(QueryClient client) {
  final feed = queries.devices.feed;

  // Wrong page data.
  final strings = InfiniteData<List<String>, int>(pages: [], pageParams: []);
  // EXPECT error argument_type_not_assignable
  feed.write(client, strings);
  // Wrong page params.
  final keyed = InfiniteData<List<Device>, String>(pages: [], pageParams: []);
  // EXPECT error argument_type_not_assignable
  feed.write(client, keyed);
  // A wrong element in a literal page.
  feed.write(
    client,
    InfiniteData(
      pages: [
        // EXPECT error list_element_type_not_assignable
        ['d1'],
      ],
      pageParams: [0],
    ),
  );
  // A wrong page param in a literal.
  feed.write(
    client,
    // EXPECT error list_element_type_not_assignable
    InfiniteData(pages: [], pageParams: ['first']),
  );
  // A list of pages is not the paged data.
  // EXPECT error argument_type_not_assignable
  feed.write(client, [const Device('d1')]);
  // An updater returning the pages instead of the paged data.
  // EXPECT error return_of_invalid_type_from_closure
  feed.update(client, (previous) => previous?.pages);

  // Reads are the paged data of both declared types.
  // EXPECT error invalid_assignment
  final InfiniteData<List<Device>, String>? wrongParam = feed.read(client);
  // EXPECT error invalid_assignment
  final List<Device>? flat = feed.read(client);

  // A plain definition's options are not infinite options, and the reverse.
  InfiniteQueryObserver<List<Device>, int, InfiniteData<List<Device>, int>>(
    client,
    // EXPECT error argument_type_not_assignable
    queries.devices.list.options(),
  );
  final options = feed.options();
  // EXPECT error invalid_assignment
  final QueryObserverOptions<InfiniteData<List<Device>, int>> plain = options;

  _use([wrongParam, flat, plain]);
}

void _use(List<Object?> values) {}
