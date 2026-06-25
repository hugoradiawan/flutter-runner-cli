import '../app_state.dart';
import 'command.dart';

class DetachCommand extends Command {
  @override
  String get name => 'detach';

  @override
  String get summary => 'Detach from app (keeps app running, disconnects tool)';

  @override
  List<String> get aliases => const ['d'];

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    if (state.runController.activeTab?.session == null) {
      state.visibleTranscript.warn('No app running.');
      return CommandResult.ok;
    }
    await state.runController.detachActive();
    state.visibleTranscript.success('Detached — app continues running.');
    return CommandResult.ok;
  }
}
