enum FrunIde {
  vscode,
  zed;

  static FrunIde fromString(String? value) {
    switch (value) {
      case 'vscode':
        return FrunIde.vscode;
      case 'zed':
        return FrunIde.zed;
      default:
        return FrunIde.vscode;
    }
  }

  String get id => name;
}

enum FrunEditorMode {
  normal,
  vim;

  static FrunEditorMode fromString(String? value) {
    switch (value) {
      case 'vim':
        return FrunEditorMode.vim;
      case 'normal':
      default:
        return FrunEditorMode.normal;
    }
  }

  String get id => name;
}

enum FrunDevToolsAutoOpen {
  always,
  never,
  ask;

  static FrunDevToolsAutoOpen fromString(String? value) {
    switch (value) {
      case 'always':
        return FrunDevToolsAutoOpen.always;
      case 'never':
        return FrunDevToolsAutoOpen.never;
      case 'ask':
      default:
        return FrunDevToolsAutoOpen.ask;
    }
  }

  String get id => name;
}

enum FrunThemeMode {
  dark,
  light;

  static FrunThemeMode fromString(String? value) {
    switch (value) {
      case 'light':
        return FrunThemeMode.light;
      case 'dark':
      default:
        return FrunThemeMode.dark;
    }
  }

  String get id => name;
}

enum FrunEmulatorBoot {
  quick,
  cold;

  static FrunEmulatorBoot fromString(String? value) {
    switch (value) {
      case 'cold':
        return FrunEmulatorBoot.cold;
      case 'quick':
      default:
        return FrunEmulatorBoot.quick;
    }
  }

  String get id => name;
}

class FrunConfig {
  FrunConfig({
    this.ide = FrunIde.vscode,
    this.editorMode = FrunEditorMode.normal,
    this.theme = FrunThemeMode.dark,
    this.hotReloadOnSave = true,
    this.defaultDeviceId,
    this.openDevtoolsOnLaunch = FrunDevToolsAutoOpen.ask,
    this.emulatorBoot = FrunEmulatorBoot.quick,
  });

  FrunIde ide;
  FrunEditorMode editorMode;
  FrunThemeMode theme;
  bool hotReloadOnSave;
  String? defaultDeviceId;
  FrunDevToolsAutoOpen openDevtoolsOnLaunch;
  FrunEmulatorBoot emulatorBoot;

  factory FrunConfig.fromMap(Map<dynamic, dynamic> map) {
    return FrunConfig(
      ide: FrunIde.fromString(map['ide'] as String?),
      editorMode: FrunEditorMode.fromString(map['editor_mode'] as String?),
      theme: FrunThemeMode.fromString(map['theme'] as String?),
      hotReloadOnSave: (map['hot_reload_on_save'] as bool?) ?? true,
      defaultDeviceId: map['default_device_id'] as String?,
      openDevtoolsOnLaunch: FrunDevToolsAutoOpen.fromString(
        map['open_devtools_on_launch'] as String?,
      ),
      emulatorBoot: FrunEmulatorBoot.fromString(map['emulator_boot'] as String?),
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'ide': ide.id,
    'editor_mode': editorMode.id,
    'theme': theme.id,
    'hot_reload_on_save': hotReloadOnSave,
    'default_device_id': defaultDeviceId,
    'open_devtools_on_launch': openDevtoolsOnLaunch.id,
    'emulator_boot': emulatorBoot.id,
  };

  FrunConfig copyWith({
    FrunIde? ide,
    FrunEditorMode? editorMode,
    FrunThemeMode? theme,
    bool? hotReloadOnSave,
    String? defaultDeviceId,
    bool clearDefaultDeviceId = false,
    FrunDevToolsAutoOpen? openDevtoolsOnLaunch,
    FrunEmulatorBoot? emulatorBoot,
  }) {
    return FrunConfig(
      ide: ide ?? this.ide,
      editorMode: editorMode ?? this.editorMode,
      theme: theme ?? this.theme,
      hotReloadOnSave: hotReloadOnSave ?? this.hotReloadOnSave,
      defaultDeviceId: clearDefaultDeviceId
          ? null
          : (defaultDeviceId ?? this.defaultDeviceId),
      openDevtoolsOnLaunch: openDevtoolsOnLaunch ?? this.openDevtoolsOnLaunch,
      emulatorBoot: emulatorBoot ?? this.emulatorBoot,
    );
  }
}
