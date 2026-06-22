import '../../ca/result.dart';
import '../entities/app_config.entity.dart';
import '../failures/config_failure.dart';
import '../params/config.params.dart';

abstract class IConfigRepository {
  Future<Result<ConfigFailure, AppConfigEntity>> getConfig();
  Future<Result<ConfigFailure, void>> setConfig(ConfigSetParams params);
  Future<Result<ConfigFailure, void>> saveConfig(AppConfigEntity entity);
  String getConfigPath();
}
