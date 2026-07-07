import 'dart:async';

import '../../core/result.dart';
import '../../domain/entities/launch_entry.dart';
import '../../domain/entities/run_session.dart';
import '../../domain/entities/session_event.dart';
import '../../domain/failures/session_failure.dart';
import '../../domain/params/reload_params.dart';
import '../../domain/params/session_params.dart';
import '../../domain/repositories/session_repository.dart';
import '../datasources/app_session.dart';
import '../services/session_event_mapper.dart';

/// Spawns an [AppRunSession]. Injectable so tests can substitute a fake
/// process; defaults to [AppRunSession.start].
typedef AppRunSessionStarter =
    Future<AppRunSession> Function({
      required String projectRoot,
      required LaunchEntryEntity entry,
      required String deviceId,
    });

/// Owns every live `flutter run` session, keyed by the caller-assigned
/// session id (the run tab id). Presentation receives only the domain
/// [RunSession] handle; the raw [AppRunSession] never leaves this layer.
///
/// Lifecycle: [start] registers a session; [stop]/[detach] release its id;
/// a process exit emits [SessionExited], closes the handle's event stream,
/// and evicts the id so late operations fail with "No session for tab N".
class SessionRepositoryImpl implements SessionRepository {
  SessionRepositoryImpl({AppRunSessionStarter? starter})
    : _starter = starter ?? AppRunSession.start;

  final AppRunSessionStarter _starter;
  final Map<int, _RunSessionHandle> _sessions = <int, _RunSessionHandle>{};

  @override
  Future<Result<SessionFailure, RunSession>> start(
    SessionStartParams params,
  ) async {
    final AppRunSession inner;
    try {
      inner = await _starter(
        projectRoot: params.projectRoot,
        entry: params.entry,
        deviceId: params.deviceId,
      );
    } catch (e, st) {
      return Result.failure(
        SessionFailure(message: e.toString(), cause: e, stackTrace: st),
      );
    }
    late final _RunSessionHandle handle;
    handle = _RunSessionHandle(
      id: params.sessionId,
      inner: inner,
      spawnDiagnostic: AppRunSession.lastSpawnDiagnostic,
      onExit: () {
        // Only evict if this handle still owns the id — a rerun may have
        // registered a newer session under the same tab id.
        if (identical(_sessions[params.sessionId], handle)) {
          _sessions.remove(params.sessionId);
        }
      },
    );
    _sessions[params.sessionId] = handle;
    return Result.success(handle);
  }

  @override
  Future<Result<SessionFailure, void>> hotReload(ReloadParams params) =>
      _run(params.tabId, (s) => s.hotReload());

  @override
  Future<Result<SessionFailure, void>> hotRestart(ReloadParams params) =>
      _run(params.tabId, (s) => s.hotRestart());

  @override
  Future<Result<SessionFailure, void>> stop(ReloadParams params) =>
      _release(params.tabId, (s) => s.stop());

  @override
  Future<Result<SessionFailure, void>> detach(ReloadParams params) =>
      _release(params.tabId, (s) => s.detach());

  Future<Result<SessionFailure, void>> _run(
    int tabId,
    Future<void> Function(AppRunSession session) action,
  ) async {
    final handle = _sessions[tabId];
    if (handle == null) return _noSession(tabId);
    return _guard(() => action(handle._inner));
  }

  /// Like [_run], but the id is released up front — stop/detach end the
  /// session even when the underlying request errors.
  Future<Result<SessionFailure, void>> _release(
    int tabId,
    Future<void> Function(AppRunSession session) action,
  ) async {
    final handle = _sessions.remove(tabId);
    if (handle == null) return _noSession(tabId);
    return _guard(() => action(handle._inner));
  }

  Result<SessionFailure, void> _noSession(int tabId) =>
      Result.failure(SessionFailure(message: 'No session for tab $tabId'));

  Future<Result<SessionFailure, void>> _guard(
    Future<void> Function() action,
  ) async {
    try {
      await action();
      return Result.success(null);
    } catch (e, st) {
      return Result.failure(
        SessionFailure(message: e.toString(), cause: e, stackTrace: st),
      );
    }
  }
}

class _RunSessionHandle implements RunSession {
  _RunSessionHandle({
    required this.id,
    required AppRunSession inner,
    required this.spawnDiagnostic,
    required void Function() onExit,
  }) : _inner = inner {
    _sub = inner.events.listen((e) => _events.add(mapDaemonEvent(e)));
    unawaited(
      inner.exitCode.then((code) async {
        await _sub?.cancel();
        _sub = null;
        if (!_events.isClosed) {
          _events.add(SessionExited(code));
          await _events.close();
        }
        onExit();
      }),
    );
  }

  @override
  final int id;

  @override
  final String? spawnDiagnostic;

  final AppRunSession _inner;
  final StreamController<SessionEvent> _events =
      StreamController<SessionEvent>.broadcast();
  StreamSubscription<Object?>? _sub;

  @override
  String? get appId => _inner.appId;

  @override
  String? get vmServiceUri => _inner.vmServiceUri;

  @override
  bool get canHotReload => _inner.appId != null && _inner.started;

  @override
  Stream<SessionEvent> get events => _events.stream;

  @override
  Future<Object?> callServiceExtension(
    String method, [
    Map<String, Object?> params = const <String, Object?>{},
  ]) => _inner.callServiceExtension(method, params);
}
