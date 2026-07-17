import 'dart:async';

import '../../../domain/domain.dart';
import '../app_state.dart';
import 'command.dart';

/// `melos` — pick a melos command (or run one by index/name) in a monorepo.
///
/// Usage:
///   melos               → open the melos command picker
///   melos `<index>`     → run the command at that index
///   melos `<name>`      → run the command by name (e.g. `melos bootstrap`)
///   melos cancel        → cancel every in-flight melos run (shadows any
///                         script literally named `cancel`)
///
/// Output streams live into the transcript; a desktop notification fires when
/// the command starts and when it finishes (success or failure).
class MelosCommand extends Command {
  MelosCommand();

  @override
  String get name => 'melos';

  @override
  String get summary => 'Run a melos command (bootstrap, clean, scripts)';

  @override
  String get usage => 'melos [index|name|cancel]';

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    if (args.isNotEmpty && args.first == 'cancel') {
      final count = state.melosRunSubs.length;
      await state.cancelMelosRuns();
      state.visibleTranscript.system(
        count == 0
            ? 'No melos command is running.'
            : 'Cancelled $count melos ${count == 1 ? 'command' : 'commands'}.',
      );
      return CommandResult.ok;
    }

    final commands = await _discover(state);
    if (commands == null) return CommandResult.ok; // failure already reported

    if (commands.isEmpty) {
      state.clearPickers();
      state.visibleTranscript.warn(
        'No melos config found. Add a `melos:` section to pubspec.yaml or a '
        'melos.yaml at the monorepo root.',
      );
      return CommandResult.ok;
    }

    if (args.isEmpty) {
      state.setMelosPicker(commands);
      return CommandResult.ok;
    }

    final picked = _resolve(args.first, commands);
    if (picked == null) {
      state.visibleTranscript.error(
        'No melos command matches "${args.first}".',
      );
      return CommandResult.ok;
    }

    state.clearPickers();
    _runStreaming(picked, state);
    return CommandResult.ok;
  }

  /// Returns the discovered commands, or null when discovery failed (in which
  /// case the error has already been written to the transcript).
  Future<List<MelosCommandEntity>?> _discover(AppState state) async {
    final useCase = state.deps.discoverMelosCommandsUseCase;
    if (useCase == null) {
      state.visibleTranscript.warn('Melos support is still starting up.');
      return null;
    }
    final result = await useCase.call();
    return result.fold((failure) {
      state.visibleTranscript.error(
        'Melos discovery failed: ${failure.message}',
      );
      return null;
    }, (commands) => commands);
  }

  MelosCommandEntity? _resolve(String token, List<MelosCommandEntity> cmds) {
    final asInt = int.tryParse(token);
    if (asInt != null && asInt >= 0 && asInt < cmds.length) return cmds[asInt];
    for (final c in cmds) {
      if (c.name == token) return c;
    }
    return null;
  }

  /// Fire-and-forget: run the command and stream its output to the transcript
  /// without blocking the input line (bootstrap can take a while).
  void _runStreaming(MelosCommandEntity command, AppState state) {
    final useCase = state.deps.runMelosCommandUseCase;
    if (useCase == null) {
      state.visibleTranscript.warn('Melos support is still starting up.');
      return;
    }

    state.deps.notifier.notify(
      FrunNotifEvent.melosRunning,
      label: 'melos',
      detail: '${command.commandLine}…',
    );
    state.visibleTranscript.system('▶ ${command.commandLine}');

    late final StreamSubscription<MelosRunEvent> sub;
    sub = useCase.call(command).listen((event) {
      switch (event) {
        case MelosRunLine(:final text, :final isError):
          if (text.isEmpty) return;
          if (isError) {
            state.visibleTranscript.error(text);
          } else {
            state.visibleTranscript.info(text);
          }
        case MelosRunExit(:final code, :final ok):
          state.melosRunSubs.remove(sub);
          if (ok) {
            state.visibleTranscript.success('✓ ${command.commandLine} — done');
            state.deps.notifier.notify(
              FrunNotifEvent.melosDone,
              label: 'melos',
              detail: command.commandLine,
            );
          } else {
            state.visibleTranscript.error(
              '✗ ${command.commandLine} — exited ${code ?? '?'}',
            );
            state.deps.notifier.notify(
              FrunNotifEvent.melosFailed,
              label: 'melos',
              detail: '${command.commandLine} · exit ${code ?? '?'}',
            );
          }
      }
    });
    state.melosRunSubs.add(sub);
  }
}
