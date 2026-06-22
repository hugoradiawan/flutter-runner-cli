import 'dart:async';
import 'dart:io';

import 'package:frun/src/ca/result.dart';
import 'package:frun/src/daemon/daemon_messages.dart';
import 'package:frun/src/data/datasources/config_datasource.dart';
import 'package:frun/src/data/datasources/config_store.dart';
import 'package:frun/src/data/models/frun_config.dart';
import 'package:frun/src/data/repositories/config_repository_impl.dart';
import 'package:frun/src/data/repositories/device_repository_impl.dart';
import 'package:frun/src/data/repositories/emulator_repository_impl.dart';
import 'package:frun/src/devices/device_manager.dart';
import 'package:frun/src/devices/emulator_manager.dart';
import 'package:frun/src/domain/entities/device.entity.dart';
import 'package:frun/src/domain/entities/emulator.entity.dart';
import 'package:frun/src/domain/failures/config_failure.dart';
import 'package:frun/src/domain/failures/device_failure.dart';
import 'package:frun/src/domain/params/config.params.dart';
import 'package:frun/src/domain/params/emulator_launch.params.dart';
import 'package:frun/src/domain/value_objects/config_values.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class MockDeviceManager extends Mock implements DeviceManager {}

class MockEmulatorManager extends Mock implements EmulatorManager {}

// ── Fixtures ──────────────────────────────────────────────────────────────────

final _flutterDevice = FlutterDevice(
  id: 'emulator-5554',
  name: 'Pixel 7',
  platform: 'android-x64',
  category: 'mobile',
  platformType: 'android',
  ephemeral: true,
  emulator: true,
  emulatorId: 'Pixel_7_API_34',
);

final _flutterEmulator = FlutterEmulator(
  id: 'Pixel_7_API_34',
  name: 'Pixel 7 API 34',
  category: 'mobile',
  platformType: 'android',
);

const _emulatorEntity = EmulatorEntity(
  id: 'Pixel_7_API_34',
  name: 'Pixel 7 API 34',
);

// ── ConfigRepositoryImpl ──────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    registerFallbackValue(Duration.zero);
  });

  group('ConfigRepositoryImpl', () {
    late Directory tempDir;
    late ConfigStore store;
    late ConfigRepositoryImpl repo;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('frun_config_repo_test_');
      store = ConfigStore(overridePath: p.join(tempDir.path, 'cfg.yaml'));
      repo = ConfigRepositoryImpl(ConfigDataSource(store));
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('getConfig returns Success with default AppConfigEntity', () async {
      final result = await repo.getConfig();

      expect(result.isSuccess, isTrue);
      final entity = (result as Success).value;
      expect(entity.ide, FrunIde.vscode);
      expect(entity.hotReloadOnSave, isTrue);
      expect(entity.verboseErrors, isFalse);
    });

    test('getConfig maps non-default values', () async {
      store.save(
        FrunConfig(
          ide: FrunIde.zed,
          editorMode: FrunEditorMode.vim,
          theme: FrunThemeMode.light,
          hotReloadOnSave: false,
        ),
      );

      final result = await repo.getConfig();
      final entity = (result as Success).value;

      expect(entity.ide, FrunIde.zed);
      expect(entity.editorMode, FrunEditorMode.vim);
      expect(entity.theme, FrunThemeMode.light);
      expect(entity.hotReloadOnSave, isFalse);
    });

    test('setConfig(ide, zed) saves and reflects in getConfig', () async {
      final setResult = await repo.setConfig(
        const ConfigSetParams(key: 'ide', value: 'zed'),
      );
      expect(setResult.isSuccess, isTrue);

      final getResult = await repo.getConfig();
      expect((getResult as Success).value.ide, FrunIde.zed);
      expect(store.load().ide, FrunIde.zed);
    });

    test('setConfig(hot_reload_on_save, false) toggles the flag', () async {
      await repo.setConfig(
        const ConfigSetParams(key: 'hot_reload_on_save', value: 'false'),
      );
      expect(store.load().hotReloadOnSave, isFalse);
    });

    test('setConfig(verbose_errors, true) toggles the flag', () async {
      await repo.setConfig(
        const ConfigSetParams(key: 'verbose_errors', value: 'true'),
      );
      expect(store.load().verboseErrors, isTrue);
    });

    test('setConfig with unknown key returns ConfigFailure', () async {
      final result = await repo.setConfig(
        const ConfigSetParams(key: 'no_such_key', value: 'val'),
      );

      expect(result.isFailure, isTrue);
      expect((result as Failure).error, isA<ConfigFailure>());
    });

    test('setConfig(nvim_server, addr) sets the server', () async {
      await repo.setConfig(
        const ConfigSetParams(key: 'nvim_server', value: '/tmp/nvim.sock'),
      );
      expect(store.load().nvimServer, '/tmp/nvim.sock');
    });

    test('setConfig(nvim_server, empty) clears the server', () async {
      store.save(FrunConfig(nvimServer: '/tmp/nvim.sock'));
      await repo.setConfig(
        const ConfigSetParams(key: 'nvim_server', value: ''),
      );
      expect(store.load().nvimServer, isNull);
    });
  });

  // ── DeviceRepositoryImpl ──────────────────────────────────────────────────────

  group('DeviceRepositoryImpl', () {
    late MockDeviceManager manager;
    late DeviceRepositoryImpl repo;

    setUp(() {
      manager = MockDeviceManager();
      repo = DeviceRepositoryImpl(manager);
    });

    test('listDevices returns Success with mapped DeviceEntity list', () async {
      when(() => manager.devices).thenReturn([_flutterDevice]);

      final result = await repo.listDevices();

      expect(result.isSuccess, isTrue);
      final devices = (result as Success).value;
      expect(devices.length, 1);
      expect(devices.first.id, _flutterDevice.id);
      expect(devices.first.name, _flutterDevice.name);
      expect(devices.first.platform, _flutterDevice.platform);
      expect(devices.first.emulator, isTrue);
    });

    test(
      'listDevices returns Success with empty list when no devices',
      () async {
        when(() => manager.devices).thenReturn([]);

        final result = await repo.listDevices();
        expect(result.isSuccess, isTrue);
        expect((result as Success).value, isEmpty);
      },
    );

    test('listDevices returns DeviceFailure when manager throws', () async {
      when(() => manager.devices).thenThrow(Exception('daemon dead'));

      final result = await repo.listDevices();
      expect(result.isFailure, isTrue);
      expect((result as Failure).error, isA<DeviceFailure>());
    });

    test(
      'watchDevices maps FlutterDevice stream to DeviceEntity stream',
      () async {
        final controller = StreamController<List<FlutterDevice>>();
        when(() => manager.changes).thenAnswer((_) => controller.stream);

        final events = <List<DeviceEntity>>[];
        final sub = repo.watchDevices().listen(events.add);

        controller.add([_flutterDevice]);
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();
        await controller.close();

        expect(events.length, 1);
        expect(events.first.first.id, _flutterDevice.id);
      },
    );

    test('watchDevices emits empty list when stream emits empty', () async {
      when(
        () => manager.changes,
      ).thenAnswer((_) => Stream.value(<FlutterDevice>[]));

      final events = await repo.watchDevices().toList();
      expect(events.length, 1);
      expect(events.first, isEmpty);
    });
  });

  // ── EmulatorRepositoryImpl ────────────────────────────────────────────────────

  group('EmulatorRepositoryImpl', () {
    late MockEmulatorManager manager;
    late EmulatorRepositoryImpl repo;

    setUp(() {
      manager = MockEmulatorManager();
      repo = EmulatorRepositoryImpl(manager);
    });

    test(
      'listEmulators returns Success with mapped EmulatorEntity list',
      () async {
        when(() => manager.list()).thenAnswer((_) async => [_flutterEmulator]);

        final result = await repo.listEmulators();

        expect(result.isSuccess, isTrue);
        final emulators = (result as Success).value;
        expect(emulators.length, 1);
        expect(emulators.first.id, _flutterEmulator.id);
        expect(emulators.first.name, _flutterEmulator.name);
      },
    );

    test('listEmulators returns Success with empty list', () async {
      when(() => manager.list()).thenAnswer((_) async => []);

      final result = await repo.listEmulators();
      expect(result.isSuccess, isTrue);
      expect((result as Success).value, isEmpty);
    });

    test('listEmulators returns DeviceFailure when manager throws', () async {
      when(() => manager.list()).thenThrow(Exception('sdk not found'));

      final result = await repo.listEmulators();
      expect(result.isFailure, isTrue);
      expect((result as Failure).error, isA<DeviceFailure>());
    });

    test(
      'launchEmulator returns Success with DeviceEntity on device found',
      () async {
        final params = EmulatorLaunchParams(emulator: _emulatorEntity);
        when(
          () => manager.launchAndAwaitDevice(
            _flutterEmulator.id,
            coldBoot: any(named: 'coldBoot'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer((_) async => _flutterDevice);

        final result = await repo.launchEmulator(params);

        expect(result.isSuccess, isTrue);
        final device = (result as Success).value;
        expect(device.id, _flutterDevice.id);
        expect(device, isA<DeviceEntity>());
      },
    );

    test(
      'launchEmulator returns DeviceFailure when device times out (null)',
      () async {
        final params = EmulatorLaunchParams(emulator: _emulatorEntity);
        when(
          () => manager.launchAndAwaitDevice(
            _flutterEmulator.id,
            coldBoot: any(named: 'coldBoot'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer((_) async => null);

        final result = await repo.launchEmulator(params);
        expect(result.isFailure, isTrue);
        expect((result as Failure).error, isA<DeviceFailure>());
      },
    );

    test('launchEmulator returns DeviceFailure when manager throws', () async {
      final params = EmulatorLaunchParams(emulator: _emulatorEntity);
      when(
        () => manager.launchAndAwaitDevice(
          _flutterEmulator.id,
          coldBoot: any(named: 'coldBoot'),
          timeout: any(named: 'timeout'),
        ),
      ).thenThrow(Exception('avd failure'));

      final result = await repo.launchEmulator(params);
      expect(result.isFailure, isTrue);
      expect((result as Failure).error, isA<DeviceFailure>());
    });
  });
}
