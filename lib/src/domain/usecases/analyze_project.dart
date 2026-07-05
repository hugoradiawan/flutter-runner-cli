import '../../core/base/params.dart';
import '../../core/base/use_case.dart';
import '../../core/result.dart';
import '../entities/diagnostic.dart';
import '../failures/analysis_failure.dart';
import '../repositories/diagnostics_repository.dart';

class AnalyzeProjectUseCase
    extends UseCase<AnalysisFailure, List<DiagnosticEntity>, Params> {
  const AnalyzeProjectUseCase(this._repo);

  final DiagnosticsRepository _repo;

  @override
  Future<Result<AnalysisFailure, List<DiagnosticEntity>>> call([
    Params? params,
  ]) => _repo.analyzeProject();
}
