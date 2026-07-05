import '../../core/error/failure.dart';

class IdeFailure extends AppFailure {
  const IdeFailure({required super.message, super.cause, super.stackTrace});

  @override
  String get failureType => 'IdeFailure';
}
