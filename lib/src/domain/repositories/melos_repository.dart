import '../../core/result.dart';
import '../entities/melos_command.dart';
import '../entities/melos_run_event.dart';
import '../failures/melos_failure.dart';

abstract class MelosRepository {
  /// Discover runnable melos commands: the built-ins (`bootstrap`, `clean`)
  /// plus every custom script declared in the monorepo config (`melos:` key
  /// in the root `pubspec.yaml` and/or a `melos.yaml`). Returns an empty list
  /// when the project is not a melos workspace.
  Future<Result<MelosFailure, List<MelosCommandEntity>>> discoverCommands();

  /// Run [command] as a child process in the melos workspace root, streaming
  /// its stdout/stderr as [MelosRunLine]s and ending with a [MelosRunExit].
  Stream<MelosRunEvent> run(MelosCommandEntity command);
}
