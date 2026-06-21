import '../../ca/failures/app_failure.dart';

class AnalysisFailure extends AppFailure {
  const AnalysisFailure({
    required super.message,
    super.cause,
    super.stackTrace,
  });

  @override
  String get failureType => 'AnalysisFailure';
}
