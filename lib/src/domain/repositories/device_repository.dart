import '../../core/result.dart';
import '../entities/device.dart';
import '../failures/device_failure.dart';

abstract class DeviceRepository {
  Future<Result<DeviceFailure, List<DeviceEntity>>> listDevices();
}
