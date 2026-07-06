import '../../domain/domain.dart';

/// A target the user can pick from the run picker: a connected device, or an
/// offline emulator that must be booted first ([needsBoot] = true).
class RunTarget {
  const RunTarget({
    required this.id,
    required this.name,
    required this.platform,
    required this.needsBoot,
  });

  /// Device id (connected target) or emulator id (offline target to boot).
  final String id;
  final String name;

  /// Platform string for a device, or platformType for an emulator. May be ''.
  final String platform;

  /// `true` when [id] is an offline emulator that must be launched before run.
  final bool needsBoot;

  factory RunTarget.device(DeviceEntity d) =>
      RunTarget(id: d.id, name: d.name, platform: d.platform, needsBoot: false);

  factory RunTarget.emulator(EmulatorEntity e) => RunTarget(
    id: e.id,
    name: e.name,
    platform: e.platformType ?? '',
    needsBoot: true,
  );
}
