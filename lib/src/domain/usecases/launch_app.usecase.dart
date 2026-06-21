import '../../ca/result.dart';
import '../../ca/usecase.dart';
import '../entities/run_session.entity.dart';
import '../failures/session_failure.dart';
import '../params/run.params.dart';
import '../repositories/session_repository.dart';

class LaunchAppUseCase extends UseCase<SessionFailure, RunSessionEntity, RunParams> {
  const LaunchAppUseCase(this._repo);

  final ISessionRepository _repo;

  @override
  Future<Result<SessionFailure, RunSessionEntity>> call([RunParams? params]) {
    if (params == null) {
      return Future.value(
        Result.failure(const SessionFailure(message: 'RunParams required')),
      );
    }
    return _repo.launch(params);
  }
}
