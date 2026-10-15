/// The backend without a server: the routes this app calls on
/// `examples/showcase/server/`, answered in this process, wired into dio as
/// an [HttpClientAdapter].
///
/// Two callers. `flutter run` without `--dart-define=BACKEND=…` runs the app
/// against it, so the example works as it comes out of the package archive.
/// And the widget tests drive the real `ExampleApi` against it: its URLs,
/// its JSON, its errors and its cancellation.
///
/// It mirrors the server's answers for these routes, its seed (a copy, in
/// `assets/seed.json`), its latency and its scripted failures.
/// `test/backend_contract_test.dart` runs one list of cases against both;
/// the server's other routes are not mirrored, because nothing here calls
/// them.
///
/// No `dart:io` here: it compiles for the web.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';

/// One answered request, as the server's request log keeps it.
class LoggedRequest {
  const LoggedRequest(this.method, this.path, this.query, this.status);

  final String method;

  /// The full path, `/api/todos/1`.
  final String path;
  final Map<String, String> query;
  final int status;

  @override
  String toString() => '$method $path → $status';
}

class _Script {
  _Script(this.method, this.path, this.count, this.status, this.message);

  final String method;
  final String path;
  int count;
  final int status;
  final String? message;

  bool matches(String method, String path) =>
      count > 0 &&
      this.method == method &&
      (this.path.endsWith('*')
          ? path.startsWith(this.path.substring(0, this.path.length - 1))
          : this.path == path);
}

class _HttpError implements Exception {
  const _HttpError(this.status, this.message);

  final int status;
  final String message;
}

class InMemoryBackend implements HttpClientAdapter {
  /// A backend holding [seed], the decoded `assets/seed.json`, answering
  /// every request after [latency].
  InMemoryBackend(
      {required Map<String, Object?> seed, this.latency = Duration.zero})
      : posts = _rows(seed, 'posts'),
        comments = _rows(seed, 'comments'),
        todos = _rows(seed, 'todos'),
        projectCount = seed['projectCount']! as int {
    _nextTodoId = todos.fold<int>(
            0, (highest, todo) => max(highest, todo['id']! as int)) +
        1;
  }

  /// Applied to every request, as the server's scenario `latency` is.
  Duration latency;

  final List<Map<String, Object?>> posts;
  final List<Map<String, Object?>> comments;
  final List<Map<String, Object?>> todos;
  final int projectCount;

  /// The requests answered so far, oldest first.
  final List<LoggedRequest> log = <LoggedRequest>[];

  final List<_Script> _scripts = <_Script>[];
  final Set<Timer> _timers = <Timer>{};
  late int _nextTodoId;

  static List<Map<String, Object?>> _rows(
    Map<String, Object?> seed,
    String name,
  ) =>
      (seed[name]! as List<Object?>)
          .map((row) => Map<String, Object?>.of(row! as Map<String, Object?>))
          .toList();

  /// Makes the next [count] requests matching [method] and [path] (the full
  /// path, exact, or a prefix when it ends in `*`) answer [status], as the
  /// server's `failNext` does.
  void failNext(
    String method,
    String path, {
    int count = 1,
    int status = 500,
    String? message,
  }) =>
      _scripts.add(_Script(method.toUpperCase(), path, count, status, message));

  /// How many answered requests match [method] and [path], an exact full
  /// path or a pattern on it.
  int count(String method, Pattern path) => log
      .where((entry) =>
          entry.method == method &&
          (path is RegExp ? path.hasMatch(entry.path) : entry.path == path))
      .length;

  Map<String, Object?> _post(String id) =>
      posts.where((post) => post['id'] == int.tryParse(id)).firstOrNull ??
      (throw const _HttpError(404, 'Post not found'));

  Map<String, Object?> _todo(String id) =>
      todos.where((todo) => todo['id'] == int.tryParse(id)).firstOrNull ??
      (throw const _HttpError(404, 'Todo not found'));

  static String _text(Map<String, Object?> body) {
    final text = body['text'];
    if (text is! String || text.trim().isEmpty) {
      throw const _HttpError(400, 'Field "text" is missing or empty');
    }
    return text.trim();
  }

  static int _int(Map<String, String> query, String name, int fallback) =>
      int.tryParse(query[name] ?? '') ?? fallback;

  /// The request body as a map: dio hands an adapter the original object in
  /// `options.data`, or a string when the caller encoded it.
  static Map<String, Object?> _body(RequestOptions options) {
    final data = options.data;
    if (data is Map) {
      return data.cast<String, Object?>();
    }
    if (data is String && data.isNotEmpty) {
      return jsonDecode(data) as Map<String, Object?>;
    }
    return const <String, Object?>{};
  }

  /// The route table, in the order `server/routes.ts` registers these
  /// routes. Each answers a status and a body, or throws an [_HttpError].
  (int, Object?) _route(
    String method,
    String path,
    Map<String, String> query,
    RequestOptions options,
  ) {
    final segments = path.split('/').skip(1).toList();
    switch ((method, segments)) {
      case ('GET', ['posts']):
        return (200, posts);
      case ('GET', ['posts', final id]):
        return (200, _post(id));
      case ('GET', ['posts', final id, 'comments']):
        final post = _post(id);
        return (
          200,
          comments.where((comment) => comment['postId'] == post['id']).toList()
        );
      case ('GET', ['todos']):
        return (200, todos);
      case ('POST', ['todos']):
        final todo = <String, Object?>{
          'id': _nextTodoId++,
          'text': _text(_body(options)),
          'done': false,
        };
        todos.add(todo);
        return (201, todo);
      case ('PATCH', ['todos', final id]):
        final todo = _todo(id);
        final body = _body(options);
        if (body.containsKey('text')) {
          todo['text'] = _text(body);
        }
        if (body.containsKey('done')) {
          if (body['done'] is! bool) {
            throw const _HttpError(400, 'Field "done" is not a boolean');
          }
          todo['done'] = body['done'];
        }
        return (200, todo);
      case ('GET', ['projects']) when query.containsKey('cursor'):
        final cursor = max(0, _int(query, 'cursor', 0));
        final limit = max(1, _int(query, 'limit', 10));
        final ids = List<int>.generate(
            max(0, min(limit, projectCount - cursor)), (i) => cursor + i);
        return (
          200,
          <String, Object?>{
            'items': [
              for (final id in ids)
                <String, Object?>{
                  'id': id,
                  'name': 'Project $id',
                  'fetchedAt': DateTime.now().toUtc().toIso8601String(),
                },
            ],
            'nextId': cursor + limit < projectCount ? cursor + limit : null,
            'previousId': cursor > 0 ? max(0, cursor - limit) : null,
          }
        );
    }
    throw _HttpError(404, 'Unknown route $method /api$path');
  }

  /// Waits [duration] on a timer this backend owns, so [close] can cancel it
  /// and no widget test ends with a pending timer.
  Future<void> _wait(Duration duration) {
    if (duration <= Duration.zero) {
      return Future<void>.value();
    }
    final completer = Completer<void>();
    late final Timer timer;
    timer = Timer(duration, () {
      _timers.remove(timer);
      completer.complete();
    });
    _timers.add(timer);
    return completer.future;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final method = options.method.toUpperCase();
    final path = options.path;
    final fullPath = '/api$path';
    final query = <String, String>{
      for (final entry in options.queryParameters.entries)
        entry.key: '${entry.value}',
    };

    // `cancelFuture` completes when dio's CancelToken is cancelled, which is
    // what a cancelled query does to its request.
    var cancelled = false;
    unawaited(cancelFuture?.then((_) => cancelled = true));

    ResponseBody reply(int status, Object? body) {
      log.add(LoggedRequest(method, fullPath, query, status));
      return ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        },
      );
    }

    // The server's fault chain, in its order: latency, then a scripted
    // failure, then the route.
    await _wait(latency);
    if (cancelled) {
      throw DioException.requestCancelled(
        requestOptions: options,
        reason: 'cancelled',
      );
    }
    final script =
        _scripts.where((entry) => entry.matches(method, fullPath)).firstOrNull;
    if (script != null) {
      script.count -= 1;
      return reply(script.status, <String, Object?>{
        'message': script.message ?? 'Scripted failure ${script.status}',
      });
    }
    try {
      final (status, body) = _route(method, path, query, options);
      return reply(status, body);
    } on _HttpError catch (error) {
      return reply(error.status, <String, Object?>{'message': error.message});
    }
  }

  @override
  void close({bool force = false}) {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
  }
}
