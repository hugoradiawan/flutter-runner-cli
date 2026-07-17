import '../entities/melos_command.dart';
import '../entities/melos_run_event.dart';
import '../repositories/melos_repository.dart';

/// Runs a melos command and yields its live output. Unlike the [UseCase] base
/// (single Future result), a melos run is a stream of lines terminated by an
/// exit event, so this exposes the repository stream directly.
class RunMelosCommandUseCase {
  const RunMelosCommandUseCase(this._repo);

  final MelosRepository _repo;

  Stream<MelosRunEvent> call(MelosCommandEntity command) => _repo.run(command);
}
