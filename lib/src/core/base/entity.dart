import 'package:equatable/equatable.dart' show Equatable;

abstract class Entity<T extends Equatable> extends Equatable {
  const Entity();
}
