import '../../ca/data_source.dart';
import '../../domain/failures/analysis_failure.dart';
import 'analysis_server.dart';

class AnalysisDataSource extends RemoteDataSource<AnalysisFailure> {
  AnalysisDataSource(this.server);

  final DartAnalysisServer server;
}
