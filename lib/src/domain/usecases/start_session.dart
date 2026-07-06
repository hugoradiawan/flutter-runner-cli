import '../../core/base/use_case.dart';
import '../../core/result.dart';
import '../entities/run_session.dart';
import '../failures/session_failure.dart';
import '../params/session_params.dart';
import '../repositories/session_repository.dart';

class StartSessionUseCase
    extends UseCase<SessionFailure, RunSession, SessionStartParams> {
  const StartSessionUseCase(this._repo);

  final SessionRepository _repo;

  @override
  Future<Result<SessionFailure, RunSession>> call([
    SessionStartParams? params,
  ]) {
    if (params == null) {
      return Future.value(
        Result.failure(
          const SessionFailure(message: 'SessionStartParams required'),
        ),
      );
    }
    return _repo.start(params);
  }
}
