import '../../core/base/params.dart';
import '../../core/base/use_case.dart';
import '../../core/result.dart';
import '../entities/melos_command.dart';
import '../failures/melos_failure.dart';
import '../repositories/melos_repository.dart';

class DiscoverMelosCommandsUseCase
    extends UseCase<MelosFailure, List<MelosCommandEntity>, Params> {
  const DiscoverMelosCommandsUseCase(this._repo);

  final MelosRepository _repo;

  @override
  Future<Result<MelosFailure, List<MelosCommandEntity>>> call([
    Params? params,
  ]) => _repo.discoverCommands();
}
