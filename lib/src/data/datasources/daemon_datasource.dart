import '../../ca/data_source.dart';
import 'flutter_daemon.dart';
import '../../domain/failures/daemon_failure.dart';

class DaemonDataSource extends RemoteDataSource<DaemonFailure> {
  DaemonDataSource(this.daemon);

  final FlutterDaemon daemon;
}

