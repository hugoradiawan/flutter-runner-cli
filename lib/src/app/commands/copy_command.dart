import '../app_state.dart';
import 'command.dart';

/// Copies every line currently shown in the transcript panel to the OS
/// clipboard. Mirrors the Ctrl+C selection-copy affordance but grabs the whole
/// visible buffer (active tab's log, or the system transcript when no tab is
/// open).
class CopyCommand extends Command {
  CopyCommand(this._copy);

  /// Injected clipboard writer. Returns true when the platform accepted the
  /// text; false on headless/SSH sessions with no clipboard helper. Injected so
  /// this command stays out of the TUI layer and is testable without touching
  /// the real OS clipboard.
  final Future<bool> Function(String text) _copy;

  @override
  String get name => 'copy';

  @override
  String get summary => 'Copy the whole transcript to the clipboard';

  @override
  List<String> get aliases => const ['yank', 'copyall'];

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    final transcript = state.visibleTranscript;
    final lines = transcript.lines;
    if (lines.isEmpty) {
      transcript.warn('Nothing to copy — transcript is empty.');
      return CommandResult.ok;
    }

    final text = lines.map((l) => l.text).join('\n');
    final ok = await _copy(text);
    if (ok) {
      transcript.system('Copied ${lines.length} lines (${text.length} chars).');
    } else {
      transcript.warn(
        'Copy failed — no clipboard helper available (headless or SSH session?).',
      );
    }
    return CommandResult.ok;
  }
}
