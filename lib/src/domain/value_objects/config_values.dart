enum FrunIde {
  vscode,
  zed,
  neovim;

  static FrunIde fromString(String? value) {
    switch (value) {
      case 'vscode':
        return FrunIde.vscode;
      case 'zed':
        return FrunIde.zed;
      case 'neovim':
        return FrunIde.neovim;
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
