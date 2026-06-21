import '../../ca/params.dart';
import '../../ca/result.dart';
import '../../ca/usecase.dart';
import '../entities/device.entity.dart';
import '../failures/device_failure.dart';
import '../repositories/device_repository.dart';

class ListDevicesUseCase extends UseCase<DeviceFailure, List<DeviceEntity>, Params> {
  const ListDevicesUseCase(this._repo);

  final IDeviceRepository _repo;

  @override
  Future<Result<DeviceFailure, List<DeviceEntity>>> call([Params? params]) =>
      _repo.listDevices();
}
