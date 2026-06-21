import '../../ca/params.dart';
import '../../ca/result.dart';
import '../../ca/usecase.dart';
import '../entities/app_config.entity.dart';
import '../failures/config_failure.dart';
import '../repositories/config_repository.dart';

class GetConfigUseCase extends UseCase<ConfigFailure, AppConfigEntity, Params> {
  const GetConfigUseCase(this._repo);

  final IConfigRepository _repo;

  @override
  Future<Result<ConfigFailure, AppConfigEntity>> call([Params? params]) =>
      _repo.getConfig();
}
