import '../../ca/result.dart';
import '../entities/device.entity.dart';
import '../entities/emulator.entity.dart';
import '../failures/device_failure.dart';
import '../params/emulator_launch.params.dart';

abstract class IEmulatorRepository {
  Future<Result<DeviceFailure, List<EmulatorEntity>>> listEmulators();
  Future<Result<DeviceFailure, DeviceEntity>> launchEmulator(
    EmulatorLaunchParams params,
  );
}
