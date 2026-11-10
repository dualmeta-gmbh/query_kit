/// D10, the other half of `boundary/untyped_definition.dart`: a definition
/// without type arguments has an `Object?` input, so the ordinary one, whose
/// fetcher hands its input to a typed repository, does not compile. The
/// error is in the declaration, at the use of the input.
///
/// An infinite definition without type arguments fails the same way at the
/// use of its page, and with a `configure` it fails later still: at every
/// use of the definition. What cures each is
/// `positive/written_type_arguments.dart`.
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

// An infinite definition whose `getNextPageParam` reads its page. The
// declaration's own type is inferred exactly, and the closure's `page`
// parameter is not: it was typed before the page function's return was
// known. The error is at the use of the page.
final readsPage = InfiniteQueryDefinition(
  namespace: _devices,
  name: 'readsPage',
  pageFn: (context) => _repository.page(context.pageParam),
  initialPageParam: 0,
  getNextPageParam: (page, pages, pageParam, pageParams) =>
      // EXPECT error unchecked_use_of_nullable_value
      page.isEmpty ? null : pageParam + 1,
);

// The pages before it are no better off.
final readsPages = InfiniteQueryDefinition(
  namespace: _devices,
  name: 'readsPages',
  pageFn: (context) => _repository.page(context.pageParam),
  initialPageParam: 0,
  getNextPageParam: (page, pages, pageParam, pageParams) =>
      // EXPECT error unchecked_use_of_nullable_value
      pages.last.isEmpty ? null : pageParam + 1,
);

// The same in the factory form, and in an infinite family.
final readsPageFactory = _devices.infiniteQuery(
  'readsPageFactory',
  pageFn: (context) => _repository.page(context.pageParam),
  initialPageParam: 0,
  getNextPageParam: (page, pages, pageParam, pageParams) =>
      // EXPECT error unchecked_use_of_nullable_value
      page.isEmpty ? null : pageParam + 1,
);

final readsPageFamily = InfiniteQueryFamily(
  namespace: _devices,
  name: 'readsPageFamily',
  pageFn: (id, context) => _repository.page(context.pageParam),
  initialPageParam: (id) => 0,
  getNextPageParam: (id, page, pages, pageParam, pageParams) =>
      // EXPECT error unchecked_use_of_nullable_value
      page.isEmpty ? null : pageParam + 1,
);

// It is how Dart infers a call's closures, not something of this surface:
// the existing options do the same.
final readsPageOptions = InfiniteQueryObserverOptions(
  queryKey: QueryKey(const ['devices', 'readsPageOptions']),
  pageFn: (context) => _repository.page(context.pageParam),
  initialPageParam: 0,
  getNextPageParam: (page, pages, pageParam, pageParams) =>
      // EXPECT error unchecked_use_of_nullable_value
      page.isEmpty ? null : pageParam + 1,
);

// With a `configure` the page type is lost without a word
// (`boundary/untyped_definition.dart`). Typing the page where it is read
// does not bring it back; it turns the silence into two errors, one at the
// declaration and one at the closure.
// EXPECT error could_not_infer
final typedPageConfigured = InfiniteQueryDefinition(
  namespace: _devices,
  name: 'typedPageConfigured',
  pageFn: (context) => _repository.page(context.pageParam),
  initialPageParam: 0,
  // EXPECT error argument_type_not_assignable
  getNextPageParam: (List<Device> page, pages, pageParam, pageParams) =>
      page.isEmpty ? null : pageParam + 1,
  configure: (base) => base.copyWith(maxPages: 3),
);

// And the declaration that did compile is not the definition it was meant
// to be, nor are its pages the pages.
final _configured = InfiniteQueryDefinition(
  namespace: _devices,
  name: 'configured',
  pageFn: (context) => _repository.page(context.pageParam),
  initialPageParam: 0,
  getNextPageParam: (page, pages, pageParam, pageParams) => pageParam + 1,
  configure: (base) => base.copyWith(maxPages: 3),
);

// EXPECT error invalid_assignment
final InfiniteQueryDefinition<List<Device>, int> assignedFeed = _configured;

int? firstPageLength(QueryClient client) =>
    // EXPECT error unchecked_use_of_nullable_value
    _configured.read(client)?.pages.first.length;

void writesAPage(QueryClient client) {
  // EXPECT error invalid_assignment
  final List<List<Device>>? pages = _configured.read(client)?.pages;
  _use([pages]);
}

void _use(List<Object?> values) {}
