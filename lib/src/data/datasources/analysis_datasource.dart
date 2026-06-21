import '../../analysis/analysis_server.dart';
import '../../ca/data_source.dart';
import '../../domain/failures/analysis_failure.dart';

class AnalysisDataSource extends RemoteDataSource<AnalysisFailure> {
  AnalysisDataSource(this.server);

  final DartAnalysisServer server;
}
