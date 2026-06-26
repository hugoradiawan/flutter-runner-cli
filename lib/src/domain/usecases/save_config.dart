import '../../core/result.dart';
import '../entities/app_config.dart';
import '../failures/config_failure.dart';
import '../repositories/config_repository.dart';

class SaveConfigUseCase {
  const SaveConfigUseCase(this._repo);

  final ConfigRepository _repo;

  Future<Result<ConfigFailure, void>> call(AppConfigEntity entity) =>
      _repo.saveConfig(entity);
}
