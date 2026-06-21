import '../../ca/result.dart';
import '../../ca/usecase.dart';
import '../entities/diagnostic.entity.dart';
import '../failures/analysis_failure.dart';
import '../params/diagnostics_filter.params.dart';
import '../repositories/diagnostics_repository.dart';

class GetDiagnosticsUseCase
    extends UseCase<AnalysisFailure, List<DiagnosticEntity>, DiagnosticsFilterParams> {
  const GetDiagnosticsUseCase(this._repo);

  final IDiagnosticsRepository _repo;

  @override
  Future<Result<AnalysisFailure, List<DiagnosticEntity>>> call([
    DiagnosticsFilterParams? params,
  ]) =>
      _repo.getDiagnostics(params ?? const DiagnosticsFilterParams());
}
