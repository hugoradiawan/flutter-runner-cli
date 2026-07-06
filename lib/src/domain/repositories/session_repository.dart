import '../../core/result.dart';
import '../entities/run_session.dart';
import '../failures/session_failure.dart';
import '../params/reload_params.dart';
import '../params/session_params.dart';

abstract class SessionRepository {
  /// Spawn `flutter run` for the given entry/device and register the live
  /// session under [SessionStartParams.sessionId].
  Future<Result<SessionFailure, RunSession>> start(SessionStartParams params);

  Future<Result<SessionFailure, void>> hotReload(ReloadParams params);
  Future<Result<SessionFailure, void>> hotRestart(ReloadParams params);

  /// Stop the app and kill the tool process; the session id is released.
  Future<Result<SessionFailure, void>> stop(ReloadParams params);

  /// Detach the tool, leaving the app running on the device; the session id
  /// is released.
  Future<Result<SessionFailure, void>> detach(ReloadParams params);
}
