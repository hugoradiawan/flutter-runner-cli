import '../app_state.dart';
import 'command.dart';
import 'command_registry.dart';

class HelpCommand extends Command {
  HelpCommand(this.registry);

  final CommandRegistry registry;

  @override
  String get name => 'help';

  @override
  String get summary => 'Show available commands';

  @override
  List<String> get aliases => const ['h', '?'];

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    state.visibleTranscript.system('Available commands:');
    for (final cmd in registry.all) {
      final aliasPart = cmd.aliases.isEmpty
          ? ''
          : ' (aliases: ${cmd.aliases.join(', ')})';
      state.visibleTranscript.info(
        '  ${cmd.name.padRight(11)} ${cmd.summary}$aliasPart',
      );
    }
    return CommandResult.ok;
  }
}
