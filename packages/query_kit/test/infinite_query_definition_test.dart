/// Typed query definitions over infinite queries: `InfiniteQueryDefinition`,
/// `InfiniteQueryFamily` and the `InfiniteQueryRef` they hand out. Port-only
/// behaviour; PORTING_NOTES' "Typed query definitions" section. The plain
/// side, and everything the two share through `QueryTarget`, is in
/// `query_definition_test.dart`.
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:query_kit/query_kit.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

class Post {
  const Post(this.id);

  final int id;

  @override
  bool operator ==(Object other) =>
      other is Post && other.runtimeType == runtimeType && other.id == id;

  @override
  int get hashCode => Object.hash(runtimeType, id);

  @override
  String toString() => '$runtimeType($id)';
}

class Pinned extends Post {
  const Pinned(super.id);
}

typedef Feed = InfiniteData<List<Post>, int>;

Type typeOf<T>() => T;

bool get assertionsOn {
  var on = false;
  assert(() {
    on = true;
    return true;
  }());
  return on;
}

Matcher dataTypeError(QueryKey key, Type expected, Type actual) =>
    isA<QueryDataTypeError>()
        .having((e) => e.queryKey, 'queryKey', key)
        .having((e) => e.expected, 'expected', expected)
        .having((e) => e.actual, 'actual', actual);

final posts = QueryNamespace(['posts']);

/// Pages of three posts, numbered from the page param.
List<Post> page(int offset) => [for (var i = 0; i < 3; i++) Post(offset + i)];

InfiniteQueryDefinition<List<Post>, int> feed({
  FutureOr<List<Post>> Function(InfinitePageContext<int> context)? pageFn,
  InfiniteQueryObserverOptions<List<Post>, int> Function(
    InfiniteQueryObserverOptions<List<Post>, int> base,
  )? configure,
}) =>
    InfiniteQueryDefinition<List<Post>, int>(
      namespace: posts,
      name: 'feed',
      pageFn: pageFn ?? (context) => page(context.pageParam),
      initialPageParam: 0,
      getNextPageParam: (page, pages, pageParam, pageParams) =>
          pageParam >= 6 ? null : pageParam + 3,
      getPreviousPageParam: (page, pages, pageParam, pageParams) =>
          pageParam <= 0 ? null : pageParam - 3,
      configure: configure,
    );

InfiniteQueryFamily<String, List<Post>, int> byAuthor({
  InfiniteQueryObserverOptions<List<Post>, int> Function(
    InfiniteQueryObserverOptions<List<Post>, int> base,
    String author,
  )? configure,
}) =>
    InfiniteQueryFamily<String, List<Post>, int>(
      namespace: posts,
      name: 'byAuthor',
      pageFn: (author, context) => page(context.pageParam),
      initialPageParam: (author) => 0,
      getNextPageParam: (author, page, pages, pageParam, pageParams) =>
          pageParam + 3,
      configure: configure,
    );

/// A value of narrower type arguments than the feed declares, as an
/// `InfiniteData` built from literals elsewhere is.
InfiniteData<List<Pinned>, int> narrow([int id = 1]) =>
    InfiniteData<List<Pinned>, int>(
      pages: [
        [Pinned(id)],
      ],
      pageParams: [0],
    );

Feed exact([int id = 1]) => Feed(
      pages: [
        [Post(id)],
      ],
      pageParams: [0],
    );

Query<Object?> entry(QueryClient client, QueryKey key) => client.queryCache
    .findAll(filters: QueryFilters(queryKey: key, exact: true))
    .single;

/// Callbacks that are one function object however often `configure` runs,
/// as a top-level or static function is.
Feed keepNext(Feed? previous, Feed next) => next;

Feed keepSeven(Feed? previous, Feed next) => narrow(7);

Feed? seedOfSeven() => narrow(7);

class Sharer {
  Feed keep(Feed? previous, Feed next) => next;
}

void main() {
  group('keys and identity', () {
    test('keys are the namespace, the name and the input', () {
      final family = byAuthor();
      expect(feed().key.rawKey, QueryKey(['posts', 'feed']));
      expect(feed().key.dataType, typeOf<Feed>());
      expect(family.rawKey, QueryKey(['posts', 'byAuthor']));
      expect(
        family('ada').key.rawKey,
        QueryKey(['posts', 'byAuthor', 'ada']),
      );

      final byTags = InfiniteQueryFamily<({String author, List<String> tags}),
          List<Post>, int>(
        namespace: posts,
        name: 'byTags',
        keyOf: (input) => [input.author, input.tags],
        pageFn: (input, context) => page(context.pageParam),
        initialPageParam: (input) => 0,
        getNextPageParam: (input, page, pages, pageParam, pageParams) => null,
      );
      expect(
        byTags((author: 'ada', tags: ['a'])).key.rawKey,
        QueryKey([
          'posts',
          'byTags',
          'ada',
          ['a'],
        ]),
      );
      expect(
        byTags((author: 'ada', tags: ['a'])),
        byTags((author: 'ada', tags: ['a'])),
      );
    });

    test('references from equal inputs are equal, whoever made them', () {
      final first = byAuthor();
      final second = byAuthor();
      expect(identical(first('ada'), first('ada')), isFalse);
      expect(first('ada'), second('ada'));
      expect(first('ada').hashCode, second('ada').hashCode);
      expect(first('ada'), isNot(first('bob')));
      expect(feed(), feed());

      // Other page types under the same key are another reference.
      final other = InfiniteQueryDefinition<List<Post>, String>(
        namespace: posts,
        name: 'feed',
        pageFn: (context) => const [],
        initialPageParam: '',
        getNextPageParam: (page, pages, pageParam, pageParams) => null,
      );
      expect(other, isNot(feed()));
      expect(other.key.rawKey, feed().key.rawKey);

      final InfiniteQueryRef<Object?, Object?> wide = feed();
      expect(wide, feed());
    });

    test('toString names the kind, the types and the key', () {
      final family = byAuthor();
      expect(
        '${feed()}',
        'InfiniteQueryRef<List<Post>, int>(${feed().key.rawKey.debugString})',
      );
      expect(
        '$family',
        'InfiniteQueryFamily<String, List<Post>, int>'
            '(${family.rawKey.debugString})',
      );
      expect(
        '${family('ada')}',
        'InfiniteQueryRef<List<Post>, int>'
            '(${family('ada').key.rawKey.debugString})',
      );
    });

    testFakeAsync('declaring and binding do no work', (time) async {
      final client = testClient();
      final events = <QueryCacheEvent>[];
      client.queryCache.subscribe(events.add);
      var calls = 0;
      final family = InfiniteQueryFamily<String, List<Post>, int>(
        namespace: posts,
        name: 'idle',
        pageFn: (author, context) {
          calls++;
          return const [];
        },
        initialPageParam: (author) {
          calls++;
          return 0;
        },
        getNextPageParam: (author, page, pages, pageParam, pageParams) {
          calls++;
          return null;
        },
        configure: (base, author) {
          calls++;
          return base;
        },
      );
      final ref = family('ada');
      expect(ref.key.dataType, typeOf<Feed>());
      expect(ref.read(client), isNull);
      expect(ref.state(client), isNull);
      expect(family.readAll(client), isEmpty);
      await time.flushMicrotasks();
      expect(calls, 0);
      expect(events, isEmpty);
      expect(time.pendingTimers, 0);
    });
  });

  group('options and fetching', () {
    test('options are made anew, and hold the definition\'s paging functions',
        () {
      final definition = feed();
      final a = definition.options();
      final b = definition.options();
      expect(identical(a, b), isFalse);
      expect(a.queryKey, definition.key.rawKey);
      expect(a.initialPageParam, 0);
      expect(a.getNextPageParam(const [], const [], 0, const [0]), 3);
      expect(a.getNextPageParam(const [], const [], 6, const [6]), isNull);
      expect(a.getPreviousPageParam!(const [], const [], 3, const [3]), 0);

      // The optional one stays out when the definition has none.
      expect(byAuthor()('ada').options().getPreviousPageParam, isNull);
    });

    test(
        'a definition hands out the paging functions it was given, a '
        'family\'s reference binds new ones: what an observer hears', () {
      final client = testClient();
      final events = <String>[];
      client.queryCache.subscribe((event) {
        if (event is QueryObserverOptionsUpdated) {
          events.add(event.query.queryKey.parts.join('/'));
        }
      });

      // No input: the same functions in new options.
      final definition = feed();
      final a = definition.options();
      final b = definition.options();
      expect(identical(a.pageFn, b.pageFn), isTrue);
      expect(identical(a.getNextPageParam, b.getNextPageParam), isTrue);
      expect(identical(a.getPreviousPageParam, b.getPreviousPageParam), isTrue);
      final observer = InfiniteQueryObserver(client, definition.options());
      observer
        ..setInfiniteOptions(definition.options())
        ..setInfiniteOptions(definition.options());
      expect(events, isEmpty);
      // The definition made again per rebuild holds other functions.
      observer.setInfiniteOptions(feed().options());
      expect(events, ['posts/feed']);
      events.clear();

      // A family binds the input into functions of its own, per call.
      final ref = byAuthor()('ada');
      expect(ref.options().pageFn == ref.options().pageFn, isFalse);
      final refObserver = InfiniteQueryObserver(client, ref.options());
      refObserver
        ..setInfiniteOptions(ref.options())
        ..setInfiniteOptions(ref.options());
      expect(events, ['posts/byAuthor/ada', 'posts/byAuthor/ada']);

      observer.destroy();
      refObserver.destroy();
      client.clear();
    });

    // A `structuralSharing` and a computed seed from `configure` are held
    // to the page types by a wrapper. A wrapper made per call made the
    // options of a held definition differ from call to call.
    group('the wrapper of a callback is the same for the same callback (SC-3)',
        () {
      // How many times an observer handed the options [times] more times
      // heard that they changed.
      int changes(
        InfiniteQueryObserverOptions<List<Post>, int> Function() options, {
        int times = 2,
      }) {
        final client = testClient();
        var heard = 0;
        final observer = InfiniteQueryObserver(client, options());
        client.queryCache.subscribe((event) {
          if (event is QueryObserverOptionsUpdated) heard++;
        });
        for (var i = 0; i < times; i++) {
          observer.setInfiniteOptions(options());
        }
        observer.destroy();
        client.clear();
        return heard;
      }

      bool equalOnceResolved(
        InfiniteQueryObserverOptions<List<Post>, int> a,
        InfiniteQueryObserverOptions<List<Post>, int> b,
      ) {
        final client = testClient();
        final resolvedA = client.defaultQueryOptions<Feed>(a);
        final resolvedB = client.defaultQueryOptions<Feed>(b);
        return resolvedA == resolvedB &&
            resolvedA.hashCode == resolvedB.hashCode;
      }

      test('a structuralSharing that is one function: equal options', () {
        final definition = feed(
          configure: (base) => base.copyWith(structuralSharing: keepNext),
        );
        final a = definition.options();
        final b = definition.options();
        expect(identical(a, b), isFalse);
        // A wrapper, and the same one.
        expect(a.structuralSharing, isNot(same(keepNext)));
        expect(a.structuralSharing, same(b.structuralSharing));
        expect(equalOnceResolved(a, b), isTrue);
        expect(changes(definition.options), 0);

        // Held in a field or a local, as a closure can be.
        Feed held(Feed? previous, Feed next) => next;
        final holding = feed(
          configure: (base) => base.copyWith(structuralSharing: held),
        );
        expect(equalOnceResolved(holding.options(), holding.options()), isTrue);
        expect(changes(holding.options), 0);
      });

      test('a computed seed that is one function: equal options', () {
        final definition = feed(
          configure: (base) =>
              base.copyWith(initialData: InitialData.compute(seedOfSeven)),
        );
        final a = definition.options();
        final b = definition.options();
        expect(a.initialData, isNot(same(b.initialData)));
        expect(a.initialData, b.initialData);
        expect(equalOnceResolved(a, b), isTrue);
        expect(changes(definition.options), 0);

        // The wrapper is still what seeds the entry, under the page types.
        final client = testClient();
        InfiniteQueryObserver(client, definition.options());
        expect(definition.read(client).runtimeType, typeOf<Feed>());
        expect(definition.read(client)!.pages, [
          [const Pinned(7)],
        ]);
        client.clear();
      });

      test('a narrower seed value that is held is rebuilt per call, and equal',
          () {
        // Rebuilt around the same pages, and two `InfiniteData` are equal
        // by their pages.
        final seed = InitialData<Feed>.value(narrow());
        final definition = feed(
          configure: (base) => base.copyWith(initialData: seed),
        );
        final a = definition.options();
        final b = definition.options();
        expect(a.initialData, isNot(same(seed)));
        expect(a.initialData, isNot(same(b.initialData)));
        expect(equalOnceResolved(a, b), isTrue);
        expect(changes(definition.options), 0);

        // The control: a seed made in `configure` has pages of its own
        // every time, rebuilt or not, as it has in options written by hand.
        for (final value in [narrow, exact]) {
          final making = feed(
            configure: (base) =>
                base.copyWith(initialData: InitialData.value(value())),
          );
          expect(
            equalOnceResolved(making.options(), making.options()),
            isFalse,
          );
        }
      });

      test('both at once, and the wrapper still holds the page types', () {
        final definition = feed(
          configure: (base) => base.copyWith(
            structuralSharing: keepSeven,
            initialData: InitialData.compute(seedOfSeven),
          ),
        );
        expect(
          equalOnceResolved(definition.options(), definition.options()),
          isTrue,
        );
        expect(changes(definition.options, times: 3), 0);

        final client = testClient();
        definition.options();
        final stored = definition.write(client, exact());
        expect(stored.runtimeType, typeOf<Feed>());
        expect(stored.pages, [
          [const Pinned(7)],
        ]);
        client.clear();
      });

      test('the control: a callback made in configure is another every call',
          () {
        final definition = feed(
          configure: (base) => base.copyWith(
            structuralSharing: (previous, next) => next,
          ),
        );
        final a = definition.options();
        final b = definition.options();
        expect(a.structuralSharing, isNot(same(b.structuralSharing)));
        expect(equalOnceResolved(a, b), isFalse);
        expect(changes(definition.options), 2);

        final seeded = feed(
          configure: (base) => base.copyWith(
            initialData: InitialData.compute(() => null),
          ),
        );
        expect(equalOnceResolved(seeded.options(), seeded.options()), isFalse);
        expect(changes(seeded.options), 2);
      });

      // The wrapper is found by identity. Two tear-offs of one method are
      // equal, which is all options written by hand need, and on the VM
      // they are two objects.
      test('a method torn off in configure: another wrapper per call', () {
        final sharer = Sharer();
        expect(sharer.keep == sharer.keep, isTrue);
        final tearing = feed(
          configure: (base) => base.copyWith(structuralSharing: sharer.keep),
        );
        expect(
          equalOnceResolved(tearing.options(), tearing.options()),
          isFalse,
        );
        expect(changes(tearing.options), 2);

        // Torn off once and held, it is one function.
        final keep = sharer.keep;
        final holding = feed(
          configure: (base) => base.copyWith(structuralSharing: keep),
        );
        expect(equalOnceResolved(holding.options(), holding.options()), isTrue);
        expect(changes(holding.options), 0);
      }, testOn: 'vm');

      test('a wrapper belongs to its definition, and to its callback', () {
        final first = feed(
          configure: (base) => base.copyWith(structuralSharing: keepNext),
        );
        final second = feed(
          configure: (base) => base.copyWith(structuralSharing: keepNext),
        );
        expect(
          first.options().structuralSharing,
          isNot(same(second.options().structuralSharing)),
        );

        // One definition, two callbacks in turn: each keeps its own.
        var seven = false;
        final turning = feed(
          configure: (base) => base.copyWith(
            structuralSharing: seven ? keepSeven : keepNext,
          ),
        );
        final next = turning.options().structuralSharing!;
        seven = true;
        final sevens = turning.options().structuralSharing!;
        expect(sevens, isNot(same(next)));
        expect(sevens(null, exact()).pages, [
          [const Pinned(7)],
        ]);
        expect(next(null, exact()).pages, exact().pages);
        seven = false;
        expect(turning.options().structuralSharing, same(next));
      });

      test('a family keeps no wrapper: its options differ already', () {
        final family = byAuthor(
          configure: (base, author) => base.copyWith(
            structuralSharing: keepNext,
            initialData: InitialData.compute(seedOfSeven),
          ),
        );
        final ref = family('ada');
        final a = ref.options();
        final b = ref.options();
        expect(a.structuralSharing, isNot(same(b.structuralSharing)));
        expect(a.initialData, isNot(b.initialData));
        expect(changes(ref.options), 2);
      });
    });

    testFakeAsync('fetch is client.infiniteQuery: fresh, stale, joined',
        (time) async {
      final client = testClient();
      var requests = 0;
      final definition = feed(
        pageFn: (context) async {
          requests++;
          await sleep(ms(10));
          return page(context.pageParam);
        },
        configure: (base) => base.copyWith(
          staleTime: const StaleTime.duration(Duration(seconds: 20)),
        ),
      );

      final first = definition.fetch(client);
      final joined = definition.fetch(client);
      await time.advance(ms(10));
      expect(requests, 1);
      expect((await first).pages, [page(0)]);
      expect(await joined, same(await first));
      expect(entry(client, definition.key.rawKey).dataType, typeOf<Feed>());

      // Fresh: no request.
      expect((await definition.fetch(client)).pageParams, [0]);
      expect(requests, 1);

      // Stale, revalidating: the cached pages at once, a request behind.
      await time.advance(const Duration(seconds: 30));
      final cached = await definition.fetch(client, revalidateIfStale: true);
      expect(cached.pages, [page(0)]);
      expect(requests, 2);
      await time.advance(ms(10));

      // Stale: a request, awaited.
      await time.advance(const Duration(seconds: 30));
      final refetched = definition.fetch(client);
      await time.advance(ms(10));
      expect(requests, 3);
      expect((await refetched).pages, [page(0)]);
      client.clear();
    });

    testFakeAsync('an observer on the options pages through the definition',
        (time) async {
      final client = testClient();
      final definition = feed();
      final observer = InfiniteQueryObserver(client, definition.options());
      final unsubscribe = observer.subscribe((result) {});
      await time.flushMicrotasks();
      await observer.fetchNextPage();
      expect(definition.read(client)!.pageParams, [0, 3]);
      await observer.fetchNextPage();
      expect(definition.read(client)!.pageParams, [0, 3, 6]);
      expect(observer.hasNextPage, isFalse);
      expect(observer.hasPreviousPage, isFalse);
      expect(definition.read(client)!.pages, [page(0), page(3), page(6)]);
      unsubscribe();
      client.clear();
    });

    testFakeAsync('a family hands every paging function its input',
        (time) async {
      final client = testClient();
      final seen = <String>[];
      final family =
          InfiniteQueryFamily<({String author, int start}), List<Post>, int>(
        namespace: posts,
        name: 'from',
        pageFn: (input, context) {
          seen.add('page ${input.author} ${context.pageParam}');
          return page(context.pageParam);
        },
        initialPageParam: (input) => input.start,
        getNextPageParam: (input, page, pages, pageParam, pageParams) {
          seen.add('next ${input.author} $pageParam');
          return pageParam + 3;
        },
        getPreviousPageParam: (input, page, pages, pageParam, pageParams) {
          seen.add('previous ${input.author} $pageParam');
          return pageParam - 3;
        },
      );
      final ref = family((author: 'ada', start: 30));
      expect(ref.options().initialPageParam, 30);

      final observer = InfiniteQueryObserver(client, ref.options());
      final unsubscribe = observer.subscribe((result) {});
      await time.flushMicrotasks();
      expect(ref.read(client)!.pageParams, [30]);
      seen.clear();
      await observer.fetchNextPage();
      await observer.fetchPreviousPage();
      expect(ref.read(client)!.pageParams, [27, 30, 33]);
      expect(
        seen,
        containsAll([
          'next ada 30',
          'page ada 33',
          'previous ada 30',
          'page ada 27',
        ]),
      );
      expect(seen.where((line) => !line.contains(' ada ')), isEmpty);
      unsubscribe();
      client.clear();
    });

    testFakeAsync(
        'configure sets the rest, per input, and cannot move the '
        'key or the paging functions', (time) async {
      final client = testClient();
      final elsewhere = QueryKey(['elsewhere']);
      final definition = feed(
        configure: (base) => base.copyWith(
          queryKey: elsewhere,
          pageFn: (context) => const [Post(-1)],
          initialPageParam: 99,
          getNextPageParam: (page, pages, pageParam, pageParams) => 1000,
          getPreviousPageParam: (page, pages, pageParam, pageParams) => 1000,
          maxPages: 2,
          meta: 'kept',
        ),
      );
      final options = definition.options();
      expect(options.queryKey, definition.key.rawKey);
      expect(options.initialPageParam, 0);
      expect(options.getNextPageParam(const [], const [], 0, const [0]), 3);
      expect(
          options.getPreviousPageParam!(const [], const [], 3, const [3]), 0);
      expect(options.maxPages, 2);
      expect(options.meta, 'kept');
      expect((await definition.fetch(client)).pages, [page(0)]);
      expect(
        client.queryCache.findAll(filters: QueryFilters(queryKey: elsewhere)),
        isEmpty,
      );

      final authors = <String>[];
      final family = byAuthor(
        configure: (base, author) {
          authors.add(author);
          return base.copyWith(
            queryKey: elsewhere,
            pageFn: (context) => const [Post(-1)],
            initialPageParam: 99,
            getNextPageParam: (page, pages, pageParam, pageParams) => 1000,
            meta: author,
          );
        },
      );
      final ada = family('ada').options();
      expect(authors, ['ada']);
      expect(ada.queryKey, family('ada').key.rawKey);
      expect(ada.initialPageParam, 0);
      expect(ada.getNextPageParam(const [], const [], 0, const [0]), 3);
      expect(ada.meta, 'ada');
      expect((await family('ada').fetch(client)).pages, [page(0)]);
      client.clear();
    });

    test('configure may add the previous-page function a definition lacks', () {
      final family = byAuthor(
        configure: (base, author) => base.copyWith(
          getPreviousPageParam: (page, pages, pageParam, pageParams) => -1,
        ),
      );
      expect(
        family('ada').options().getPreviousPageParam!(
          const [],
          const [],
          0,
          const [0],
        ),
        -1,
      );
    });

    // The zero-input twin. A definition pins what it declares; what it
    // leaves unset, `configure` may set.
    test('a definition that declares no previous-page function: the same', () {
      final definition = InfiniteQueryDefinition<List<Post>, int>(
        namespace: posts,
        name: 'forward',
        pageFn: (context) => page(context.pageParam),
        initialPageParam: 0,
        getNextPageParam: (page, pages, pageParam, pageParams) => pageParam + 3,
        configure: (base) => base.copyWith(
          getPreviousPageParam: (page, pages, pageParam, pageParams) => -1,
          // Declared, so pinned: this one is put back.
          getNextPageParam: (page, pages, pageParam, pageParams) => 99,
        ),
      );
      final options = definition.options();
      expect(
        options.getPreviousPageParam!(const [], const [], 0, const [0]),
        -1,
      );
      expect(options.getNextPageParam(const [], const [], 0, const [0]), 3);
    });

    // `copyWith` reads null as "keep", so this is the one thing a
    // definition cannot put back after `configure`.
    test('a first page param of null that configure changed is an error', () {
      InfiniteQueryDefinition<List<Post>, String?> cursor(
        InfiniteQueryObserverOptions<List<Post>, String?> Function(
          InfiniteQueryObserverOptions<List<Post>, String?> base,
        ) configure,
      ) =>
          InfiniteQueryDefinition<List<Post>, String?>(
            namespace: posts,
            name: 'cursor',
            pageFn: (context) => const [],
            initialPageParam: null,
            getNextPageParam: (page, pages, pageParam, pageParams) => null,
            configure: configure,
          );

      final kept = cursor((base) => base.copyWith(maxPages: 3));
      expect(kept.options().initialPageParam, isNull);
      expect(kept.options().maxPages, 3);

      final moved = cursor((base) => base.copyWith(initialPageParam: 'c1'));
      expect(
        moved.options,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(contains('initialPageParam'), contains('cursor')),
          ),
        ),
      );
      // A write would resolve the options to create the entry: refused the
      // same way, with nothing written.
      final client = testClient();
      expect(
        () => moved.write(
          client,
          InfiniteData<List<Post>, String?>(
              pages: const [], pageParams: const []),
        ),
        throwsStateError,
      );
      expect(client.queryCache.findAll(), isEmpty);
    });

    // Options of narrower page types are a subtype of the definition's, so
    // the analyzer lets `configure` return them. They cannot take the
    // definition's paging functions back, and are refused before that is
    // tried.
    group('configure returns options of the definition\'s own type (S0-2)', () {
      Matcher wrongOptions(String key, Type returned, Type declared) => throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('configure'),
                contains(key),
                contains('$returned'),
                contains('$declared'),
              ),
            ),
          );

      InfiniteQueryObserverOptions<List<Pinned>, int> pinnedOptions(
        QueryKey key,
      ) =>
          InfiniteQueryObserverOptions<List<Pinned>, int>(
            queryKey: key,
            pageFn: (context) => const [],
            initialPageParam: 0,
            getNextPageParam: (page, pages, pageParam, pageParams) => null,
          );

      test('a definition: narrower page data is refused, with both types', () {
        final definition =
            feed(configure: (base) => pinnedOptions(base.queryKey));
        expect(
          definition.options,
          wrongOptions(
            '["posts","feed"]',
            typeOf<InfiniteQueryObserverOptions<List<Pinned>, int>>(),
            typeOf<InfiniteQueryObserverOptions<List<Post>, int>>(),
          ),
        );
        // A write would resolve the options to create the entry.
        final client = testClient();
        expect(() => definition.write(client, exact()), throwsStateError);
        expect(() => definition.fetch(client), throwsStateError);
        expect(client.queryCache.findAll(), isEmpty);
      });

      test('a definition: a narrower page param is refused too', () {
        final cursor = InfiniteQueryDefinition<List<Post>, num>(
          namespace: posts,
          name: 'cursor',
          pageFn: (context) => const [],
          initialPageParam: 0.5,
          getNextPageParam: (page, pages, pageParam, pageParams) => null,
          configure: (base) => InfiniteQueryObserverOptions<List<Post>, int>(
            queryKey: base.queryKey,
            pageFn: (context) => const [],
            initialPageParam: 0,
            getNextPageParam: (page, pages, pageParam, pageParams) => null,
          ),
        );
        expect(
          cursor.options,
          wrongOptions(
            '["posts","cursor"]',
            typeOf<InfiniteQueryObserverOptions<List<Post>, int>>(),
            typeOf<InfiniteQueryObserverOptions<List<Post>, num>>(),
          ),
        );
      });

      test('a family: refused per input, naming that input\'s key', () {
        final family = byAuthor(
          configure: (base, author) => pinnedOptions(base.queryKey),
        );
        final ada = family('ada');
        expect(
          ada.options,
          wrongOptions(
            '["posts","byAuthor","ada"]',
            typeOf<InfiniteQueryObserverOptions<List<Pinned>, int>>(),
            typeOf<InfiniteQueryObserverOptions<List<Post>, int>>(),
          ),
        );
      });

      // The control: the declared type passes, made from the base or from
      // nothing, and the definition's paging functions are pinned as before.
      test('options of the declared type pass, however they are made', () {
        final copied = feed(configure: (base) => base.copyWith(maxPages: 2));
        final made = feed(
          configure: (base) => InfiniteQueryObserverOptions<List<Post>, int>(
            queryKey: QueryKey(['elsewhere']),
            pageFn: (context) => const [],
            initialPageParam: 99,
            getNextPageParam: (page, pages, pageParam, pageParams) => null,
            maxPages: 4,
          ),
        );
        expect(copied.options().maxPages, 2);
        expect(made.options().maxPages, 4);
        expect(made.options().queryKey, made.key.rawKey);
        expect(made.options().initialPageParam, 0);
      });
    });

    testFakeAsync('withSelect changes what an observer sees, not the entry',
        (time) async {
      final client = testClient();
      final definition = feed();
      final observer = InfiniteQueryObserver(
        client,
        definition.options().withSelect((data) => data.pages.length),
      );
      final counts = <int?>[];
      final unsubscribe =
          observer.subscribe((result) => counts.add(result.dataOrNull));
      await time.flushMicrotasks();
      expect(counts.last, 1);
      expect(entry(client, definition.key.rawKey).dataType, typeOf<Feed>());
      unsubscribe();
      client.clear();
    });
  });

  group('a written value is stored under the declared page types', () {
    test('a narrower value is rebuilt from its pages', () {
      final client = testClient();
      final definition = feed();
      final written = narrow();
      expect(written.runtimeType, isNot(typeOf<Feed>()));

      final stored = definition.write(client, written);
      expect(stored, isNot(same(written)));
      expect(stored.runtimeType, typeOf<Feed>());
      expect(stored.pages, written.pages);
      expect(stored.pageParams, written.pageParams);
      expect(definition.read(client), same(stored));
      expect(entry(client, definition.key.rawKey).dataType, typeOf<Feed>());

      // What it is for: the cached value takes a page of the declared type.
      final grown = definition.update(
        client,
        (data) => data!.copyWith(
          pages: [
            ...data.pages,
            [const Post(2)],
          ],
          pageParams: [...data.pageParams, 3],
        ),
      );
      expect(grown!.pages.last, [const Post(2)]);
      // The narrower value itself could not: its lists are of `Pinned`.
      expect(written.pages, isA<List<List<Pinned>>>());
      client.clear();
    });

    test('the rebuilt value\'s lists are unmodifiable', () {
      final client = testClient();
      final stored = feed().write(client, narrow());
      expect(() => stored.pages.add(const []), throwsUnsupportedError);
      expect(() => stored.pageParams.add(1), throwsUnsupportedError);
      client.clear();
    });

    test('an exact value is stored as it is, the same instance', () {
      final client = testClient();
      final definition = feed();
      final value = exact();
      expect(definition.write(client, value), same(value));
      expect(definition.read(client), same(value));
      client.clear();
    });

    test(
        'rebuilding restores sharing: an equal narrower write keeps the '
        'cached instance', () {
      final client = testClient();
      final definition = feed();
      final first = definition.write(client, narrow());
      expect(definition.write(client, narrow()), same(first));
      // The control, on the client: with nothing rebuilt, the runtime
      // types differ from write to write and nothing is shared.
      final key = QueryKey(['posts', 'raw']);
      client.setQueryData<Feed>(key, exact());
      final second = narrow();
      expect(client.setQueryData<Feed>(key, second), same(second));
      client.clear();
    });

    test('an updater\'s narrower result is rebuilt too', () {
      final client = testClient();
      final definition = feed();
      final created = definition.update(client, (data) => narrow());
      expect(created.runtimeType, typeOf<Feed>());
      final replaced = definition.update(client, (data) => narrow(2));
      expect(replaced.runtimeType, typeOf<Feed>());
      expect(replaced!.pages, [
        [const Pinned(2)],
      ]);
      expect(definition.update(client, (data) => null), isNull);
      expect(definition.read(client), same(replaced));
      client.clear();
    });

    test('an entry of narrower page types is refused, as any other type is',
        () {
      final client = testClient();
      final definition = feed();
      final key = definition.key.rawKey;
      client.setQueryData(key, narrow());
      expect(
        () => definition.write(client, exact()),
        throwsA(
          dataTypeError(
            key,
            typeOf<Feed>(),
            typeOf<InfiniteData<List<Pinned>, int>>(),
          ),
        ),
      );
      expect(
        () => definition.read(client),
        throwsA(
          dataTypeError(
            key,
            typeOf<Feed>(),
            typeOf<InfiniteData<List<Pinned>, int>>(),
          ),
        ),
      );
      client.clear();
    });

    testFakeAsync('a written entry pages on from the definition\'s functions',
        (time) async {
      final client = testClient();
      final definition = feed();
      definition.write(client, narrow());
      final observer = InfiniteQueryObserver(
        client,
        definition.options().copyWith(
              staleTime: StaleTime.infinite,
            ),
      );
      final unsubscribe = observer.subscribe((result) {});
      await time.flushMicrotasks();
      await observer.fetchNextPage();
      final data = definition.read(client)!;
      expect(data.pageParams, [0, 3]);
      expect(data.pages, [
        [const Pinned(1)],
        page(3),
      ]);
      unsubscribe();
      client.clear();
    });
  });

  group('the definition\'s structuralSharing is held to the page types', () {
    test('a hook that returns a narrower value: the commit is exact', () {
      final client = testClient();
      final calls = <(Feed?, Feed)>[];
      final definition = feed(
        configure: (base) => base.copyWith(
          structuralSharing: (previous, next) {
            calls.add((previous, next));
            // A hook of the caller's own, which keeps whatever it likes.
            return narrow(7);
          },
        ),
      );
      final stored = definition.write(client, exact());
      expect(calls, hasLength(1));
      expect(stored.runtimeType, typeOf<Feed>());
      expect(stored.pages, [
        [const Pinned(7)],
      ]);
      expect(definition.read(client), same(stored));
      client.clear();
    });

    testFakeAsync('fetched pages go through it as well', (time) async {
      final client = testClient();
      final definition = feed(
        configure: (base) => base.copyWith(
          structuralSharing: (previous, next) => narrow(7),
        ),
      );
      final fetched = await definition.fetch(client);
      expect(fetched.runtimeType, typeOf<Feed>());
      expect(definition.read(client).runtimeType, typeOf<Feed>());

      final observer = InfiniteQueryObserver(client, definition.options());
      final unsubscribe = observer.subscribe((result) {});
      await time.flushMicrotasks();
      await observer.refetch();
      expect(definition.read(client).runtimeType, typeOf<Feed>());
      unsubscribe();
      client.clear();
    });

    test('a hook that returns an exact value is not second-guessed', () {
      final client = testClient();
      final kept = exact(9);
      final definition = feed(
        configure: (base) =>
            base.copyWith(structuralSharing: (previous, next) => kept),
      );
      expect(definition.write(client, exact()), same(kept));
      client.clear();
    });

    test('the default and the opt-out are left as they are', () {
      expect(feed().options().structuralSharing, isNull);
      expect(
        feed(configure: (base) => base.copyWith(maxPages: 2))
            .options()
            .structuralSharing,
        isNull,
      );

      final optOut = noStructuralSharing<Feed>();
      final definition = feed(
        configure: (base) => base.copyWith(structuralSharing: optOut),
      );
      // The same function: the observer recognises the opt-out by identity,
      // and stops sharing what `select` returns as well.
      expect(definition.options().structuralSharing, same(optOut));

      final client = testClient();
      final first = definition.write(client, exact());
      final second = exact();
      expect(definition.write(client, second), same(second));
      expect(second, isNot(same(first)));
      // And without sharing a narrower write is still rebuilt, by the write.
      expect(
        definition.write(client, narrow()).runtimeType,
        typeOf<Feed>(),
      );
      client.clear();
    });

    test('the family\'s hook is wrapped per input', () {
      final client = testClient();
      final family = byAuthor(
        configure: (base, author) => base.copyWith(
          structuralSharing: (previous, next) => narrow(author.length),
        ),
      );
      final stored = family('ada').write(client, exact());
      expect(stored.runtimeType, typeOf<Feed>());
      expect(stored.pages, [
        [const Pinned(3)],
      ]);
      client.clear();
    });

    // The documented limit: only what the definition itself declares.
    test('a hook given through a per-use copyWith is used as it is', () {
      final client = testClient();
      final definition = feed();
      final observer = InfiniteQueryObserver(
        client,
        definition.options().copyWith(
              structuralSharing: (previous, next) => narrow(7),
              enabled: Enabled.no,
            ),
      );
      final unsubscribe = observer.subscribe((result) {});
      // The observer's options are now the entry's; the write is still
      // exact going in, and the per-use hook has the last word.
      final stored = definition.write(client, exact());
      expect(stored.runtimeType, typeOf<InfiniteData<List<Pinned>, int>>());
      unsubscribe();
      client.clear();
    });

    // The other documented limit. A default's hook is typed `Object?`, the
    // client checks what it returns against the entry's type, and a
    // narrower `InfiniteData` passes that check.
    test('a hook from the client\'s or a key\'s defaults is used as it is', () {
      final client = testClient(
        defaultOptions: DefaultOptions(
          queries: QueryDefaults(
            structuralSharing: (previous, next) => narrow(7),
          ),
        ),
      );
      final definition = feed();
      expect(
        definition.write(client, exact()).runtimeType,
        typeOf<InfiniteData<List<Pinned>, int>>(),
      );

      final keyed = testClient()
        ..setQueryDefaults(
          definition.key.rawKey,
          QueryDefaults(structuralSharing: (previous, next) => narrow(8)),
        );
      expect(
        definition.write(keyed, exact()).runtimeType,
        typeOf<InfiniteData<List<Pinned>, int>>(),
      );
      // The definition's own hook goes before both, and is held to the type.
      final own = feed(
        configure: (base) => base.copyWith(
          structuralSharing: (previous, next) => narrow(9),
        ),
      );
      keyed.removeQueries();
      expect(own.write(keyed, exact()).runtimeType, typeOf<Feed>());
      client.clear();
      keyed.clear();
    });
  });

  group('the definition\'s initialData is held to the page types', () {
    test('a narrower seed value is rebuilt', () {
      final client = testClient();
      final definition = feed(
        configure: (base) =>
            base.copyWith(initialData: InitialData.value(narrow())),
      );
      InfiniteQueryObserver(client, definition.options());
      final seeded = definition.read(client)!;
      expect(seeded.runtimeType, typeOf<Feed>());
      expect(seeded.pages, [
        [const Pinned(1)],
      ]);
      client.clear();
    });

    test('an exact seed value is kept, the InitialData instance included', () {
      final client = testClient();
      final value = exact();
      final seed = InitialData<Feed>.value(value);
      final definition = feed(
        configure: (base) => base.copyWith(initialData: seed),
      );
      expect(definition.options().initialData, same(seed));
      InfiniteQueryObserver(client, definition.options());
      expect(definition.read(client), same(value));
      client.clear();
    });

    test('a computed seed is rebuilt when it is narrower, and may be null', () {
      final client = testClient();
      Feed? computed = narrow();
      var computes = 0;
      final definition = feed(
        configure: (base) => base.copyWith(
          initialData: InitialData.compute(() {
            computes++;
            return computed;
          }),
        ),
      );
      // Making the options computes nothing.
      definition.options();
      expect(computes, 0);

      InfiniteQueryObserver(client, definition.options());
      expect(computes, greaterThan(0));
      expect(definition.read(client).runtimeType, typeOf<Feed>());

      final other = testClient();
      computed = null;
      InfiniteQueryObserver(other, definition.options());
      expect(definition.state(other)!.hasData, isFalse);

      final third = testClient();
      final value = exact();
      computed = value;
      InfiniteQueryObserver(third, definition.options());
      expect(definition.read(third), same(value));
      client.clear();
      other.clear();
      third.clear();
    });

    test('an entry a write creates is seeded the same way, then written', () {
      final client = testClient();
      final family = byAuthor(
        configure: (base, author) =>
            base.copyWith(initialData: InitialData.value(narrow())),
      );
      family('ada').write(client, exact(5));
      expect(family('ada').read(client)!.pages, [
        [const Post(5)],
      ]);
      // What a reset goes back to is the rebuilt seed.
      final reset = entry(client, family('ada').key.rawKey).resetState.data;
      expect(reset.runtimeType, typeOf<Feed>());
      client.clear();
    });

    test('a seed given through a per-use copyWith is used as it is', () {
      final client = testClient();
      final definition = feed();
      InfiniteQueryObserver(
        client,
        definition.options().copyWith(
              initialData: InitialData.value(narrow()),
            ),
      );
      expect(
        definition.read(client).runtimeType,
        typeOf<InfiniteData<List<Pinned>, int>>(),
      );
      client.clear();
    });
  });

  // The infinite references write through the function the plain ones do.
  // These are the same points with the page types in the check: an entry of
  // narrower page types is another type.
  group('a write goes into the entry the cache holds (SC-1)', () {
    final rawKey = QueryKey(['posts', 'feed']);
    final narrower = typeOf<InfiniteData<List<Pinned>, int>>();
    final writes = <String,
        Feed? Function(QueryClient, InfiniteQueryRef<List<Post>, int>)>{
      'ref.write': (client, ref) => ref.write(client, narrow(2)),
      'ref.update': (client, ref) =>
          ref.update(client, (previous) => narrow(2)),
      'key.write': (client, ref) => ref.key.write(client, narrow(2)),
      'key.update': (client, ref) =>
          ref.key.update(client, (previous) => narrow(2)),
    };

    void remove(QueryClient client) =>
        client.removeQueries(filters: QueryFilters(queryKey: rawKey));

    // Answers the first `QueryAdded` it hears, once; the function it
    // returns says whether it has.
    bool Function() whenAdded(QueryClient client, void Function() answer) {
      var answered = false;
      client.queryCache.subscribe((event) {
        if (event is QueryAdded && !answered) {
          answered = true;
          answer();
        }
      });
      return () => answered;
    }

    // Two `InfiniteData` are equal by their page lists, which two calls of
    // `narrow` do not share; the posts in them are compared here.
    List<List<Post>> pagesOf(QueryClient client, QueryKey key) =>
        (entry(client, key).state.data! as InfiniteData<List<Post>, int>).pages;

    for (final MapEntry(key: name, value: write) in writes.entries) {
      group(name, () {
        test('narrower page types put in its place when it was added', () {
          final client = testClient();
          whenAdded(client, () {
            remove(client);
            client.setQueryData(rawKey, narrow(9));
          });
          expect(
            () => write(client, feed()),
            throwsA(dataTypeError(rawKey, typeOf<Feed>(), narrower)),
          );
          final held = entry(client, rawKey);
          expect(held.dataType, narrower);
          expect(pagesOf(client, rawKey), narrow(9).pages);
          expect(held.state.dataUpdateCount, 1);
          client.clear();
        });

        test('the same page types put in its place: that entry is written', () {
          final client = testClient();
          whenAdded(client, () {
            remove(client);
            client.setQueryData<Feed>(rawKey, exact(9));
          });
          final stored = write(client, feed())!;
          // Under the declared page types, as every infinite write.
          expect(stored.runtimeType, typeOf<Feed>());
          expect(stored.pages, [
            [const Pinned(2)],
          ]);
          final held = entry(client, rawKey);
          expect(held.state.data, same(stored));
          expect(held.state.dataUpdateCount, 2);
          client.clear();
        });

        test('removed when it was added: StateError, nothing stored', () {
          final client = testClient();
          whenAdded(client, () => remove(client));
          expect(() => write(client, feed()), throwsStateError);
          expect(client.queryCache.findAll(), isEmpty);
          client.clear();
        });

        test('the definition\'s structuralSharing removes its entry', () {
          final client = testClient();
          var ran = 0;
          final definition = feed(
            configure: (base) => base.copyWith(
              structuralSharing: (previous, next) {
                // Not for the write that sets the scene.
                if (previous != null) {
                  ran++;
                  remove(client);
                }
                return next;
              },
            ),
          );
          definition.write(client, exact());
          expect(() => write(client, definition), throwsStateError);
          expect(ran, 1);
          expect(client.queryCache.findAll(), isEmpty);
          client.clear();
        });

        test('the definition\'s structuralSharing puts narrower pages there',
            () {
          final client = testClient();
          final definition = feed(
            configure: (base) => base.copyWith(
              structuralSharing: (previous, next) {
                if (previous != null) {
                  remove(client);
                  client.setQueryData(rawKey, narrow(9));
                }
                return next;
              },
            ),
          );
          definition.write(client, exact());
          expect(
            () => write(client, definition),
            throwsA(dataTypeError(rawKey, typeOf<Feed>(), narrower)),
          );
          expect(entry(client, rawKey).dataType, narrower);
          expect(pagesOf(client, rawKey), narrow(9).pages);
          client.clear();
        });

        // Second whole-feature review, R1: the clock that dates the value
        // is the caller's code as well.
        test('a clock that removes its entry or puts narrower pages there (R1)',
            () {
          for (final replace in [false, true]) {
            final client = testClient();
            final definition = feed();
            definition.write(client, exact());
            var ran = 0;
            withClock(
              Clock(() {
                if (ran++ == 0) {
                  remove(client);
                  if (replace) client.setQueryData(rawKey, narrow(9));
                }
                return DateTime.utc(2026);
              }),
              () => expect(
                () => write(client, definition),
                replace
                    ? throwsA(dataTypeError(rawKey, typeOf<Feed>(), narrower))
                    : throwsStateError,
              ),
            );
            if (replace) {
              expect(entry(client, rawKey).dataType, narrower);
              expect(pagesOf(client, rawKey), narrow(9).pages);
            } else {
              expect(client.queryCache.findAll(), isEmpty);
            }
            client.clear();
          }
        });
      });
    }

    test('a family\'s updateAll: an entry made again and replaced when added',
        () {
      final client = testClient();
      final family = byAuthor();
      final ada = family('ada');
      final bob = family('bob');
      ada.write(client, exact(1));
      bob.write(client, exact(2));
      void removeBob() => client.removeQueries(
            filters: QueryFilters(queryKey: bob.key.rawKey, exact: true),
          );
      final answered = whenAdded(client, () {
        removeBob();
        client.setQueryData(bob.key.rawKey, narrow(9));
      });
      expect(
        () => family.updateAll(client, (previous) {
          // The updater removes the later entry; its write makes it again.
          final id = previous!.pages.single.single.id;
          if (id == 2) removeBob();
          return narrow(id + 10);
        }),
        throwsA(dataTypeError(bob.key.rawKey, typeOf<Feed>(), narrower)),
      );
      expect(answered(), isTrue);
      // The earlier write was made, as a batch that fails while writing
      // leaves it.
      expect(ada.read(client)!.pages, [
        [const Pinned(11)],
      ]);
      expect(pagesOf(client, bob.key.rawKey), narrow(9).pages);
      client.clear();
    });

    test('a family\'s updateAll: the same page types put there are written',
        () {
      final client = testClient();
      final family = byAuthor();
      final bob = family('bob');
      family('ada').write(client, exact(1));
      bob.write(client, exact(2));
      void removeBob() => client.removeQueries(
            filters: QueryFilters(queryKey: bob.key.rawKey, exact: true),
          );
      final answered = whenAdded(client, () {
        removeBob();
        client.setQueryData<Feed>(bob.key.rawKey, exact(9));
      });
      final updated = family.updateAll(client, (previous) {
        final id = previous!.pages.single.single.id;
        if (id == 2) removeBob();
        return narrow(id + 10);
      });
      expect(answered(), isTrue);
      expect(updated[1].$2.runtimeType, typeOf<Feed>());
      expect(bob.read(client), same(updated[1].$2));
      expect(bob.read(client)!.pages, [
        [const Pinned(12)],
      ]);
      expect(bob.state(client)!.dataUpdateCount, 2);
      client.clear();
    });
  });

  group('a family\'s bulk operations', () {
    test('readAll returns every input\'s pages under its typed key', () {
      final client = testClient();
      final family = byAuthor();
      final ada = family('ada').write(client, exact(1));
      final bob = family('bob').write(client, exact(2));
      feed().write(client, exact(3));
      final all = family.readAll(client);
      expect(all, hasLength(2));
      expect(all[0].$1, family('ada').key);
      expect(all[0].$2, same(ada));
      expect(all[1].$1, family('bob').key);
      expect(all[1].$2, same(bob));
      expect(all[0].$1.read(client), same(ada));
      client.clear();
    });

    test('updateAll writes every input, rebuilt under the page types', () {
      final client = testClient();
      final family = byAuthor();
      family('ada').write(client, exact(1));
      family('bob').write(client, exact(2));
      feed().write(client, exact(3));
      final at = DateTime.utc(2020, 2, 2);

      final updated = family.updateAll(
        client,
        (data) => data!.pages.first.first.id == 1 ? narrow(10) : null,
        updatedAt: at,
      );
      expect(updated, hasLength(2));
      expect(updated[0].$1, family('ada').key);
      expect(updated[0].$2.runtimeType, typeOf<Feed>());
      expect(updated[0].$2!.pages, [
        [const Pinned(10)],
      ]);
      expect(updated[1], (family('bob').key, null));
      expect(family('ada').read(client), same(updated[0].$2));
      expect(family('ada').state(client)!.dataUpdatedAt, at);
      expect(family('bob').state(client)!.dataUpdateCount, 1);
      expect(feed().read(client)!.pages, [
        [const Post(3)],
      ]);
      client.clear();
    });

    test('an entry of other page types under the prefix: nothing is written',
        () {
      final client = testClient();
      final family = byAuthor();
      family('ada').write(client, exact(1));
      final other = family('bob').key.rawKey;
      client.setQueryData(other, narrow());
      var ran = 0;
      final refused = throwsA(
        dataTypeError(
          other,
          typeOf<Feed>(),
          typeOf<InfiniteData<List<Pinned>, int>>(),
        ),
      );
      expect(
        () => family.updateAll(client, (data) {
          ran++;
          return data;
        }),
        refused,
      );
      expect(ran, 0);
      expect(() => family.readAll(client), refused);
      expect(family('ada').state(client)!.dataUpdateCount, 1);
      client.clear();
    });
  });

  // The typed key of an infinite reference writes as the reference does:
  // it knows the two page types, and nothing else of the definition.
  group('the typed key of an infinite query writes under the page types', () {
    test('a reference\'s key rebuilds a narrower value, written or returned',
        () {
      final client = testClient();
      final key = feed().key;
      final written = narrow();

      final stored = key.write(client, written);
      expect(stored, isNot(same(written)));
      expect(stored.runtimeType, typeOf<Feed>());
      expect(stored.pages, written.pages);
      expect(key.read(client), same(stored));
      expect(entry(client, key.rawKey).dataType, typeOf<Feed>());
      expect(() => stored.pages.add(const []), throwsUnsupportedError);

      final replaced = key.update(client, (data) => narrow(2));
      expect(replaced.runtimeType, typeOf<Feed>());
      // What it is for: the cached value takes a page of the declared type.
      final grown = key.update(
        client,
        (data) => data!.copyWith(
          pages: [
            ...data.pages,
            [const Post(3)],
          ],
          pageParams: [...data.pageParams, 3],
        ),
      );
      expect(grown!.pages.last, [const Post(3)]);
      client.clear();
    });

    test('an exact value is stored as it is, and an equal one is shared', () {
      final client = testClient();
      final key = feed().key;
      final value = exact();
      expect(key.write(client, value), same(value));
      // Rebuilding is what lets sharing work: an equal narrower write
      // keeps the cached instance, as through the reference.
      final first = key.write(client, narrow());
      expect(key.write(client, narrow()), same(first));
      client.clear();
    });

    test('a family\'s reference, and the keys readAll and updateAll return',
        () {
      final client = testClient();
      final family = byAuthor();
      expect(
        family('ada').key.write(client, narrow(1)).runtimeType,
        typeOf<Feed>(),
      );
      family('bob').write(client, exact(2));

      final snapshot = family.readAll(client);
      final updated = family.updateAll(client, (data) => narrow(10));
      for (final (key, data) in updated) {
        expect(data.runtimeType, typeOf<Feed>());
        expect(key.write(client, narrow(11)).runtimeType, typeOf<Feed>());
        expect(
          key.update(client, (data) => narrow(12)).runtimeType,
          typeOf<Feed>(),
        );
      }
      // The restore: the snapshot's keys, written what they were read with
      // and, to show the key and not the value does it, a narrower copy.
      for (final (key, data) in snapshot) {
        final restored = key.write(
          client,
          InfiniteData<List<Pinned>, int>(
            pages: [
              [for (final post in data!.pages.single) Pinned(post.id)],
            ],
            pageParams: data.pageParams,
          ),
        );
        expect(restored.runtimeType, typeOf<Feed>());
      }
      expect(family('ada').read(client)!.pages, [
        [const Pinned(1)],
      ]);
      expect(family('bob').read(client)!.pages, [
        [const Pinned(2)],
      ]);
      client.clear();
    });

    test('an entry it creates is bare: no hook, no seed of the definition\'s',
        () {
      final client = testClient();
      var shared = 0;
      var configured = 0;
      final definition = feed(
        configure: (base) {
          configured++;
          return base.copyWith(
            structuralSharing: (previous, next) {
              shared++;
              return next;
            },
            initialData: InitialData.value(exact(9)),
            gcTime: GcTime.never,
          );
        },
      );
      definition.key.write(client, exact(1));
      definition.key.write(client, exact(2));
      expect(configured, 0);
      expect(shared, 0);
      final made = entry(client, definition.key.rawKey);
      expect(made.dataType, typeOf<Feed>());
      expect(made.gcTime, GcTime.defaultValue);
      expect(made.resetState.hasData, isFalse);

      // The control: the reference's write makes it with the definition's.
      definition.remove(client);
      definition.write(client, exact(1));
      definition.write(client, exact(2));
      expect(configured, 1);
      expect(shared, 2);
      expect(entry(client, definition.key.rawKey).gcTime, GcTime.never);
      client.clear();
    });

    test('over an entry of narrower page types it throws, nothing written', () {
      final client = testClient();
      final key = feed().key;
      client.setQueryData(key.rawKey, narrow());
      final refused = throwsA(
        dataTypeError(
          key.rawKey,
          typeOf<Feed>(),
          typeOf<InfiniteData<List<Pinned>, int>>(),
        ),
      );
      expect(() => key.write(client, exact()), refused);
      expect(() => key.update(client, (data) => exact()), refused);
      expect(entry(client, key.rawKey).state.dataUpdateCount, 1);
      client.clear();
    });

    // What the key carries is not part of what it is: the cache compares
    // raw keys, and a typed key adds the data type and nothing more.
    test(
        'a plain definition\'s key of the same InfiniteData type is equal, '
        'and stores a narrower value as it is', () {
      final client = testClient();
      final plain = QueryDefinition<Feed>(namespace: posts, name: 'feed').key;
      final infinite = feed().key;
      expect(plain, infinite);
      expect(infinite, plain);
      expect(plain.hashCode, infinite.hashCode);
      expect(<Object>{plain, infinite}, hasLength(1));
      expect(plain.toString(), infinite.toString());

      // The plain definition's key has one type, the whole value's.
      final asIs = plain.write(client, narrow());
      expect(asIs.runtimeType, typeOf<InfiniteData<List<Pinned>, int>>());
      // The infinite definition's key, over the same entry, rebuilds.
      final rebuilt = infinite.write(client, narrow(2));
      expect(rebuilt.runtimeType, typeOf<Feed>());
      client.clear();
    });

    test('through a widened key a wrong value is refused, nothing written', () {
      final client = testClient();
      final TypedQueryKey<Object?> wide = feed().key;
      final refused = throwsA(
        anyOf(isA<TypeError>(), isA<QueryDataTypeError>()),
      );
      expect(
        () => wide.write(
          client,
          InfiniteData<String, String>(pages: ['a'], pageParams: ['b']),
        ),
        refused,
      );
      expect(() => wide.update(client, (data) => const [Post(1)]), refused);
      expect(client.queryCache.findAll(), isEmpty);
      client.clear();
    });
  });

  group('a plain and an infinite definition on one key', () {
    test('of different data types: the cache\'s own type error', () {
      final client = testClient();
      final plain = QueryDefinition<List<Post>>(namespace: posts, name: 'feed');
      final definition = feed();
      plain.write(client, const [Post(1)]);
      expect(
        () => definition.read(client),
        throwsA(
          dataTypeError(
            definition.key.rawKey,
            typeOf<Feed>(),
            typeOf<List<Post>>(),
          ),
        ),
      );
      expect(
        () => definition.write(client, exact()),
        throwsA(
          dataTypeError(
            definition.key.rawKey,
            typeOf<Feed>(),
            typeOf<List<Post>>(),
          ),
        ),
      );
      client.clear();
    });

    test('of the same InfiniteData type: one entry, and nothing reports it',
        () {
      final client = testClient();
      final plain = QueryDefinition<Feed>(namespace: posts, name: 'feed');
      final definition = feed();
      final written = plain.write(client, exact());
      expect(definition.read(client), same(written));
      expect(plain, isNot(definition));
      client.clear();
    });

    // Holding a written value to the declared page types is what an
    // infinite definition does, because it has the two page types to
    // rebuild from. A plain definition has one type, `T`, and stores what
    // it is given: one typed `InfiniteData` is outside that promise.
    test(
        'a plain definition typed InfiniteData stores a narrower value as '
        'it is (S0-3)', () {
      final client = testClient();
      final plain = QueryDefinition<Feed>(namespace: posts, name: 'feed');
      final written = plain.write(client, narrow());

      // The entry has the declared type; the value in it has its own.
      expect(entry(client, plain.key.rawKey).dataType, typeOf<Feed>());
      expect(written, same(plain.read(client)));
      expect(
        written.runtimeType,
        typeOf<InfiniteData<List<Pinned>, int>>(),
      );
      // What that costs: a page of the declared type does not fit. (The
      // check is the language's; a build that compiles such checks out
      // lets the call through, which the fixture runner records.)
      expect(
        () => plain.read(client)!.copyWith(
          pages: [
            [const Post(2)],
          ],
        ),
        throwsA(isA<TypeError>()),
      );
      // The infinite definition on the same key reads the same entry, and
      // gets the value as it was stored.
      expect(feed().read(client), same(written));
      expect(
        feed().read(client).runtimeType,
        typeOf<InfiniteData<List<Pinned>, int>>(),
      );
      client.clear();
    });

    // The control: the same value through the infinite definition.
    test('the same value written through the infinite definition is rebuilt',
        () {
      final client = testClient();
      final plain = QueryDefinition<Feed>(namespace: posts, name: 'feed');
      final written = feed().write(client, narrow());
      expect(written.runtimeType, typeOf<Feed>());
      expect(plain.read(client), same(written));
      expect(
        plain.read(client)!.copyWith(
          pages: [
            [const Post(2)],
          ],
        ).pages,
        [
          [const Post(2)],
        ],
      );
      client.clear();
    });
  });

  group('the targets and the checks', () {
    test('an infinite reference is exact, its family a prefix', () async {
      final client = testClient();
      final family = byAuthor();
      family('ada').write(client, exact(1));
      family('bob').write(client, exact(2));
      feed().write(client, exact(3));

      expect(family('ada').filters().exact, isTrue);
      expect(family.filters().exact, isFalse);
      expect(family.filters().queryKey, family.rawKey);
      expect(
          client.queryCache.findAll(filters: family.filters()), hasLength(2));

      await family('ada').invalidate(client);
      expect(family('ada').state(client)!.isInvalidated, isTrue);
      expect(family('bob').state(client)!.isInvalidated, isFalse);

      family.remove(client);
      expect(family('ada').state(client), isNull);
      expect(family('bob').state(client), isNull);
      expect(feed().state(client), isNotNull);
      posts.remove(client);
      expect(client.queryCache.findAll(), isEmpty);
    });

    test('through a widened family a wrong input or result is refused', () {
      final client = testClient();
      final family = byAuthor();
      family('ada').write(client, exact());
      final InfiniteQueryFamily<Object?, Object?, Object?> wide = family;
      final refused = throwsA(
        anyOf(
          isA<TypeError>(),
          isA<QueryDataTypeError>(),
          isA<ArgumentError>(),
        ),
      );
      expect(() => wide(42), refused);
      expect(
        () => wide.updateAll(
          client,
          (data) => InfiniteData<Object?, Object?>(
            pages: const ['not a page'],
            pageParams: const ['not a param'],
          ),
        ),
        refused,
      );
      final QueryEntryRef<Object?> wideRef = family('ada');
      expect(() => wideRef.write(client, 'not pages'), refused);
      expect(family('ada').state(client)!.dataUpdateCount, 1);
      client.clear();
    });

    test('a top type as a type argument is refused in a debug build', () {
      void refused(Object? Function() declare, List<String> message) {
        if (!assertionsOn) {
          expect(declare(), isNotNull);
          return;
        }
        expect(
          declare,
          throwsA(
            isA<AssertionError>().having(
              (error) => '${error.message}',
              'message',
              allOf([for (final part in message) contains(part)]),
            ),
          ),
        );
      }

      refused(
        () => InfiniteQueryDefinition<dynamic, int>(
          namespace: posts,
          name: 'x',
          pageFn: (context) => null,
          initialPageParam: 0,
          getNextPageParam: (page, pages, pageParam, pageParams) => null,
        ),
        ['InfiniteQueryDefinition', 'the type argument TPageData', 'dynamic'],
      );
      refused(
        () => InfiniteQueryDefinition<List<Post>, Object?>(
          namespace: posts,
          name: 'x',
          pageFn: (context) => const [],
          initialPageParam: 0,
          getNextPageParam: (page, pages, pageParam, pageParams) => null,
        ),
        ['InfiniteQueryDefinition', 'the type argument TPageParam', 'Object?'],
      );
      refused(
        () => InfiniteQueryFamily<Object?, List<Post>, int>(
          namespace: posts,
          name: 'x',
          pageFn: (input, context) => const [],
          initialPageParam: (input) => 0,
          getNextPageParam: (input, page, pages, pageParam, pageParams) => null,
        ),
        ['InfiniteQueryFamily', 'the type argument TInput', 'Object?'],
      );
      refused(
        () => InfiniteQueryFamily<String, dynamic, int>(
          namespace: posts,
          name: 'x',
          pageFn: (input, context) => null,
          initialPageParam: (input) => 0,
          getNextPageParam: (input, page, pages, pageParam, pageParams) => null,
        ),
        ['InfiniteQueryFamily', 'the type argument TPageData', 'dynamic'],
      );
      refused(
        () => InfiniteQueryFamily<String, List<Post>, dynamic>(
          namespace: posts,
          name: 'x',
          pageFn: (input, context) => const [],
          initialPageParam: (input) => 0,
          getNextPageParam: (input, page, pages, pageParam, pageParams) => null,
        ),
        ['InfiniteQueryFamily', 'the type argument TPageParam', 'dynamic'],
      );
    });
  });
}
