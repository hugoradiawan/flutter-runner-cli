import 'dart:async';

import 'package:frun/src/data/datasources/emulator_manager.dart';
import 'package:frun/src/data/datasources/flutter_daemon.dart';
import 'package:frun/src/data/models/daemon_messages.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockFlutterDaemon extends Mock implements FlutterDaemon {}

void main() {
  late MockFlutterDaemon daemon;
  late StreamController<DaemonEvent> events;
  late EmulatorManager manager;

  setUp(() {
    daemon = MockFlutterDaemon();
    events = StreamController<DaemonEvent>.broadcast();
    when(() => daemon.events).thenAnswer((_) => events.stream);
    manager = EmulatorManager(daemon);
  });

  tearDown(() => events.close());

  test('launchAndAwaitDevice resolves with the matching device', () async {
    when(
      () => daemon.launchEmulator('pixel_api_35', coldBoot: false),
    ).thenAnswer((_) async {});

    final future = manager.launchAndAwaitDevice('pixel_api_35');
    await pumpEventQueue();

    // A device from a different emulator must be ignored.
    events.add(
      const DaemonEvent(
        name: 'device.added',
        params: {'id': 'other', 'emulatorId': 'other_avd'},
      ),
    );
    events.add(
      const DaemonEvent(
        name: 'device.added',
        params: {'id': 'emulator-5554', 'emulatorId': 'pixel_api_35'},
      ),
    );

    final device = await future;
    expect(device?.id, 'emulator-5554');
    expect(events.hasListener, isFalse, reason: 'subscription cancelled');
  });

  test('returns null on timeout and cancels its subscription', () async {
    when(
      () => daemon.launchEmulator('slow_avd', coldBoot: false),
    ).thenAnswer((_) async {});

    final device = await manager.launchAndAwaitDevice(
      'slow_avd',
      timeout: const Duration(milliseconds: 1),
    );

    expect(device, isNull);
    expect(events.hasListener, isFalse);
  });

  test('propagates a launch failure and cancels its subscription', () async {
    when(
      () => daemon.launchEmulator('broken_avd', coldBoot: false),
    ).thenThrow(StateError('sdk missing'));

    await expectLater(
      manager.launchAndAwaitDevice('broken_avd'),
      throwsStateError,
    );
    expect(events.hasListener, isFalse);
  });
}
