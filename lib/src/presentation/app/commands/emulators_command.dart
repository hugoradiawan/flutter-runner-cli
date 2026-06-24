import 'dart:async';

import '../../../data/datasources/emulator_manager.dart';
import '../../../data/datasources/frun_notifier.dart';
import '../../../domain/entities/emulator.entity.dart';
import '../../../domain/params/emulator_launch.params.dart';
import '../../../domain/value_objects/config_values.dart';
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
    if (args.isEmpty) {
      await _openPicker(state);
      return CommandResult.ok;
    }
    if (args.first == 'list' || args.first == 'ls') {
      await _list(state);
      return CommandResult.ok;
    }
    if (args.first == 'launch' && args.length >= 2) {
      final hasFlag =
          args.length >= 3 && (args[2] == 'cold' || args[2] == '--cold');
      final coldBoot =
          hasFlag || state.config.emulatorBoot == FrunEmulatorBoot.cold;
      await _launch(args[1], state, coldBoot: coldBoot);
      return CommandResult.ok;
    }
    if (args.first == 'create') {
      final daemon = state.daemon;
      if (daemon == null) {
        state.visibleTranscript.warn(
          'Flutter daemon is still starting. Try emulators again shortly.',
        );
        return CommandResult.ok;
      }
      final name = args.length >= 2 ? args.sublist(1).join('_') : null;
      await _create(EmulatorManager(daemon), name, state);
      return CommandResult.ok;
    }
    state.visibleTranscript.warn('Usage: $usage');
    return CommandResult.ok;
  }

  Future<void> _openPicker(AppState state) async {
    final useCase = state.listEmulatorsUseCase;
    if (useCase == null) {
      state.visibleTranscript.warn(
        'Flutter daemon is still starting. Try emulators again shortly.',
      );
      return;
    }
    state.visibleTranscript.system('Fetching emulators…');
    final result = await useCase.call();
    result.fold(
      (failure) => state.visibleTranscript.error(
        'Failed to list emulators: ${failure.message}',
      ),
      (emulators) {
        if (emulators.isEmpty) {
          state.visibleTranscript.warn(
            'No emulators found. Try `emulators create [name]` (Android only).',
          );
          return;
        }
        state.setEmulatorPicker(emulators);
      },
    );
  }

  Future<void> _list(AppState state) async {
    final useCase = state.listEmulatorsUseCase;
    if (useCase == null) {
      state.visibleTranscript.warn(
        'Flutter daemon is still starting. Try emulators again shortly.',
      );
      return;
    }
    state.visibleTranscript.system('Fetching emulators…');
    final result = await useCase.call();
    result.fold(
      (failure) => state.visibleTranscript.error(
        'Failed to list emulators: ${failure.message}',
      ),
      (emulators) {
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
      },
    );
  }

  Future<void> _launch(
    String id,
    AppState state, {
    bool coldBoot = false,
  }) async {
    final listUseCase = state.listEmulatorsUseCase;
    final launchUseCase = state.launchEmulatorUseCase;
    if (listUseCase == null || launchUseCase == null) {
      state.visibleTranscript.warn(
        'Flutter daemon is still starting. Try emulators again shortly.',
      );
      return;
    }

    final listResult = await listUseCase.call();
    EmulatorEntity? entity;
    listResult.fold(
      (failure) => state.visibleTranscript.error(
        'Failed to list emulators: ${failure.message}',
      ),
      (emulators) {
        try {
          entity = emulators.firstWhere((e) => e.id == id);
        } on StateError {
          state.visibleTranscript.warn(
            'Emulator "$id" not found. Run `emulators list` to see available IDs.',
          );
        }
      },
    );
    if (entity == null) return;

    final bootLabel = coldBoot ? ' (cold boot)' : '';
    state.visibleTranscript.system('Launching emulator $id$bootLabel…');
    state.notifier.notify(
      FrunNotifEvent.launchingEmulator,
      detail: 'Launching emulator $id$bootLabel…',
    );

    final result = await launchUseCase.call(
      EmulatorLaunchParams(emulator: entity!, coldBoot: coldBoot),
    );
    result.fold(
      (failure) => state.visibleTranscript.error(
        'Failed to launch emulator $id: ${failure.message}',
      ),
      (device) {
        state.notifier.notify(
          FrunNotifEvent.emulatorReady,
          detail: 'Emulator ready: ${device.name}',
        );
        state.visibleTranscript.success(
          'Emulator ready: ${device.name} (${device.id}).',
        );
      },
    );
  }

  Future<void> _create(
    EmulatorManager manager,
    String? name,
    AppState state,
  ) async {
    state.visibleTranscript.system(
      'Creating emulator${name == null ? "" : " $name"}…',
    );
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
