import '../../core/result.dart';
import '../failures/ide_failure.dart';
import '../value_objects/config_values.dart';
import '../value_objects/source_location.dart';

/// Opens source locations in the user's IDE.
abstract class IdeLauncher {
  const IdeLauncher();

  /// Open [location] in [ide]. [nvimServer] overrides the environment-derived
  /// Neovim RPC address (`$NVIM` / `$NVIM_LISTEN_ADDRESS`).
  Future<Result<IdeFailure, void>> open(
    SourceLocation location, {
    required FrunIde ide,
    String? nvimServer,
  });
}
