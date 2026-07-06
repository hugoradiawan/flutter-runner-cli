import '../../core/base/params.dart';
import '../entities/launch_entry.dart';

class SessionStartParams extends Params {
  const SessionStartParams({
    required this.sessionId,
    required this.projectRoot,
    required this.entry,
    required this.deviceId,
  });

  /// Caller-assigned session identity (the run tab id).
  final int sessionId;
  final String projectRoot;
  final LaunchEntryEntity entry;
  final String deviceId;
}
