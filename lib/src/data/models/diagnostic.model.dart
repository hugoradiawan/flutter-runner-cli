import '../../ca/model.dart';
import '../../domain/entities/diagnostic.entity.dart';

class DiagnosticModel extends DiagnosticEntity implements Model<DiagnosticModel> {
  const DiagnosticModel({
    required super.filePath,
    required super.line,
    required super.column,
    required super.severity,
    required super.message,
    super.code,
  });

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
