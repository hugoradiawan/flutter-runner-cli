import '../../ca/result.dart';
import '../../ca/usecase.dart';
import '../failures/session_failure.dart';
import '../params/reload.params.dart';
import '../repositories/session_repository.dart';

class WatchLogsUseCase extends StreamUseCase<SessionFailure, String, ReloadParams> {
  const WatchLogsUseCase(this._repo);

  final ISessionRepository _repo;

  @override
  Stream<Result<SessionFailure, String>> call([ReloadParams? params]) {
    if (params == null) {
      return Stream.value(
        Result.failure(const SessionFailure(message: 'ReloadParams required')),
      );
    }
    return _repo.watchLogs(params.tabId).map(Result.success);
  }
}
