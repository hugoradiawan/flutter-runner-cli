import '../app_state.dart';
import 'command.dart';

class QuitCommand extends SlashCommand {
  @override
  String get name => 'quit';

  @override
  String get summary => 'Exit frun';

  @override
  List<String> get aliases => const ['q', 'exit'];

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    state.visibleTranscript.system('Bye.');
    return CommandResult.quit;
  }
}
