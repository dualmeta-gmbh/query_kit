/// What the typed samples of the cache guides promise, run.
///
/// The pages say the typed declarations address the same entries as the raw
/// keys beside them, that the rollbacks put back what they say they put
/// back, and that a seed is as old as the list it came from. Each case below
/// is one of those sentences. The mutation recipes are driven through their
/// own callbacks, in the order a mutation runs them, so a failure can be
/// played without a backend that refuses.
library;

import 'package:doc_snippets/c4b_guides.dart' as c4b show DeviceKeys;
import 'package:doc_snippets/c4c_guides.dart'
    show Device, DeviceKeys, settingsKey;
import 'package:doc_snippets/doc_snippets.dart' show Task;
import 'package:doc_snippets/typed_guides.dart';
import 'package:doc_snippets/typed_guides_home.dart' as home;
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

void main() {
  late QueryClient client;

  setUp(() => client = QueryClient());
  tearDown(() => client.clear());

  group('the typed declarations address the raw keys beside them', () {
    test('devices: lists, details and the namespace', () {
      expect(deviceQueries.list('kitchen').key.rawKey,
          DeviceKeys.list(room: 'kitchen'));
      expect(deviceQueries.detail('d1').key.rawKey, DeviceKeys.detail('d1'));
      expect(deviceQueries.list.rawKey, DeviceKeys.lists);
      expect(DeviceQueries.namespace.rawKey, DeviceKeys.all);
    });

    test('settings, pages, the home devices and the JSON family', () {
      expect(notificationSettings.key.rawKey, settingsKey);
      expect(devicePages(3).key.rawKey, c4b.DeviceKeys.page(3));
      expect(
        home.homeDevices('h1').key.rawKey,
        QueryKey(<Object?>['devices', 'home', 'h1']),
      );
      expect(
        roomDevicesJson('kitchen').key.rawKey,
        QueryKey(<Object?>[
          'api',
          '/devices',
          <String, Object?>{'room': 'kitchen'},
        ]),
      );
    });

    test('a home of null is a reference whose query waits', () {
      final options = client.defaultQueryOptions(
        home.homeDevices(null).options(),
      );
      expect(options.enabled, Enabled.no);
      expect(
        client.defaultQueryOptions(home.homeDevices('h1').options()).enabled,
        Enabled.yes,
      );
    });
  });

  group('optimistic updates', () {
    const lamp = Device(id: 'd1', name: 'Lamp', room: 'kitchen', isOn: true);
    const kettle =
        Device(id: 'd2', name: 'Kettle', room: 'kitchen', isOn: true);
    const radio = Device(id: 'd3', name: 'Radio', room: 'hall', isOn: true);

    test('one task: patched, then put back on failure', () async {
      const task = Task(id: '1', name: 'Draft', done: false);
      taskQueries.detail('1').write(client, task);
      final options = renameOptimistically(client, '1');

      final previous = await options.onMutate!('Final');
      expect(taskQueries.detail('1').read(client)?.name, 'Final');

      await options.onError!(
          StateError('refused'), StackTrace.empty, 'Final', previous);
      expect(taskQueries.detail('1').read(client), task);
    });

    test('a whole device: the rollback keeps the old dataUpdatedAt', () async {
      final fetchedAt = DateTime.utc(2026, 1, 1, 12);
      deviceQueries.detail('d1').write(client, lamp, updatedAt: fetchedAt);
      final options = saveDevice(client);
      final edited = lamp.copyWith(isOn: false);

      final snapshot = await options.onMutate!(edited);
      expect(deviceQueries.detail('d1').read(client), edited);

      await options.onError!(
          StateError('refused'), StackTrace.empty, edited, snapshot);
      final state = deviceQueries.detail('d1').state(client)!;
      expect(state.data, lamp);
      expect(state.dataUpdatedAt, fetchedAt);
    });

    test('a whole device that was not cached: the rollback removes it',
        () async {
      final options = saveDevice(client);

      final snapshot = await options.onMutate!(lamp);
      expect(deviceQueries.detail('d1').read(client), lamp);

      await options.onError!(
          StateError('refused'), StackTrace.empty, lamp, snapshot);
      expect(deviceQueries.detail('d1').state(client), isNull);
    });

    test('a room switched off: only what the write changed comes back',
        () async {
      for (final device in [lamp, kettle, radio]) {
        deviceQueries.detail(device.id).write(client, device);
      }
      final options = roomOff(client);

      final switchedOff = await options.onMutate!('kitchen');
      expect(switchedOff, hasLength(2));
      expect(deviceQueries.detail('d1').read(client)?.isOn, isFalse);
      expect(deviceQueries.detail('d2').read(client)?.isOn, isFalse);
      expect(deviceQueries.detail('d3').read(client)?.isOn, isTrue);

      await options.onError!(
          StateError('refused'), StackTrace.empty, 'kitchen', switchedOff);
      expect(deviceQueries.detail('d1').read(client), lamp);
      expect(deviceQueries.detail('d2').read(client), kettle);
      expect(deviceQueries.detail('d3').read(client), radio);
    });

    test('a room switched off: a detail removed meanwhile comes back typed',
        () async {
      deviceQueries.detail('d1').write(client, lamp);
      final options = roomOff(client);

      final switchedOff = await options.onMutate!('kitchen');
      deviceQueries.detail('d1').remove(client);

      await options.onError!(
          StateError('refused'), StackTrace.empty, 'kitchen', switchedOff);
      expect(deviceQueries.detail('d1').read(client), lamp);
    });
  });

  test('a detail seeded from the list is as old as the list', () {
    final listedAt = DateTime.utc(2026, 1, 1, 12);
    const task = Task(id: '7', name: 'Ship', done: false);
    taskQueries.list.write(client, const <Task>[task], updatedAt: listedAt);

    final observer = QueryObserver<Task, Task>(
      client,
      taskSeededFromList(client, '7'),
    );
    addTearDown(observer.destroy);

    final state = taskQueries.detail('7').state(client)!;
    expect(state.data, task);
    expect(state.dataUpdatedAt, listedAt);
  });

  test('the response writes reach the detail and every list that holds it',
      () async {
    const lamp = Device(id: 'd1', name: 'Lamp', room: 'kitchen');
    const radio = Device(id: 'd3', name: 'Radio', room: 'hall');
    deviceQueries.list('kitchen').write(client, const <Device>[lamp]);
    deviceQueries.list('hall').write(client, const <Device>[radio]);
    final hall = deviceQueries.list('hall').read(client);

    final renamed = lamp.copyWith(name: 'Desk lamp');
    await renameDeviceMutation(client, 'd1').onSuccess!(renamed, 'x', null);

    expect(deviceQueries.detail('d1').read(client), renamed);
    expect(deviceQueries.list('kitchen').read(client), <Device>[renamed]);
    expect(identical(deviceQueries.list('hall').read(client), hall), isTrue,
        reason: 'a list without the device is left alone');
  });
}
