import '../../core/base/use_case.dart';
import '../../core/result.dart';
import '../failures/config_failure.dart';
import '../params/config_params.dart';
import '../repositories/config_repository.dart';

class SetConfigUseCase extends UseCase<ConfigFailure, void, ConfigSetParams> {
  const SetConfigUseCase(this._repo);

  final ConfigRepository _repo;

  @override
  Future<Result<ConfigFailure, void>> call([ConfigSetParams? params]) {
    if (params == null) {
      return Future.value(
        Result.failure(
          const ConfigFailure(message: 'ConfigSetParams required'),
        ),
      );
    }
    return _repo.setConfig(params);
  }
}
