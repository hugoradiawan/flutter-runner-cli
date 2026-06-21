import '../../ca/result.dart';
import '../../config/config.dart';
import '../../config/config_store.dart';
import '../../domain/entities/app_config.entity.dart';
import '../../domain/failures/config_failure.dart';
import '../../domain/params/config.params.dart';
import '../../domain/repositories/config_repository.dart';

class ConfigRepositoryImpl implements IConfigRepository {
  ConfigRepositoryImpl(this._store);

  final ConfigStore _store;

  AppConfigEntity _toEntity(FrunConfig c) => AppConfigEntity(
    ide: c.ide,
    editorMode: c.editorMode,
    theme: c.theme,
    hotReloadOnSave: c.hotReloadOnSave,
    openDevtoolsOnLaunch: c.openDevtoolsOnLaunch,
    emulatorBoot: c.emulatorBoot,
    verboseErrors: c.verboseErrors,
    nvimServer: c.nvimServer,
  );

  @override
  Future<Result<ConfigFailure, AppConfigEntity>> getConfig() async {
    try {
      final config = _store.load();
      return Result.success(_toEntity(config));
    } catch (e, st) {
      return Result.failure(
        ConfigFailure(message: e.toString(), cause: e, stackTrace: st),
      );
    }
  }

  @override
  Future<Result<ConfigFailure, void>> setConfig(ConfigSetParams params) async {
    try {
      final current = _store.load();
      final updated = _applyKey(current, params.key, params.value);
      _store.save(updated);
      return Result.success(null);
    } catch (e, st) {
      return Result.failure(
        ConfigFailure(message: e.toString(), cause: e, stackTrace: st),
      );
    }
  }

  FrunConfig _applyKey(FrunConfig c, String key, String value) =>
      switch (key) {
        'ide' => c.copyWith(ide: FrunIde.fromString(value)),
        'editor_mode' => c.copyWith(editorMode: FrunEditorMode.fromString(value)),
        'theme' => c.copyWith(theme: FrunThemeMode.fromString(value)),
        'hot_reload_on_save' => c.copyWith(hotReloadOnSave: value == 'true'),
        'open_devtools_on_launch' => c.copyWith(
          openDevtoolsOnLaunch: FrunDevToolsAutoOpen.fromString(value),
        ),
        'emulator_boot' => c.copyWith(
          emulatorBoot: FrunEmulatorBoot.fromString(value),
        ),
        'verbose_errors' => c.copyWith(verboseErrors: value == 'true'),
        'nvim_server' => c.copyWith(nvimServer: value.isEmpty ? null : value),
        _ => throw ArgumentError('Unknown config key: $key'),
      };
}
