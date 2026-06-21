import '../../ca/params.dart';
import '../../ca/result.dart';
import '../../ca/usecase.dart';
import '../entities/emulator.entity.dart';
import '../failures/device_failure.dart';
import '../repositories/emulator_repository.dart';

class ListEmulatorsUseCase
    extends UseCase<DeviceFailure, List<EmulatorEntity>, Params> {
  const ListEmulatorsUseCase(this._repo);

  final IEmulatorRepository _repo;

  @override
  Future<Result<DeviceFailure, List<EmulatorEntity>>> call([Params? params]) =>
      _repo.listEmulators();
}
