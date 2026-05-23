/// Public entry point for the `frun` TUI.
library;

import 'dart:async';
import 'dart:io';

import 'package:utopia_tui/utopia_tui.dart';

import 'src/app/app_state.dart';
import 'src/app/commands/clear_command.dart';
import 'src/app/commands/command_registry.dart';
import 'src/app/commands/config_command.dart';
import 'src/app/commands/devices_command.dart';
import 'src/app/commands/devtools_command.dart';
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
  final workingDir = cwd ?? Directory.current.path;
  final detection = ProjectDetector.detect(startDir: workingDir);
  if (!detection.isOk) {
    stderr.writeln('frun: ${detection.error}');
    return 64;
  }
  final project = detection.project!;
  final configStore = configStoreOverride ?? ConfigStore();
  final config = configStore.load();

  final state = AppState(project: project, config: config)
    ..selectedDeviceId = config.defaultDeviceId;

  final registry = CommandRegistry()
    ..register(QuitCommand())
    ..register(ClearCommand())
    ..register(ConfigCommand(configStore))
    ..register(DevicesCommand(configStore: configStore))
    ..register(EmulatorsCommand(configStore: configStore))
    ..register(DevToolsCommand())
    ..register(RunCommand(state.runController))
    ..register(ReloadCommand(state.runController))
    ..register(RestartCommand(state.runController))
    ..register(StopCommand(state.runController))
    ..register(IsolatesCommand(state.isolateManager, state.ideLauncher))
    ..register(InspectCommand())
    ..register(StatusCommand());
  registry.register(HelpCommand(registry));

  final tuiApp = FrunApp(
    state: state,
    registry: registry,
    onQuit: _restoreTerminalAndExit,
  );

  // Kick the daemon off in the background so the TUI is interactive
  // immediately. Any failure is surfaced in the transcript.
  unawaited(_bootDaemon(state));

  await TuiRunner(tuiApp).run();
  await state.runController.stop();
  await state.isolateManager.disconnect();
  await state.daemon?.shutdown();
  return 0;
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

/// `/quit` exits hard. We restore the terminal first so the user's shell isn't
/// left in raw-mode with the alt-screen buffer active. `TuiRunner` doesn't
/// currently expose a programmatic stop, so this is the safest cross-platform
/// way to leave from inside an event handler.
Never _restoreTerminalAndExit() {
  try {
    stdin.lineMode = true;
    stdin.echoMode = true;
  } catch (_) {/* not a TTY — ignore */}
  stdout
    ..write('\x1b[0m') // reset color
    ..write('\x1b[?25h') // show cursor
    ..write('\x1b[?1049l'); // leave alt-screen buffer
  exit(0);
}
