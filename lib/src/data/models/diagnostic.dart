import '../../core/base/model.dart';
import '../../domain/entities/diagnostic.dart';

class DiagnosticModel extends DiagnosticEntity
    implements Model<DiagnosticModel> {
  const DiagnosticModel({
    required super.filePath,
    required super.line,
    required super.column,
    required super.severity,
    required super.message,
    super.code,
  });

  /// Build a model from an LSP `publishDiagnostics` entry. [line]/[column] are
  /// the already 1-based source position; [lspSeverity] is the raw LSP severity
  /// int (1 = error, 2 = warning, 3 = information, 4 = hint → info).
  factory DiagnosticModel.fromLsp({
    required String filePath,
    required int line,
    required int column,
    required int? lspSeverity,
    required String message,
    String? code,
  }) => DiagnosticModel(
    filePath: filePath,
    line: line,
    column: column,
    severity: severityFromLsp(lspSeverity),
    message: message,
    code: code,
  );

  /// Maps an LSP `DiagnosticSeverity` int onto the domain [DiagnosticSeverity].
  static DiagnosticSeverity severityFromLsp(int? n) {
    switch (n) {
      case 1:
        return DiagnosticSeverity.error;
      case 2:
        return DiagnosticSeverity.warning;
      default:
        // 3 = information, 4 = hint, null/unknown → info.
        return DiagnosticSeverity.info;
    }
  }

  factory DiagnosticModel.fromJson(Map<String, Object?> json) {
    final severityStr = json['severity'] as String?;
    final severity = DiagnosticSeverity.values.firstWhere(
      (s) => s.name == severityStr,
      orElse: () => DiagnosticSeverity.info,
    );
    return DiagnosticModel(
      filePath: json['file'] as String? ?? '',
      line: (json['line'] as num?)?.toInt() ?? 1,
      column: (json['column'] as num?)?.toInt() ?? 1,
      severity: severity,
      message: json['message'] as String? ?? '',
      code: json['code'] as String?,
    );
  }

  @override
  Json toJson() => <String, dynamic>{
    'file': filePath,
    'line': line,
    'column': column,
    'severity': severity.name,
    'message': message,
    if (code != null) 'code': code,
  };

  @override
  DiagnosticModel? fromJson(dynamic json) {
    if (json is! Map<String, Object?>) return null;
    return DiagnosticModel.fromJson(json);
  }
}
