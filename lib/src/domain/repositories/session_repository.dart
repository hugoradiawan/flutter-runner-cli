import '../../ca/result.dart';
import '../entities/run_session.entity.dart';
import '../failures/session_failure.dart';
import '../params/reload.params.dart';
import '../params/run.params.dart';

abstract class ISessionRepository {
  Future<Result<SessionFailure, RunSessionEntity>> launch(RunParams params);
  Future<Result<SessionFailure, void>> hotReload(ReloadParams params);
  Future<Result<SessionFailure, void>> hotRestart(ReloadParams params);
  Future<Result<SessionFailure, void>> stop(ReloadParams params);
  Stream<String> watchLogs(int tabId);
}
