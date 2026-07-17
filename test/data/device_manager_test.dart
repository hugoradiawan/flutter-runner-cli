import 'dart:async';

import 'package:frun/src/data/datasources/device_manager.dart';
import 'package:frun/src/data/datasources/flutter_daemon.dart';
import 'package:frun/src/data/models/daemon_messages.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockFlutterDaemon extends Mock implements FlutterDaemon {}

void main() {
  late MockFlutterDaemon daemon;
  late StreamController<DaemonEvent> events;
  late DeviceManager manager;

  const pixel = FlutterDevice(
    id: 'pixel',
    name: 'Pixel 9',
    platform: 'android-arm64',
    category: 'mobile',
    platformType: 'android',
    ephemeral: true,
    emulator: false,
  );

  setUp(() {
    daemon = MockFlutterDaemon();
    events = StreamController<DaemonEvent>.broadcast();
    when(() => daemon.events).thenAnswer((_) => events.stream);
    when(() => daemon.enableDevicePolling()).thenAnswer((_) async {});
    manager = DeviceManager(daemon);
  });

  tearDown(() => events.close());

  test('start enables polling and seeds from getDevices', () async {
    when(() => daemon.getDevices()).thenAnswer((_) async => [pixel]);

    await manager.start();

    verify(() => daemon.enableDevicePolling()).called(1);
    expect(manager.devices.single.id, 'pixel');
    expect(manager.byId('pixel')?.name, 'Pixel 9');
  });

  test('device.added and device.removed mutate the sorted snapshot', () async {
    when(() => daemon.getDevices()).thenAnswer((_) async => []);
    await manager.start();

    final snapshots = <List<FlutterDevice>>[];
    manager.changes.listen(snapshots.add);

    events.add(
      const DaemonEvent(
        name: 'device.added',
        params: {'id': 'z-mac', 'name': 'zMac'},
      ),
    );
    events.add(
      const DaemonEvent(
        name: 'device.added',
        params: {'id': 'a-linux', 'name': 'aLinux'},
      ),
    );
    await pumpEventQueue();

    expect(manager.devices.map((d) => d.name), ['aLinux', 'zMac']);

    events.add(
      const DaemonEvent(name: 'device.removed', params: {'id': 'z-mac'}),
    );
    await pumpEventQueue();

    expect(manager.devices.map((d) => d.id), ['a-linux']);
    expect(snapshots, hasLength(3));
  });

  test('unrelated events are ignored', () async {
    when(() => daemon.getDevices()).thenAnswer((_) async => []);
    await manager.start();

    events.add(const DaemonEvent(name: 'daemon.logMessage', params: {}));
    await pumpEventQueue();

    expect(manager.devices, isEmpty);
  });

  test('byId(null) returns null', () {
    expect(manager.byId(null), isNull);
  });

  test('dispose cancels the subscription and closes changes', () async {
    when(() => daemon.getDevices()).thenAnswer((_) async => []);
    await manager.start();

    final done = expectLater(manager.changes, emitsThrough(emitsDone));
    await manager.dispose();
    await done;

    // Events after dispose must not throw.
    events.add(const DaemonEvent(name: 'device.added', params: {'id': 'late'}));
    await pumpEventQueue();
  });
}
