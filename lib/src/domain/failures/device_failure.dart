import '../../core/error/failure.dart';

class DeviceFailure extends AppFailure {
  const DeviceFailure({required super.message, super.cause, super.stackTrace});

  @override
  String get failureType => 'DeviceFailure';
}
