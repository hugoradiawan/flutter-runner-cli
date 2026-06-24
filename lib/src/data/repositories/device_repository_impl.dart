import '../../ca/result.dart';
import '../../data/models/device.model.dart';
import '../datasources/device_manager.dart';
import '../../domain/entities/device.entity.dart';
import '../../domain/failures/device_failure.dart';
import '../../domain/repositories/device_repository.dart';

class DeviceRepositoryImpl implements IDeviceRepository {
  DeviceRepositoryImpl(this._manager);

  final DeviceManager _manager;

  @override
  Stream<List<DeviceEntity>> watchDevices() => _manager.changes.map(
    (devices) => devices
        .map(
          (d) => DeviceModel(
            id: d.id,
            name: d.name,
            platform: d.platform,
            category: d.category,
            platformType: d.platformType,
            ephemeral: d.ephemeral,
            emulator: d.emulator,
            emulatorId: d.emulatorId,
          ),
        )
        .toList(),
  );

  @override
  Future<Result<DeviceFailure, List<DeviceEntity>>> listDevices() async {
    try {
      final devices = _manager.devices
          .map(
            (d) => DeviceModel(
              id: d.id,
              name: d.name,
              platform: d.platform,
              category: d.category,
              platformType: d.platformType,
              ephemeral: d.ephemeral,
              emulator: d.emulator,
              emulatorId: d.emulatorId,
            ),
          )
          .toList();
      return Result.success(devices);
    } catch (e, st) {
      return Result.failure(
        DeviceFailure(message: e.toString(), cause: e, stackTrace: st),
      );
    }
  }
}
