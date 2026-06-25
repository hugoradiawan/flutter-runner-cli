import '../app_state.dart';
import 'command.dart';

class StopCommand extends Command {
  @override
  String get name => 'stop';

  @override
  String get summary => 'Stop the active tab (or `stop all` for every tab)';

  @override
  List<String> get aliases => const ['q'];

  @override
  String get usage => 'stop [all]';

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    if (args.isNotEmpty && args.first == 'all') {
      await state.runController.stopAll();
    } else {
      await state.runController.stopActive();
    }
    return CommandResult.ok;
  }
}
