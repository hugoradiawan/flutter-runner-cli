import '../../../domain/entities/launch_entry.dart';
import '../app_state.dart';
import '../run_controller.dart';
import 'command.dart';

/// `run` — pick a launch entry and start the app.
///
/// Usage:
///   run               → open the launch-entry button bar above the input
///   run `<index>`     → launch by index from the discovered entries
///   run `<name>`      → launch by entry name
class RunCommand extends Command {
  RunCommand(this.controller);

  final RunController controller;

  @override
  String get name => 'run';

  @override
  String get summary => 'Pick a launch config and run the app';

  @override
  String get usage => 'run [index|name]';

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    final entries = await _discover(state);

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
    await controller.openRunTargetPicker(picked);
    return CommandResult.ok;
  }

  Future<List<LaunchEntryEntity>> _discover(AppState state) async {
    final useCase = state.deps.discoverLaunchEntriesUseCase;
    if (useCase == null) return const <LaunchEntryEntity>[];
    final result = await useCase.call();
    return result.fold((failure) {
      state.visibleTranscript.error(
        'Launch discovery failed: ${failure.message}',
      );
      return const <LaunchEntryEntity>[];
    }, (entries) => entries);
  }

  LaunchEntryEntity? _resolve(String token, List<LaunchEntryEntity> entries) {
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
