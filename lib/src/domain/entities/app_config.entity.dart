import '../../ca/entity.dart';
import '../../config/config.dart'
    show
        FrunDevToolsAutoOpen,
        FrunEditorMode,
        FrunEmulatorBoot,
        FrunIde,
        FrunThemeMode;

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

  final FrunIde ide;
  final FrunEditorMode editorMode;
  final FrunThemeMode theme;
  final bool hotReloadOnSave;
  final FrunDevToolsAutoOpen openDevtoolsOnLaunch;
  final FrunEmulatorBoot emulatorBoot;
  final bool verboseErrors;
  final String? nvimServer;

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
