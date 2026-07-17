import '../../core/error/failure.dart';

class MelosFailure extends AppFailure {
  const MelosFailure({required super.message, super.cause, super.stackTrace});

  @override
  String get failureType => 'MelosFailure';
}
