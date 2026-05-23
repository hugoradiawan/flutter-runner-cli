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
class ConfigCommand extends SlashCommand {
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
        _show(state);
        return CommandResult.ok;
      case 'path':
        state.transcript.info(store.path);
        return CommandResult.ok;
      case 'set':
        if (args.length < 3) {
          state.transcript.warn('Usage: $usage');
          return CommandResult.ok;
        }
        _set(args[1], args.sublist(2).join(' '), state);
        return CommandResult.ok;
      default:
        state.transcript.warn('Unknown subcommand "$sub". $usage');
        return CommandResult.ok;
    }
  }

  void _show(AppState state) {
    final c = state.config;
    state.transcript
      ..system('Config (${store.path}):')
      ..info('  ide                       = ${c.ide.id}')
      ..info('  editor_mode               = ${c.editorMode.id}')
      ..info('  theme                     = ${c.theme.id}')
      ..info('  hot_reload_on_save        = ${c.hotReloadOnSave}')
      ..info('  default_device_id         = ${c.defaultDeviceId ?? "(none)"}')
      ..info('  open_devtools_on_launch   = ${c.openDevtoolsOnLaunch.id}');
  }

  void _set(String key, String value, AppState state) {
    final current = state.config;
    FrunConfig? next;
    switch (key) {
      case 'ide':
        next = current.copyWith(ide: FrunIde.fromString(value));
      case 'editor_mode':
        next = current.copyWith(editorMode: FrunEditorMode.fromString(value));
      case 'theme':
        next = current.copyWith(theme: FrunThemeMode.fromString(value));
      case 'hot_reload_on_save':
        next = current.copyWith(hotReloadOnSave: _parseBool(value));
      case 'default_device_id':
        next = value.isEmpty || value == 'null'
            ? current.copyWith(clearDefaultDeviceId: true)
            : current.copyWith(defaultDeviceId: value);
      case 'open_devtools_on_launch':
        next = current.copyWith(
          openDevtoolsOnLaunch: FrunDevToolsAutoOpen.fromString(value),
        );
      default:
        state.transcript.warn('Unknown key "$key".');
        return;
    }
    state.setConfig(next);
    store.save(next);
    state.transcript.success('Set $key = $value');
  }

  static bool _parseBool(String v) {
    final s = v.toLowerCase();
    return s == 'true' || s == 'yes' || s == 'on' || s == '1';
  }
}
