import 'package:frun/src/domain/entities/diagnostic.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('DiagnosticEntity.merge', () {
    DiagnosticEntity diag(
      String path,
      int line, {
      String? code,
      DiagnosticSeverity severity = DiagnosticSeverity.warning,
    }) => DiagnosticEntity(
      filePath: path,
      line: line,
      column: 1,
      severity: severity,
      message: 'm',
      code: code,
    );

    test('dedupes identical (path, line, column, code) entries', () {
      final a = diag(p.normalize('/x/lib/a.dart'), 3, code: 'todo');
      final dup = diag(p.normalize('/x/lib/a.dart'), 3, code: 'todo');
      final other = diag(p.normalize('/x/lib/a.dart'), 4, code: 'todo');

      final merged = DiagnosticEntity.merge([a], [dup, other]);
      expect(merged, [a, other]);
    });

    test('keeps analyzer entry when a todo duplicates it', () {
      final analyzer = diag(
        p.normalize('/x/lib/a.dart'),
        3,
        code: 'todo',
        severity: DiagnosticSeverity.info,
      );
      final todo = diag(p.normalize('/x/lib/a.dart'), 3, code: 'todo');

      final merged = DiagnosticEntity.merge([analyzer], [todo]);
      expect(merged.single.severity, DiagnosticSeverity.info);
    });

    test('distinct codes on the same location are kept', () {
      final a = diag(p.normalize('/x/lib/a.dart'), 3, code: 'todo');
      final b = diag(p.normalize('/x/lib/a.dart'), 3, code: 'fixme');

      expect(DiagnosticEntity.merge([a], [b]), hasLength(2));
    });
  });
}
