import '../../ca/failures/app_failure.dart';

class DaemonFailure extends AppFailure {
  const DaemonFailure({
    required super.message,
    super.cause,
    super.stackTrace,
  });

  @override
  String get failureType => 'DaemonFailure';
}
