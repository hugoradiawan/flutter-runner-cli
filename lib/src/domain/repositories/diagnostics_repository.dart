import '../../ca/result.dart';
import '../entities/diagnostic.entity.dart';
import '../failures/analysis_failure.dart';
import '../params/diagnostics_filter.params.dart';

abstract class IDiagnosticsRepository {
  Stream<List<DiagnosticEntity>> watchDiagnostics(DiagnosticsFilterParams params);
  Future<Result<AnalysisFailure, List<DiagnosticEntity>>> getDiagnostics(
    DiagnosticsFilterParams params,
  );
}
