import 'package:frun/src/ca/result.dart';
import 'package:frun/src/domain/entities/app_config.entity.dart';
import 'package:frun/src/domain/entities/device.entity.dart';
import 'package:frun/src/domain/entities/diagnostic.entity.dart';
import 'package:frun/src/domain/entities/emulator.entity.dart';
import 'package:frun/src/domain/entities/launch_entry.entity.dart';
import 'package:frun/src/domain/entities/run_session.entity.dart';
import 'package:frun/src/domain/failures/analysis_failure.dart';
import 'package:frun/src/domain/failures/config_failure.dart';
import 'package:frun/src/domain/failures/device_failure.dart';
import 'package:frun/src/domain/failures/session_failure.dart';
import 'package:frun/src/domain/params/config.params.dart';
import 'package:frun/src/domain/params/diagnostics_filter.params.dart';
import 'package:frun/src/domain/params/emulator_launch.params.dart';
import 'package:frun/src/domain/params/reload.params.dart';
import 'package:frun/src/domain/params/run.params.dart';
import 'package:frun/src/domain/repositories/config_repository.dart';
import 'package:frun/src/domain/repositories/device_repository.dart';
import 'package:frun/src/domain/repositories/diagnostics_repository.dart';
import 'package:frun/src/domain/repositories/emulator_repository.dart';
import 'package:frun/src/domain/repositories/session_repository.dart';
import 'package:frun/src/domain/usecases/get_config.usecase.dart';
import 'package:frun/src/domain/usecases/get_diagnostics.usecase.dart';
import 'package:frun/src/domain/usecases/hot_reload.usecase.dart';
import 'package:frun/src/domain/usecases/hot_restart.usecase.dart';
import 'package:frun/src/domain/usecases/launch_app.usecase.dart';
import 'package:frun/src/domain/usecases/launch_emulator.usecase.dart';
import 'package:frun/src/domain/usecases/list_devices.usecase.dart';
import 'package:frun/src/domain/usecases/list_emulators.usecase.dart';
import 'package:frun/src/domain/usecases/set_config.usecase.dart';
import 'package:frun/src/domain/usecases/stop_session.usecase.dart';
import 'package:frun/src/domain/usecases/watch_devices.usecase.dart';
import 'package:frun/src/domain/usecases/watch_diagnostics.usecase.dart';
import 'package:frun/src/domain/usecases/watch_logs.usecase.dart';
import 'package:frun/src/domain/value_objects/config_values.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class MockDeviceRepository extends Mock implements IDeviceRepository {}

class MockEmulatorRepository extends Mock implements IEmulatorRepository {}

class MockSessionRepository extends Mock implements ISessionRepository {}

class MockDiagnosticsRepository extends Mock implements IDiagnosticsRepository {}

class MockConfigRepository extends Mock implements IConfigRepository {}

// ── Fixtures ──────────────────────────────────────────────────────────────────

const _device = DeviceEntity(
  id: 'emulator-5554',
  name: 'Pixel 7',
  platform: 'android-x64',
  ephemeral: true,
  emulator: true,
);

const _emulator = EmulatorEntity(id: 'Pixel_7_API_34', name: 'Pixel 7 API 34');

const _entry = LaunchEntryEntity(name: 'main', program: 'lib/main.dart');

const _session = RunSessionEntity(
  tabId: 1,
  entry: _entry,
  deviceId: 'emulator-5554',
  isRunning: true,
);

const _diagnostic = DiagnosticEntity(
  filePath: '/app/lib/main.dart',
  line: 10,
  column: 5,
  severity: DiagnosticSeverity.error,
  message: 'Undefined name',
);

AppConfigEntity _config() => AppConfigEntity(
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
    registerFallbackValue(EmulatorLaunchParams(emulator: _emulator));
    registerFallbackValue(RunParams(entry: _entry, device: _device));
  });
  // ── ListDevicesUseCase ───────────────────────────────────────────────────────
  group('ListDevicesUseCase', () {
    late MockDeviceRepository repo;

    setUp(() => repo = MockDeviceRepository());

    test('returns Success with devices from repo', () async {
      when(() => repo.listDevices())
          .thenAnswer((_) async => Result.success([_device]));

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

  // ── WatchDevicesUseCase ──────────────────────────────────────────────────────
  group('WatchDevicesUseCase', () {
    late MockDeviceRepository repo;

    setUp(() => repo = MockDeviceRepository());

    test('maps repo stream to Result.success', () async {
      when(() => repo.watchDevices())
          .thenAnswer((_) => Stream.value([_device]));

      final events =
          await WatchDevicesUseCase(repo).call().toList();

      expect(events.length, 1);
      _expectSuccess(events.first, [_device]);
    });
  });

  // ── ListEmulatorsUseCase ─────────────────────────────────────────────────────
  group('ListEmulatorsUseCase', () {
    late MockEmulatorRepository repo;

    setUp(() => repo = MockEmulatorRepository());

    test('returns Success with emulators', () async {
      when(() => repo.listEmulators())
          .thenAnswer((_) async => Result.success([_emulator]));

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
      final params = EmulatorLaunchParams(emulator: _emulator);
      when(() => repo.launchEmulator(any()))
          .thenAnswer((_) async => Result.success(_device));

      final result = await LaunchEmulatorUseCase(repo).call(params);

      _expectSuccess(result, _device);
      verify(() => repo.launchEmulator(any())).called(1);
    });

    test('propagates DeviceFailure from repo', () async {
      final params = EmulatorLaunchParams(emulator: _emulator);
      when(() => repo.launchEmulator(any())).thenAnswer(
        (_) async => Result.failure(const DeviceFailure(message: 'timeout')),
      );

      _expectFailure(await LaunchEmulatorUseCase(repo).call(params));
    });
  });

  // ── LaunchAppUseCase ─────────────────────────────────────────────────────────
  group('LaunchAppUseCase', () {
    late MockSessionRepository repo;

    setUp(() => repo = MockSessionRepository());

    test('returns SessionFailure when params is null', () async {
      final result = await LaunchAppUseCase(repo).call(null);
      _expectFailure(result);
      verifyNever(() => repo.launch(any()));
    });

    test('delegates to repo on success', () async {
      final params = RunParams(entry: _entry, device: _device);
      when(() => repo.launch(any()))
          .thenAnswer((_) async => Result.success(_session));

      final result = await LaunchAppUseCase(repo).call(params);

      _expectSuccess(result, _session);
      verify(() => repo.launch(any())).called(1);
    });

    test('propagates SessionFailure', () async {
      final params = RunParams(entry: _entry, device: _device);
      when(() => repo.launch(any())).thenAnswer(
        (_) async =>
            Result.failure(const SessionFailure(message: 'build failed')),
      );

      _expectFailure(await LaunchAppUseCase(repo).call(params));
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
      final params = ReloadParams(tabId: 1);
      when(() => repo.hotReload(any()))
          .thenAnswer((_) async => Result.success(null));

      final result = await HotReloadUseCase(repo).call(params);

      expect(result.isSuccess, isTrue);
      verify(() => repo.hotReload(any())).called(1);
    });

    test('propagates SessionFailure from repo', () async {
      final params = ReloadParams(tabId: 1);
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
      final params = ReloadParams(tabId: 2);
      when(() => repo.hotRestart(any()))
          .thenAnswer((_) async => Result.success(null));

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
      final params = ReloadParams(tabId: 1);
      when(() => repo.stop(any()))
          .thenAnswer((_) async => Result.success(null));

      expect((await StopSessionUseCase(repo).call(params)).isSuccess, isTrue);
      verify(() => repo.stop(any())).called(1);
    });
  });

  // ── WatchLogsUseCase ─────────────────────────────────────────────────────────
  group('WatchLogsUseCase', () {
    late MockSessionRepository repo;

    setUp(() => repo = MockSessionRepository());

    test('returns single SessionFailure event when params is null', () async {
      final events = await WatchLogsUseCase(repo).call(null).toList();
      expect(events.length, 1);
      _expectFailure(events.first);
    });

    test('maps repo log stream to Result.success', () async {
      final params = ReloadParams(tabId: 1);
      when(() => repo.watchLogs(any()))
          .thenAnswer((_) => Stream.fromIterable(['line 1', 'line 2']));

      final events = await WatchLogsUseCase(repo).call(params).toList();

      expect(events.length, 2);
      expect(events.every((r) => r.isSuccess), isTrue);
      expect((events.first as Success).value, 'line 1');
      expect((events.last as Success).value, 'line 2');
    });
  });

  // ── GetDiagnosticsUseCase ────────────────────────────────────────────────────
  group('GetDiagnosticsUseCase', () {
    late MockDiagnosticsRepository repo;

    setUp(() => repo = MockDiagnosticsRepository());

    test('calls repo with empty filter when no params', () async {
      when(() => repo.getDiagnostics(any()))
          .thenAnswer((_) async => Result.success([_diagnostic]));

      final result = await GetDiagnosticsUseCase(repo).call();

      _expectSuccess(result, [_diagnostic]);
      verify(() => repo.getDiagnostics(const DiagnosticsFilterParams()))
          .called(1);
    });

    test('passes filter params to repo', () async {
      const params =
          DiagnosticsFilterParams(category: DiagnosticCategory.error);
      when(() => repo.getDiagnostics(any()))
          .thenAnswer((_) async => Result.success([_diagnostic]));

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
      when(() => repo.watchDiagnostics(any()))
          .thenAnswer((_) => Stream.value([_diagnostic]));

      final events =
          await WatchDiagnosticsUseCase(repo).call().toList();

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
      when(() => repo.getConfig())
          .thenAnswer((_) async => Result.success(entity));

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
      when(() => repo.setConfig(any()))
          .thenAnswer((_) async => Result.success(null));

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
