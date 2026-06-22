import '../../ca/result.dart';
import '../entities/app_config.entity.dart';
import '../failures/config_failure.dart';
import '../repositories/config_repository.dart';

class SaveConfigUseCase {
  const SaveConfigUseCase(this._repo);

  final IConfigRepository _repo;

  Future<Result<ConfigFailure, void>> call(AppConfigEntity entity) =>
      _repo.saveConfig(entity);
}
