import 'package:frun/src/data/models/diagnostic.dart';
import 'package:test/test.dart';

Diagnostic mk(DiagnosticSeverity sev, {String? code}) => Diagnostic(
      filePath: '/x.dart',
      line: 1,
      column: 1,
      severity: sev,
      message: 'm',
      code: code,
    );

void main() {
  group('Diagnostic.category', () {
    test('review-marker codes on info become todo', () {
      for (final code in ['todo', 'TODO', 'fixme', 'hack', 'undone']) {
        expect(
          mk(DiagnosticSeverity.info, code: code).category,
          DiagnosticCategory.todo,
          reason: code,
        );
      }
    });

    test('plain info / warning / error keep their category', () {
      expect(mk(DiagnosticSeverity.info, code: 'deprecated_member_use').category,
          DiagnosticCategory.info);
      expect(mk(DiagnosticSeverity.warning, code: 'todo').category,
          DiagnosticCategory.warning); // only infos become todo
      expect(mk(DiagnosticSeverity.error).category, DiagnosticCategory.error);
    });
  });

  test('counts tallies (error, warning, info, todo) by category', () {
    final (e, w, i, t) = Diagnostic.counts(<Diagnostic>[
      mk(DiagnosticSeverity.error),
      mk(DiagnosticSeverity.warning),
      mk(DiagnosticSeverity.info, code: 'deprecated_member_use'),
      mk(DiagnosticSeverity.info, code: 'deprecated_member_use'),
      mk(DiagnosticSeverity.info, code: 'todo'),
      mk(DiagnosticSeverity.info, code: 'fixme'),
    ]);
    expect((e, w, i, t), (1, 1, 2, 2));
  });
}
