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
    final useCase = state.listDevicesUseCase;
    if (useCase == null) {
      state.visibleTranscript.warn(
        'Flutter daemon is still starting. Try devices again in a moment.',
      );
      return CommandResult.ok;
    }
    final result = await useCase.call();
    return result.fold(
      (failure) {
        state.visibleTranscript.warn(failure.message);
        return CommandResult.ok;
      },
      (devices) {
        if (devices.isEmpty) {
          state.visibleTranscript.warn(
            'No devices found. Try emulators to launch one or connect a device.',
          );
          return CommandResult.ok;
        }
        state.visibleTranscript.system('Devices:');
        for (final d in devices) {
          final kind = d.emulator ? 'emulator' : 'physical';
          state.visibleTranscript.info(
            '  ${d.name.padRight(30)} ${d.id.padRight(28)} ${d.platform.padRight(14)} $kind',
          );
        }
        state.visibleTranscript.info('Pick a device when you /run.');
        return CommandResult.ok;
      },
    );
  }
}
