import '../../core/result.dart';
import '../failures/session_failure.dart';
import '../params/reload_params.dart';

abstract class SessionRepository {
  Future<Result<SessionFailure, void>> hotReload(ReloadParams params);
  Future<Result<SessionFailure, void>> hotRestart(ReloadParams params);
  Future<Result<SessionFailure, void>> stop(ReloadParams params);
}
