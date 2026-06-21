import '../../ca/result.dart';
import '../entities/device.entity.dart';
import '../failures/device_failure.dart';

abstract class IDeviceRepository {
  Stream<List<DeviceEntity>> watchDevices();
  Future<Result<DeviceFailure, List<DeviceEntity>>> listDevices();
}
