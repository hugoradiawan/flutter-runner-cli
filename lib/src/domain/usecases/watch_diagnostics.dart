import '../../core/base/use_case.dart';
import '../../core/result.dart';
import '../entities/diagnostic.dart';
import '../failures/analysis_failure.dart';
import '../params/diagnostics_filter_params.dart';
import '../repositories/diagnostics_repository.dart';

class WatchDiagnosticsUseCase
    extends
        StreamUseCase<
          AnalysisFailure,
          List<DiagnosticEntity>,
          DiagnosticsFilterParams
        > {
  const WatchDiagnosticsUseCase(this._repo);

  final DiagnosticsRepository _repo;

  @override
  Stream<Result<AnalysisFailure, List<DiagnosticEntity>>> call([
    DiagnosticsFilterParams? params,
  ]) => _repo
      .watchDiagnostics(params ?? const DiagnosticsFilterParams())
      .map(Result.success);
}
