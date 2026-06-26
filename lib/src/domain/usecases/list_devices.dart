import '../../core/base/params.dart';
import '../../core/base/use_case.dart';
import '../../core/result.dart';
import '../entities/device.dart';
import '../failures/device_failure.dart';
import '../repositories/device_repository.dart';

class ListDevicesUseCase
    extends UseCase<DeviceFailure, List<DeviceEntity>, Params> {
  const ListDevicesUseCase(this._repo);

  final DeviceRepository _repo;

  @override
  Future<Result<DeviceFailure, List<DeviceEntity>>> call([Params? params]) =>
      _repo.listDevices();
}
