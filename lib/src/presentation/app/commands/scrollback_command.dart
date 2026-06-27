import '../../../domain/params/config_params.dart';
import '../app_state.dart';
import 'command.dart';

/// View or set the transcript scrollback cap — the max lines each transcript
/// (the system log and every run tab) retains before evicting the oldest.
/// Lower caps trade history for memory. The value is **persisted to config**
/// and applied live to every open transcript, so it also survives restarts.
/// (Thin sugar over `config set scrollback_lines <n>`.)
class ScrollbackCommand extends Command {
  @override
  String get name => 'scrollback';

  @override
  String get summary => 'Show or set the transcript scrollback line cap';

  @override
  String get usage => '/scrollback [lines]';

  @override
  List<String> get aliases => const ['sb'];

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    if (args.isEmpty) {
      state.transcript.system(
        'scrollback: ${state.config.scrollbackLines} lines per transcript.',
      );
      return CommandResult.ok;
    }

    final n = int.tryParse(args.first);
    if (n == null || n < 1) {
      state.transcript.error('scrollback: need a positive integer.');
      return CommandResult.ok;
    }

    final setUseCase = state.deps.setConfigUseCase;
    if (setUseCase == null) {
      state.transcript.warn('Config not ready.');
      return CommandResult.ok;
    }

    final setResult = await setUseCase.call(
      ConfigSetParams(key: 'scrollback_lines', value: '$n'),
    );
    await setResult.fold(
      (failure) async => state.transcript.warn(failure.message),
      (_) async {
        // Re-read the saved config and apply it; AppState.setConfig retunes
        // every live transcript to the new cap (trimming immediately).
        final getResult = await state.deps.getConfigUseCase?.call();
        getResult?.fold(
          (f) => state.transcript.warn(f.message),
          state.setConfig,
        );
        state.transcript.system(
          'scrollback set to $n lines per transcript (saved).',
        );
      },
    );
    return CommandResult.ok;
  }
}
