/// The calls the app makes, over dio: the client's copy of the routes it
/// uses on `examples/showcase/server/server.ts`.
///
/// Every request carries the scenario id in `x-scenario` when there is one,
/// so the backend keeps a world of this run's own; the end-to-end suites mint
/// one per test. Without a server, the same calls go to
/// `in_memory_backend.dart`, which dio runs in place of the network.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:query_kit_hooks/query_kit_hooks.dart';

import 'in_memory_backend.dart';
import 'models.dart';

/// What the backend said when it refused: its `{ "message": … }`, so a
/// screen shows the backend's sentence and not dio's status-code prose.
class BackendException implements Exception {
  const BackendException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ExampleApi {
  ExampleApi({required String baseUrl, String? scenario})
      : this._(
          Dio(BaseOptions(
            baseUrl: baseUrl,
            // A backend that hangs must fail the query, not leave it
            // fetching forever.
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 30),
          )),
          scenario,
        );

  /// The same calls, answered by [backend] in this process. The base URL is
  /// never resolved, and `.invalid` says so.
  ExampleApi.inMemory(InMemoryBackend backend)
      : this._(
          Dio(BaseOptions(baseUrl: 'http://in-memory.invalid/api'))
            ..httpClientAdapter = backend,
          null,
        );

  ExampleApi._(this._dio, this.scenario) {
    final scenario = this.scenario;
    if (scenario != null) {
      _dio.options.headers['x-scenario'] = scenario;
    }
  }

  final Dio _dio;

  /// The backend world every request of this api is tagged with, if any.
  final String? scenario;

  /// Bridges a query's cancellation to dio's: a query that is cancelled
  /// aborts its request.
  static CancelToken? _bridge(QueryCancelToken? signal) {
    if (signal == null) {
      return null;
    }
    final token = CancelToken();
    signal.onCancel(token.cancel);
    return token;
  }

  Future<List<Post>> posts({QueryCancelToken? signal}) =>
      _list('/posts', Post.fromJson, signal: signal);

  Future<Post> post(int id, {QueryCancelToken? signal}) =>
      _get('/posts/$id', Post.fromJson, signal: signal);

  Future<List<Comment>> comments(int postId, {QueryCancelToken? signal}) =>
      _list('/posts/$postId/comments', Comment.fromJson, signal: signal);

  Future<List<Todo>> todos({QueryCancelToken? signal}) =>
      _list('/todos', Todo.fromJson, signal: signal);

  Future<Todo> addTodo(String text) => _run(
        () => _dio.post<Map<String, Object?>>(
          '/todos',
          data: <String, Object?>{'text': text},
        ),
        Todo.fromJson,
      );

  Future<Todo> setDone(int id, {required bool done}) => _run(
        () => _dio.patch<Map<String, Object?>>(
          '/todos/$id',
          data: <String, Object?>{'done': done},
        ),
        Todo.fromJson,
      );

  Future<ProjectSlice> projects(
    int cursor, {
    int limit = 10,
    QueryCancelToken? signal,
  }) =>
      _get(
        '/projects',
        ProjectSlice.fromJson,
        query: <String, Object?>{'cursor': cursor, 'limit': limit},
        signal: signal,
      );

  Future<T> _get<T>(
    String path,
    T Function(Map<String, Object?> json) parse, {
    Map<String, Object?> query = const <String, Object?>{},
    QueryCancelToken? signal,
  }) =>
      _run(
        () => _dio.get<Map<String, Object?>>(
          path,
          queryParameters: query,
          cancelToken: _bridge(signal),
        ),
        parse,
      );

  Future<List<T>> _list<T>(
    String path,
    T Function(Map<String, Object?> json) parse, {
    QueryCancelToken? signal,
  }) =>
      _run(
        () => _dio.get<List<Object?>>(path, cancelToken: _bridge(signal)),
        (items) =>
            items.map((item) => parse(item! as Map<String, Object?>)).toList(),
      );

  /// Every failure leaves here as a [BackendException] with a sentence a
  /// user can read, except a cancellation, which is the library's business.
  Future<T> _run<R, T>(
    Future<Response<R>> Function() request,
    T Function(R data) parse,
  ) async {
    final Response<R> response;
    try {
      response = await request();
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) {
        rethrow;
      }
      throw BackendException(
        _messageFrom(error.response?.data) ?? 'The backend is unreachable',
      );
    }
    try {
      return parse(response.data as R);
    } on Object {
      throw const BackendException('Unexpected response from the backend');
    }
  }

  /// The backend's `{ "message": … }`, parsed or as raw text, depending on
  /// the content type dio saw.
  static String? _messageFrom(Object? data) {
    Object? decoded = data;
    if (data is String) {
      try {
        decoded = jsonDecode(data);
      } on FormatException {
        return null;
      }
    }
    return decoded is Map && decoded['message'] is String
        ? decoded['message'] as String
        : null;
  }
}
