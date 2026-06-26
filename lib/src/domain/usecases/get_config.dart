import '../../core/base/params.dart';
import '../../core/base/use_case.dart';
import '../../core/result.dart';
import '../entities/app_config.dart';
import '../failures/config_failure.dart';
import '../repositories/config_repository.dart';

class GetConfigUseCase extends UseCase<ConfigFailure, AppConfigEntity, Params> {
  const GetConfigUseCase(this._repo);

  final ConfigRepository _repo;

  @override
  Future<Result<ConfigFailure, AppConfigEntity>> call([Params? params]) =>
      _repo.getConfig();
}
