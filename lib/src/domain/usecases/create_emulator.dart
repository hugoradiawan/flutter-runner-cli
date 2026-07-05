import '../../core/base/use_case.dart';
import '../../core/result.dart';
import '../failures/device_failure.dart';
import '../params/emulator_create_params.dart';
import '../repositories/emulator_repository.dart';

class CreateEmulatorUseCase
    extends UseCase<DeviceFailure, void, EmulatorCreateParams> {
  const CreateEmulatorUseCase(this._repo);

  final EmulatorRepository _repo;

  @override
  Future<Result<DeviceFailure, void>> call([EmulatorCreateParams? params]) =>
      _repo.createEmulator(params ?? const EmulatorCreateParams());
}
