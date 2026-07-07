import 'dart:async';

import 'package:frun/src/core/result.dart';
import 'package:frun/src/data/datasources/app_session.dart';
import 'package:frun/src/data/models/daemon_messages.dart';
import 'package:frun/src/data/repositories/session_repository_impl.dart';
import 'package:frun/src/domain/entities/launch_entry.dart';
import 'package:frun/src/domain/entities/session_event.dart';
import 'package:frun/src/domain/failures/session_failure.dart';
import 'package:frun/src/domain/params/reload_params.dart';
import 'package:frun/src/domain/params/session_params.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAppRunSession extends Mock implements AppRunSession {}

const _entry = LaunchEntryEntity(name: 'app', program: 'lib/main.dart');

SessionStartParams _params({int sessionId = 1}) => SessionStartParams(
  sessionId: sessionId,
  projectRoot: '/proj',
  entry: _entry,
  deviceId: 'device-1',
);

void main() {
  late MockAppRunSession inner;
  late StreamController<DaemonEvent> events;
  late Completer<int> exitCode;
  late SessionRepositoryImpl repo;

  setUp(() {
    inner = MockAppRunSession();
    events = StreamController<DaemonEvent>.broadcast();
    exitCode = Completer<int>();
    when(() => inner.events).thenAnswer((_) => events.stream);
    when(() => inner.exitCode).thenAnswer((_) => exitCode.future);
    repo = SessionRepositoryImpl(
      starter:
          ({
            required String projectRoot,
            required LaunchEntryEntity entry,
            required String deviceId,
          }) async => inner,
    );
  });

  tearDown(() async {
    await events.close();
  });

  test(
    'start registers the session and exposes a mapped event stream',
    () async {
      final result = await repo.start(_params());
      expect(result.isSuccess, isTrue);
      final session = result.fold((f) => fail(f.message), (s) => s);
      expect(session.id, 1);

      final seen = <SessionEvent>[];
      session.events.listen(seen.add);
      events.add(
        const DaemonEvent(name: 'app.start', params: {'appId': 'a-1'}),
      );
      await pumpEventQueue();

      expect(seen.single, isA<SessionStarted>());
      expect((seen.single as SessionStarted).appId, 'a-1');
    },
  );

  test('canHotReload requires both an appId and app.started', () async {
    when(() => inner.appId).thenReturn(null);
    when(() => inner.started).thenReturn(false);
    final session = (await repo.start(
      _params(),
    )).fold((f) => fail(f.message), (s) => s);
    expect(session.canHotReload, isFalse);

    // app.start arrived (appId in hand) but the build/install is still
    // running — auto-reload must stay gated.
    when(() => inner.appId).thenReturn('a-1');
    expect(session.canHotReload, isFalse);

    when(() => inner.started).thenReturn(true);
    expect(session.canHotReload, isTrue);
  });

  test('hotReload delegates to the registered session', () async {
    when(() => inner.hotReload()).thenAnswer((_) async {});
    await repo.start(_params());

    final result = await repo.hotReload(const ReloadParams(tabId: 1));
    expect(result.isSuccess, isTrue);
    verify(() => inner.hotReload()).called(1);
  });

  test('operations on an unknown id fail with a SessionFailure', () async {
    final result = await repo.hotReload(const ReloadParams(tabId: 99));
    expect(result.isFailure, isTrue);
    expect(
      (result as Failure).error,
      isA<SessionFailure>().having(
        (f) => f.message,
        'message',
        'No session for tab 99',
      ),
    );
  });

  test('stop calls inner.stop and releases the id', () async {
    when(() => inner.stop()).thenAnswer((_) async {});
    await repo.start(_params());

    expect((await repo.stop(const ReloadParams(tabId: 1))).isSuccess, isTrue);
    verify(() => inner.stop()).called(1);

    final again = await repo.hotReload(const ReloadParams(tabId: 1));
    expect(again.isFailure, isTrue);
  });

  test('detach calls inner.detach (not stop) and releases the id', () async {
    when(() => inner.detach()).thenAnswer((_) async {});
    await repo.start(_params());

    expect((await repo.detach(const ReloadParams(tabId: 1))).isSuccess, isTrue);
    verify(() => inner.detach()).called(1);
    verifyNever(() => inner.stop());

    final again = await repo.stop(const ReloadParams(tabId: 1));
    expect(again.isFailure, isTrue);
  });

  test(
    'process exit emits SessionExited, closes the stream, evicts the id',
    () async {
      final session = (await repo.start(
        _params(),
      )).fold((f) => fail(f.message), (s) => s);
      final seen = <SessionEvent>[];
      var closed = false;
      session.events.listen(seen.add, onDone: () => closed = true);

      exitCode.complete(42);
      await pumpEventQueue();

      expect(seen.single, isA<SessionExited>());
      expect((seen.single as SessionExited).exitCode, 42);
      expect(closed, isTrue);

      final late = await repo.hotReload(const ReloadParams(tabId: 1));
      expect(late.isFailure, isTrue);
    },
  );

  test('start failure propagates as a SessionFailure', () async {
    final failing = SessionRepositoryImpl(
      starter:
          ({
            required String projectRoot,
            required LaunchEntryEntity entry,
            required String deviceId,
          }) async => throw StateError('flutter not on PATH'),
    );

    final result = await failing.start(_params());
    expect(result.isFailure, isTrue);
    expect((result as Failure).error.message, contains('flutter not on PATH'));
  });

  test('a rerun re-registers the same id for a new session', () async {
    when(() => inner.stop()).thenAnswer((_) async {});
    await repo.start(_params());
    await repo.stop(const ReloadParams(tabId: 1));

    final second = MockAppRunSession();
    final secondEvents = StreamController<DaemonEvent>.broadcast();
    addTearDown(secondEvents.close);
    when(() => second.events).thenAnswer((_) => secondEvents.stream);
    when(() => second.exitCode).thenAnswer((_) => Completer<int>().future);
    when(() => second.hotReload()).thenAnswer((_) async {});
    repo = SessionRepositoryImpl(
      starter:
          ({
            required String projectRoot,
            required LaunchEntryEntity entry,
            required String deviceId,
          }) async => second,
    );

    await repo.start(_params());
    final result = await repo.hotReload(const ReloadParams(tabId: 1));
    expect(result.isSuccess, isTrue);
    verify(() => second.hotReload()).called(1);
  });
}
