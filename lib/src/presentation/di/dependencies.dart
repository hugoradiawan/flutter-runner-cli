import '../../data/datasources/analysis_server.dart';
import '../../data/datasources/device_manager.dart';
import '../../data/datasources/flutter_daemon.dart';
import '../../data/services/dart_file_watcher.dart';
import '../../data/services/frun_notifier.dart';
import '../../data/services/ide_launcher.dart';
import '../../data/services/inspector_bridge.dart';
import '../../data/services/isolate_manager.dart';
import '../../domain/repositories/config_repository.dart';
import '../../domain/repositories/device_repository.dart';
import '../../domain/repositories/diagnostics_repository.dart';
import '../../domain/repositories/emulator_repository.dart';
import '../../domain/repositories/session_repository.dart';
import '../../domain/usecases/get_config.dart';
import '../../domain/usecases/get_diagnostics.dart';
import '../../domain/usecases/hot_reload.dart';
import '../../domain/usecases/hot_restart.dart';
import '../../domain/usecases/launch_emulator.dart';
import '../../domain/usecases/list_devices.dart';
import '../../domain/usecases/list_emulators.dart';
import '../../domain/usecases/save_config.dart';
import '../../domain/usecases/set_config.dart';
import '../../domain/usecases/stop_session.dart';
import '../../domain/usecases/watch_diagnostics.dart';

/// Dependency container assembled at the composition root ([runFrun]).
///
/// Owns the long-lived infrastructure services and the Clean-Architecture
/// repositories, and hands out use cases built **once** from those
/// repositories. The daemon and the analysis server boot in the background, so
/// each backing repository is nullable until its service is ready and every
/// use-case accessor returns null until its repository exists.
///
/// This is the only seam where the presentation layer reaches concrete data
/// types; everything else depends on domain abstractions handed out here.
class Dependencies {
  // ── Eager infrastructure services ─────────────────────────────────────────
  final IsolateManager isolateManager = IsolateManager();
  final IdeLauncher ideLauncher = IdeLauncher();
  final InspectorBridge inspectorBridge = InspectorBridge();
  final FrunNotifier notifier = const FrunNotifier();

  // ── Services populated as the daemon comes up ─────────────────────────────
  FlutterDaemon? daemon;
  DeviceManager? deviceManager;
  bool daemonReady = false;
  String? daemonError;

  // ── Services populated as the analysis server comes up ────────────────────
  DartAnalysisServer? analysisServer;
  DartFileWatcher? analysisWatcher;
  String? analysisError;

  // ── CA repositories (set when their backing service starts) ───────────────
  DeviceRepository? deviceRepository;
  EmulatorRepository? emulatorRepository;
  DiagnosticsRepository? diagnosticsRepository;
  ConfigRepository? configRepository;
  SessionRepository? sessionRepository;

  // ── Use cases (built once, lazily, from their repository) ─────────────────
  ListDevicesUseCase? _listDevices;
  ListDevicesUseCase? get listDevicesUseCase => deviceRepository == null
      ? null
      : (_listDevices ??= ListDevicesUseCase(deviceRepository!));

  ListEmulatorsUseCase? _listEmulators;
  ListEmulatorsUseCase? get listEmulatorsUseCase => emulatorRepository == null
      ? null
      : (_listEmulators ??= ListEmulatorsUseCase(emulatorRepository!));

  LaunchEmulatorUseCase? _launchEmulator;
  LaunchEmulatorUseCase? get launchEmulatorUseCase => emulatorRepository == null
      ? null
      : (_launchEmulator ??= LaunchEmulatorUseCase(emulatorRepository!));

  GetDiagnosticsUseCase? _getDiagnostics;
  GetDiagnosticsUseCase? get getDiagnosticsUseCase =>
      diagnosticsRepository == null
      ? null
      : (_getDiagnostics ??= GetDiagnosticsUseCase(diagnosticsRepository!));

  WatchDiagnosticsUseCase? _watchDiagnostics;
  WatchDiagnosticsUseCase? get watchDiagnosticsUseCase =>
      diagnosticsRepository == null
      ? null
      : (_watchDiagnostics ??= WatchDiagnosticsUseCase(diagnosticsRepository!));

  GetConfigUseCase? _getConfig;
  GetConfigUseCase? get getConfigUseCase => configRepository == null
      ? null
      : (_getConfig ??= GetConfigUseCase(configRepository!));

  SetConfigUseCase? _setConfig;
  SetConfigUseCase? get setConfigUseCase => configRepository == null
      ? null
      : (_setConfig ??= SetConfigUseCase(configRepository!));

  SaveConfigUseCase? _saveConfig;
  SaveConfigUseCase? get saveConfigUseCase => configRepository == null
      ? null
      : (_saveConfig ??= SaveConfigUseCase(configRepository!));

  HotReloadUseCase? _hotReload;
  HotReloadUseCase? get hotReloadUseCase => sessionRepository == null
      ? null
      : (_hotReload ??= HotReloadUseCase(sessionRepository!));

  HotRestartUseCase? _hotRestart;
  HotRestartUseCase? get hotRestartUseCase => sessionRepository == null
      ? null
      : (_hotRestart ??= HotRestartUseCase(sessionRepository!));

  StopSessionUseCase? _stopSession;
  StopSessionUseCase? get stopSessionUseCase => sessionRepository == null
      ? null
      : (_stopSession ??= StopSessionUseCase(sessionRepository!));
}
