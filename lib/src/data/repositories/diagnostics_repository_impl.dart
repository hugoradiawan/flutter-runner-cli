import '../../core/result.dart';
import '../../domain/entities/diagnostic.dart';
import '../../domain/failures/analysis_failure.dart';
import '../../domain/params/diagnostics_filter_params.dart';
import '../../domain/repositories/diagnostics_repository.dart';
import '../datasources/analysis_server.dart';

class DiagnosticsRepositoryImpl implements DiagnosticsRepository {
  DiagnosticsRepositoryImpl(this._server);

  final DartAnalysisServer _server;

  List<DiagnosticEntity> _applyFilter(
    List<DiagnosticEntity> raw,
    DiagnosticsFilterParams params,
  ) {
    var result = raw;
    if (params.category != null) {
      result = result.where((d) => d.category == params.category).toList();
    }
    if (params.text != null && params.text!.isNotEmpty) {
      final q = params.text!.toLowerCase();
      result = result
          .where(
            (d) =>
                d.message.toLowerCase().contains(q) ||
                d.filePath.toLowerCase().contains(q),
          )
          .toList();
    }
    return result;
  }

  @override
  Stream<List<DiagnosticEntity>> watchDiagnostics(
    DiagnosticsFilterParams params,
  ) => _server.diagnostics.map((raw) => _applyFilter(raw, params));

  @override
  Future<Result<AnalysisFailure, List<DiagnosticEntity>>> getDiagnostics(
    DiagnosticsFilterParams params,
  ) async {
    try {
      return Result.success(_applyFilter(_server.snapshot, params));
    } catch (e, st) {
      return Result.failure(
        AnalysisFailure(message: e.toString(), cause: e, stackTrace: st),
      );
    }
  }
}
