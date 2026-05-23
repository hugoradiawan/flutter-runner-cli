import 'dart:io';

import 'package:path/path.dart' as p;

import '../../project/launch_config.dart';
import '../../project/main_scanner.dart';
import '../app_state.dart';
import '../run_controller.dart';
import 'command.dart';

/// `/run` — pick a launch entry and start the app.
///
/// Usage:
///   /run               → list discovered entries
///   /run `<index>`     → launch by index from the last `/run` list
///   /run `<name>`      → launch by entry name
class RunCommand extends SlashCommand {
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
      state.transcript.warn(
        'No launch entries found. Add lib/main.dart or a .vscode/launch.json with type=dart.',
      );
      return CommandResult.ok;
    }

    if (args.isEmpty) {
      _printList(state, entries);
      return CommandResult.ok;
    }

    final picked = _resolve(args.first, entries);
    if (picked == null) {
      state.transcript.error('No launch entry matches "${args.first}".');
      return CommandResult.ok;
    }

    final deviceId = picked.deviceId ?? state.selectedDeviceId;
    if (deviceId == null) {
      state.transcript.warn(
        'No device for this entry. Use /devices first, or add `"deviceId": "<id>"` to the launch config.',
      );
      return CommandResult.ok;
    }
    if (picked.deviceId != null && picked.deviceId != state.selectedDeviceId) {
      state.transcript.system(
        'Using deviceId "${picked.deviceId}" from launch config.',
      );
    }
    await controller.start(picked, deviceId: deviceId);
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

  void _printList(AppState state, List<LaunchEntry> entries) {
    state.transcript.system('Launch entries:');
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final src = e.source == LaunchEntrySource.launchJson ? 'launch.json' : 'lib scan';
      final bits = <String>[
        if (e.flutterMode != null) e.flutterMode!,
        if (e.flavor != null) 'flavor=${e.flavor}',
        if (e.deviceId != null) 'device=${e.deviceId}',
        if (e.cwd != null) 'cwd=${_shorten(e.cwd!, state.project.workspaceRoot)}',
      ].join(' ');
      state.transcript.info(
        '  [${i.toString().padLeft(2)}] ${e.name.padRight(34)} ${p.basename(e.program).padRight(18)} $src  $bits',
      );
    }
    state.transcript.info('Pick one with `/run <index>` or `/run <name>`.');
  }

  String _shorten(String absPath, String workspaceRoot) {
    if (absPath == workspaceRoot) return '.';
    if (absPath.startsWith('$workspaceRoot/') ||
        absPath.startsWith('$workspaceRoot\\')) {
      return absPath.substring(workspaceRoot.length + 1);
    }
    return absPath;
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
