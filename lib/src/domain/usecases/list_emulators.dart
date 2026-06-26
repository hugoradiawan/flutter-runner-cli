import '../../core/base/params.dart';
import '../../core/base/use_case.dart';
import '../../core/result.dart';
import '../entities/emulator.dart';
import '../failures/device_failure.dart';
import '../repositories/emulator_repository.dart';

class ListEmulatorsUseCase
    extends UseCase<DeviceFailure, List<EmulatorEntity>, Params> {
  const ListEmulatorsUseCase(this._repo);

  final EmulatorRepository _repo;

  @override
  Future<Result<DeviceFailure, List<EmulatorEntity>>> call([Params? params]) =>
      _repo.listEmulators();
}
