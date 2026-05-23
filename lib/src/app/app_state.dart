import '../config/config.dart';
import '../daemon/flutter_daemon.dart';
import '../devices/device_manager.dart';
import '../ide/ide_launcher.dart';
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
  final Transcript transcript;

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
  bool daemonReady = false;
  String? daemonError;

  /// `true` while the user has indicated they want to quit (via `/quit` or
  /// Ctrl-C). The TUI runner watches this between events.
  bool quitRequested = false;

  /// Whether the bottom status block is rendered. Toggled by `/status`.
  bool showStatusPanel = true;
}
