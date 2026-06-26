import '../../core/base/model.dart';
import '../../domain/entities/device.dart';

class DeviceModel extends DeviceEntity implements Model<DeviceModel> {
  const DeviceModel({
    required super.id,
    required super.name,
    required super.platform,
    super.category,
    super.platformType,
    required super.ephemeral,
    required super.emulator,
    super.emulatorId,
  });

  factory DeviceModel.fromJson(Map<String, Object?> json) => DeviceModel(
    id: json['id'] as String? ?? '<unknown>',
    name: json['name'] as String? ?? '<unknown>',
    platform: json['platform'] as String? ?? 'unknown',
    category: json['category'] as String?,
    platformType: json['platformType'] as String?,
    ephemeral: (json['ephemeral'] as bool?) ?? true,
    emulator: (json['emulator'] as bool?) ?? false,
    emulatorId: json['emulatorId'] as String?,
  );

  @override
  Json toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'platform': platform,
    if (category != null) 'category': category,
    if (platformType != null) 'platformType': platformType,
    'ephemeral': ephemeral,
    'emulator': emulator,
    if (emulatorId != null) 'emulatorId': emulatorId,
  };

  @override
  DeviceModel? fromJson(dynamic json) {
    if (json is! Map<String, Object?>) return null;
    return DeviceModel.fromJson(json);
  }
}
