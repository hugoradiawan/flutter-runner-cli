import '../../core/error/failure.dart';

class SessionFailure extends AppFailure {
  const SessionFailure({required super.message, super.cause, super.stackTrace});

  @override
  String get failureType => 'SessionFailure';
}
