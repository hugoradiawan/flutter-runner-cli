import '../../core/result.dart';
import '../../data/models/device.dart';
import '../../data/models/emulator.dart';
import '../../domain/entities/device.dart';
import '../../domain/entities/emulator.dart';
import '../../domain/failures/device_failure.dart';
import '../../domain/params/emulator_launch_params.dart';
import '../../domain/repositories/emulator_repository.dart';
import '../datasources/emulator_manager.dart';

class EmulatorRepositoryImpl implements EmulatorRepository {
  EmulatorRepositoryImpl(this._manager);

  final EmulatorManager _manager;

  @override
  Future<Result<DeviceFailure, List<EmulatorEntity>>> listEmulators() async {
    try {
      final emulators = await _manager.list();
      return Result.success(
        emulators
            .map(
              (e) => EmulatorModel(
                id: e.id,
                name: e.name,
                category: e.category,
                platformType: e.platformType,
              ),
            )
            .toList(),
      );
    } catch (e, st) {
      return Result.failure(
        DeviceFailure(message: e.toString(), cause: e, stackTrace: st),
      );
    }
  }

  @override
  Future<Result<DeviceFailure, DeviceEntity>> launchEmulator(
    EmulatorLaunchParams params,
  ) async {
    try {
      final device = await _manager.launchAndAwaitDevice(
        params.emulator.id,
        coldBoot: params.coldBoot,
      );
      if (device == null) {
        return Result.failure(
          DeviceFailure(
            message: 'Emulator ${params.emulator.id} did not produce a device',
          ),
        );
      }
      return Result.success(
        DeviceModel(
          id: device.id,
          name: device.name,
          platform: device.platform,
          category: device.category,
          platformType: device.platformType,
          ephemeral: device.ephemeral,
          emulator: device.emulator,
          emulatorId: device.emulatorId,
        ),
      );
    } catch (e, st) {
      return Result.failure(
        DeviceFailure(message: e.toString(), cause: e, stackTrace: st),
      );
    }
  }
}
