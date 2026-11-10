/// Open-1, infinite queries (D8): the page type, the page-param type and the
/// `InfiniteData` over both are inferred at every call site.
library;

import '../support/models.dart';
import '../support/static_type.dart';
import '../surface.dart';

typedef _Feed = InfiniteData<List<Device>, int>;
typedef _History = InfiniteData<List<DeviceEvent>, int>;

Future<void> infinite(QueryClient client) async {
  // A zero-input infinite definition is itself the reference (D1).
  final feed = queries.devices.feed;
  feed.expectStaticType<Exactly<InfiniteQueryDefinition<List<Device>, int>>>();
  final InfiniteQueryRef<List<Device>, int> asReference = feed;
  final QueryEntryRef<_Feed> asEntry = feed;

  final options = feed.options();
  final InfiniteQueryObserverOptions<List<Device>, int> typedOptions = options;
  options.expectStaticType<
      Exactly<InfiniteQueryObserverOptions<List<Device>, int>>>();

  final cached = feed.read(client);
  final _Feed? typedCached = cached;
  cached.expectStaticType<Exactly<_Feed?>>();
  feed.key.expectStaticType<Exactly<TypedQueryKey<_Feed>>>();
  feed.key.read(client).expectStaticType<Exactly<_Feed?>>();
  feed.state(client).expectStaticType<Exactly<QueryState<_Feed>?>>();

  final fetched = await feed.fetch(client);
  final _Feed typedFetched = fetched;
  fetched.expectStaticType<Exactly<_Feed>>();
  fetched.pages.expectStaticType<Exactly<List<List<Device>>>>();
  fetched.pageParams.expectStaticType<Exactly<List<int>>>();

  // The literal takes its type arguments from the receiver, so narrow
  // literals are written under the declared page types.
  feed
      .write(
        client,
        InfiniteData(
          pages: [
            [const Thermostat('t1')],
          ],
          pageParams: [0],
        ),
      )
      .expectStaticType<Exactly<_Feed>>();
  feed.update(client, (previous) {
    previous.expectStaticType<Exactly<_Feed?>>();
    return previous?.copyWith(pages: [...previous.pages.skip(1)]);
  }).expectStaticType<Exactly<_Feed?>>();

  // The existing infinite consumers infer all three types from the options.
  InfiniteQueryObserver(client, feed.options()).expectStaticType<
      Exactly<InfiniteQueryObserver<List<Device>, int, _Feed>>>();
  client
      .infiniteQuery(feed.options())
      .expectStaticType<Exactly<Future<_Feed>>>()
      .ignore();

  // Selection changes what the observer reports, not the entry.
  final ids = feed.options().withSelect((data) {
    data.expectStaticType<Exactly<_Feed>>();
    return [
      for (final page in data.pages)
        for (final device in page) device.id,
    ];
  });
  ids.expectStaticType<
      Exactly<InfiniteQuerySelectOptions<List<Device>, int, List<String>>>>();

  // A family binds an input and returns an infinite reference.
  final history = queries.devices.history('d1');
  final InfiniteQueryRef<List<DeviceEvent>, int> typedHistory = history;
  history.expectStaticType<Exactly<InfiniteQueryRef<List<DeviceEvent>, int>>>();
  history.read(client).expectStaticType<Exactly<_History?>>();
  history.options().expectStaticType<
      Exactly<InfiniteQueryObserverOptions<List<DeviceEvent>, int>>>();
  (await history.fetch(client)).expectStaticType<Exactly<_History>>();
  queries.devices.history.expectStaticType<
      Exactly<InfiniteQueryFamily<String, List<DeviceEvent>, int>>>();
  queries.devices.history
      .readAll(client)
      .expectStaticType<Exactly<List<(TypedQueryKey<_History>, _History?)>>>();
  queries.devices.history.updateAll(client, (previous) {
    previous.expectStaticType<Exactly<_History?>>();
    return previous;
  }).expectStaticType<Exactly<List<(TypedQueryKey<_History>, _History?)>>>();

  // The typed key of paged data writes it: the literal takes its type
  // arguments from the key, as it does from the reference.
  feed.key
      .write(
        client,
        InfiniteData(
          pages: [
            [const Thermostat('t1')],
          ],
          pageParams: [0],
        ),
      )
      .expectStaticType<Exactly<_Feed>>();
  feed.key.update(client, (previous) {
    previous.expectStaticType<Exactly<_Feed?>>();
    return previous?.copyWith(pages: [...previous.pages.skip(1)]);
  }).expectStaticType<Exactly<_Feed?>>();
  for (final (key, data) in queries.devices.history.readAll(client)) {
    key.expectStaticType<Exactly<TypedQueryKey<_History>>>();
    if (data != null) {
      key.write(client, data).expectStaticType<Exactly<_History>>();
    }
  }

  // The callbacks of a declaration see the declared types.
  final namespace = QueryNamespace(['events']);
  InfiniteQueryDefinition<List<DeviceEvent>, String>(
    namespace: namespace,
    name: 'all',
    pageFn: (context) {
      context.expectStaticType<Exactly<InfinitePageContext<String>>>();
      context.pageParam.expectStaticType<Exactly<String>>();
      return const [DeviceEvent(0)];
    },
    initialPageParam: 'start',
    getNextPageParam: (page, pages, pageParam, pageParams) {
      page.expectStaticType<Exactly<List<DeviceEvent>>>();
      pages.expectStaticType<Exactly<List<List<DeviceEvent>>>>();
      pageParam.expectStaticType<Exactly<String>>();
      pageParams.expectStaticType<Exactly<List<String>>>();
      return page.isEmpty ? null : '$pageParam+';
    },
    configure: (base) {
      base.expectStaticType<
          Exactly<InfiniteQueryObserverOptions<List<DeviceEvent>, String>>>();
      return base.copyWith(maxPages: 3);
    },
  );
  InfiniteQueryFamily<Room, List<Device>, int>(
    namespace: namespace,
    name: 'byRoom',
    pageFn: (room, context) {
      room.expectStaticType<Exactly<Room>>();
      context.expectStaticType<Exactly<InfinitePageContext<int>>>();
      return const [Device('d1')];
    },
    initialPageParam: (room) {
      room.expectStaticType<Exactly<Room>>();
      return room.index;
    },
    getNextPageParam: (room, page, pages, pageParam, pageParams) {
      room.expectStaticType<Exactly<Room>>();
      page.expectStaticType<Exactly<List<Device>>>();
      pageParam.expectStaticType<Exactly<int>>();
      return null;
    },
    getPreviousPageParam: (room, page, pages, pageParam, pageParams) =>
        pageParam > 0 ? pageParam - 1 : null,
    configure: (base, room) {
      room.expectStaticType<Exactly<Room>>();
      return base;
    },
  )(Room.hall)
      .expectStaticType<Exactly<InfiniteQueryRef<List<Device>, int>>>();

  // A zero-input infinite definition without type arguments is anchored by
  // its initial page param and by what its page function returns, as long
  // as no closure reads the page and there is no `configure` (D10). It is
  // measured here; the documented form writes both type arguments
  // (`written_type_arguments.dart`).
  InfiniteQueryDefinition(
    namespace: namespace,
    name: 'inferred',
    pageFn: (context) => const DeviceRepository().page(context.pageParam),
    initialPageParam: 0,
    getNextPageParam: (page, pages, pageParam, pageParams) => pageParam + 1,
  ).expectStaticType<Exactly<InfiniteQueryDefinition<List<Device>, int>>>();

  _use([
    asReference,
    asEntry,
    typedOptions,
    typedCached,
    typedFetched,
    typedHistory,
  ]);
}

void _use(List<Object?> values) {}
