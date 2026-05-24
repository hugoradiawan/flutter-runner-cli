import '../../config/config_store.dart';
import '../app_state.dart';
import 'command.dart';

/// `/devices` — list devices, or `/devices select <id>` to pick one.
class DevicesCommand extends SlashCommand {
  DevicesCommand({required this.configStore});

  final ConfigStore configStore;

  @override
  String get name => 'devices';

  @override
  String get summary => 'List devices or select one';

  @override
  String get usage => '/devices [select <id>|list]';

  @override
  List<String> get aliases => const ['dev'];

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    final mgr = state.deviceManager;
    if (mgr == null) {
      state.visibleTranscript.warn(
        'Flutter daemon is still starting. Try /devices again in a moment.',
      );
      return CommandResult.ok;
    }
    if (args.isEmpty) {
      _openPicker(state);
      return CommandResult.ok;
    }
    if (args.first == 'list' || args.first == 'ls') {
      _printList(state);
      return CommandResult.ok;
    }
    if (args.first == 'select' && args.length >= 2) {
      _select(args[1], state);
      return CommandResult.ok;
    }
    // `/devices <id>` shortcut for select.
    if (args.length == 1) {
      _select(args.first, state);
      return CommandResult.ok;
    }
    state.visibleTranscript.warn('Usage: $usage');
    return CommandResult.ok;
  }

  void _openPicker(AppState state) {
    final list = state.deviceManager!.devices;
    if (list.isEmpty) {
      state.visibleTranscript.warn(
        'No devices found. Try /emulators to launch one or connect a device.',
      );
      return;
    }
    state.setDevicePicker(list);
  }

  void _printList(AppState state) {
    final list = state.deviceManager!.devices;
    if (list.isEmpty) {
      state.visibleTranscript.warn(
        'No devices found. Try /emulators to launch one or connect a device.',
      );
      return;
    }
    state.visibleTranscript.system('Devices:');
    for (final d in list) {
      final marker = d.id == state.selectedDeviceId ? '>' : ' ';
      final kind = d.emulator ? 'emulator' : 'physical';
      state.visibleTranscript.info(
        '  $marker ${d.name.padRight(30)} ${d.id.padRight(28)} ${d.platform.padRight(14)} $kind',
      );
    }
    state.visibleTranscript.info('Pick one with `/devices select <id>`.');
  }

  void _select(String id, AppState state) {
    final device = state.deviceManager!.byId(id);
    if (device == null) {
      state.visibleTranscript.error('No device with id "$id".');
      return;
    }
    state.selectedDeviceId = device.id;
    final updated = state.config.copyWith(defaultDeviceId: device.id);
    state.setConfig(updated);
    configStore.save(updated);
    state.visibleTranscript.success('Selected device: ${device.name} (${device.id}).');
  }
}
