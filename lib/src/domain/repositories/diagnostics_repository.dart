import '../../core/result.dart';
import '../entities/diagnostic.dart';
import '../failures/analysis_failure.dart';
import '../params/diagnostics_filter_params.dart';

abstract class DiagnosticsRepository {
  /// Diagnostics last persisted to the on-disk cache. Used to seed the counters
  /// instantly on launch, before the analyzer's first pass completes. Returns an
  /// empty list when there is no cache.
  List<DiagnosticEntity> cachedDiagnostics();

  Stream<List<DiagnosticEntity>> watchDiagnostics(
    DiagnosticsFilterParams params,
  );
  Future<Result<AnalysisFailure, List<DiagnosticEntity>>> getDiagnostics(
    DiagnosticsFilterParams params,
  );
}
