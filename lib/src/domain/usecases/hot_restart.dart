import '../../core/base/use_case.dart';
import '../../core/result.dart';
import '../failures/session_failure.dart';
import '../params/reload_params.dart';
import '../repositories/session_repository.dart';

class HotRestartUseCase extends UseCase<SessionFailure, void, ReloadParams> {
  const HotRestartUseCase(this._repo);

  final SessionRepository _repo;

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
