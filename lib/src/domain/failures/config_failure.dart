import '../../core/error/failure.dart';

class ConfigFailure extends AppFailure {
  const ConfigFailure({required super.message, super.cause, super.stackTrace});

  @override
  String get failureType => 'ConfigFailure';
}
