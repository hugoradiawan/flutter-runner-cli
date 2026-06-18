/// Public entry point for the `frun` TUI.
library;

import 'dart:async';
import 'dart:io';

import 'package:dart_tui/dart_tui.dart';

import 'src/analysis/analysis_server.dart';
import 'src/analysis/diagnostics_store.dart';
import 'src/analysis/package_locator.dart';
import 'src/app/app_state.dart';
import 'src/app/commands/clear_command.dart';
import 'src/app/commands/command_registry.dart';
import 'src/app/commands/config_command.dart';
import 'src/app/commands/devices_command.dart';
import 'src/app/commands/devtools_command.dart';
import 'src/app/commands/diagnostics_command.dart';
import 'src/app/commands/emulators_command.dart';
import 'src/app/commands/help_command.dart';
import 'src/app/commands/inspect_command.dart';
import 'src/app/commands/isolates_command.dart';
import 'src/app/commands/quit_command.dart';
import 'src/app/commands/reload_command.dart';
import 'src/app/commands/run_command.dart';
import 'src/app/commands/status_command.dart';
import 'src/config/config_store.dart';
import 'src/daemon/flutter_daemon.dart';
import 'src/devices/device_manager.dart';
import 'src/platform/windows_console.dart';
import 'src/project/project_detector.dart';
import 'src/tui/frun_app.dart';

export 'src/version.dart';

/// Boot the TUI. Returns the process exit code.
Future<int> runFrun({String? cwd, ConfigStore? configStoreOverride}) async {
  if (!stdout.hasTerminal) {
    stderr.writeln(
      'frun: this command is a terminal UI — please run it from an interactive shell.',
    );
    return 64;
  }
  if (Platform.isWindows && !stdout.supportsAnsiEscapes) {
    stderr.writeln(
      'frun: your terminal does not advertise ANSI support. Try Windows Terminal '
      'or PowerShell 7+, or set TERM=xterm-256color and retry.',
    );
    return 64;
  }
  // Disable QuickEdit on the legacy console host so mouse events flow through.
  final restoreConsole = prepareWindowsConsoleForMouse();
  final workingDir = cwd ?? Directory.current.path;
  final detection = ProjectDetector.detect(startDir: workingDir);
  if (!detection.isOk) {
    stderr.writeln('frun: ${detection.error}');
    return 64;
  }
  final project = detection.project!;
  final configStore = configStoreOverride ?? ConfigStore();
  final config = configStore.load();

  final state = AppState(project: project, config: config);

  final registry = CommandRegistry()
    ..register(QuitCommand())
    ..register(ClearCommand())
    ..register(ConfigCommand(configStore))
    ..register(DevicesCommand())
    ..register(EmulatorsCommand())
    ..register(DevToolsCommand())
    ..register(RunCommand(state.runController))
    ..register(ReloadCommand(state.runController))
    ..register(RestartCommand(state.runController))
    ..register(StopCommand(state.runController))
    ..register(DetachCommand(state.runController))
    ..register(PerformanceOverlayCommand(state.runController))
    ..register(IsolatesCommand(state.isolateManager, state.ideLauncher))
    ..register(InspectCommand())
    ..register(StatusCommand())
    ..register(DiagnosticsCommand());
  registry.register(HelpCommand(registry));

  final program = Program(
    programOptions: [
      withAltScreen(),
      withHideCursor(),
      withMouseCellMotion(),
      withTickInterval(const Duration(milliseconds: 250)),
    ],
  );

  final tuiApp = FrunModel(
    state: state,
    registry: registry,
    onQuit: program.quit,
    configStore: configStore,
  );

  // Kick the daemon off in the background so the TUI is interactive
  // immediately. Any failure is surfaced in the transcript.
  unawaited(_bootDaemon(state));
  // Start the analyzer in the background too — independent of the daemon.
  unawaited(_bootAnalysis(state));

  try {
    await program.run(tuiApp);
  } finally {
    restoreConsole();
  }
  await state.runController.stopAll();
  await state.isolateManager.disconnect();
  await state.analysisServer?.shutdown();
  await state.daemon?.shutdown();
  return 0;
}

/// Boot the Dart analysis server (LSP) and stream realtime diagnostics into
/// [state]. Seeds counters from the per-project cache first so they appear
/// instantly, then live-updates and re-caches as the analyzer reports.
Future<void> _bootAnalysis(AppState state) async {
  final store = DiagnosticsStore(projectRoot: state.project.root);
  state.diagnosticsStore = store;
  // Seed from cache before the first analysis pass completes.
  final cached = store.load();
  if (cached.isNotEmpty) state.diagnostics = cached;

  // Discover every package in the project so monorepos (melos / pub
  // workspaces) get all packages analyzed, not just the root's own package.
  final packages = locatePackageRoots(state.project.root);

  try {
    final server = await DartAnalysisServer.start(
      projectRoot: state.project.root,
      workspaceFolders: packages,
    );
    state.analysisServer = server;
    server.stderrLines.listen((l) => state.transcript.warn('analysis: $l'));
    state.transcript.system(
      packages.length > 1
          ? 'Analyzing ${packages.length} packages… '
              '(first pass can take ~20s on large monorepos)'
          : 'Analyzing project…',
    );
    Timer? saveDebounce;
    server.diagnostics.listen((items) {
      state.diagnostics = items;
      // Debounce disk writes — analysis can settle in bursts.
      saveDebounce?.cancel();
      saveDebounce = Timer(const Duration(seconds: 1), () {
        try {
          store.save(items);
        } catch (_) {/* best-effort cache */}
      });
    });
  } catch (e) {
    state.analysisError = e.toString();
    state.transcript.warn(
      'Diagnostics unavailable — could not start "dart language-server". '
      'Is the Dart SDK on your PATH? ($e)',
    );
  }
}

Future<void> _bootDaemon(AppState state) async {
  state.transcript.system('Starting flutter daemon…');
  try {
    final daemon = await FlutterDaemon.start();
    state.daemon = daemon;
    daemon.stderrLines.listen((line) => state.transcript.warn('daemon: $line'));
    final manager = DeviceManager(daemon);
    state.deviceManager = manager;
    manager.changes.listen((devices) {
      state.transcript.system(
        'Devices changed: ${devices.length} connected.',
      );
    });
    await manager.start();
    state.daemonReady = true;
    state.transcript.success(
      'Flutter daemon ready (${state.deviceManager!.devices.length} devices).',
    );
  } catch (e) {
    state.daemonError = e.toString();
    state.transcript.error('Failed to start flutter daemon: $e');
  }
}

