import '../../core/result.dart';
import '../../data/models/device.dart';
import '../../domain/entities/device.dart';
import '../../domain/failures/device_failure.dart';
import '../../domain/repositories/device_repository.dart';
import '../datasources/device_manager.dart';

class DeviceRepositoryImpl implements DeviceRepository {
  DeviceRepositoryImpl(this._manager);

  final DeviceManager _manager;

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
