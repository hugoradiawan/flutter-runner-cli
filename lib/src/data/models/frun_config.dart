import '../../ca/model.dart';
import '../../domain/entities/app_config.entity.dart';
import '../../domain/value_objects/config_values.dart';

class FrunConfig extends AppConfigEntity implements Model<FrunConfig> {
  const FrunConfig({
    super.ide = FrunIde.vscode,
    super.editorMode = FrunEditorMode.normal,
    super.theme = FrunThemeMode.dark,
    super.hotReloadOnSave = true,
    super.openDevtoolsOnLaunch = FrunDevToolsAutoOpen.ask,
    super.emulatorBoot = FrunEmulatorBoot.quick,
    super.verboseErrors = false,
    super.nvimServer,
  });

  factory FrunConfig.fromMap(Map<dynamic, dynamic> map) => FrunConfig(
    ide: FrunIde.fromString(map['ide'] as String?),
    editorMode: FrunEditorMode.fromString(map['editor_mode'] as String?),
    theme: FrunThemeMode.fromString(map['theme'] as String?),
    hotReloadOnSave: (map['hot_reload_on_save'] as bool?) ?? true,
    openDevtoolsOnLaunch: FrunDevToolsAutoOpen.fromString(
      map['open_devtools_on_launch'] as String?,
    ),
    emulatorBoot: FrunEmulatorBoot.fromString(map['emulator_boot'] as String?),
    verboseErrors: (map['verbose_errors'] as bool?) ?? false,
    nvimServer: map['nvim_server'] as String?,
  );

  @override
  Json toJson() => <String, dynamic>{
    'ide': ide.id,
    'editor_mode': editorMode.id,
    'theme': theme.id,
    'hot_reload_on_save': hotReloadOnSave,
    'open_devtools_on_launch': openDevtoolsOnLaunch.id,
    'emulator_boot': emulatorBoot.id,
    'verbose_errors': verboseErrors,
    'nvim_server': nvimServer,
  };

  @override
  FrunConfig? fromJson(dynamic json) {
    if (json is! Map) return null;
    return FrunConfig.fromMap(json);
  }

  @override
  FrunConfig copyWith({
    FrunIde? ide,
    FrunEditorMode? editorMode,
    FrunThemeMode? theme,
    bool? hotReloadOnSave,
    FrunDevToolsAutoOpen? openDevtoolsOnLaunch,
    FrunEmulatorBoot? emulatorBoot,
    bool? verboseErrors,
    String? nvimServer,
    bool clearNvimServer = false,
  }) => FrunConfig(
    ide: ide ?? this.ide,
    editorMode: editorMode ?? this.editorMode,
    theme: theme ?? this.theme,
    hotReloadOnSave: hotReloadOnSave ?? this.hotReloadOnSave,
    openDevtoolsOnLaunch: openDevtoolsOnLaunch ?? this.openDevtoolsOnLaunch,
    emulatorBoot: emulatorBoot ?? this.emulatorBoot,
    verboseErrors: verboseErrors ?? this.verboseErrors,
    nvimServer: clearNvimServer ? null : (nvimServer ?? this.nvimServer),
  );
}
