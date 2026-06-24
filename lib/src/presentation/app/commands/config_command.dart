import '../../../domain/params/config.params.dart';
import '../app_state.dart';
import 'command.dart';

/// `config` — read or set config keys.
///
/// Usage:
///   config                 → print current config
///   config show            → same as above
///   config path            → print where the config file lives
///   config set `<k>` `<v>` → set a key and save
class ConfigCommand extends Command {
  ConfigCommand();

  @override
  String get name => 'config';

  @override
  String get summary => 'View or change frun configuration';

  @override
  String get usage => 'config [show|path|set <key> <value>]';

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    final sub = args.isEmpty ? 'show' : args.first;
    switch (sub) {
      case 'show':
        state.showConfigEditor = true;
        return CommandResult.ok;
      case 'path':
        state.visibleTranscript.info(state.configPath);
        return CommandResult.ok;
      case 'set':
        if (args.length < 3) {
          state.visibleTranscript.warn('Usage: $usage');
          return CommandResult.ok;
        }
        await _set(args[1], args.sublist(2).join(' '), state);
        return CommandResult.ok;
      default:
        state.visibleTranscript.warn('Unknown subcommand "$sub". $usage');
        return CommandResult.ok;
    }
  }

  Future<void> _set(String key, String value, AppState state) async {
    final setUseCase = state.setConfigUseCase;
    if (setUseCase == null) {
      state.visibleTranscript.warn('Config not ready.');
      return;
    }
    final setResult =
        await setUseCase.call(ConfigSetParams(key: key, value: value));
    await setResult.fold(
      (failure) async => state.visibleTranscript.warn(failure.message),
      (_) async {
        final getResult = await state.getConfigUseCase?.call();
        getResult?.fold(
          (f) => state.visibleTranscript.warn(f.message),
          (entity) {
            state.setConfig(entity);
            state.visibleTranscript.success('Set $key = $value');
          },
        );
        if (getResult == null) {
          state.visibleTranscript.success('Set $key = $value');
        }
      },
    );
  }
}
