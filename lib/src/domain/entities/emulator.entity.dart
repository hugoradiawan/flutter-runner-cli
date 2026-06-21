import '../../ca/entity.dart';

class EmulatorEntity extends Entity<EmulatorEntity> {
  const EmulatorEntity({
    required this.id,
    required this.name,
    this.category,
    this.platformType,
  });

  final String id;
  final String name;
  final String? category;
  final String? platformType;

  @override
  List<Object?> get props => [id, name, category, platformType];
}
