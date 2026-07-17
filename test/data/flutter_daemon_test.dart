import 'package:frun/src/data/datasources/flutter_daemon.dart';
import 'package:frun/src/data/models/daemon_messages.dart';
import 'package:test/test.dart';

import 'fake_process.dart';

void main() {
  late FakeProcess process;
  late FlutterDaemon daemon;

  setUp(() {
    process = FakeProcess();
    daemon = FlutterDaemon.forTesting(process);
  });

  test('request resolves with the matching response id', () async {
    final future = daemon.request('device.enable');
    await pumpEventQueue();

    expect(process.requestMethod(0), 'device.enable');
    process.writeRpc({'id': process.requestId(0), 'result': 'ok'});

    expect(await future, 'ok');
  });

  test('responses match by id, not order', () async {
    final first = daemon.request('a');
    final second = daemon.request('b');
    await pumpEventQueue();

    process.writeRpc({'id': process.requestId(1), 'result': 'second'});
    process.writeRpc({'id': process.requestId(0), 'result': 'first'});

    expect(await second, 'second');
    expect(await first, 'first');
  });

  test('an error response throws DaemonRequestException', () async {
    final future = daemon.request('device.enable');
    await pumpEventQueue();

    process.writeRpc({'id': process.requestId(0), 'error': 'boom'});

    await expectLater(future, throwsA(isA<DaemonRequestException>()));
  });

  test('event messages surface on the events stream', () async {
    final events = <DaemonEvent>[];
    daemon.events.listen(events.add);

    process.writeRpc({
      'event': 'device.added',
      'params': {'id': 'mac', 'name': 'macOS'},
    });
    await pumpEventQueue();

    expect(events, hasLength(1));
    expect(events.single.name, 'device.added');
    expect(events.single.params['id'], 'mac');
  });

  test('banners and junk JSON are ignored', () async {
    final events = <DaemonEvent>[];
    daemon.events.listen(events.add);

    process.emitStdout('Welcome to Flutter!');
    process.emitStdout('[not json');
    process.emitStdout('[]');
    process.emitStdout('[42]');
    await pumpEventQueue();

    expect(events, isEmpty);
  });

  test('stderr lines surface on stderrLines', () async {
    final lines = <String>[];
    daemon.stderrLines.listen(lines.add);

    process.emitStderr('something scary');
    await pumpEventQueue();

    expect(lines, ['something scary']);
  });

  test('process exit fails pending requests and fast-fails new ones', () async {
    final pending = expectLater(
      daemon.request('device.getDevices'),
      throwsStateError,
    );
    await pumpEventQueue();

    await process.exit(1);
    await pumpEventQueue();

    await pending;
    await expectLater(daemon.request('device.enable'), throwsStateError);
  });

  test('getDevices maps JSON and tolerates a non-list result', () async {
    final future = daemon.getDevices();
    await pumpEventQueue();
    process.writeRpc({
      'id': process.requestId(0),
      'result': [
        {'id': 'pixel', 'name': 'Pixel 9', 'platform': 'android-arm64'},
      ],
    });
    final devices = await future;
    expect(devices.single.id, 'pixel');
    expect(devices.single.name, 'Pixel 9');

    final other = daemon.getDevices();
    await pumpEventQueue();
    process.writeRpc({'id': process.requestId(1), 'result': 'garbage'});
    expect(await other, isEmpty);
  });

  test('getEmulators maps JSON', () async {
    final future = daemon.getEmulators();
    await pumpEventQueue();
    process.writeRpc({
      'id': process.requestId(0),
      'result': [
        {'id': 'pixel_api_35', 'name': 'Pixel API 35'},
      ],
    });
    final emulators = await future;
    expect(emulators.single.id, 'pixel_api_35');
  });

  test('shutdown kills the process and closes both streams', () async {
    final eventsDone = expectLater(daemon.events, emitsDone);
    final stderrDone = expectLater(daemon.stderrLines, emitsDone);

    final shutdown = daemon.shutdown();
    await pumpEventQueue();
    process.writeRpc({'id': process.requestId(0), 'result': null});
    await shutdown;

    expect(process.killed, isTrue);
    await eventsDone;
    await stderrDone;
  });

  test('shutdown tolerates a daemon that is already dead', () async {
    await process.exit(0);
    await pumpEventQueue();

    await daemon.shutdown();
    expect(process.killed, isTrue);
  });

  test('a broken stdin pipe fails the request, not the process', () async {
    process.stdinSink.throwOnWrite = true;

    await expectLater(daemon.request('device.enable'), throwsStateError);
  });
}
