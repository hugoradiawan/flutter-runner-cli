import '../app_state.dart';
import 'command.dart';

class ClearCommand extends SlashCommand {
  @override
  String get name => 'clear';

  @override
  String get summary => 'Clear the transcript';

  @override
  List<String> get aliases => const ['cls'];

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    state.transcript.clear();
    return CommandResult.ok;
  }
}
