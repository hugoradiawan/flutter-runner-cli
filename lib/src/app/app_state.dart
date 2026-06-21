import '../analysis/analysis_server.dart';
import '../analysis/diagnostic.dart';
import '../analysis/diagnostics_store.dart';
import '../config/config.dart';
import '../daemon/daemon_messages.dart';
import '../daemon/flutter_daemon.dart';
import '../devices/device_manager.dart';
import '../domain/repositories/config_repository.dart';
import '../domain/repositories/device_repository.dart';
import '../domain/repositories/diagnostics_repository.dart';
import '../domain/repositories/emulator_repository.dart';
import '../domain/repositories/session_repository.dart';
import '../domain/usecases/get_config.usecase.dart';
import '../domain/usecases/get_diagnostics.usecase.dart';
import '../domain/usecases/list_devices.usecase.dart';
import '../domain/usecases/list_emulators.usecase.dart';
import '../domain/usecases/set_config.usecase.dart';
import '../domain/usecases/watch_diagnostics.usecase.dart';
import '../ide/frun_notifier.dart';
import '../ide/ide_launcher.dart';
import '../ide/inspector_bridge.dart';
import '../project/launch_config.dart';
import '../project/project_detector.dart';
import '../vm/isolate_manager.dart';
import '../watcher/dart_file_watcher.dart';
import 'run_controller.dart';
import 'run_target.dart';
import 'transcript.dart';

export 'run_target.dart';

/// Mutable, observable-ish state shared between the TUI shell, commands, and
/// services. Components read it during build; commands and services mutate it.
class AppState {
  AppState({required this.project, required FrunConfig config})
    : _config = config,
      transcript = Transcript();

  final FlutterProject project;

  /// The "system" transcript — boot banner, project info, `/devices`, `/help`,
  /// daemon errors. Anything not tied to a specific running session. Per-tab
  /// logs live on each [RunTab.transcript]; see [visibleTranscript].
  final Transcript transcript;

  /// What the TUI renders in the body panel: the active tab's log if any tab
  /// is open, otherwise the system transcript.
  Transcript get visibleTranscript =>
      runController.activeTab?.transcript ?? transcript;

  FrunConfig _config;
  FrunConfig get config => _config;

  /// Replace the config — call after editing via `/config set ...` or the
  /// upcoming first-run wizard.
  void setConfig(FrunConfig next) {
    _config = next;
  }

  /// Once the daemon has started, services are populated. Until then the
  /// status panel and `/devices` command surface a "starting" message.
  FlutterDaemon? daemon;
  DeviceManager? deviceManager;

  // ── CA repositories (set when respective services start) ──────────────────
  IDeviceRepository? deviceRepository;
  IEmulatorRepository? emulatorRepository;
  IDiagnosticsRepository? diagnosticsRepository;
  IConfigRepository? configRepository;
  ISessionRepository? sessionRepository;

  // ── UseCase accessors (constructed on demand from repos) ──────────────────
  ListDevicesUseCase? get listDevicesUseCase =>
      deviceRepository != null ? ListDevicesUseCase(deviceRepository!) : null;

  ListEmulatorsUseCase? get listEmulatorsUseCase =>
      emulatorRepository != null ? ListEmulatorsUseCase(emulatorRepository!) : null;

  GetDiagnosticsUseCase? get getDiagnosticsUseCase =>
      diagnosticsRepository != null
          ? GetDiagnosticsUseCase(diagnosticsRepository!)
          : null;

  WatchDiagnosticsUseCase? get watchDiagnosticsUseCase =>
      diagnosticsRepository != null
          ? WatchDiagnosticsUseCase(diagnosticsRepository!)
          : null;

  GetConfigUseCase? get getConfigUseCase =>
      configRepository != null ? GetConfigUseCase(configRepository!) : null;

  SetConfigUseCase? get setConfigUseCase =>
      configRepository != null ? SetConfigUseCase(configRepository!) : null;
  late final RunController runController = RunController(this);
  late final IsolateManager isolateManager = IsolateManager();
  late final IdeLauncher ideLauncher = IdeLauncher();
  late final InspectorBridge inspectorBridge = InspectorBridge();
  final FrunNotifier notifier = const FrunNotifier();
  bool daemonReady = false;
  String? daemonError;

  /// `true` while the user has indicated they want to quit (via `/quit` or
  /// Ctrl-C). The TUI runner watches this between events.
  bool quitRequested = false;

  /// Whether the bottom status block is rendered. Toggled by `/status`.
  bool showStatusPanel = false;

  /// Set to `true` by `/config` to trigger the interactive footer editor.
  bool showConfigEditor = false;

  // ── Diagnostics (analyzer errors / warnings / infos) ──────────────────────

  /// The Dart analysis server client (LSP). Null until the analysis boot
  /// completes, and null forever if `dart` isn't on the PATH.
  DartAnalysisServer? analysisServer;

  /// Per-project on-disk cache for [diagnostics].
  DiagnosticsStore? diagnosticsStore;

  /// Set when the analysis server fails to start.
  String? analysisError;

  /// Always-on watcher that keeps the analyzer's view of edited files in sync
  /// with disk (re-opens/re-pushes changed `.dart` files as priority docs).
  /// Independent of the run controller's hot-reload watcher.
  DartFileWatcher? analysisWatcher;

  /// Latest project-wide analyzer diagnostics. Updated in realtime by the
  /// analysis server; seeded from the cache on launch so counters show
  /// last-known totals immediately.
  List<Diagnostic> diagnostics = const <Diagnostic>[];

  /// Whether the diagnostics ("problems") overlay is open. Toggled by
  /// `/diagnostics`, by clicking the prompt-box counters, or closed with esc.
  bool showDiagnosticsPanel = false;

  /// Active category filter in the diagnostics overlay; null = show all.
  DiagnosticCategory? diagnosticsFilter;

  /// Free-text filter applied to the diagnostics overlay (matches file path or
  /// message). Empty = no text filter.
  String diagnosticsSearch = '';

  /// Active `/run` picker. When non-empty, the TUI renders a button bar of
  /// launch entries above the input line. Cleared after the user picks one
  /// or dismisses the picker.
  List<LaunchEntry> launchChoices = const <LaunchEntry>[];

  /// Active `/emulators` picker. Same shape as [launchChoices] — only one
  /// picker is open at a time; opening one clears the others.
  List<FlutterEmulator> emulatorChoices = const <FlutterEmulator>[];

  /// Launch entry awaiting a run-target choice. Set when the user picks an
  /// entry in the `/run` launch picker; cleared once a target is chosen.
  LaunchEntry? pendingRunEntry;

  /// Active `/run` target picker — connected devices plus offline emulators.
  List<RunTarget> runTargetChoices = const <RunTarget>[];

  /// Emulator id waiting for boot mode selection.
  String? pendingEmulatorId;

  /// Boot mode picker choices — `['quick', 'cold']` when active, else empty.
  List<String> bootModeChoices = const <String>[];

  bool get hasActivePicker =>
      launchChoices.isNotEmpty ||
      emulatorChoices.isNotEmpty ||
      bootModeChoices.isNotEmpty ||
      runTargetChoices.isNotEmpty;

  void clearPickers() {
    launchChoices = const <LaunchEntry>[];
    emulatorChoices = const <FlutterEmulator>[];
    bootModeChoices = const <String>[];
    pendingEmulatorId = null;
    runTargetChoices = const <RunTarget>[];
  }

  void setLaunchPicker(List<LaunchEntry> entries) {
    clearPickers();
    launchChoices = entries;
  }

  void setEmulatorPicker(List<FlutterEmulator> emulators) {
    clearPickers();
    emulatorChoices = emulators;
  }

  void setBootModePicker(String emulatorId) {
    clearPickers();
    pendingEmulatorId = emulatorId;
    bootModeChoices = const <String>['quick', 'cold'];
  }

  void setRunTargetPicker(List<RunTarget> targets) {
    clearPickers();
    runTargetChoices = targets;
  }
}
