import '../app_state.dart';
import 'command.dart';

class StatusCommand extends Command {
  @override
  String get name => 'status';

  @override
  String get summary => 'Toggle the status panel at the bottom';

  @override
  List<String> get aliases => const ['s'];

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    state.showStatusPanel = !state.showStatusPanel;
    state.transcript.system(
      'Status panel ${state.showStatusPanel ? "shown" : "hidden"}.',
    );
    return CommandResult.ok;
  }
}
