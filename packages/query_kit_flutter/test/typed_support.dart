/// What the typed-definition suites share: a model, a fake backend that
/// writes into a trace, the definitions under test with their raw twins,
/// one reader per call style for plain and infinite queries, and an exact
/// static-type pin.
///
/// Every reader reports each result it builds from to a callback and
/// renders nothing of its own, so a case reads one list — what was fetched
/// and what was shown, in order — and compares the list a reference
/// produced with the one the same raw options produced.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

// ------------------------------------------------------------ static types

/// A function type with `T` in both positions: a subtype of `Exactly<S>`
/// only when `T` and `S` are subtypes of each other.
typedef Exactly<T> = T Function(T);

/// Pins the static type of an expression exactly: compiles only when the
/// receiver's static type is the `X` of `R = Exactly<X>`, so a wider and a
/// narrower inferred type both fail to compile
/// (`type_argument_not_matching_bounds`). The receiver has no context type,
/// so nothing widens `T` before the bound is checked.
extension StaticType<T> on T {
  T expectStaticType<R extends Exactly<T>>() => this;
}

// ------------------------------------------------------------------ model

final class Device {
  const Device(this.id, this.version);

  final String id;
  final String version;

  Device bump(String to) => Device(id, to);

  @override
  bool operator ==(Object other) =>
      other is Device && other.id == id && other.version == version;

  @override
  int get hashCode => Object.hash(id, version);

  @override
  String toString() => '$id@$version';
}

/// A backend that answers at once and writes each request into [trace]:
/// `fetch <tag><n>`, where `n` counts this backend's requests per id. A
/// second backend with another [tag] is "a definition with a different
/// fetcher".
class Api {
  Api(this.trace, {this.tag = 'A'});

  final List<String> trace;
  final String tag;
  final Map<String, int> _calls = <String, int>{};

  int callsFor(String id) => _calls[id] ?? 0;

  Future<Device> device(String id) async {
    final n = _calls[id] = callsFor(id) + 1;
    trace.add('fetch $tag$n');
    return Device(id, '$tag$n');
  }

  Future<List<int>> page(String id, int param) async {
    final n = _calls['$id/$param'] = callsFor('$id/$param') + 1;
    trace.add('page $tag$param#$n');
    return <int>[param * 10, param * 10 + 1];
  }
}

// ------------------------------------------------------------ definitions

typedef Policy = QueryObserverOptions<Device> Function(
  QueryObserverOptions<Device> base,
);

typedef InfinitePolicy = InfiniteQueryObserverOptions<List<int>, int> Function(
  InfiniteQueryObserverOptions<List<int>, int> base,
);

QueryObserverOptions<Device> noPolicy(QueryObserverOptions<Device> base) =>
    base;

InfiniteQueryObserverOptions<List<int>, int> noInfinitePolicy(
  InfiniteQueryObserverOptions<List<int>, int> base,
) =>
    base;

/// A new namespace each call: what a rebuild that recreates the whole
/// declaration hands in.
QueryNamespace devicesNamespace() => QueryNamespace(const ['devices']);

QueryFamily<String, Device> detailFamily(Api api, {Policy policy = noPolicy}) =>
    QueryFamily<String, Device>(
      namespace: devicesNamespace(),
      name: 'detail',
      queryFn: (id, _) => api.device(id),
      configure: (base, _) => policy(base),
    );

QueryKey detailKey(String id) => QueryKey(['devices', 'detail', id]);

/// The raw twin of `detailFamily(api, policy: policy)(id).options()`, built
/// inline as an options function builds it.
QueryObserverOptions<Device> rawDetail(
  Api api,
  String id, {
  Policy policy = noPolicy,
}) =>
    policy(QueryObserverOptions<Device>(
      queryKey: detailKey(id),
      queryFn: (_) => api.device(id),
    ));

/// A zero-input definition, `['devices', 'current']`.
QueryDefinition<Device> currentDefinition(
  Api api, {
  Policy policy = noPolicy,
}) =>
    QueryDefinition<Device>(
      namespace: devicesNamespace(),
      name: 'current',
      queryFn: (_) => api.device('a'),
      configure: policy,
    );

QueryKey get currentKey => QueryKey(const ['devices', 'current']);

QueryObserverOptions<Device> rawCurrent(Api api, {Policy policy = noPolicy}) =>
    policy(QueryObserverOptions<Device>(
      queryKey: currentKey,
      queryFn: (_) => api.device('a'),
    ));

/// An infinite family over a feed id: pages 0, 1, 2.
InfiniteQueryFamily<String, List<int>, int> feedFamily(
  Api api, {
  InfinitePolicy policy = noInfinitePolicy,
}) =>
    InfiniteQueryFamily<String, List<int>, int>(
      namespace: devicesNamespace(),
      name: 'feed',
      pageFn: (id, context) => api.page(id, context.pageParam),
      initialPageParam: (_) => 0,
      getNextPageParam: (_, __, ___, param, ____) =>
          param < 2 ? param + 1 : null,
      configure: (base, _) => policy(base),
    );

QueryKey feedKey(String id) => QueryKey(['devices', 'feed', id]);

InfiniteQueryObserverOptions<List<int>, int> rawFeed(
  Api api,
  String id, {
  InfinitePolicy policy = noInfinitePolicy,
}) =>
    policy(InfiniteQueryObserverOptions<List<int>, int>(
      queryKey: feedKey(id),
      pageFn: (context) => api.page(id, context.pageParam),
      initialPageParam: 0,
      getNextPageParam: (_, __, param, ___) => param < 2 ? param + 1 : null,
    ));

/// A zero-input infinite definition, `['devices', 'log']`.
InfiniteQueryDefinition<List<int>, int> logDefinition(
  Api api, {
  InfinitePolicy policy = noInfinitePolicy,
}) =>
    InfiniteQueryDefinition<List<int>, int>(
      namespace: devicesNamespace(),
      name: 'log',
      pageFn: (context) => api.page('log', context.pageParam),
      initialPageParam: 0,
      getNextPageParam: (_, __, param, ___) => param < 2 ? param + 1 : null,
      configure: policy,
    );

QueryKey get logKey => QueryKey(const ['devices', 'log']);

InfiniteQueryObserverOptions<List<int>, int> rawLog(
  Api api, {
  InfinitePolicy policy = noInfinitePolicy,
}) =>
    policy(InfiniteQueryObserverOptions<List<int>, int>(
      queryKey: logKey,
      pageFn: (context) => api.page('log', context.pageParam),
      initialPageParam: 0,
      getNextPageParam: (_, __, param, ___) => param < 2 ? param + 1 : null,
    ));

// ---------------------------------------------------------------- tracing

/// One line per result a reader built from.
String describe<T>(QueryResult<T> result) =>
    _line(result, '${result.dataOrNull ?? '-'}');

/// One line per infinite result a reader built from: the flattened pages.
String describeFeed(QueryResult<InfiniteData<List<int>, int>> result) => _line(
      result,
      result.dataOrNull?.pages.expand((page) => page).join(',') ?? '-',
    );

String _line(QueryResult<Object?> result, String data) =>
    'show $data ${result.status.name}/${result.fetchStatus.name}'
    '${result.isPlaceholderData ? ' placeholder' : ''}'
    '${result.isStale ? ' stale' : ''}';

// ---------------------------------------------------------------- readers

/// The four call styles. None is a default; every case runs all four.
enum Style { controller, builder, mixin, context }

/// [options] read in [style]; [seen] hears every result a build used.
/// [id] is handed to the two styles that take one.
Widget readPlain<T>(
  Style style,
  QueryObserverOptions<T> options, {
  required void Function(QueryResult<T> result) seen,
  Object? id,
}) =>
    switch (style) {
      Style.controller => ControllerReader<T>(options, seen),
      Style.builder => QueryBuilder<T>(
          options: options,
          builder: (_, result) {
            seen(result);
            return const SizedBox();
          },
        ),
      Style.mixin => MixinReader<T>(options, seen, id: id),
      Style.context => ContextReader<T>(options, seen, id: id),
    };

/// The controller style as an app writes it: the controller is created for
/// the provider's client, re-created when that client changes, handed the
/// parent's options on every update, and disposed with the state.
class ControllerReader<T> extends StatefulWidget {
  const ControllerReader(this.options, this.seen, {super.key});

  final QueryObserverOptions<T> options;
  final void Function(QueryResult<T> result) seen;

  @override
  State<ControllerReader<T>> createState() => _ControllerReaderState<T>();
}

class _ControllerReaderState<T> extends State<ControllerReader<T>> {
  QueryController<T, T>? _controller;
  QueryClient? _client;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final client = QueryClientProvider.of(context);
    if (!identical(client, _client)) {
      final retired = _controller;
      // Disposed after the frame: the ListenableBuilder below still holds
      // it until this build replaces it.
      if (retired != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => retired.dispose());
      }
      _client = client;
      _controller = QueryController<T, T>(client, widget.options);
    }
  }

  @override
  void didUpdateWidget(ControllerReader<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller!.setOptions(widget.options);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller!;
    return ListenableBuilder(
      key: ObjectKey(controller),
      listenable: controller,
      builder: (_, __) {
        widget.seen(controller.value);
        return const SizedBox();
      },
    );
  }
}

class MixinReader<T> extends StatefulWidget {
  const MixinReader(this.options, this.seen, {super.key, this.id});

  final QueryObserverOptions<T> options;
  final void Function(QueryResult<T> result) seen;
  final Object? id;

  @override
  State<MixinReader<T>> createState() => _MixinReaderState<T>();
}

class _MixinReaderState<T> extends State<MixinReader<T>> with QueryMixin {
  @override
  Widget build(BuildContext context) {
    widget.seen(watchQuery(widget.options, id: widget.id));
    return const SizedBox();
  }
}

class ContextReader<T> extends StatelessWidget {
  const ContextReader(this.options, this.seen, {super.key, this.id});

  final QueryObserverOptions<T> options;
  final void Function(QueryResult<T> result) seen;
  final Object? id;

  @override
  Widget build(BuildContext context) {
    seen(context.query(options, id: id));
    return const SizedBox();
  }
}

typedef Feed
    = InfiniteQueryController<List<int>, int, InfiniteData<List<int>, int>>;

/// [options] read in [style] as an infinite query; [seen] hears the
/// controller every build used.
Widget readInfinite(
  Style style,
  InfiniteQueryObserverOptions<List<int>, int> options, {
  required void Function(Feed feed) seen,
  Object? id,
}) =>
    switch (style) {
      Style.controller => InfiniteControllerReader(options, seen),
      Style.builder =>
        InfiniteQueryBuilder<List<int>, int, InfiniteData<List<int>, int>>(
          options: options,
          builder: (_, feed) {
            seen(feed);
            return const SizedBox();
          },
        ),
      Style.mixin => InfiniteMixinReader(options, seen, id: id),
      Style.context => InfiniteContextReader(options, seen, id: id),
    };

class InfiniteControllerReader extends StatefulWidget {
  const InfiniteControllerReader(this.options, this.seen, {super.key});

  final InfiniteQueryObserverOptions<List<int>, int> options;
  final void Function(Feed feed) seen;

  @override
  State<InfiniteControllerReader> createState() =>
      _InfiniteControllerReaderState();
}

class _InfiniteControllerReaderState extends State<InfiniteControllerReader> {
  Feed? _controller;
  QueryClient? _client;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final client = QueryClientProvider.of(context);
    if (!identical(client, _client)) {
      final retired = _controller;
      if (retired != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => retired.dispose());
      }
      _client = client;
      _controller = InfiniteQueryController(client, widget.options);
    }
  }

  @override
  void didUpdateWidget(InfiniteControllerReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller!.setInfiniteOptions(widget.options);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller!;
    return ListenableBuilder(
      key: ObjectKey(controller),
      listenable: controller,
      builder: (_, __) {
        widget.seen(controller);
        return const SizedBox();
      },
    );
  }
}

class InfiniteMixinReader extends StatefulWidget {
  const InfiniteMixinReader(this.options, this.seen, {super.key, this.id});

  final InfiniteQueryObserverOptions<List<int>, int> options;
  final void Function(Feed feed) seen;
  final Object? id;

  @override
  State<InfiniteMixinReader> createState() => _InfiniteMixinReaderState();
}

class _InfiniteMixinReaderState extends State<InfiniteMixinReader>
    with QueryMixin {
  @override
  Widget build(BuildContext context) {
    widget.seen(watchInfiniteQuery(widget.options, id: widget.id));
    return const SizedBox();
  }
}

class InfiniteContextReader extends StatelessWidget {
  const InfiniteContextReader(this.options, this.seen, {super.key, this.id});

  final InfiniteQueryObserverOptions<List<int>, int> options;
  final void Function(Feed feed) seen;
  final Object? id;

  @override
  Widget build(BuildContext context) {
    seen(context.infiniteQuery(options, id: id));
    return const SizedBox();
  }
}

// ------------------------------------------------------------------- lab

/// A parent that rebuilds its child on [rebuild], handing it what [child]
/// builds for that generation: the shape of a screen whose state changes
/// above a reader.
class Lab {
  Lab(this.tester);

  final WidgetTester tester;
  final List<String> trace = <String>[];
  final ValueNotifier<int> generation = ValueNotifier<int>(0);

  Widget host(Widget Function(int generation) child) =>
      ValueListenableBuilder<int>(
        valueListenable: generation,
        builder: (_, value, __) => child(value),
      );

  /// One parent rebuild, and the frame it schedules.
  Future<void> rebuild() async {
    generation.value++;
    await tester.pump();
  }

  void dispose() => generation.dispose();
}

/// Counts the [QueryObserverOptionsUpdated] events [client]'s cache emits:
/// how many times an observer was handed options unequal to its last ones.
({int Function() count, void Function() stop}) countOptionsUpdates(
  QueryClient client,
) {
  var n = 0;
  final stop = client.queryCache.subscribe((event) {
    if (event is QueryObserverOptionsUpdated) n++;
  });
  return (count: () => n, stop: stop);
}
