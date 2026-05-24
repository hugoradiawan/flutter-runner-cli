import '../config/config.dart';
import '../daemon/flutter_daemon.dart';
import '../devices/device_manager.dart';
import '../ide/ide_launcher.dart';
import '../ide/inspector_bridge.dart';
import '../project/launch_config.dart';
import '../project/project_detector.dart';
import '../vm/isolate_manager.dart';
import 'run_controller.dart';
import 'transcript.dart';

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

  /// Selected device id (set by `/devices` or remembered from config). Wired
  /// in M3; lives here so M2 can render a status placeholder.
  String? selectedDeviceId;

  /// Once the daemon has started, services are populated. Until then the
  /// status panel and `/devices` command surface a "starting" message.
  FlutterDaemon? daemon;
  DeviceManager? deviceManager;
  late final RunController runController = RunController(this);
  late final IsolateManager isolateManager = IsolateManager();
  late final IdeLauncher ideLauncher = IdeLauncher();
  late final InspectorBridge inspectorBridge = InspectorBridge();
  bool daemonReady = false;
  String? daemonError;

  /// `true` while the user has indicated they want to quit (via `/quit` or
  /// Ctrl-C). The TUI runner watches this between events.
  bool quitRequested = false;

  /// Whether the bottom status block is rendered. Toggled by `/status`.
  bool showStatusPanel = false;

  /// Active `/run` picker. When non-empty, the TUI renders a button bar of
  /// launch entries above the input line. Cleared after the user picks one
  /// or dismisses the picker.
  List<LaunchEntry> launchChoices = const <LaunchEntry>[];
}
