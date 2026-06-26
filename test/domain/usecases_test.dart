import 'package:frun/src/core/result.dart';
import 'package:frun/src/domain/entities/app_config.dart';
import 'package:frun/src/domain/entities/device.dart';
import 'package:frun/src/domain/entities/diagnostic.dart';
import 'package:frun/src/domain/entities/emulator.dart';
import 'package:frun/src/domain/failures/analysis_failure.dart';
import 'package:frun/src/domain/failures/config_failure.dart';
import 'package:frun/src/domain/failures/device_failure.dart';
import 'package:frun/src/domain/failures/session_failure.dart';
import 'package:frun/src/domain/params/config_params.dart';
import 'package:frun/src/domain/params/diagnostics_filter_params.dart';
import 'package:frun/src/domain/params/emulator_launch_params.dart';
import 'package:frun/src/domain/params/reload_params.dart';
import 'package:frun/src/domain/repositories/config_repository.dart';
import 'package:frun/src/domain/repositories/device_repository.dart';
import 'package:frun/src/domain/repositories/diagnostics_repository.dart';
import 'package:frun/src/domain/repositories/emulator_repository.dart';
import 'package:frun/src/domain/repositories/session_repository.dart';
import 'package:frun/src/domain/usecases/get_config.dart';
import 'package:frun/src/domain/usecases/get_diagnostics.dart';
import 'package:frun/src/domain/usecases/hot_reload.dart';
import 'package:frun/src/domain/usecases/hot_restart.dart';
import 'package:frun/src/domain/usecases/launch_emulator.dart';
import 'package:frun/src/domain/usecases/list_devices.dart';
import 'package:frun/src/domain/usecases/list_emulators.dart';
import 'package:frun/src/domain/usecases/set_config.dart';
import 'package:frun/src/domain/usecases/stop_session.dart';
import 'package:frun/src/domain/usecases/watch_diagnostics.dart';
import 'package:frun/src/domain/value_objects/config_values.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class MockDeviceRepository extends Mock implements DeviceRepository {}

class MockEmulatorRepository extends Mock implements EmulatorRepository {}

class MockSessionRepository extends Mock implements SessionRepository {}

class MockDiagnosticsRepository extends Mock implements DiagnosticsRepository {}

class MockConfigRepository extends Mock implements ConfigRepository {}

// ── Fixtures ──────────────────────────────────────────────────────────────────

const _device = DeviceEntity(
  id: 'emulator-5554',
  name: 'Pixel 7',
  platform: 'android-x64',
  ephemeral: true,
  emulator: true,
);

const _emulator = EmulatorEntity(id: 'Pixel_7_API_34', name: 'Pixel 7 API 34');

const _diagnostic = DiagnosticEntity(
  filePath: '/app/lib/main.dart',
  line: 10,
  column: 5,
  severity: DiagnosticSeverity.error,
  message: 'Undefined name',
);

AppConfigEntity _config() => const AppConfigEntity(
  ide: FrunIde.vscode,
  editorMode: FrunEditorMode.normal,
  theme: FrunThemeMode.dark,
  hotReloadOnSave: true,
  openDevtoolsOnLaunch: FrunDevToolsAutoOpen.ask,
  emulatorBoot: FrunEmulatorBoot.quick,
  verboseErrors: false,
);

// ── Helpers ───────────────────────────────────────────────────────────────────

void _expectSuccess<F, S>(Result<F, S> result, S expected) {
  expect(result.isSuccess, isTrue);
  expect((result as Success<F, S>).value, equals(expected));
}

void _expectFailure<F, S>(Result<F, S> result) {
  expect(result.isFailure, isTrue);
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    registerFallbackValue(const DiagnosticsFilterParams());
    registerFallbackValue(const ConfigSetParams(key: '', value: ''));
    registerFallbackValue(const ReloadParams(tabId: 0));
    registerFallbackValue(const EmulatorLaunchParams(emulator: _emulator));
  });
  // ── ListDevicesUseCase ───────────────────────────────────────────────────────
  group('ListDevicesUseCase', () {
    late MockDeviceRepository repo;

    setUp(() => repo = MockDeviceRepository());

    test('returns Success with devices from repo', () async {
      when(
        () => repo.listDevices(),
      ).thenAnswer((_) async => Result.success([_device]));

      final result = await ListDevicesUseCase(repo).call();

      _expectSuccess(result, [_device]);
      verify(() => repo.listDevices()).called(1);
    });

    test('propagates DeviceFailure from repo', () async {
      when(() => repo.listDevices()).thenAnswer(
        (_) async => Result.failure(const DeviceFailure(message: 'no daemon')),
      );

      final result = await ListDevicesUseCase(repo).call();

      _expectFailure(result);
    });
  });

  // ── ListEmulatorsUseCase ─────────────────────────────────────────────────────
  group('ListEmulatorsUseCase', () {
    late MockEmulatorRepository repo;

    setUp(() => repo = MockEmulatorRepository());

    test('returns Success with emulators', () async {
      when(
        () => repo.listEmulators(),
      ).thenAnswer((_) async => Result.success([_emulator]));

      final result = await ListEmulatorsUseCase(repo).call();

      _expectSuccess(result, [_emulator]);
    });

    test('propagates DeviceFailure', () async {
      when(() => repo.listEmulators()).thenAnswer(
        (_) async =>
            Result.failure(const DeviceFailure(message: 'sdk not found')),
      );

      _expectFailure(await ListEmulatorsUseCase(repo).call());
    });
  });

  // ── LaunchEmulatorUseCase ────────────────────────────────────────────────────
  group('LaunchEmulatorUseCase', () {
    late MockEmulatorRepository repo;

    setUp(() => repo = MockEmulatorRepository());

    test('returns DeviceFailure when params is null', () async {
      final result = await LaunchEmulatorUseCase(repo).call(null);
      _expectFailure(result);
      verifyNever(() => repo.launchEmulator(any()));
    });

    test('delegates to repo and returns device', () async {
      const params = EmulatorLaunchParams(emulator: _emulator);
      when(
        () => repo.launchEmulator(any()),
      ).thenAnswer((_) async => Result.success(_device));

      final result = await LaunchEmulatorUseCase(repo).call(params);

      _expectSuccess(result, _device);
      verify(() => repo.launchEmulator(any())).called(1);
    });

    test('propagates DeviceFailure from repo', () async {
      const params = EmulatorLaunchParams(emulator: _emulator);
      when(() => repo.launchEmulator(any())).thenAnswer(
        (_) async => Result.failure(const DeviceFailure(message: 'timeout')),
      );

      _expectFailure(await LaunchEmulatorUseCase(repo).call(params));
    });
  });

  // ── HotReloadUseCase ─────────────────────────────────────────────────────────
  group('HotReloadUseCase', () {
    late MockSessionRepository repo;

    setUp(() => repo = MockSessionRepository());

    test('returns SessionFailure when params is null', () async {
      _expectFailure(await HotReloadUseCase(repo).call(null));
      verifyNever(() => repo.hotReload(any()));
    });

    test('delegates to repo.hotReload', () async {
      const params = ReloadParams(tabId: 1);
      when(
        () => repo.hotReload(any()),
      ).thenAnswer((_) async => Result.success(null));

      final result = await HotReloadUseCase(repo).call(params);

      expect(result.isSuccess, isTrue);
      verify(() => repo.hotReload(any())).called(1);
    });

    test('propagates SessionFailure from repo', () async {
      const params = ReloadParams(tabId: 1);
      when(() => repo.hotReload(any())).thenAnswer(
        (_) async => Result.failure(const SessionFailure(message: 'no app')),
      );

      _expectFailure(await HotReloadUseCase(repo).call(params));
    });
  });

  // ── HotRestartUseCase ────────────────────────────────────────────────────────
  group('HotRestartUseCase', () {
    late MockSessionRepository repo;

    setUp(() => repo = MockSessionRepository());

    test('returns SessionFailure when params is null', () async {
      _expectFailure(await HotRestartUseCase(repo).call(null));
    });

    test('delegates to repo.hotRestart', () async {
      const params = ReloadParams(tabId: 2);
      when(
        () => repo.hotRestart(any()),
      ).thenAnswer((_) async => Result.success(null));

      expect((await HotRestartUseCase(repo).call(params)).isSuccess, isTrue);
      verify(() => repo.hotRestart(any())).called(1);
    });
  });

  // ── StopSessionUseCase ───────────────────────────────────────────────────────
  group('StopSessionUseCase', () {
    late MockSessionRepository repo;

    setUp(() => repo = MockSessionRepository());

    test('returns SessionFailure when params is null', () async {
      _expectFailure(await StopSessionUseCase(repo).call(null));
    });

    test('delegates to repo.stop', () async {
      const params = ReloadParams(tabId: 1);
      when(
        () => repo.stop(any()),
      ).thenAnswer((_) async => Result.success(null));

      expect((await StopSessionUseCase(repo).call(params)).isSuccess, isTrue);
      verify(() => repo.stop(any())).called(1);
    });
  });

  // ── GetDiagnosticsUseCase ────────────────────────────────────────────────────
  group('GetDiagnosticsUseCase', () {
    late MockDiagnosticsRepository repo;

    setUp(() => repo = MockDiagnosticsRepository());

    test('calls repo with empty filter when no params', () async {
      when(
        () => repo.getDiagnostics(any()),
      ).thenAnswer((_) async => Result.success([_diagnostic]));

      final result = await GetDiagnosticsUseCase(repo).call();

      _expectSuccess(result, [_diagnostic]);
      verify(
        () => repo.getDiagnostics(const DiagnosticsFilterParams()),
      ).called(1);
    });

    test('passes filter params to repo', () async {
      const params = DiagnosticsFilterParams(
        category: DiagnosticCategory.error,
      );
      when(
        () => repo.getDiagnostics(any()),
      ).thenAnswer((_) async => Result.success([_diagnostic]));

      final result = await GetDiagnosticsUseCase(repo).call(params);

      _expectSuccess(result, [_diagnostic]);
    });

    test('propagates AnalysisFailure', () async {
      when(() => repo.getDiagnostics(any())).thenAnswer(
        (_) async =>
            Result.failure(const AnalysisFailure(message: 'server down')),
      );

      _expectFailure(await GetDiagnosticsUseCase(repo).call());
    });
  });

  // ── WatchDiagnosticsUseCase ──────────────────────────────────────────────────
  group('WatchDiagnosticsUseCase', () {
    late MockDiagnosticsRepository repo;

    setUp(() => repo = MockDiagnosticsRepository());

    test('maps repo stream to Result.success events', () async {
      when(
        () => repo.watchDiagnostics(any()),
      ).thenAnswer((_) => Stream.value([_diagnostic]));

      final events = await WatchDiagnosticsUseCase(repo).call().toList();

      expect(events.length, 1);
      _expectSuccess(events.first, [_diagnostic]);
    });
  });

  // ── GetConfigUseCase ─────────────────────────────────────────────────────────
  group('GetConfigUseCase', () {
    late MockConfigRepository repo;

    setUp(() => repo = MockConfigRepository());

    test('returns AppConfigEntity from repo', () async {
      final entity = _config();
      when(
        () => repo.getConfig(),
      ).thenAnswer((_) async => Result.success(entity));

      final result = await GetConfigUseCase(repo).call();

      _expectSuccess(result, entity);
      verify(() => repo.getConfig()).called(1);
    });

    test('propagates ConfigFailure', () async {
      when(() => repo.getConfig()).thenAnswer(
        (_) async =>
            Result.failure(const ConfigFailure(message: 'file missing')),
      );

      _expectFailure(await GetConfigUseCase(repo).call());
    });
  });

  // ── SetConfigUseCase ─────────────────────────────────────────────────────────
  group('SetConfigUseCase', () {
    late MockConfigRepository repo;

    setUp(() => repo = MockConfigRepository());

    test('returns ConfigFailure when params is null', () async {
      _expectFailure(await SetConfigUseCase(repo).call(null));
      verifyNever(() => repo.setConfig(any()));
    });

    test('delegates to repo.setConfig', () async {
      const params = ConfigSetParams(key: 'ide', value: 'zed');
      when(
        () => repo.setConfig(any()),
      ).thenAnswer((_) async => Result.success(null));

      expect((await SetConfigUseCase(repo).call(params)).isSuccess, isTrue);
      verify(() => repo.setConfig(any())).called(1);
    });

    test('propagates ConfigFailure from repo', () async {
      const params = ConfigSetParams(key: 'ide', value: 'bad');
      when(() => repo.setConfig(any())).thenAnswer(
        (_) async =>
            Result.failure(const ConfigFailure(message: 'unknown key')),
      );

      _expectFailure(await SetConfigUseCase(repo).call(params));
    });
  });
}
