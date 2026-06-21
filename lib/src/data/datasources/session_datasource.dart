import '../../ca/data_source.dart';
import '../../daemon/app_session.dart';
import '../../domain/failures/session_failure.dart';

class SessionDataSource extends RemoteDataSource<SessionFailure> {
  SessionDataSource(this.session);

  final AppRunSession session;
}
