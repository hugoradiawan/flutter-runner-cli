import '../app_state.dart';
import 'command.dart';
import 'command_registry.dart';

class HelpCommand extends SlashCommand {
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
    state.transcript.system('Available commands:');
    for (final cmd in registry.all) {
      final aliasPart =
          cmd.aliases.isEmpty ? '' : ' (aliases: ${cmd.aliases.join(', ')})';
      state.transcript.info('  /${cmd.name.padRight(10)} ${cmd.summary}$aliasPart');
    }
    return CommandResult.ok;
  }
}
