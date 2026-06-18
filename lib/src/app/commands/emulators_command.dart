import 'dart:async';

import '../../config/config.dart';
import '../../devices/emulator_manager.dart';
import '../../ide/frun_notifier.dart';
import '../app_state.dart';
import 'command.dart';

/// `/emulators` — list, launch, or create emulators.
///
/// Usage:
///   /emulators                  → list
///   /emulators launch `<id>`    → launch an emulator and auto-select it
///   /emulators create [name]    → create a new Android emulator
class EmulatorsCommand extends Command {
  EmulatorsCommand();

  @override
  String get name => 'emulators';

  @override
  String get summary => 'List, launch, or create emulators';

  @override
  String get usage => 'emulators [launch `<id>`|create [name]|list]';

  @override
  List<String> get aliases => const ['emu'];

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    final daemon = state.daemon;
    if (daemon == null) {
      state.visibleTranscript.warn(
        'Flutter daemon is still starting. Try emulators again shortly.',
      );
      return CommandResult.ok;
    }
    final manager = EmulatorManager(daemon);

    if (args.isEmpty) {
      await _openPicker(manager, state);
      return CommandResult.ok;
    }
    if (args.first == 'list' || args.first == 'ls') {
      await _list(manager, state);
      return CommandResult.ok;
    }
    if (args.first == 'launch' && args.length >= 2) {
      final hasFlag = args.length >= 3 && (args[2] == 'cold' || args[2] == '--cold');
      final coldBoot = hasFlag || state.config.emulatorBoot == FrunEmulatorBoot.cold;
      await _launch(manager, args[1], state, coldBoot: coldBoot);
      return CommandResult.ok;
    }
    if (args.first == 'create') {
      final name = args.length >= 2 ? args.sublist(1).join('_') : null;
      await _create(manager, name, state);
      return CommandResult.ok;
    }
    state.visibleTranscript.warn('Usage: $usage');
    return CommandResult.ok;
  }

  Future<void> _openPicker(EmulatorManager manager, AppState state) async {
    state.visibleTranscript.system('Fetching emulators…');
    bool timedOut = false;
    try {
      final emulators = await manager.list().timeout(
        const Duration(seconds: 90),
        onTimeout: () {
          timedOut = true;
          return const [];
        },
      );
      if (timedOut) {
        state.visibleTranscript.warn(
          'Emulator list timed out. Flutter daemon may be slow or Android SDK not configured.',
        );
        return;
      }
      if (emulators.isEmpty) {
        state.visibleTranscript.warn(
          'No emulators found. Try `emulators create [name]` (Android only).',
        );
        return;
      }
      state.setEmulatorPicker(emulators);
    } catch (e) {
      state.visibleTranscript.error('Failed to list emulators: $e');
    }
  }

  Future<void> _list(EmulatorManager manager, AppState state) async {
    state.visibleTranscript.system('Fetching emulators…');
    bool timedOut = false;
    try {
      final emulators = await manager.list().timeout(
        const Duration(seconds: 90),
        onTimeout: () {
          timedOut = true;
          return const [];
        },
      );
      if (timedOut) {
        state.visibleTranscript.warn(
          'Emulator list timed out. Flutter daemon may be slow or Android SDK not configured.',
        );
        return;
      }
      if (emulators.isEmpty) {
        state.visibleTranscript.warn(
          'No emulators defined. Try `emulators create [name]` (Android only).',
        );
        return;
      }
      state.visibleTranscript.system('Emulators:');
      for (final e in emulators) {
        state.visibleTranscript.info(
          '  ${e.id.padRight(28)} ${e.name.padRight(30)} ${e.platformType ?? ""}',
        );
      }
      state.visibleTranscript.info('Launch with `/emulators launch <id>`.');
    } catch (e) {
      state.visibleTranscript.error('Failed to list emulators: $e');
    }
  }

  Future<void> _launch(
    EmulatorManager manager,
    String id,
    AppState state, {
    bool coldBoot = false,
  }) async {
    final bootLabel = coldBoot ? ' (cold boot)' : '';
    state.visibleTranscript.system('Launching emulator $id$bootLabel…');
    state.notifier.notify(FrunNotifEvent.launchingEmulator, detail: 'Launching emulator $id$bootLabel…');
    try {
      final device = await manager.launchAndAwaitDevice(id, coldBoot: coldBoot);
      if (device == null) {
        state.visibleTranscript.warn(
          'Emulator $id launched but no device appeared within the timeout.',
        );
        return;
      }
      state.notifier.notify(FrunNotifEvent.emulatorReady, detail: 'Emulator ready: ${device.name}');
      state.visibleTranscript.success(
        'Emulator ready: ${device.name} (${device.id}).',
      );
    } catch (e) {
      state.visibleTranscript.error('Failed to launch emulator $id: $e');
    }
  }

  Future<void> _create(
    EmulatorManager manager,
    String? name,
    AppState state,
  ) async {
    state.visibleTranscript.system('Creating emulator${name == null ? "" : " $name"}…');
    try {
      await manager.create(name: name);
      state.visibleTranscript.success(
        'Emulator created. Run `emulators` to see it.',
      );
    } catch (e) {
      state.visibleTranscript.error('Failed to create emulator: $e');
    }
  }
}
