import '../../core/base/entity.dart';
import '../value_objects/config_values.dart';

class AppConfigEntity extends Entity<AppConfigEntity> {
  const AppConfigEntity({
    required this.ide,
    required this.editorMode,
    required this.theme,
    required this.hotReloadOnSave,
    required this.openDevtoolsOnLaunch,
    required this.emulatorBoot,
    required this.verboseErrors,
    this.nvimServer,
  });

  factory AppConfigEntity.defaults() => const AppConfigEntity(
    ide: FrunIde.vscode,
    editorMode: FrunEditorMode.normal,
    theme: FrunThemeMode.dark,
    hotReloadOnSave: true,
    openDevtoolsOnLaunch: FrunDevToolsAutoOpen.ask,
    emulatorBoot: FrunEmulatorBoot.quick,
    verboseErrors: false,
  );

  final FrunIde ide;
  final FrunEditorMode editorMode;
  final FrunThemeMode theme;
  final bool hotReloadOnSave;
  final FrunDevToolsAutoOpen openDevtoolsOnLaunch;
  final FrunEmulatorBoot emulatorBoot;
  final bool verboseErrors;
  final String? nvimServer;

  AppConfigEntity copyWith({
    FrunIde? ide,
    FrunEditorMode? editorMode,
    FrunThemeMode? theme,
    bool? hotReloadOnSave,
    FrunDevToolsAutoOpen? openDevtoolsOnLaunch,
    FrunEmulatorBoot? emulatorBoot,
    bool? verboseErrors,
    String? nvimServer,
    bool clearNvimServer = false,
  }) {
    return AppConfigEntity(
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

  @override
  List<Object?> get props => [
    ide,
    editorMode,
    theme,
    hotReloadOnSave,
    openDevtoolsOnLaunch,
    emulatorBoot,
    verboseErrors,
    nvimServer,
  ];
}
