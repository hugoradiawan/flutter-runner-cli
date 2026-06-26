import '../../core/base/entity.dart';

class DeviceEntity extends Entity<DeviceEntity> {
  const DeviceEntity({
    required this.id,
    required this.name,
    required this.platform,
    this.category,
    this.platformType,
    required this.ephemeral,
    required this.emulator,
    this.emulatorId,
  });

  final String id;
  final String name;
  final String platform;
  final String? category;
  final String? platformType;
  final bool ephemeral;
  final bool emulator;
  final String? emulatorId;

  @override
  List<Object?> get props => [
    id,
    name,
    platform,
    category,
    platformType,
    ephemeral,
    emulator,
    emulatorId,
  ];
}
