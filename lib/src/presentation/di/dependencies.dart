import '../../data/datasources/analysis_server.dart';
import '../../data/datasources/device_manager.dart';
import '../../data/datasources/flutter_daemon.dart';
import '../../data/services/desktop_notifier.dart';
import '../../data/services/ide_launcher.dart';
import '../../data/services/inspector_bridge.dart';
import '../../data/services/isolate_manager.dart';
import '../../data/services/live_diagnostics.dart';
import '../../data/services/package_config_uri_resolver.dart';
import '../../domain/ports/ide_launcher.dart';
import '../../domain/ports/notifier.dart';
import '../../domain/ports/vm_uri_resolver.dart';
import '../../domain/repositories/config_repository.dart';
import '../../domain/repositories/device_repository.dart';
import '../../domain/repositories/diagnostics_repository.dart';
import '../../domain/repositories/emulator_repository.dart';
import '../../domain/repositories/launch_repository.dart';
import '../../domain/repositories/session_repository.dart';
import '../../domain/usecases/analyze_project.dart';
import '../../domain/usecases/create_emulator.dart';
import '../../domain/usecases/discover_launch_entries.dart';
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
/// repositories. The daemon boots in the background, so daemon-backed
/// repositories are nullable until the service is ready and every use-case
/// accessor returns null until its repository exists.
///
/// This is the only seam where the presentation layer reaches concrete data
/// types; everything else depends on domain abstractions handed out here.
class Dependencies {
  Dependencies({IsolateManager? isolateManager})
    : isolateManager = isolateManager ?? IsolateManager();

  // ── Eager infrastructure services ─────────────────────────────────────────
  final IsolateManager isolateManager;
  final IdeLauncher ideLauncher = const DesktopIdeLauncher();
  late final InspectorBridge inspectorBridge = InspectorBridge(
    extensionEvents: isolateManager.extensionEvents,
  );
  final Notifier notifier = const DesktopNotifier();
  final VmUriResolver vmUriResolver = const PackageConfigUriResolver();

  // ── Services populated as the daemon comes up ─────────────────────────────
  FlutterDaemon? daemon;
  DeviceManager? deviceManager;
  bool daemonReady = false;
  String? daemonError;

  // ── CA repositories (set when their backing service starts) ───────────────
  DeviceRepository? deviceRepository;
  EmulatorRepository? emulatorRepository;
  ConfigRepository? configRepository;
  DiagnosticsRepository? diagnosticsRepository;
  SessionRepository? sessionRepository;
  LaunchRepository? launchRepository;

  // ── Live diagnostics services ────────────────────────────────────────────
  DartAnalysisServer? analysisServer;

  /// The live analyzer + TODO pipeline. Set by `_bootLiveDiagnostics`; owns
  /// the TODO index, the source watcher, and the merged publish debounce.
  LiveDiagnosticsCoordinator? liveDiagnostics;

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

  AnalyzeProjectUseCase? _analyzeProject;
  AnalyzeProjectUseCase? get analyzeProjectUseCase =>
      diagnosticsRepository == null
      ? null
      : (_analyzeProject ??= AnalyzeProjectUseCase(diagnosticsRepository!));

  CreateEmulatorUseCase? _createEmulator;
  CreateEmulatorUseCase? get createEmulatorUseCase => emulatorRepository == null
      ? null
      : (_createEmulator ??= CreateEmulatorUseCase(emulatorRepository!));

  DiscoverLaunchEntriesUseCase? _discoverLaunchEntries;
  DiscoverLaunchEntriesUseCase? get discoverLaunchEntriesUseCase =>
      launchRepository == null
      ? null
      : (_discoverLaunchEntries ??= DiscoverLaunchEntriesUseCase(
          launchRepository!,
        ));

  /// Tear down every service this container owns. Called once by the
  /// composition root after the TUI run loop exits.
  Future<void> dispose() async {
    await isolateManager.disconnect();
    await liveDiagnostics?.dispose();
    await analysisServer?.shutdown();
    await daemon?.shutdown();
  }
}
