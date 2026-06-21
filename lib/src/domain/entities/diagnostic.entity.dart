import '../../ca/entity.dart';

enum DiagnosticSeverity { error, warning, info }

enum DiagnosticCategory { error, warning, info, todo }

const _todoCodes = <String>{'todo', 'fixme', 'hack', 'undone'};

class DiagnosticEntity extends Entity<DiagnosticEntity> {
  const DiagnosticEntity({
    required this.filePath,
    required this.line,
    required this.column,
    required this.severity,
    required this.message,
    this.code,
  });

  final String filePath;
  final int line;
  final int column;
  final DiagnosticSeverity severity;
  final String message;
  final String? code;

  DiagnosticCategory get category {
    if (severity == DiagnosticSeverity.info &&
        _todoCodes.contains((code ?? '').toLowerCase())) {
      return DiagnosticCategory.todo;
    }
    return switch (severity) {
      DiagnosticSeverity.error => DiagnosticCategory.error,
      DiagnosticSeverity.warning => DiagnosticCategory.warning,
      DiagnosticSeverity.info => DiagnosticCategory.info,
    };
  }

  @override
  List<Object?> get props => [filePath, line, column, severity, message, code];
}
