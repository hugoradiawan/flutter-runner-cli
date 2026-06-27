import 'dart:io';

import '../app_state.dart';
import 'command.dart';

/// Reports the process's resident memory so memory work can be measured rather
/// than guessed. `ProcessInfo.currentRss` / `maxRss` are bytes of physical RAM
/// the frun process is using now and at its peak.
class MemCommand extends Command {
  @override
  String get name => 'mem';

  @override
  String get summary => 'Show frun process memory (resident + peak)';

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    final rss = ProcessInfo.currentRss;
    final peak = ProcessInfo.maxRss;
    state.transcript.system('mem: rss ${_mb(rss)} · peak ${_mb(peak)}');
    return CommandResult.ok;
  }

  static String _mb(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
