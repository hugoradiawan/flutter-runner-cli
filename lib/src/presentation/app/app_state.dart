import '../../domain/domain.dart';
import '../di/dependencies.dart';
import 'run_controller.dart';
import 'run_target.dart';
import 'transcript.dart';

export 'run_target.dart';

/// Mutable, presentation-only state shared between the TUI shell, commands, and
/// services. Components read it during build; commands and services mutate it.
///
/// Everything the app can *do* lives on [deps] (the dependency container);
/// everything the app is *showing* lives here.
class AppState {
  AppState({
    required this.project,
    required AppConfigEntity config,
    required this.deps,
  }) : _config = config,
       transcript = Transcript();

  final FlutterProjectEntity project;

  /// Use cases, repositories, and infrastructure services, assembled at the
  /// composition root. See [Dependencies].
  final Dependencies deps;

  /// The "system" transcript — boot banner, project info, `/devices`, `/help`,
  /// daemon errors. Anything not tied to a specific running session. Per-tab
  /// logs live on each [RunTab.transcript]; see [visibleTranscript].
  final Transcript transcript;

  /// What the TUI renders in the body panel: the active tab's log if any tab
  /// is open, otherwise the system transcript.
  Transcript get visibleTranscript =>
      runController.activeTab?.transcript ?? transcript;

  AppConfigEntity _config;
  AppConfigEntity get config => _config;

  /// Replace the in-memory config — call after editing via `/config set ...`
  /// or the config editor overlay. Applies any config-driven runtime state
  /// (currently the scrollback cap) to all live transcripts so the change takes
  /// effect immediately, not just on the next launch.
  void setConfig(AppConfigEntity next) {
    _config = next;
    Transcript.defaultMaxLines = next.scrollbackLines;
    transcript.maxLines = next.scrollbackLines;
    for (final tab in runController.tabs) {
      tab.transcript.maxLines = next.scrollbackLines;
    }
  }

  /// The file-system path where config is persisted.
  String get configPath => deps.configRepository?.getConfigPath() ?? '';

  late final RunController runController = RunController(this);

  /// `true` while the user has indicated they want to quit (via `/quit` or
  /// Ctrl-C). The TUI runner watches this between events.
  bool quitRequested = false;

  /// Whether the bottom status block is rendered. Toggled by `/status`.
  bool showStatusPanel = false;

  /// Set to `true` by `/config` to trigger the interactive footer editor.
  bool showConfigEditor = false;

  // ── Diagnostics (analyzer errors / warnings / infos) ──────────────────────

  static const int _maxDiagnostics = 2000;

  List<DiagnosticEntity> _diagnostics = const <DiagnosticEntity>[];
  int _diagnosticsRevision = 0;

  /// Latest project-wide analyzer diagnostics. Updated in realtime by the
  /// analysis server; seeded from the cache on launch so counters show
  /// last-known totals immediately. Capped at [_maxDiagnostics] entries;
  /// errors are retained first so high-severity items are never dropped.
  List<DiagnosticEntity> get diagnostics => _diagnostics;
  int get diagnosticsRevision => _diagnosticsRevision;

  set diagnostics(List<DiagnosticEntity> value) {
    if (value.length <= _maxDiagnostics) {
      _diagnostics = value;
      _diagnosticsRevision++;
      return;
    }
    final capped = List<DiagnosticEntity>.from(value)
      ..sort((a, b) => a.severity.index.compareTo(b.severity.index));
    _diagnostics = capped.sublist(0, _maxDiagnostics);
    _diagnosticsRevision++;
  }

  /// Whether the diagnostics ("problems") overlay is open. Toggled by
  /// `/diagnostics`, by clicking the prompt-box counters, or closed with esc.
  bool showDiagnosticsPanel = false;

  /// Whether the isolate lifecycle panel is open. Toggled by `/isolates` and
  /// closed with esc/q.
  bool showIsolatesPanel = false;

  /// Active category filter in the diagnostics overlay; null = show all.
  DiagnosticCategory? diagnosticsFilter;

  /// Free-text filter applied to the diagnostics overlay (matches file path or
  /// message). Empty = no text filter.
  String diagnosticsSearch = '';

  /// Active `/run` picker. When non-empty, the TUI renders a button bar of
  /// launch entries above the input line. Cleared after the user picks one
  /// or dismisses the picker.
  List<LaunchEntryEntity> launchChoices = const <LaunchEntryEntity>[];

  /// Active `/emulators` picker. Same shape as [launchChoices] — only one
  /// picker is open at a time; opening one clears the others.
  List<EmulatorEntity> emulatorChoices = const <EmulatorEntity>[];

  /// Active `/melos` picker — built-in melos commands plus custom scripts.
  List<MelosCommandEntity> melosChoices = const <MelosCommandEntity>[];

  /// Launch entry awaiting a run-target choice. Set when the user picks an
  /// entry in the `/run` launch picker; cleared once a target is chosen.
  LaunchEntryEntity? pendingRunEntry;

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
      runTargetChoices.isNotEmpty ||
      melosChoices.isNotEmpty;

  void clearPickers() {
    launchChoices = const <LaunchEntryEntity>[];
    emulatorChoices = const <EmulatorEntity>[];
    bootModeChoices = const <String>[];
    pendingEmulatorId = null;
    runTargetChoices = const <RunTarget>[];
    melosChoices = const <MelosCommandEntity>[];
  }

  void setLaunchPicker(List<LaunchEntryEntity> entries) {
    clearPickers();
    launchChoices = entries;
  }

  void setMelosPicker(List<MelosCommandEntity> commands) {
    clearPickers();
    melosChoices = commands;
  }

  void setEmulatorPicker(List<EmulatorEntity> emulators) {
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
