import '../../analysis/analysis_server.dart';
import '../../analysis/diagnostic.dart' as src;
import '../../ca/result.dart';
import '../../data/models/diagnostic.model.dart';
import '../../domain/entities/diagnostic.entity.dart';
import '../../domain/failures/analysis_failure.dart';
import '../../domain/params/diagnostics_filter.params.dart';
import '../../domain/repositories/diagnostics_repository.dart';

class DiagnosticsRepositoryImpl implements IDiagnosticsRepository {
  DiagnosticsRepositoryImpl(this._server);

  final DartAnalysisServer _server;

  DiagnosticModel _fromSrc(src.Diagnostic d) => DiagnosticModel(
    filePath: d.filePath,
    line: d.line,
    column: d.column,
    severity: _mapSeverity(d.severity),
    message: d.message,
    code: d.code,
  );

  static DiagnosticSeverity _mapSeverity(src.DiagnosticSeverity s) =>
      switch (s) {
        src.DiagnosticSeverity.error => DiagnosticSeverity.error,
        src.DiagnosticSeverity.warning => DiagnosticSeverity.warning,
        src.DiagnosticSeverity.info => DiagnosticSeverity.info,
      };

  List<DiagnosticModel> _applyFilter(
    List<src.Diagnostic> raw,
    DiagnosticsFilterParams params,
  ) {
    var result = raw.map(_fromSrc).toList();
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
  ) =>
      _server.diagnostics.map((raw) => _applyFilter(raw, params));

  @override
  Future<Result<AnalysisFailure, List<DiagnosticEntity>>> getDiagnostics(
    DiagnosticsFilterParams params,
  ) async {
    try {
      final current = _server.snapshot;
      return Result.success(_applyFilter(current, params));
    } catch (e, st) {
      return Result.failure(
        AnalysisFailure(message: e.toString(), cause: e, stackTrace: st),
      );
    }
  }
}
