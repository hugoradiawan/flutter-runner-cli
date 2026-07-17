import 'package:frun/src/data/datasources/app_session.dart';
import 'package:frun/src/data/models/daemon_messages.dart';
import 'package:test/test.dart';

import 'fake_process.dart';

void main() {
  late FakeProcess process;
  late AppRunSession session;

  setUp(() {
    process = FakeProcess();
    session = AppRunSession.forTesting(process);
  });

  test(
    'app.start / app.started / app.debugPort populate session state',
    () async {
      process.writeRpc({
        'event': 'app.start',
        'params': {'appId': 'app-1', 'deviceId': 'pixel', 'launchMode': 'run'},
      });
      process.writeRpc({
        'event': 'app.debugPort',
        'params': {'wsUri': 'ws://127.0.0.1:1234/ws'},
      });
      process.writeRpc({'event': 'app.started', 'params': <String, Object?>{}});
      await pumpEventQueue();

      expect(session.appId, 'app-1');
      expect(session.deviceId, 'pixel');
      expect(session.launchMode, 'run');
      expect(session.vmServiceUri, 'ws://127.0.0.1:1234/ws');
      expect(session.started, isTrue);
    },
  );

  test('non-RPC stdout chatter becomes app.log events', () async {
    final events = <DaemonEvent>[];
    session.events.listen(events.add);

    process.emitStdout('Launching lib/main.dart on Pixel...');
    await pumpEventQueue();

    expect(events.single.name, 'app.log');
    expect(events.single.params['log'], 'Launching lib/main.dart on Pixel...');
    expect(events.single.params['error'], isNull);
  });

  test('stderr lines become app.log events flagged as errors', () async {
    final events = <DaemonEvent>[];
    session.events.listen(events.add);

    process.emitStderr('Gradle build failed');
    await pumpEventQueue();

    expect(events.single.name, 'app.log');
    expect(events.single.params['error'], isTrue);
  });

  test('stop sends app.stop, kills the process, and closes events', () async {
    process.writeRpc({
      'event': 'app.start',
      'params': {'appId': 'app-1'},
    });
    await pumpEventQueue();

    final eventsDone = expectLater(session.events, emitsThrough(emitsDone));
    final stop = session.stop();
    await pumpEventQueue();

    expect(process.requestMethod(0), 'app.stop');
    process.writeRpc({'id': process.requestId(0), 'result': null});
    await stop;

    expect(process.killed, isTrue);
    await eventsDone;
  });

  test('detach sends app.detach and closes WITHOUT killing', () async {
    process.writeRpc({
      'event': 'app.start',
      'params': {'appId': 'app-1'},
    });
    await pumpEventQueue();

    final detach = session.detach();
    await pumpEventQueue();

    expect(process.requestMethod(0), 'app.detach');
    process.writeRpc({'id': process.requestId(0), 'result': null});
    await detach;

    expect(process.killed, isFalse);
  });

  test('hotReload before app.start throws StateError', () {
    expect(session.hotReload, throwsStateError);
  });

  test('hotReload sends app.restart with fullRestart false', () async {
    process.writeRpc({
      'event': 'app.start',
      'params': {'appId': 'app-1'},
    });
    await pumpEventQueue();

    final reload = session.hotReload();
    await pumpEventQueue();

    expect(process.requestMethod(0), 'app.restart');
    expect(process.stdinSink.lines[0], contains('"fullRestart":false'));
    process.writeRpc({'id': process.requestId(0), 'result': null});
    await reload;
  });

  test(
    'process exit fails pending requests and is a no-op when repeated',
    () async {
      process.writeRpc({
        'event': 'app.start',
        'params': {'appId': 'app-1'},
      });
      await pumpEventQueue();

      final pending = expectLater(session.hotReload(), throwsStateError);
      await pumpEventQueue();

      await process.exit(0);
      await pumpEventQueue();
      await pending;

      // Double-stop after close must be a no-op.
      await session.stop();
      await session.stop();
    },
  );
}
