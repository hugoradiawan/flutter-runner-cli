import '../../ca/result.dart';
import '../../ca/usecase.dart';
import '../failures/config_failure.dart';
import '../params/config.params.dart';
import '../repositories/config_repository.dart';

class SetConfigUseCase extends UseCase<ConfigFailure, void, ConfigSetParams> {
  const SetConfigUseCase(this._repo);

  final IConfigRepository _repo;

  @override
  Future<Result<ConfigFailure, void>> call([ConfigSetParams? params]) {
    if (params == null) {
      return Future.value(
        Result.failure(const ConfigFailure(message: 'ConfigSetParams required')),
      );
    }
    return _repo.setConfig(params);
  }
}
