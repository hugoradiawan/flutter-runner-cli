import '../../core/base/use_case.dart';
import '../../core/result.dart';
import '../entities/diagnostic.dart';
import '../failures/analysis_failure.dart';
import '../params/diagnostics_filter_params.dart';
import '../repositories/diagnostics_repository.dart';

class GetDiagnosticsUseCase
    extends
        UseCase<
          AnalysisFailure,
          List<DiagnosticEntity>,
          DiagnosticsFilterParams
        > {
  const GetDiagnosticsUseCase(this._repo);

  final DiagnosticsRepository _repo;

  @override
  Future<Result<AnalysisFailure, List<DiagnosticEntity>>> call([
    DiagnosticsFilterParams? params,
  ]) => _repo.getDiagnostics(params ?? const DiagnosticsFilterParams());
}
