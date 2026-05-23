import '../app_state.dart';
import '../run_controller.dart';
import 'command.dart';

class ReloadCommand extends SlashCommand {
  ReloadCommand(this.controller);
  final RunController controller;

  @override
  String get name => 'reload';

  @override
  String get summary => 'Hot reload the running app';

  @override
  List<String> get aliases => const ['r'];

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    await controller.hotReload();
    return CommandResult.ok;
  }
}

class RestartCommand extends SlashCommand {
  RestartCommand(this.controller);
  final RunController controller;

  @override
  String get name => 'restart';

  @override
  String get summary => 'Hot restart the running app';

  @override
  List<String> get aliases => const ['R'];

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    await controller.hotRestart();
    return CommandResult.ok;
  }
}

class StopCommand extends SlashCommand {
  StopCommand(this.controller);
  final RunController controller;

  @override
  String get name => 'stop';

  @override
  String get summary => 'Stop the running app';

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    await controller.stop();
    return CommandResult.ok;
  }
}
