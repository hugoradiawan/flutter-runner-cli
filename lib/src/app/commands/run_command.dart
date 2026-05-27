import 'dart:io';

import '../../project/launch_config.dart';
import '../../project/main_scanner.dart';
import '../app_state.dart';
import '../run_controller.dart';
import 'command.dart';

/// `/run` — pick a launch entry and start the app.
///
/// Usage:
///   /run               → open the launch-entry button bar above the input
///   /run `<index>`     → launch by index from the discovered entries
///   /run `<name>`      → launch by entry name
class RunCommand extends Command {
  RunCommand(this.controller);

  final RunController controller;

  @override
  String get name => 'run';

  @override
  String get summary => 'Pick a launch config and run the app';

  @override
  String get usage => '/run [index|name]';

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    final entries = _discover(state);

    if (entries.isEmpty) {
      state.clearPickers();
      state.visibleTranscript.warn(
        'No launch entries found. Add lib/main.dart or a .vscode/launch.json with type=dart.',
      );
      return CommandResult.ok;
    }

    if (args.isEmpty) {
      // Hand the list to the TUI picker — buttons render above the input.
      state.setLaunchPicker(entries);
      return CommandResult.ok;
    }

    final picked = _resolve(args.first, entries);
    if (picked == null) {
      state.visibleTranscript.error('No launch entry matches "${args.first}".');
      return CommandResult.ok;
    }

    state.clearPickers();
    await controller.launchEntry(picked);
    return CommandResult.ok;
  }

  List<LaunchEntry> _discover(AppState state) {
    final launchJsonFile = File(state.project.launchJsonPath);
    final launchJson = LaunchConfigParser.parseFile(
      launchJsonFile,
      workspaceFolder: state.project.workspaceRoot,
    );
    final scanned = MainScanner.scan(state.project.libDir);
    return MainScanner.merge(launchJson, scanned);
  }

  LaunchEntry? _resolve(String token, List<LaunchEntry> entries) {
    final asInt = int.tryParse(token);
    if (asInt != null && asInt >= 0 && asInt < entries.length) {
      return entries[asInt];
    }
    for (final e in entries) {
      if (e.name == token || e.program == token) return e;
    }
    return null;
  }
}
