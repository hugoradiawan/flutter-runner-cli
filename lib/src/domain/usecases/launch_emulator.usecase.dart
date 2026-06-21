import '../../ca/result.dart';
import '../../ca/usecase.dart';
import '../entities/device.entity.dart';
import '../failures/device_failure.dart';
import '../params/emulator_launch.params.dart';
import '../repositories/emulator_repository.dart';

class LaunchEmulatorUseCase
    extends UseCase<DeviceFailure, DeviceEntity, EmulatorLaunchParams> {
  const LaunchEmulatorUseCase(this._repo);

  final IEmulatorRepository _repo;

  @override
  Future<Result<DeviceFailure, DeviceEntity>> call([
    EmulatorLaunchParams? params,
  ]) {
    if (params == null) {
      return Future.value(
        Result.failure(
          const DeviceFailure(message: 'EmulatorLaunchParams required'),
        ),
      );
    }
    return _repo.launchEmulator(params);
  }
}
