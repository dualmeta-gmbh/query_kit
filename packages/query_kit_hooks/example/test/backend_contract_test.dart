// The calls the app makes, answered by the in-memory backend and, when
// `HOOKS_EXAMPLE_SERVER` names a running showcase server
// (`http://localhost:5178/api`), by that server too.
//
// One list of cases, two targets: a widget test that passes against the
// in-memory backend says something about the app only while the two answer
// alike, and this file is where they would drift apart. It covers the routes
// the app calls and the faults its tests script, not the server's other
// routes, which the showcase's own contract test covers.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_hooks_example/src/api.dart';
import 'package:query_kit_hooks_example/src/in_memory_backend.dart';
import 'package:query_kit_hooks_example/src/models.dart';

import 'harness.dart';

/// A backend the cases run against: the app's api on it, and the fixture
/// calls a test needs.
abstract class _Target {
  ExampleApi get api;

  /// Back to the seed, with no latency and nothing scripted or logged.
  Future<void> reset();

  /// Refuses the next [count] requests matching [method] and [path].
  /// Called once per case: the server replaces its scripts, the in-memory
  /// backend adds one.
  Future<void> failNext(
    String method,
    String path, {
    int count = 1,
    int status = 500,
    String? message,
  });

  Future<void> setLatency(Duration latency);

  /// The answered requests, oldest first, as `GET /api/posts 200`.
  Future<List<String>> requests();
}

class _InMemory implements _Target {
  late InMemoryBackend _backend;

  @override
  late ExampleApi api;

  @override
  Future<void> reset() async {
    _backend = InMemoryBackend(seed: seed());
    api = ExampleApi.inMemory(_backend);
  }

  @override
  Future<void> failNext(
    String method,
    String path, {
    int count = 1,
    int status = 500,
    String? message,
  }) async =>
      _backend.failNext(
        method,
        path,
        count: count,
        status: status,
        message: message,
      );

  @override
  Future<void> setLatency(Duration latency) async => _backend.latency = latency;

  @override
  Future<List<String>> requests() async => [
        for (final entry in _backend.log)
          '${entry.method} ${entry.path} ${entry.status}',
      ];
}

class _Server implements _Target {
  _Server(this.baseUrl);

  final String baseUrl;
  late String _scenario;
  late Dio _fixture;
  var _run = 0;

  @override
  late ExampleApi api;

  @override
  Future<void> reset() async {
    // A scenario of this run's own, so a second run against the same server
    // does not read the first one's log.
    _scenario =
        'hooks-contract-${pid.toRadixString(36)}-${(_run++).toRadixString(36)}';
    _fixture = Dio(BaseOptions(baseUrl: '$baseUrl/__scenario/$_scenario'));
    api = ExampleApi(baseUrl: baseUrl, scenario: _scenario);
    await _fixture.post<Object?>('/reset');
    await _fixture.post<Object?>('/config', data: {'latency': 0});
  }

  @override
  Future<void> failNext(
    String method,
    String path, {
    int count = 1,
    int status = 500,
    String? message,
  }) =>
      _fixture.post<Object?>('/config', data: {
        'failNext': [
          {
            'method': method,
            'path': path,
            'count': count,
            'status': status,
            if (message != null) 'message': message,
          },
        ],
      });

  @override
  Future<void> setLatency(Duration latency) => _fixture
      .post<Object?>('/config', data: {'latency': latency.inMilliseconds});

  @override
  Future<List<String>> requests() async {
    final log = (await _fixture.get<List<Object?>>('/requests')).data!;
    return [
      for (final entry in log.cast<Map<String, Object?>>())
        '${entry['method']} ${entry['path']} ${entry['status']}',
    ];
  }
}

Matcher _refused(String message) => throwsA(
    isA<BackendException>().having((e) => e.message, 'message', message));

List<Map<String, Object?>> _seedRows(String name) =>
    (seed()[name]! as List<Object?>).cast<Map<String, Object?>>();

/// A post as its fields, to compare with a row of the seed.
Map<String, Object?> _post(Post post) =>
    {'id': post.id, 'title': post.title, 'body': post.body};

/// A comment as its fields, to compare with a row of the seed.
Map<String, Object?> _comment(Comment comment) => {
      'id': comment.id,
      'postId': comment.postId,
      'author': comment.author,
      'text': comment.text,
    };

void main() {
  final posts = _seedRows('posts');
  final comments = _seedRows('comments');
  final todos = [for (final row in _seedRows('todos')) Todo.fromJson(row)];

  void contract(String name, _Target target, {Object? skip}) {
    group(name, skip: skip, () {
      setUp(target.reset);

      test('posts: the seed, every field, in order', () async {
        expect(posts, hasLength(30));
        expect((await target.api.posts()).map(_post), posts);
      });

      test('post: each by id, every field, and a refusal for one not there',
          () async {
        for (final post in posts) {
          expect(_post(await target.api.post(post['id']! as int)), post);
        }
        await expectLater(target.api.post(999), _refused('Post not found'));
      });

      test(
          'comments: every post\'s three from the seed, every field, in '
          'order, and none for a post not there', () async {
        for (final id in [for (final post in posts) post['id']! as int]) {
          final expected = [
            for (final comment in comments)
              if (comment['postId'] == id) comment,
          ];
          expect(expected, hasLength(3));
          expect((await target.api.comments(id)).map(_comment), expected);
        }
        await expectLater(
          target.api.comments(999),
          _refused('Post not found'),
        );
      });

      test('todos: the seed, an add, trimmed, and a refused one', () async {
        expect(todos, const [
          Todo(id: 1, text: 'Update the deploy checklist', done: false),
          Todo(id: 2, text: 'Rename the columns on the board', done: true),
          Todo(id: 3, text: 'Replace the expired API token', done: false),
        ]);
        expect(await target.api.todos(), todos);
        expect(
          await target.api.addTodo('  Write the README  '),
          const Todo(id: 4, text: 'Write the README', done: false),
        );
        await expectLater(
          target.api.addTodo('   '),
          _refused('Field "text" is missing or empty'),
        );
        // What was stored, not only what was answered.
        expect(await target.api.todos(), [
          ...todos,
          const Todo(id: 4, text: 'Write the README', done: false),
        ]);
      });

      test('todos: done both ways, and a refusal for a todo not there',
          () async {
        expect(
          await target.api.setDone(1, done: true),
          const Todo(id: 1, text: 'Update the deploy checklist', done: true),
        );
        expect(
          await target.api.setDone(2, done: false),
          todos[1].copyWith(done: false),
        );
        await expectLater(
          target.api.setDone(999, done: true),
          _refused('Todo not found'),
        );
        expect(await target.api.todos(), [
          todos[0].copyWith(done: true),
          todos[1].copyWith(done: false),
          todos[2],
        ]);
      });

      test('projects: ten at a time from a cursor, a hundred in all', () async {
        // Every field the app reads: the id, and the name it shows.
        Iterable<(int, String)> named(ProjectSlice slice) =>
            slice.items.map((project) => (project.id, project.name));
        Iterable<(int, String)> expected(int from, int count) =>
            List.generate(count, (i) => (from + i, 'Project ${from + i}'));

        expect(seed()['projectCount'], 100);
        final first = await target.api.projects(0);
        expect(named(first), expected(0, 10));
        expect(first.nextId, 10);
        final last = await target.api.projects(90);
        expect(named(last), expected(90, 10));
        expect(last.nextId, isNull);
        final short = await target.api.projects(95);
        expect(named(short), expected(95, 5));
        expect(short.nextId, isNull);
        expect((await target.api.projects(100)).items, isEmpty);
      });

      test('failNext: an exact path, the next requests, then it clears',
          () async {
        await target.failNext('GET', '/api/posts/3', count: 2);
        for (var i = 0; i < 2; i++) {
          await expectLater(
            target.api.post(3),
            _refused('Scripted failure 500'),
          );
        }
        expect(_post(await target.api.post(3)), posts[2]);
        // The path is exact, so a neighbour was never affected.
        expect(
          (await target.api.comments(3)).map(_comment),
          [
            for (final comment in comments)
              if (comment['postId'] == 3) comment,
          ],
        );
      });

      test('failNext: a prefix, its own message, and the method it names',
          () async {
        await target.failNext(
          'PATCH',
          '/api/todos*',
          status: 409,
          message: 'Taken',
        );
        // A read of the same path is the other method.
        expect(await target.api.todos(), todos);
        await expectLater(
          target.api.setDone(1, done: true),
          _refused('Taken'),
        );
        // Refused ahead of the route, so nothing was written.
        expect(await target.api.todos(), todos);
        expect(
          await target.api.setDone(1, done: true),
          todos[0].copyWith(done: true),
        );
        expect(await target.api.todos(), [
          todos[0].copyWith(done: true),
          todos[1],
          todos[2],
        ]);
      });

      test('the log: every answered request with its status', () async {
        await target.failNext('POST', '/api/todos');
        await target.api.posts();
        await expectLater(
          target.api.addTodo('Refused'),
          _refused('Scripted failure 500'),
        );
        await target.api.projects(10);
        await expectLater(target.api.post(999), _refused('Post not found'));
        expect(await target.requests(), [
          'GET /api/posts 200',
          'POST /api/todos 500',
          'GET /api/projects 200',
          'GET /api/posts/999 404',
        ]);
      });

      test('latency: every request waits it out', () async {
        await target.setLatency(const Duration(milliseconds: 200));
        final stopwatch = Stopwatch()..start();
        await target.api.todos();
        expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(180));
      });
    });
  }

  contract('the in-memory backend', _InMemory());

  final server = Platform.environment['HOOKS_EXAMPLE_SERVER'];
  contract(
    'the showcase server',
    _Server(server ?? ''),
    skip: server == null ? 'HOOKS_EXAMPLE_SERVER is not set' : false,
  );
}
