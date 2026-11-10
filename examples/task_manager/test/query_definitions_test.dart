/// The app's query definitions against the keys the app cached under before
/// it had them.
///
/// Declaring a query moves nothing in the cache only if the declared key is
/// the key the app always used. These cases spell the old keys out by hand,
/// once, so that a renamed namespace, a renamed operation or a `keyOf` that
/// stops producing the filters' map fails here rather than as a cold cache
/// after an upgrade. And code that still reaches an entry through the plain
/// client, with a key and a type argument, shares it with the typed one.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';
import 'package:task_manager/src/api.dart';
import 'package:task_manager/src/models.dart';
import 'package:task_manager/src/queries.dart';

import 'fake_backend.dart';

const Task _task = Task(
  id: '1',
  name: 'Draft the changelog',
  priority: Priority.normal,
  project: 'Inbox',
  progress: 0,
  estimate: 1,
  synced: true,
  reminder: false,
  reminderTarget: null,
  reminderPending: false,
);

void main() {
  late QueryClient client;
  late TaskQueries tasks;

  setUp(() {
    client = QueryClient(defaultOptions: appDefaultOptions);
    tasks = TaskQueries(
      TaskApi(
        dio: Dio(BaseOptions(baseUrl: 'http://backend.test/api'))
          ..httpClientAdapter = FakeBackend(),
      ),
    );
  });

  tearDown(() => client.clear());

  group('the declared keys are the keys the app always used', () {
    test('a task', () {
      final task = tasks.byId('1');
      expect(task.key.rawKey, QueryKey(const <Object?>['tasks', 'byId', '1']));
      expect(task.key.dataType, Task);
      expect(task.options().queryKey, task.key.rawKey);
    });

    test('a list: the filters as their JSON map', () {
      const filters = TaskFilters(search: 'Renew', project: 'Admin');
      final list = tasks.list(filters);
      expect(
        list.key.rawKey,
        QueryKey(const <Object?>[
          'tasks',
          'list',
          <String, Object?>{'search': 'Renew', 'project': 'Admin'},
        ]),
      );
      expect(list.key.dataType, TaskListResponse);
      expect(
        tasks.list(TaskFilters.all).key.rawKey,
        QueryKey(const <Object?>[
          'tasks',
          'list',
          <String, Object?>{'search': '', 'project': 'all'},
        ]),
      );
    });

    test('the prefixes the invalidations select', () {
      expect(TaskQueries.namespace.rawKey, QueryKey(const <Object?>['tasks']));
      expect(tasks.list.rawKey, QueryKey(const <Object?>['tasks', 'list']));
      expect(tasks.byId.rawKey, QueryKey(const <Object?>['tasks', 'byId']));
    });

    test('a second instance over another transport addresses the same entry',
        () {
      final other = TaskQueries(TaskApi(baseUrl: 'http://elsewhere.test/api'));
      expect(other.byId('1'), tasks.byId('1'));
      expect(other.byId('1').key, tasks.byId('1').key);
      expect(
        other.list(TaskFilters.all).key,
        tasks.list(TaskFilters.all).key,
      );
    });
  });

  group('a raw consumer and a typed one share an entry', () {
    final rawTaskKey = QueryKey(const <Object?>['tasks', 'byId', '1']);

    test('a raw write is read through the reference', () {
      client.setQueryData<Task>(rawTaskKey, _task);
      expect(tasks.byId('1').read(client), same(_task));
      expect(client.queryCache.findAll(), hasLength(1));
    });

    test('a typed write is read through the raw key', () {
      final renamed = _task.copyWith(name: 'Draft the release notes');
      tasks.byId('1').write(client, renamed);
      expect(client.getQueryData<Task>(rawTaskKey), same(renamed));
      expect(client.queryCache.findAll(), hasLength(1));
    });

    test('a list cached raw seeds a detail, dated from the list', () {
      final updatedAt = DateTime.utc(2026, 1, 2, 3, 4);
      client.setQueryData<TaskListResponse>(
        QueryKey(const <Object?>[
          'tasks',
          'list',
          <String, Object?>{'search': '', 'project': 'all'},
        ]),
        TaskListResponse(
          tasks: const <Task>[_task],
          fetchedAt: updatedAt,
        ),
        updatedAt: updatedAt,
      );

      final seeded = taskQuery(client, tasks, '1');
      expect(seeded.queryKey, rawTaskKey);
      expect(seeded.initialData, isA<InitialDataCompute<Task>>());
      expect(
        (seeded.initialData! as InitialDataCompute<Task>).compute(),
        same(_task),
      );
      expect(seeded.initialDataUpdatedAt, updatedAt);

      // A task no list holds gets the definition's options alone.
      final unseeded = taskQuery(client, tasks, '2');
      expect(unseeded.initialData, isNull);
      expect(unseeded.initialDataUpdatedAt, isNull);
    });

    test('the family selects what the old prefix selected', () {
      client.setQueryData<Task>(rawTaskKey, _task);
      client.setQueryData<TaskListResponse>(
        QueryKey(const <Object?>[
          'tasks',
          'list',
          <String, Object?>{'search': '', 'project': 'all'},
        ]),
        TaskListResponse(tasks: const <Task>[_task], fetchedAt: DateTime(2026)),
      );
      final oldPrefix = QueryFilters(
        queryKey: QueryKey(const <Object?>['tasks', 'list']),
      );
      expect(
        client.queryCache.findAll(filters: tasks.list.filters()),
        client.queryCache.findAll(filters: oldPrefix),
      );
      expect(client.queryCache.findAll(filters: tasks.list.filters()),
          hasLength(1));
      expect(
        client.queryCache.findAll(filters: TaskQueries.namespace.filters()),
        hasLength(2),
      );
    });
  });
}
