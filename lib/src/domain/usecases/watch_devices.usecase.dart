import '../../ca/params.dart';
import '../../ca/result.dart';
import '../../ca/usecase.dart';
import '../entities/device.entity.dart';
import '../failures/device_failure.dart';
import '../repositories/device_repository.dart';

class WatchDevicesUseCase
    extends StreamUseCase<DeviceFailure, List<DeviceEntity>, Params> {
  const WatchDevicesUseCase(this._repo);

  final IDeviceRepository _repo;

  @override
  Stream<Result<DeviceFailure, List<DeviceEntity>>> call([Params? params]) =>
      _repo.watchDevices().map(Result.success);
}
