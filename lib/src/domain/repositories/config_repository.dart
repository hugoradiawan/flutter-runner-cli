import '../../core/result.dart';
import '../entities/app_config.dart';
import '../failures/config_failure.dart';
import '../params/config_params.dart';

abstract class ConfigRepository {
  Future<Result<ConfigFailure, AppConfigEntity>> getConfig();
  Future<Result<ConfigFailure, void>> setConfig(ConfigSetParams params);
  Future<Result<ConfigFailure, void>> saveConfig(AppConfigEntity entity);
  String getConfigPath();
}
