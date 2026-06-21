import '../../ca/entity.dart';
import 'launch_entry.entity.dart';

class RunSessionEntity extends Entity<RunSessionEntity> {
  const RunSessionEntity({
    required this.tabId,
    required this.entry,
    required this.deviceId,
    required this.isRunning,
    this.devToolsUrl,
  });

  final int tabId;
  final LaunchEntryEntity entry;
  final String deviceId;
  final bool isRunning;
  final String? devToolsUrl;

  @override
  List<Object?> get props => [
    tabId,
    entry,
    deviceId,
    isRunning,
    devToolsUrl,
  ];
}
