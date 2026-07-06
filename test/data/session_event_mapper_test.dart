import 'package:frun/src/data/models/daemon_messages.dart';
import 'package:frun/src/data/services/session_event_mapper.dart';
import 'package:frun/src/domain/entities/session_event.dart';
import 'package:test/test.dart';

DaemonEvent _e(String name, [Map<String, Object?> params = const {}]) =>
    DaemonEvent(name: name, params: params);

void main() {
  group('mapDaemonEvent', () {
    test('app.start carries appId/deviceId/launchMode', () {
      final event =
          mapDaemonEvent(
                _e('app.start', {
                  'appId': 'a-1',
                  'deviceId': 'emulator-5554',
                  'launchMode': 'run',
                }),
              )
              as SessionStarted;
      expect(event.appId, 'a-1');
      expect(event.deviceId, 'emulator-5554');
      expect(event.launchMode, 'run');
    });

    test('app.debugPort maps wsUri', () {
      final event =
          mapDaemonEvent(_e('app.debugPort', {'wsUri': 'ws://x/ws'}))
              as SessionDebugPort;
      expect(event.vmServiceUri, 'ws://x/ws');
    });

    test('app.devTools prefers wsUri and falls back to uri', () {
      expect(
        (mapDaemonEvent(_e('app.devTools', {'wsUri': 'http://a'}))
                as SessionDevTools)
            .uri,
        'http://a',
      );
      expect(
        (mapDaemonEvent(_e('app.devTools', {'uri': 'http://b'}))
                as SessionDevTools)
            .uri,
        'http://b',
      );
    });

    test('app.log strips logcat prefixes and keeps error flag', () {
      final event =
          mapDaemonEvent(
                _e('app.log', {
                  'log': 'I/flutter ( 7225): hello',
                  'error': true,
                }),
              )
              as SessionLogLine;
      expect(event.message, 'hello');
      expect(event.isError, isTrue);
    });

    test('app.log strips logcat prefixes on every line of a multiline log', () {
      final event =
          mapDaemonEvent(
                _e('app.log', {
                  'log': 'plain first\nW/System  (  123): tagged second',
                }),
              )
              as SessionLogLine;
      expect(event.message, 'plain first\ntagged second');
    });

    test('app.log keeps untagged short lines untouched', () {
      final event =
          mapDaemonEvent(_e('app.log', {'log': 'ok'})) as SessionLogLine;
      expect(event.message, 'ok');
      expect(event.isError, isFalse);
    });

    test('app.progress maps the message', () {
      final event =
          mapDaemonEvent(_e('app.progress', {'message': 'Compiling…'}))
              as SessionProgress;
      expect(event.message, 'Compiling…');
    });

    test('app.stop carries error and trace', () {
      final event =
          mapDaemonEvent(_e('app.stop', {'error': 'boom', 'trace': 't'}))
              as SessionStopped;
      expect(event.error, 'boom');
      expect(event.trace, 't');
    });

    test('daemon.logMessage maps levels', () {
      SessionLogLevel levelOf(String? level) =>
          (mapDaemonEvent(
                    _e('daemon.logMessage', {'message': 'm', 'level': ?level}),
                  )
                  as SessionDaemonLog)
              .level;
      expect(levelOf('error'), SessionLogLevel.error);
      expect(levelOf('warning'), SessionLogLevel.warning);
      expect(levelOf('status'), SessionLogLevel.status);
      expect(levelOf('info'), SessionLogLevel.info);
      expect(levelOf(null), SessionLogLevel.info);
    });

    test('unknown events pass through name and params', () {
      final event =
          mapDaemonEvent(_e('app.webLaunchUrl', {'url': 'http://x'}))
              as SessionUnknown;
      expect(event.name, 'app.webLaunchUrl');
      expect(event.params, {'url': 'http://x'});
    });
  });
}
