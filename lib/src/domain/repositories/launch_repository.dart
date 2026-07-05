import '../../core/result.dart';
import '../entities/launch_entry.dart';
import '../failures/launch_failure.dart';

abstract class LaunchRepository {
  /// Discover every way to launch the project: `.vscode/launch.json` entries
  /// merged with `main()` entry-points found under `lib/`.
  Future<Result<LaunchFailure, List<LaunchEntryEntity>>>
  discoverLaunchEntries();
}
