import '../../config/config.dart';
import '../../config/config_store.dart';
import '../app_state.dart';
import 'command.dart';

/// `/config` — read or set config keys.
///
/// Usage:
///   /config                 → print current config
///   /config show            → same as above
///   /config path            → print where the config file lives
///   /config set `<k>` `<v>` → set a key and save
class ConfigCommand extends Command {
  ConfigCommand(this.store);

  final ConfigStore store;

  @override
  String get name => 'config';

  @override
  String get summary => 'View or change frun configuration';

  @override
  String get usage => '/config [show|path|set <key> <value>]';

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    final sub = args.isEmpty ? 'show' : args.first;
    switch (sub) {
      case 'show':
        state.showConfigEditor = true;
        return CommandResult.ok;
      case 'path':
        state.visibleTranscript.info(store.path);
        return CommandResult.ok;
      case 'set':
        if (args.length < 3) {
          state.visibleTranscript.warn('Usage: $usage');
          return CommandResult.ok;
        }
        _set(args[1], args.sublist(2).join(' '), state);
        return CommandResult.ok;
      default:
        state.visibleTranscript.warn('Unknown subcommand "$sub". $usage');
        return CommandResult.ok;
    }
  }

  void _set(String key, String value, AppState state) {
    final current = state.config;
    FrunConfig? next;
    switch (key) {
      case 'ide':
        next = current.copyWith(ide: FrunIde.fromString(value));
      case 'nvim_server':
        next = value.isEmpty || value == 'null'
            ? current.copyWith(clearNvimServer: true)
            : current.copyWith(nvimServer: value);
      case 'editor_mode':
        next = current.copyWith(editorMode: FrunEditorMode.fromString(value));
      case 'theme':
        next = current.copyWith(theme: FrunThemeMode.fromString(value));
      case 'hot_reload_on_save':
        next = current.copyWith(hotReloadOnSave: _parseBool(value));
      case 'verbose_errors':
        next = current.copyWith(verboseErrors: _parseBool(value));
      case 'open_devtools_on_launch':
        next = current.copyWith(
          openDevtoolsOnLaunch: FrunDevToolsAutoOpen.fromString(value),
        );
      default:
        state.visibleTranscript.warn('Unknown key "$key".');
        return;
    }
    state.setConfig(next);
    store.save(next);
    state.visibleTranscript.success('Set $key = $value');
  }

  static bool _parseBool(String v) {
    final s = v.toLowerCase();
    return s == 'true' || s == 'yes' || s == 'on' || s == '1';
  }
}
