import '../../core/result.dart';
import '../entities/diagnostic.dart';
import '../failures/analysis_failure.dart';
import '../params/diagnostics_filter_params.dart';

abstract class DiagnosticsRepository {
  Stream<List<DiagnosticEntity>> watchDiagnostics(
    DiagnosticsFilterParams params,
  );
  Future<Result<AnalysisFailure, List<DiagnosticEntity>>> getDiagnostics(
    DiagnosticsFilterParams params,
  );
}
