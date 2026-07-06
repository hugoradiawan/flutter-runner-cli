import 'dart:async';
import 'dart:io';

import 'package:frun/src/core/result.dart';
import 'package:frun/src/domain/entities/app_config.dart';
import 'package:frun/src/domain/entities/flutter_project.dart';
import 'package:frun/src/domain/entities/launch_entry.dart';
import 'package:frun/src/domain/entities/run_session.dart';
import 'package:frun/src/domain/entities/session_event.dart';
import 'package:frun/src/domain/failures/session_failure.dart';
import 'package:frun/src/domain/params/reload_params.dart';
import 'package:frun/src/domain/params/session_params.dart';
import 'package:frun/src/domain/ports/notifier.dart';
import 'package:frun/src/domain/repositories/session_repository.dart';
import 'package:frun/src/domain/value_objects/notification_event.dart';
import 'package:frun/src/presentation/app/app_state.dart';
import 'package:frun/src/presentation/di/dependencies.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockSessionRepository extends Mock implements SessionRepository {}

class MockRunSession extends Mock implements RunSession {}

class _FakeSessionStartParams extends Fake implements SessionStartParams {}

class _FakeReloadParams extends Fake implements ReloadParams {}

class _SilentNotifier extends Notifier {
  const _SilentNotifier();

  @override
  void notify(FrunNotifEvent event, {String? label, String? detail}) {}
}

const _entry = LaunchEntryEntity(name: 'app', program: 'lib/main.dart');

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeSessionStartParams());
    registerFallbackValue(_FakeReloadParams());
  });

  late Directory temp;
  late MockSessionRepository sessions;
  late AppState state;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('frun_run_ctrl_');
    sessions = MockSessionRepository();
    // Default stop stub so tearDown's stopAll() always succeeds; individual
    // tests re-stub and verify as needed.
    when(
      () => sessions.stop(any()),
    ).thenAnswer((_) async => Result.success(null));
    final deps = Dependencies(notifier: const _SilentNotifier())
      ..sessionRepository = sessions;
    state = AppState(
      project: FlutterProjectEntity(
        root: temp.path,
        name: 'demo',
        workspaceRoot: temp.path,
        watchRoot: temp.path,
        hasVsCodeFolder: false,
        hasZedFolder: false,
      ),
      config: AppConfigEntity.defaults(),
      deps: deps,
    );
  });

  tearDown(() async {
    await state.runController.stopAll();
    temp.deleteSync(recursive: true);
  });

  MockRunSession sessionWith(StreamController<SessionEvent> events) {
    final session = MockRunSession();
    when(() => session.spawnDiagnostic).thenReturn(null);
    when(() => session.events).thenAnswer((_) => events.stream);
    return session;
  }

  test('startOrFocus adds a tab wired to the session event stream', () async {
    final events = StreamController<SessionEvent>.broadcast();
    addTearDown(events.close);
    final session = sessionWith(events);
    when(
      () => sessions.start(any()),
    ).thenAnswer((_) async => Result.success(session));

    final tab = await state.runController.startOrFocus(
      _entry,
      deviceId: 'device-1',
    );

    expect(tab, isNotNull);
    expect(state.runController.tabs, hasLength(1));
    expect(state.runController.activeTab, same(tab));
    expect(tab!.session, same(session));

    events.add(const SessionLogLine(message: 'hello from app'));
    await pumpEventQueue();
    expect(tab.transcript.lines.map((l) => l.text), contains('hello from app'));

    final captured =
        verify(() => sessions.start(captureAny())).captured.single
            as SessionStartParams;
    expect(captured.sessionId, tab.id);
    expect(captured.deviceId, 'device-1');
  });

  test('a failed launch removes the tab and reports the failure', () async {
    when(() => sessions.start(any())).thenAnswer(
      (_) async =>
          Result.failure(const SessionFailure(message: 'flutter not found')),
    );

    final tab = await state.runController.startOrFocus(
      _entry,
      deviceId: 'device-1',
    );

    expect(tab, isNull);
    expect(state.runController.tabs, isEmpty);
  });

  test('stopActive drives the stop use case and removes the tab', () async {
    final events = StreamController<SessionEvent>.broadcast();
    addTearDown(events.close);
    when(
      () => sessions.start(any()),
    ).thenAnswer((_) async => Result.success(sessionWith(events)));
    when(
      () => sessions.stop(any()),
    ).thenAnswer((_) async => Result.success(null));

    final tab = await state.runController.startOrFocus(
      _entry,
      deviceId: 'device-1',
    );
    await state.runController.stopActive();

    expect(state.runController.tabs, isEmpty);
    final captured =
        verify(() => sessions.stop(captureAny())).captured.single
            as ReloadParams;
    expect(captured.tabId, tab!.id);
  });

  test('detachActive drives the detach use case, not stop', () async {
    final events = StreamController<SessionEvent>.broadcast();
    addTearDown(events.close);
    when(
      () => sessions.start(any()),
    ).thenAnswer((_) async => Result.success(sessionWith(events)));
    when(
      () => sessions.detach(any()),
    ).thenAnswer((_) async => Result.success(null));

    await state.runController.startOrFocus(_entry, deviceId: 'device-1');
    await state.runController.detachActive();

    expect(state.runController.tabs, isEmpty);
    verify(() => sessions.detach(any())).called(1);
    verifyNever(() => sessions.stop(any()));
  });

  test('a SessionExited event clears the tab session in place', () async {
    final events = StreamController<SessionEvent>.broadcast();
    addTearDown(events.close);
    when(
      () => sessions.start(any()),
    ).thenAnswer((_) async => Result.success(sessionWith(events)));

    final tab = await state.runController.startOrFocus(
      _entry,
      deviceId: 'device-1',
    );
    events.add(const SessionExited(9));
    await pumpEventQueue();

    expect(tab!.session, isNull);
    expect(state.runController.tabs, hasLength(1));
    expect(
      tab.transcript.lines.map((l) => l.text),
      contains('flutter run exited (code 9).'),
    );
  });

  test(
    'startOrFocus focuses an existing running tab instead of relaunching',
    () async {
      final events = StreamController<SessionEvent>.broadcast();
      addTearDown(events.close);
      when(
        () => sessions.start(any()),
      ).thenAnswer((_) async => Result.success(sessionWith(events)));

      final first = await state.runController.startOrFocus(
        _entry,
        deviceId: 'device-1',
      );
      final second = await state.runController.startOrFocus(
        _entry,
        deviceId: 'device-1',
      );

      expect(second, same(first));
      expect(state.runController.tabs, hasLength(1));
      verify(() => sessions.start(any())).called(1);
    },
  );
}
