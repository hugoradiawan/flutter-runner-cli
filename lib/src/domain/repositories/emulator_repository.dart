import '../../core/result.dart';
import '../entities/device.dart';
import '../entities/emulator.dart';
import '../failures/device_failure.dart';
import '../params/emulator_launch_params.dart';

abstract class EmulatorRepository {
  Future<Result<DeviceFailure, List<EmulatorEntity>>> listEmulators();
  Future<Result<DeviceFailure, DeviceEntity>> launchEmulator(
    EmulatorLaunchParams params,
  );
}
