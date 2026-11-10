/// Typed query definitions: a query declared once — its key, its fetch
/// function, its data type — and every read, write and invalidation made
/// through the reference it hands out, with no key and no type argument at
/// the call site.
///
/// Port-specific; upstream's nearest is `queryOptions` and its query-key
/// factories. The screen's posts are a `QueryNamespace`, under which a
/// `QueryDefinition` is the list (`['typed-queries', 'posts', 'list']`) and a
/// `QueryFamily<int, Post>` the details (`[..., 'detail', id]`). Calling the
/// family with an id gives the `QueryRef<Post>` of that id's entry, which is
/// a value: two references to one entry are equal, whichever definition
/// instance made them. The server's time is a definition in a namespace of
/// its own, `['typed-queries', 'server']`, so that something on screen lies
/// outside the posts.
///
/// The reads are `context.query(ref.options())`: the options a reference
/// makes are the plain ones, so every call style takes them. Beside them a
/// `QueryBuilder` reads post 1 with plain options written by hand on the same
/// key — the raw API, untouched, and one entry for both.
///
/// The buttons, one operation each:
///
/// * `Write post 1` — `ref.write`: a value into the entry, typed as the
///   entry is, with no request;
/// * `Update post 2` — `ref.update`: the next value from the cached one;
/// * `Patch every detail` — `family.updateAll`: every cached detail
///   through one function, the list untouched;
/// * `Invalidate post 1`, `Invalidate details`, `Invalidate posts` — the
///   same `invalidate` on a reference (exactly its entry), a family (every
///   detail, not the list) and a namespace (everything under it, not the
///   time beside it).
///
/// Proofs (widget tests in `test/features/typed_queries_test.dart`,
/// end-to-end in `e2e/tests/typed_queries.spec.ts`): on open each entry is
/// fetched once, post 1 by one request for two observers — the typed reader
/// and the raw one — and `readAll=2`, `equalRefs=true`; `Write post 1` shows
/// the written title in both readers with no request; `Update post 2` changes
/// post 2 alone; `Patch every detail` changes both details and leaves the
/// list as it was; `Invalidate post 1` refetches post 1 and nothing else,
/// `Invalidate details` both details and not the list, `Invalidate posts`
/// the list as well and not the time — counted on the strips and in the
/// backend's log; and after the api is replaced above the screen, every next
/// refetch goes to the new one and not to the old.
library;

import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import '../../shared/api.dart';
import '../../shared/chrome.dart';
import '../../shared/controls.dart';
import '../../shared/debug_strip.dart';
import '../../shared/fact_group.dart';
import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';
import '../../shared/models.dart';
import '../../shared/scope.dart';

const Feature typedQueriesFeature = Feature(
  id: 'typed-queries',
  title: 'Typed query definitions',
  summary: 'A query declared once, then read, written and invalidated by '
      'reference.',
);

/// The two posts shown in detail.
const int firstPostId = 1;
const int secondPostId = 2;

/// What `Write post 1` writes.
const String writtenTitle = 'Written through the reference';

/// Long enough that opening the screen twice, or mounting a second reader,
/// does not refetch on its own: every refetch here is one a button asked for.
const StaleTime fresh = StaleTime.duration(Duration(minutes: 5));

/// The screen's posts, declared once with the api they are fetched from.
///
/// A class rather than top-level values, because the fetch functions need
/// the api; the namespace needs nothing and is static.
final class TypedPostQueries {
  TypedPostQueries(this._api);

  final ShowcaseApi _api;

  /// Everything about posts on this screen: the prefix of every key below.
  static final QueryNamespace namespace =
      QueryNamespace(const <Object?>['typed-queries', 'posts']);

  /// The list. Its type argument is written out, as on every definition:
  /// Dart would infer this one from the fetch function, but it says what the
  /// entry holds where the query is declared, and one rule for every
  /// definition is simpler than knowing which ones infer.
  late final list = QueryDefinition<List<Post>>(
    namespace: namespace,
    name: 'list',
    queryFn: (context) => _api.posts(signal: context.signal),
    configure: (base) => base.copyWith(staleTime: fresh),
  );

  /// One post per id: the input type, then the data type. Nothing else
  /// tells Dart the input type; without it, it would be `Object?`.
  late final detail = QueryFamily<int, Post>(
    namespace: namespace,
    name: 'detail',
    queryFn: (id, context) => _api.post(id, signal: context.signal),
    configure: (base, id) => base.copyWith(staleTime: fresh),
  );
}

/// What lies outside the posts: the server's time, in a namespace of its own.
final class TypedServerQueries {
  TypedServerQueries(this._api);

  final ShowcaseApi _api;

  static final QueryNamespace namespace =
      QueryNamespace(const <Object?>['typed-queries', 'server']);

  /// The server's time, its type argument written out like the list's.
  late final time = QueryDefinition<ServerTime>(
    namespace: namespace,
    name: 'time',
    queryFn: (context) => _api.time(signal: context.signal),
    configure: (base) => base.copyWith(staleTime: fresh),
  );
}

/// Post 1 the way the raw API spells it: a key written by hand, the same one
/// the family derives, and plain options with the same freshness.
QueryObserverOptions<Post> rawFirstPostQuery(ShowcaseApi api) =>
    QueryObserverOptions<Post>(
      queryKey: QueryKey(
        const <Object?>['typed-queries', 'posts', 'detail', firstPostId],
      ),
      queryFn: (context) => api.post(firstPostId, signal: context.signal),
      staleTime: fresh,
    );

/// [post] with another title; the body and the id stay.
Post _retitled(Post post, String title) =>
    Post(id: post.id, title: title, body: post.body);

class TypedQueriesScreen extends StatefulWidget {
  const TypedQueriesScreen({super.key});

  @override
  State<TypedQueriesScreen> createState() => _TypedQueriesScreenState();
}

class _TypedQueriesScreenState extends State<TypedQueriesScreen> {
  late final QueryClient _client;

  /// The api the definitions below were declared over.
  late ShowcaseApi _api;

  /// Declared once per api.
  late TypedPostQueries _posts;
  late TypedServerQueries _server;

  @override
  void initState() {
    super.initState();
    // The client lookup does not subscribe: the client is fixed for the life
    // of the app.
    _client = QueryClientProvider.read(context);
  }

  /// The api lookup subscribes, so an api replaced above the screen reaches
  /// it: the definitions are made again over the new one. Their references
  /// are equal to the old ones — the same keys, the same entries — and every
  /// next fetch goes through the new api.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = ShowcaseScope.apiOf(context);
    if (_declared && identical(api, _api)) {
      return;
    }
    _declared = true;
    _api = api;
    _posts = TypedPostQueries(api);
    _server = TypedServerQueries(api);
  }

  bool _declared = false;

  void _write() => _posts.detail(firstPostId).write(
        _client,
        const Post(
          id: firstPostId,
          title: writtenTitle,
          body: 'Written into the cache; the backend still has the old one.',
        ),
      );

  void _update() => _posts.detail(secondPostId).update(
        _client,
        (post) =>
            post == null ? null : _retitled(post, '${post.title} (updated)'),
      );

  void _patchAll() => _posts.detail.updateAll(
        _client,
        (post) =>
            post == null ? null : _retitled(post, '${post.title} (patched)'),
      );

  @override
  Widget build(BuildContext context) {
    final first = context.query(_posts.detail(firstPostId).options());
    final second = context.query(_posts.detail(secondPostId).options());
    final list = context.query(_posts.list.options());
    final time = context.query(_server.time.options());

    // A recreated definition makes an equal reference: the key and the data
    // type are the identity, not the instance.
    final equalRefs = TypedPostQueries(_api).detail(firstPostId) ==
        _posts.detail(firstPostId);

    return FeatureScaffold(
      feature: typedQueriesFeature,
      children: <Widget>[
        SectionCard(
          title: 'Through the references',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Toolbar(
                children: <Widget>[
                  ActionButton(
                    label: 'Write post 1',
                    filled: true,
                    onPressed: _write,
                  ),
                  ActionButton(
                    label: 'Update post 2',
                    filled: true,
                    onPressed: _update,
                  ),
                  ActionButton(
                    label: 'Patch every detail',
                    filled: true,
                    onPressed: _patchAll,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Toolbar(
                children: <Widget>[
                  ActionButton(
                    label: 'Invalidate post 1',
                    onPressed: () =>
                        _posts.detail(firstPostId).invalidate(_client).ignore(),
                  ),
                  ActionButton(
                    label: 'Invalidate details',
                    onPressed: () => _posts.detail.invalidate(_client).ignore(),
                  ),
                  ActionButton(
                    label: 'Invalidate posts',
                    onPressed: () =>
                        TypedPostQueries.namespace.invalidate(_client).ignore(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FactGroup(
                name: 'typed facts',
                dense: true,
                facts: <String>[
                  'readAll=${_posts.detail.readAll(_client).length}',
                  'equalRefs=$equalRefs',
                ],
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'Readers',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _PostFacts(name: 'reader post 1', result: first),
              const SizedBox(height: 8),
              const _RawReader(),
              const SizedBox(height: 8),
              _PostFacts(name: 'reader post 2', result: second),
              const SizedBox(height: 8),
              FactGroup(
                name: 'reader posts',
                dense: true,
                facts: <String>[
                  'status=${list.status.name}',
                  'count=${list.dataOrNull?.length ?? 0}',
                  'first=${list.dataOrNull?.firstOrNull?.title ?? 'none'}',
                ],
              ),
              const SizedBox(height: 8),
              FactGroup(
                name: 'reader time',
                dense: true,
                facts: <String>[
                  'status=${time.status.name}',
                  'serial=${time.dataOrNull?.serial ?? 0}',
                ],
              ),
            ],
          ),
        ),
        QueryDebugStrip(
          queryKey: _posts.detail(firstPostId).key.rawKey,
          label: 'post 1',
        ),
        QueryDebugStrip(
          queryKey: _posts.detail(secondPostId).key.rawKey,
          label: 'post 2',
        ),
        QueryDebugStrip(queryKey: _posts.list.key.rawKey, label: 'posts'),
        QueryDebugStrip(queryKey: _server.time.key.rawKey, label: 'time'),
        const SectionCard(
          title: 'What the types do not cover',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                "Every definition's type arguments are written out, "
                'QueryDefinition<List<Post>> and QueryFamily<int, Post>, '
                'including the ones Dart would infer. It cannot infer them '
                "all: nothing tells it a family's input type, which would be "
                'Object?, and an infinite definition whose paging functions '
                'read the page loses its page type.',
              ),
              SizedBox(height: 8),
              Text(
                'A reference assigned to a wider type, QueryRef<Object?>, '
                'compiles a write of any value. The write is checked when it '
                'runs and refused before anything is written.',
              ),
              SizedBox(height: 8),
              Text(
                'The raw API stays as it was: a plain read on the same key, '
                'like the one above, is a reader of the same entry, and a '
                'write through it is not checked against the definition.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One post's reader, as facts: its state and the title it shows.
class _PostFacts extends StatelessWidget {
  const _PostFacts({required this.name, required this.result});

  final String name;
  final QueryResult<Post> result;

  @override
  Widget build(BuildContext context) => FactGroup(
        name: name,
        dense: true,
        facts: <String>[
          'status=${result.status.name}',
          'title=${result.dataOrNull?.title ?? 'none'}',
        ],
      );
}

/// Post 1 through the raw API: `QueryBuilder` and options written by hand.
class _RawReader extends StatelessWidget {
  const _RawReader();

  @override
  Widget build(BuildContext context) => QueryBuilder<Post>(
        options: rawFirstPostQuery(ShowcaseScope.apiOf(context)),
        builder: (context, post) =>
            _PostFacts(name: 'reader raw post 1', result: post),
      );
}
