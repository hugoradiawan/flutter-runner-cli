import '../../config/config_store.dart';
import '../../devices/emulator_manager.dart';
import '../app_state.dart';
import 'command.dart';

/// `/emulators` — list, launch, or create emulators.
///
/// Usage:
///   /emulators                  → list
///   /emulators launch `<id>`    → launch an emulator and auto-select it
///   /emulators create [name]    → create a new Android emulator
class EmulatorsCommand extends SlashCommand {
  EmulatorsCommand({required this.configStore});

  final ConfigStore configStore;

  @override
  String get name => 'emulators';

  @override
  String get summary => 'List, launch, or create emulators';

  @override
  String get usage => '/emulators [launch `<id>`|create [name]]';

  @override
  List<String> get aliases => const ['emu'];

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    final daemon = state.daemon;
    if (daemon == null) {
      state.transcript.warn(
        'Flutter daemon is still starting. Try /emulators again shortly.',
      );
      return CommandResult.ok;
    }
    final manager = EmulatorManager(daemon);

    if (args.isEmpty || args.first == 'list' || args.first == 'ls') {
      await _list(manager, state);
      return CommandResult.ok;
    }
    if (args.first == 'launch' && args.length >= 2) {
      await _launch(manager, args[1], state);
      return CommandResult.ok;
    }
    if (args.first == 'create') {
      final name = args.length >= 2 ? args.sublist(1).join('_') : null;
      await _create(manager, name, state);
      return CommandResult.ok;
    }
    state.transcript.warn('Usage: $usage');
    return CommandResult.ok;
  }

  Future<void> _list(EmulatorManager manager, AppState state) async {
    try {
      final emulators = await manager.list();
      if (emulators.isEmpty) {
        state.transcript.warn(
          'No emulators defined. Try `/emulators create [name]` (Android only).',
        );
        return;
      }
      state.transcript.system('Emulators:');
      for (final e in emulators) {
        state.transcript.info(
          '  ${e.id.padRight(28)} ${e.name.padRight(30)} ${e.platformType ?? ""}',
        );
      }
      state.transcript.info('Launch with `/emulators launch <id>`.');
    } catch (e) {
      state.transcript.error('Failed to list emulators: $e');
    }
  }

  Future<void> _launch(
    EmulatorManager manager,
    String id,
    AppState state,
  ) async {
    state.transcript.system('Launching emulator $id…');
    try {
      final device = await manager.launchAndAwaitDevice(id);
      if (device == null) {
        state.transcript.warn(
          'Emulator $id launched but no device appeared within the timeout.',
        );
        return;
      }
      state.selectedDeviceId = device.id;
      final next = state.config.copyWith(defaultDeviceId: device.id);
      state.setConfig(next);
      configStore.save(next);
      state.transcript.success(
        'Emulator ready: ${device.name} (${device.id}). Selected.',
      );
    } catch (e) {
      state.transcript.error('Failed to launch emulator $id: $e');
    }
  }

  Future<void> _create(
    EmulatorManager manager,
    String? name,
    AppState state,
  ) async {
    state.transcript.system('Creating emulator${name == null ? "" : " $name"}…');
    try {
      await manager.create(name: name);
      state.transcript.success(
        'Emulator created. Run `/emulators` to see it.',
      );
    } catch (e) {
      state.transcript.error('Failed to create emulator: $e');
    }
  }
}
