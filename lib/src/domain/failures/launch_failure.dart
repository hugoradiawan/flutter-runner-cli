import '../../core/error/failure.dart';

class LaunchFailure extends AppFailure {
  const LaunchFailure({required super.message, super.cause, super.stackTrace});

  @override
  String get failureType => 'LaunchFailure';
}
