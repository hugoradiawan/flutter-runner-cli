import 'package:frun/src/domain/entities/app_config.dart';
import 'package:frun/src/domain/entities/flutter_project.dart';
import 'package:frun/src/presentation/app/app_state.dart';
import 'package:frun/src/presentation/app/commands/command_registry.dart';
import 'package:frun/src/presentation/app/commands/help_command.dart';
import 'package:frun/src/presentation/app/commands/vim_help_command.dart';
import 'package:frun/src/presentation/di/dependencies.dart';
import 'package:test/test.dart';

AppState _state() => AppState(
  project: const FlutterProjectEntity(
    root: '.',
    name: 'demo',
    workspaceRoot: '.',
    watchRoot: '.',
    hasVsCodeFolder: false,
    hasZedFolder: false,
  ),
  config: AppConfigEntity.defaults(),
  deps: Dependencies(),
);

void main() {
  test('/vim prints the grouped cheatsheet', () async {
    final state = _state();
    await VimHelpCommand().run(const [], state);
    final text = state.transcript.lines.map((l) => l.text).join('\n');
    expect(text, contains('Vim cheatsheet'));
    expect(text, contains('Motions'));
    expect(text, contains('Operators'));
    expect(text, contains('Text objects'));
    expect(text, contains('Registers & marks'));
    expect(text, contains('Macros'));
    expect(text, contains('Frun-specific'));
  });

  test('help vim delegates to the cheatsheet', () async {
    final state = _state();
    final registry = CommandRegistry()..register(VimHelpCommand());
    final help = HelpCommand(registry);
    registry.register(help);
    await help.run(const ['vim'], state);
    final text = state.transcript.lines.map((l) => l.text).join('\n');
    expect(text, contains('Vim cheatsheet'));
    expect(text, isNot(contains('Available commands')));
  });
}
