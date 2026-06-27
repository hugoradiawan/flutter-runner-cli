import '../../core/result.dart';
import '../../data/datasources/config_datasource.dart';
import '../../data/models/frun_config.dart';
import '../../domain/entities/app_config.dart';
import '../../domain/failures/config_failure.dart';
import '../../domain/params/config_params.dart';
import '../../domain/repositories/config_repository.dart';
import '../../domain/value_objects/config_values.dart';

class ConfigRepositoryImpl implements ConfigRepository {
  ConfigRepositoryImpl(this._source);

  final ConfigDataSource _source;

  FrunConfig _fromEntity(AppConfigEntity e) => FrunConfig(
    ide: e.ide,
    editorMode: e.editorMode,
    theme: e.theme,
    hotReloadOnSave: e.hotReloadOnSave,
    openDevtoolsOnLaunch: e.openDevtoolsOnLaunch,
    emulatorBoot: e.emulatorBoot,
    verboseErrors: e.verboseErrors,
    diagnosticsOnBoot: e.diagnosticsOnBoot,
    scrollbackLines: e.scrollbackLines,
    nvimServer: e.nvimServer,
  );

  @override
  Future<Result<ConfigFailure, AppConfigEntity>> getConfig() async {
    try {
      return Result.success(_source.load());
    } catch (e, st) {
      return Result.failure(
        ConfigFailure(message: e.toString(), cause: e, stackTrace: st),
      );
    }
  }

  @override
  Future<Result<ConfigFailure, void>> setConfig(ConfigSetParams params) async {
    try {
      final current = _source.load();
      final updated = _applyKey(current, params.key, params.value);
      _source.save(updated);
      return Result.success(null);
    } catch (e, st) {
      return Result.failure(
        ConfigFailure(message: e.toString(), cause: e, stackTrace: st),
      );
    }
  }

  @override
  Future<Result<ConfigFailure, void>> saveConfig(AppConfigEntity entity) async {
    try {
      _source.save(_fromEntity(entity));
      return Result.success(null);
    } catch (e, st) {
      return Result.failure(
        ConfigFailure(message: e.toString(), cause: e, stackTrace: st),
      );
    }
  }

  @override
  String getConfigPath() => _source.path;

  FrunConfig _applyKey(FrunConfig c, String key, String value) => switch (key) {
    'ide' => c.copyWith(ide: FrunIde.fromString(value)),
    'editor_mode' => c.copyWith(editorMode: FrunEditorMode.fromString(value)),
    'theme' => c.copyWith(theme: FrunThemeMode.fromString(value)),
    'hot_reload_on_save' => c.copyWith(hotReloadOnSave: _parseBool(value)),
    'open_devtools_on_launch' => c.copyWith(
      openDevtoolsOnLaunch: FrunDevToolsAutoOpen.fromString(value),
    ),
    'emulator_boot' => c.copyWith(
      emulatorBoot: FrunEmulatorBoot.fromString(value),
    ),
    'verbose_errors' => c.copyWith(verboseErrors: _parseBool(value)),
    'diagnostics_on_boot' => c.copyWith(diagnosticsOnBoot: _parseBool(value)),
    'scrollback_lines' => c.copyWith(scrollbackLines: _parseScrollback(value)),
    'nvim_server' =>
      value.isEmpty
          ? c.copyWith(clearNvimServer: true)
          : c.copyWith(nvimServer: value),
    _ => throw ArgumentError('Unknown config key: $key'),
  };

  static bool _parseBool(String v) {
    final s = v.toLowerCase();
    return s == 'true' || s == 'yes' || s == 'on' || s == '1';
  }

  static int _parseScrollback(String v) {
    final n = int.tryParse(v.trim());
    if (n == null || n < 1) {
      throw ArgumentError('scrollback_lines must be a positive integer');
    }
    return n;
  }
}
