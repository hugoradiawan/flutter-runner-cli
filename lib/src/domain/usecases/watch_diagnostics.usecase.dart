import '../../ca/result.dart';
import '../../ca/usecase.dart';
import '../entities/diagnostic.entity.dart';
import '../failures/analysis_failure.dart';
import '../params/diagnostics_filter.params.dart';
import '../repositories/diagnostics_repository.dart';

class WatchDiagnosticsUseCase
    extends StreamUseCase<AnalysisFailure, List<DiagnosticEntity>, DiagnosticsFilterParams> {
  const WatchDiagnosticsUseCase(this._repo);

  final IDiagnosticsRepository _repo;

  @override
  Stream<Result<AnalysisFailure, List<DiagnosticEntity>>> call([
    DiagnosticsFilterParams? params,
  ]) =>
      _repo
          .watchDiagnostics(params ?? const DiagnosticsFilterParams())
          .map(Result.success);
}
