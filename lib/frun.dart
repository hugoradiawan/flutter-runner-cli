/// Public entry point for the `frun` TUI.
library;

import 'dart:async';
import 'dart:io';

import 'package:dart_tui/dart_tui.dart';

import 'src/data/datasources/analysis_server.dart';
import 'src/data/datasources/diagnostics_store.dart';
import 'src/data/datasources/package_locator.dart';
import 'src/data/datasources/working_set.dart';
import 'src/presentation/app/app_state.dart';
import 'src/presentation/app/commands/clear_command.dart';
import 'src/presentation/app/commands/command_registry.dart';
import 'src/presentation/app/commands/config_command.dart';
import 'src/presentation/app/commands/copy_command.dart';
import 'src/presentation/app/commands/detach_command.dart';
import 'src/presentation/app/commands/devices_command.dart';
import 'src/presentation/app/commands/devtools_command.dart';
import 'src/presentation/app/commands/diagnostics_command.dart';
import 'src/presentation/app/commands/emulators_command.dart';
import 'src/presentation/app/commands/help_command.dart';
import 'src/presentation/app/commands/inspect_command.dart';
import 'src/presentation/app/commands/isolates_command.dart';
import 'src/presentation/app/commands/performance_overlay_command.dart';
import 'src/presentation/app/commands/quit_command.dart';
import 'src/presentation/app/commands/reload_command.dart';
import 'src/presentation/app/commands/restart_command.dart';
import 'src/presentation/app/commands/run_command.dart';
import 'src/presentation/app/commands/status_command.dart';
import 'src/presentation/app/commands/stop_command.dart';
import 'src/data/datasources/config_datasource.dart';
import 'src/data/datasources/config_store.dart';
import 'src/data/datasources/dart_file_watcher.dart';
import 'src/data/datasources/device_manager.dart';
import 'src/data/datasources/emulator_manager.dart';
import 'src/data/datasources/flutter_daemon.dart';
import 'src/data/datasources/project_detector.dart';
import 'src/data/repositories/config_repository_impl.dart';
import 'src/data/repositories/device_repository_impl.dart';
import 'src/data/repositories/diagnostics_repository_impl.dart';
import 'src/data/repositories/emulator_repository_impl.dart';
import 'src/data/repositories/session_repository_impl.dart';
import 'src/domain/entities/app_config.entity.dart';
import 'src/data/datasources/windows_console.dart';
import 'src/presentation/tui/clipboard.dart';
import 'src/presentation/tui/frun_app.dart';

export 'src/version.dart';

/// Boot the TUI. Returns the process exit code.
Future<int> runFrun({String? cwd, ConfigStore? configStoreOverride}) async {
  if (!stdout.hasTerminal) {
    stderr.writeln(
      'frun: this command is a terminal UI â€” please run it from an interactive shell.',
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
  final configDataSource = ConfigDataSource(configStore);
  final configRepository = ConfigRepositoryImpl(configDataSource);
  final configResult = await configRepository.getConfig();
  final configEntity = configResult.fold(
    (_) => AppConfigEntity.defaults(),
    (e) => e,
  );

  final state = AppState(project: project, config: configEntity)
    ..configRepository = configRepository;

  state.sessionRepository = SessionRepositoryImpl(
    projectRoot: project.root,
    sessionLookup: (tabId) {
      for (final tab in state.runController.tabs) {
        if (tab.id == tabId) return tab.session;
      }
      return null;
    },
  );

  final registry = CommandRegistry()
    ..register(QuitCommand())
    ..register(ClearCommand())
    ..register(CopyCommand(copyToClipboard))
    ..register(ConfigCommand())
    ..register(DevicesCommand())
    ..register(EmulatorsCommand())
    ..register(DevToolsCommand())
    ..register(RunCommand(state.runController))
    ..register(ReloadCommand())
    ..register(RestartCommand())
    ..register(StopCommand())
    ..register(DetachCommand())
    ..register(PerformanceOverlayCommand())
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
  );

  // Kick the daemon off in the background so the TUI is interactive
  // immediately. Any failure is surfaced in the transcript.
  unawaited(_bootDaemon(state));
  // Start the analyzer in the background too â€” independent of the daemon.
  unawaited(_bootAnalysis(state));

  try {
    await program.run(tuiApp);
  } finally {
    restoreConsole();
  }
  await state.runController.stopAll();
  await state.isolateManager.disconnect();
  await state.analysisWatcher?.dispose();
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
  // workspaces) get all packages analyzed, not just the runnable app's own
  // package. The runnable [root] (e.g. `app/`) is usually a *sibling* of the
  // other packages (`features/*`, `cores/*`) under the monorepo boundary, so
  // scan from [watchRoot] (the `.git`/`melos.yaml` ancestor). Scanning from
  // [root] alone walks only inside `app/` and misses every sibling package â€”
  // errors in those (e.g. `features/youchat`) then go silently unreported.
  final packages = locatePackageRoots(state.project.watchRoot);

  try {
    final server = await DartAnalysisServer.start(
      projectRoot: state.project.root,
      workspaceFolders: packages,
    );
    state.analysisServer = server;
    state.diagnosticsRepository = DiagnosticsRepositoryImpl(server);
    server.stderrLines.listen((l) => state.transcript.warn('analysis: $l'));
    state.transcript.system(
      packages.length > 1
          ? 'Analyzing ${packages.length} packagesâ€¦ '
                '(first pass can take ~20s on large monorepos)'
          : 'Analyzing projectâ€¦',
    );
    Timer? saveDebounce;
    server.diagnostics.listen((items) {
      state.diagnostics = items;
      // Debounce disk writes â€” analysis can settle in bursts.
      saveDebounce?.cancel();
      saveDebounce = Timer(const Duration(seconds: 1), () {
        try {
          store.save(items);
        } catch (_) {
          /* best-effort cache */
        }
      });
    });

    // Open the user's working set (git-dirty `.dart` files) as LSP priority
    // documents. The analyzer reports those within seconds; the whole-project
    // background pass over a large monorepo is far too slow to surface a
    // just-edited file â€” which is exactly the file the user is looking at.
    final dirty = gitDirtyDartFiles(state.project.watchRoot);
    for (final file in dirty) {
      server.openFile(file);
    }
    if (dirty.isNotEmpty) {
      state.transcript.system(
        'Prioritizing ${dirty.length} changed file(s) for analysis.',
      );
    }

    // Keep the analyzer in sync with edits made by an external editor: every
    // changed `.dart` file is (re)opened/pushed so its diagnostics refresh
    // live, and files first edited after launch start being analyzed too.
    final watcher = DartFileWatcher(
      root: state.project.watchRoot,
      pollInterval: const Duration(seconds: 1),
      onFileChanged: server.openFile,
    );
    watcher.start();
    state.analysisWatcher = watcher;
  } catch (e) {
    state.analysisError = e.toString();
    state.transcript.warn(
      'Diagnostics unavailable â€” could not start "dart language-server". '
      'Is the Dart SDK on your PATH? ($e)',
    );
  }
}

/// How many times to (re)start the flutter daemon before giving up. After a
/// PC restart the very first attempt almost always fails because the adb
/// server is down â€” flutter's `device.getDevices` then reports
/// `adb: failed to check server version: cannot connect to daemon`. Retrying
/// (with an adb restart in between) recovers without the user relaunching frun.
const int _daemonStartAttempts = 4;

/// Pause between daemon start attempts, giving the freshly-started adb server
/// time to come up before flutter queries devices again.
const Duration _daemonRetryDelay = Duration(seconds: 2);

Future<void> _bootDaemon(AppState state) async {
  // Preempt the cold-boot failure: make sure the adb server is up *before*
  // flutter's first `device.getDevices`. `start-server` is a no-op when adb is
  // already running, so this is cheap and won't disturb a healthy server with
  // its connected devices. The kill+start retry below still handles a stale
  // server that `start-server` alone can't revive.
  await _ensureAdbServer(state, restart: false, announce: false);

  for (var attempt = 1; attempt <= _daemonStartAttempts; attempt++) {
    state.transcript.system(
      attempt == 1
          ? 'Starting flutter daemonâ€¦'
          : 'Retrying flutter daemon (attempt $attempt/$_daemonStartAttempts)â€¦',
    );
    FlutterDaemon? daemon;
    DeviceManager? manager;
    try {
      daemon = await FlutterDaemon.start();
      state.daemon = daemon;
      daemon.stderrLines.listen(
        (line) => state.transcript.warn('daemon: $line'),
      );
      manager = DeviceManager(daemon);
      state.deviceManager = manager;
      manager.changes.listen((devices) {
        state.transcript.system(
          'Devices changed: ${devices.length} connected.',
        );
      });
      await manager.start();
      state.daemonReady = true;
      state.daemonError = null;
      state.deviceRepository = DeviceRepositoryImpl(manager);
      state.emulatorRepository = EmulatorRepositoryImpl(
        EmulatorManager(daemon),
      );
      state.transcript.success(
        'Flutter daemon ready (${state.deviceManager!.devices.length} devices).',
      );
      // Warm the emulator subsystem in the background. The daemon's first
      // `emulator.getEmulators` does cold Android-SDK / AVD discovery that can
      // run well past the `emu` command's timeout on a fresh boot. Paying that
      // cost now means the user's later `emu` returns from a warm daemon fast.
      unawaited(_warmEmulators(state));
      return;
    } catch (e) {
      state.daemonError = e.toString();
      // Tear down the partial daemon so the retry starts clean and we don't
      // orphan the `flutter daemon` process or stack stderr listeners.
      try {
        await manager?.dispose();
      } catch (_) {
        /* best-effort */
      }
      try {
        await daemon?.shutdown();
      } catch (_) {
        /* best-effort */
      }
      state.daemon = null;
      state.deviceManager = null;

      if (attempt < _daemonStartAttempts) {
        state.transcript.warn(
          'Flutter daemon start failed ($e). Restarting adb and retryingâ€¦',
        );
        await _ensureAdbServer(state);
        await Future<void>.delayed(_daemonRetryDelay);
        continue;
      }
      state.transcript.error('Failed to start flutter daemon: $e');
    }
  }
}

/// Make sure the adb server is up. On a fresh boot adb's own server is down and
/// flutter's first device query fails. When [restart] is true (the retry path)
/// a clean `kill-server` + `start-server` clears stale state; when false (the
/// proactive pre-flight) only `start-server` runs, which is a no-op on a
/// healthy server. Best-effort â€” every failure is swallowed so the daemon retry
/// surfaces the real error if adb genuinely can't run. [announce] silences the
/// transcript message for the quiet pre-flight call.
Future<void> _ensureAdbServer(
  AppState state, {
  bool restart = true,
  bool announce = true,
}) async {
  for (final adb in _adbCandidates()) {
    try {
      if (restart) {
        await Process.run(adb, const ['kill-server']);
      }
      final started = await Process.run(adb, const ['start-server']);
      if (started.exitCode == 0) {
        if (announce) {
          state.transcript.system(
            'adb server ${restart ? 'restarted' : 'ready'}.',
          );
        }
        return;
      }
    } on ProcessException {
      // adb isn't at this path â€” try the next candidate.
      continue;
    }
  }
  if (announce) {
    state.transcript.warn(
      'Could not restart adb automatically â€” set ANDROID_HOME or put '
      'platform-tools on PATH if the daemon keeps failing.',
    );
  }
}

/// Background warm-up: trigger the daemon's cold emulator discovery once during
/// boot so the user's later `emu` command hits a warm daemon. Best-effort â€” any
/// failure is swallowed here; the `emu` command surfaces real errors itself.
Future<void> _warmEmulators(AppState state) async {
  final daemon = state.daemon;
  if (daemon == null) return;
  try {
    await daemon.getEmulators();
  } catch (_) {
    /* best-effort warm-up */
  }
}

/// Candidate `adb` executables in priority order: explicit SDK env vars, the
/// platform's default install location, then bare `adb` (resolved via PATH).
Iterable<String> _adbCandidates() sync* {
  final env = Platform.environment;
  final exe = Platform.isWindows ? 'adb.exe' : 'adb';
  final sep = Platform.pathSeparator;
  for (final root in [env['ANDROID_HOME'], env['ANDROID_SDK_ROOT']]) {
    if (root != null && root.isNotEmpty) {
      yield '$root${sep}platform-tools$sep$exe';
    }
  }
  if (Platform.isWindows) {
    final localAppData = env['LOCALAPPDATA'];
    if (localAppData != null && localAppData.isNotEmpty) {
      yield '$localAppData\\Android\\Sdk\\platform-tools\\$exe';
    }
  } else {
    final home = env['HOME'];
    if (home != null && home.isNotEmpty) {
      yield '$home/Library/Android/sdk/platform-tools/$exe'; // macOS
      yield '$home/Android/Sdk/platform-tools/$exe'; // Linux
    }
  }
  yield exe; // bare â€” relies on PATH
}
