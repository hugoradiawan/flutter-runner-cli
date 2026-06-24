/// Severity of a single analyzer diagnostic. Maps from the LSP
/// `DiagnosticSeverity` enum: 1 = error, 2 = warning, 3 = information,
/// 4 = hint (folded into [info]).
enum DiagnosticSeverity { error, warning, info }

/// How a diagnostic is bucketed in the UI counters/filters. Same as
/// [DiagnosticSeverity] plus a [todo] bucket split out of the infos so
/// review-marker comments get their own counter.
enum DiagnosticCategory { error, warning, info, todo }

/// Analyzer diagnostic codes the IDE emits for review-marker comments. These
/// arrive as `info`-severity diagnostics; we hoist them into their own bucket.
const _todoCodes = <String>{'todo', 'fixme', 'hack', 'undone'};

/// A single analyzer diagnostic for a source location, normalized from the Dart
/// analysis server's LSP `textDocument/publishDiagnostics` payload.
///
/// [line] and [column] are 1-based: LSP reports them 0-based, so we add 1 here
/// once so they map straight onto the IDE jump (`file:line:column`) and the
/// VS Code-style "Ln/Col" display without further arithmetic.
class Diagnostic {
  const Diagnostic({
    required this.filePath,
    required this.line,
    required this.column,
    required this.severity,
    required this.message,
    this.code,
  });

  /// Absolute path on disk.
  final String filePath;
  final int line;
  final int column;
  final DiagnosticSeverity severity;
  final String message;

  /// The lint/analysis rule name, e.g. `deprecated_member_use`. May be null.
  final String? code;

  /// UI bucket: review markers (todo/fixme/…) get their own category, otherwise
  /// it mirrors [severity].
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

  /// `(errors, warnings, infos, todos)` tallied across [diagnostics] by
  /// [category] (todos are excluded from the info count).
  static (int, int, int, int) counts(List<Diagnostic> diagnostics) {
    var e = 0;
    var w = 0;
    var i = 0;
    var t = 0;
    for (final d in diagnostics) {
      switch (d.category) {
        case DiagnosticCategory.error:
          e++;
        case DiagnosticCategory.warning:
          w++;
        case DiagnosticCategory.info:
          i++;
        case DiagnosticCategory.todo:
          t++;
      }
    }
    return (e, w, i, t);
  }

  /// Groups [diagnostics] by [filePath]. Files are ordered by descending
  /// severity weight (files with errors first) then by path; each file's issues
  /// are sorted by (line, column).
  static Map<String, List<Diagnostic>> groupByFile(
    List<Diagnostic> diagnostics,
  ) {
    final map = <String, List<Diagnostic>>{};
    for (final d in diagnostics) {
      (map[d.filePath] ??= <Diagnostic>[]).add(d);
    }
    for (final list in map.values) {
      list.sort((a, b) {
        final byLine = a.line.compareTo(b.line);
        return byLine != 0 ? byLine : a.column.compareTo(b.column);
      });
    }
    final entries = map.entries.toList()
      ..sort((a, b) {
        final wa = _fileWeight(a.value);
        final wb = _fileWeight(b.value);
        if (wa != wb) return wb.compareTo(wa);
        return a.key.toLowerCase().compareTo(b.key.toLowerCase());
      });
    return <String, List<Diagnostic>>{for (final e in entries) e.key: e.value};
  }

  /// Worst severity present in [list], as a sortable weight (error > warn > info).
  static int _fileWeight(List<Diagnostic> list) {
    var weight = 0;
    for (final d in list) {
      final w = switch (d.severity) {
        DiagnosticSeverity.error => 3,
        DiagnosticSeverity.warning => 2,
        DiagnosticSeverity.info => 1,
      };
      if (w > weight) weight = w;
    }
    return weight;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'file': filePath,
        'line': line,
        'column': column,
        'severity': severity.name,
        'message': message,
        if (code != null) 'code': code,
      };

  static Diagnostic? fromJson(Map<String, Object?> json) {
    final file = json['file'];
    if (file is! String) return null;
    return Diagnostic(
      filePath: file,
      line: (json['line'] as num?)?.toInt() ?? 1,
      column: (json['column'] as num?)?.toInt() ?? 1,
      severity: DiagnosticSeverity.values.firstWhere(
        (s) => s.name == json['severity'],
        orElse: () => DiagnosticSeverity.info,
      ),
      message: json['message'] as String? ?? '',
      code: json['code'] as String?,
    );
  }
}
