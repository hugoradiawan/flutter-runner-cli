import '../app_state.dart';
import '../transcript.dart';
import 'command.dart';

/// View or set the transcript scrollback cap — the max lines each transcript
/// (the system log and every run tab) retains before evicting the oldest.
/// Lower caps trade history for memory; the change applies live to all open
/// transcripts and to any tab opened afterwards.
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
        'scrollback: ${Transcript.defaultMaxLines} lines per transcript.',
      );
      return CommandResult.ok;
    }

    final n = int.tryParse(args.first);
    if (n == null || n < 1) {
      state.transcript.error('scrollback: need a positive integer.');
      return CommandResult.ok;
    }

    // New transcripts (future tabs) pick this up via the constructor default…
    Transcript.defaultMaxLines = n;
    // …and the live ones are retuned (and trimmed) right now.
    state.transcript.maxLines = n;
    for (final tab in state.runController.tabs) {
      tab.transcript.maxLines = n;
    }

    state.transcript.system('scrollback set to $n lines per transcript.');
    return CommandResult.ok;
  }
}
