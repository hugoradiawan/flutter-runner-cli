import 'dart:io';

import 'package:frun/src/data/datasources/config_store.dart';
import 'package:frun/src/data/models/frun_config.dart';
import 'package:frun/src/domain/value_objects/config_values.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('FrunConfig', () {
    test('round-trips defaults through fromMap/toJson', () {
      const defaults = FrunConfig();
      final round = FrunConfig.fromMap(defaults.toJson());
      expect(round.ide, defaults.ide);
      expect(round.editorMode, defaults.editorMode);
      expect(round.theme, defaults.theme);
      expect(round.hotReloadOnSave, defaults.hotReloadOnSave);
      expect(round.openDevtoolsOnLaunch, defaults.openDevtoolsOnLaunch);
    });

    test('fromMap tolerates unknown / null values', () {
      final c = FrunConfig.fromMap(<String, Object?>{
        'ide': 'something-weird',
        'editor_mode': null,
        'theme': 'light',
        'hot_reload_on_save': false,
        'open_devtools_on_launch': 'always',
      });
      expect(c.ide, FrunIde.vscode);
      expect(c.editorMode, FrunEditorMode.normal);
      expect(c.theme, FrunThemeMode.light);
      expect(c.hotReloadOnSave, isFalse);
      expect(c.openDevtoolsOnLaunch, FrunDevToolsAutoOpen.always);
    });
  });

  group('ConfigStore', () {
    late Directory tempDir;
    late String path;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('frun_config_test_');
      path = p.join(tempDir.path, 'cfg.yaml');
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('creates defaults file if missing', () {
      final store = ConfigStore(overridePath: path);
      final c = store.load();
      expect(File(path).existsSync(), isTrue);
      expect(c.ide, FrunIde.vscode);
    });

    test('saves and loads non-default values', () {
      final store = ConfigStore(overridePath: path);
      store.save(
        const FrunConfig(
          ide: FrunIde.zed,
          editorMode: FrunEditorMode.vim,
          theme: FrunThemeMode.light,
          hotReloadOnSave: false,
          openDevtoolsOnLaunch: FrunDevToolsAutoOpen.never,
        ),
      );
      final loaded = store.load();
      expect(loaded.ide, FrunIde.zed);
      expect(loaded.editorMode, FrunEditorMode.vim);
      expect(loaded.theme, FrunThemeMode.light);
      expect(loaded.hotReloadOnSave, isFalse);
      expect(loaded.openDevtoolsOnLaunch, FrunDevToolsAutoOpen.never);
    });
  });
}
