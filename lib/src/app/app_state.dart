import '../config/config.dart';
import '../daemon/daemon_messages.dart';
import '../daemon/flutter_daemon.dart';
import '../devices/device_manager.dart';
import '../ide/frun_notifier.dart';
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

  /// Once the daemon has started, services are populated. Until then the
  /// status panel and `/devices` command surface a "starting" message.
  FlutterDaemon? daemon;
  DeviceManager? deviceManager;
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

/// A target the user can pick from the `/run` picker: a connected device, or an
/// offline emulator that must be booted first ([needsBoot] = true).
class RunTarget {
  const RunTarget({
    required this.id,
    required this.name,
    required this.platform,
    required this.needsBoot,
  });

  /// Device id (connected target) or emulator id (offline target to boot).
  final String id;
  final String name;

  /// Platform string for a device, or platformType for an emulator. May be ''.
  final String platform;

  /// `true` when [id] is an offline emulator that must be launched before run.
  final bool needsBoot;

  factory RunTarget.device(FlutterDevice d) => RunTarget(
    id: d.id,
    name: d.name,
    platform: d.platform,
    needsBoot: false,
  );

  factory RunTarget.emulator(FlutterEmulator e) => RunTarget(
    id: e.id,
    name: e.name,
    platform: e.platformType ?? '',
    needsBoot: true,
  );
}
