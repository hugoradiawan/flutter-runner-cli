import '../../data/data.dart';
import '../../domain/domain.dart';

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
  Dependencies({IsolateManager? isolateManager, Notifier? notifier})
    : isolateManager = isolateManager ?? IsolateManager(),
      notifier = notifier ?? const DesktopNotifier();

  // ── Eager infrastructure services ─────────────────────────────────────────
  final IsolateManager isolateManager;
  final IdeLauncher ideLauncher = const DesktopIdeLauncher();
  late final InspectorBridge inspectorBridge = InspectorBridge(
    extensionEvents: isolateManager.extensionEvents,
  );
  final Notifier notifier;
  final VmUriResolver vmUriResolver = const PackageConfigUriResolver();

  /// Builds a debounced source-tree watcher (hot-reload-on-save). A factory
  /// because watchers are created lazily per run session and torn down when
  /// the controller goes idle.
  SourceChangeWatcher Function({
    required String root,
    void Function(String path)? onFileChanged,
    void Function(Object error)? onError,
  })
  get sourceWatcherFactory =>
      ({required root, onFileChanged, onError}) => DartFileWatcher(
        root: root,
        onFileChanged: onFileChanged,
        onWatcherError: onError,
      );

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
  LaunchRepository? launchRepository;

  /// Owns every live `flutter run` session. Unlike the daemon-backed repos it
  /// needs no async boot, so it is non-nullable — as are its use cases.
  /// Overridable for tests.
  SessionRepository sessionRepository = SessionRepositoryImpl();

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

  StartSessionUseCase? _startSession;
  StartSessionUseCase get startSessionUseCase =>
      _startSession ??= StartSessionUseCase(sessionRepository);

  HotReloadUseCase? _hotReload;
  HotReloadUseCase get hotReloadUseCase =>
      _hotReload ??= HotReloadUseCase(sessionRepository);

  HotRestartUseCase? _hotRestart;
  HotRestartUseCase get hotRestartUseCase =>
      _hotRestart ??= HotRestartUseCase(sessionRepository);

  StopSessionUseCase? _stopSession;
  StopSessionUseCase get stopSessionUseCase =>
      _stopSession ??= StopSessionUseCase(sessionRepository);

  DetachSessionUseCase? _detachSession;
  DetachSessionUseCase get detachSessionUseCase =>
      _detachSession ??= DetachSessionUseCase(sessionRepository);

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
