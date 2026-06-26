import '../../core/result.dart';
import '../../domain/failures/session_failure.dart';
import '../../domain/params/reload_params.dart';
import '../../domain/repositories/session_repository.dart';
import '../datasources/app_session.dart';

/// Maps the domain session operations onto the live [AppRunSession] objects.
///
/// Sessions are owned by the presentation layer's run controller (it needs the
/// live object for per-tab event/log wiring), and looked up by tab id through
/// [sessionLookup]. This repository is the domain-facing control surface for
/// the reload / restart / stop operations.
class SessionRepositoryImpl implements SessionRepository {
  SessionRepositoryImpl({
    required AppRunSession? Function(int tabId) sessionLookup,
  }) : _lookup = sessionLookup;

  final AppRunSession? Function(int tabId) _lookup;

  @override
  Future<Result<SessionFailure, void>> hotReload(ReloadParams params) =>
      _run(params.tabId, (s) => s.hotReload());

  @override
  Future<Result<SessionFailure, void>> hotRestart(ReloadParams params) =>
      _run(params.tabId, (s) => s.hotRestart());

  @override
  Future<Result<SessionFailure, void>> stop(ReloadParams params) =>
      _run(params.tabId, (s) => s.stop());

  Future<Result<SessionFailure, void>> _run(
    int tabId,
    Future<void> Function(AppRunSession session) action,
  ) async {
    final session = _lookup(tabId);
    if (session == null) {
      return Result.failure(
        SessionFailure(message: 'No session for tab $tabId'),
      );
    }
    try {
      await action(session);
      return Result.success(null);
    } catch (e, st) {
      return Result.failure(
        SessionFailure(message: e.toString(), cause: e, stackTrace: st),
      );
    }
  }
}
