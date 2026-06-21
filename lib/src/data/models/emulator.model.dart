import '../../ca/model.dart';
import '../../domain/entities/emulator.entity.dart';

class EmulatorModel extends EmulatorEntity implements Model<EmulatorModel> {
  const EmulatorModel({
    required super.id,
    required super.name,
    super.category,
    super.platformType,
  });

  factory EmulatorModel.fromJson(Map<String, Object?> json) => EmulatorModel(
    id: json['id'] as String? ?? '<unknown>',
    name: json['name'] as String? ?? json['id'] as String? ?? '<unknown>',
    category: json['category'] as String?,
    platformType: json['platformType'] as String?,
  );

  @override
  Json toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    if (category != null) 'category': category,
    if (platformType != null) 'platformType': platformType,
  };

  @override
  EmulatorModel? fromJson(dynamic json) {
    if (json is! Map<String, Object?>) return null;
    return EmulatorModel.fromJson(json);
  }
}
