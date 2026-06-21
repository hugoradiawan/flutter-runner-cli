import '../../ca/result.dart';
import '../../ca/usecase.dart';
import '../failures/session_failure.dart';
import '../params/reload.params.dart';
import '../repositories/session_repository.dart';

class HotRestartUseCase extends UseCase<SessionFailure, void, ReloadParams> {
  const HotRestartUseCase(this._repo);

  final ISessionRepository _repo;

  @override
  Future<Result<SessionFailure, void>> call([ReloadParams? params]) {
    if (params == null) {
      return Future.value(
        Result.failure(const SessionFailure(message: 'ReloadParams required')),
      );
    }
    return _repo.hotRestart(params);
  }
}
