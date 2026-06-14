import '../app_state.dart';
import 'command.dart';

/// `/devices` — list connected devices. Device selection happens per-run via
/// the `/run` target picker, so this command is informational only.
class DevicesCommand extends Command {
  DevicesCommand();

  @override
  String get name => 'devices';

  @override
  String get summary => 'List connected devices';

  @override
  String get usage => 'devices [list]';

  @override
  List<String> get aliases => const ['dev'];

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    final mgr = state.deviceManager;
    if (mgr == null) {
      state.visibleTranscript.warn(
        'Flutter daemon is still starting. Try devices again in a moment.',
      );
      return CommandResult.ok;
    }
    _printList(state);
    return CommandResult.ok;
  }

  void _printList(AppState state) {
    final list = state.deviceManager!.devices;
    if (list.isEmpty) {
      state.visibleTranscript.warn(
        'No devices found. Try emulators to launch one or connect a device.',
      );
      return;
    }
    state.visibleTranscript.system('Devices:');
    for (final d in list) {
      final kind = d.emulator ? 'emulator' : 'physical';
      state.visibleTranscript.info(
        '  ${d.name.padRight(30)} ${d.id.padRight(28)} ${d.platform.padRight(14)} $kind',
      );
    }
    state.visibleTranscript.info('Pick a device when you /run.');
  }
}
