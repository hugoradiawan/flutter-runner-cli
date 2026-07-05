import '../../core/base/params.dart';
import '../../core/base/use_case.dart';
import '../../core/result.dart';
import '../entities/launch_entry.dart';
import '../failures/launch_failure.dart';
import '../repositories/launch_repository.dart';

class DiscoverLaunchEntriesUseCase
    extends UseCase<LaunchFailure, List<LaunchEntryEntity>, Params> {
  const DiscoverLaunchEntriesUseCase(this._repo);

  final LaunchRepository _repo;

  @override
  Future<Result<LaunchFailure, List<LaunchEntryEntity>>> call([
    Params? params,
  ]) => _repo.discoverLaunchEntries();
}
