import 'dart:io';

import 'package:frun/src/analysis/diagnostic.dart';
import 'package:frun/src/analysis/diagnostics_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('frun_diag_store_'));
  tearDown(() => temp.deleteSync(recursive: true));

  Diagnostic mk(String file, DiagnosticSeverity s) => Diagnostic(
        filePath: file,
        line: 3,
        column: 4,
        severity: s,
        message: 'msg for $file',
        code: 'rule',
      );

  test('round-trips diagnostics through save/load', () {
    final store = DiagnosticsStore(
      projectRoot: p.join(temp.path, 'projA'),
      overrideDir: p.join(temp.path, 'cache'),
    );
    store.save(<Diagnostic>[
      mk('/a.dart', DiagnosticSeverity.error),
      mk('/b.dart', DiagnosticSeverity.info),
    ]);
    final loaded = store.load();
    expect(loaded, hasLength(2));
    expect(loaded.first.filePath, '/a.dart');
    expect(loaded.first.severity, DiagnosticSeverity.error);
    expect(loaded.first.line, 3);
    expect(loaded.first.column, 4);
    expect(loaded.first.code, 'rule');
  });

  test('load returns empty when no cache file exists', () {
    final store = DiagnosticsStore(
      projectRoot: p.join(temp.path, 'fresh'),
      overrideDir: p.join(temp.path, 'cache'),
    );
    expect(store.load(), isEmpty);
  });

  test('different project roots use different cache files', () {
    final dir = p.join(temp.path, 'cache');
    final a = DiagnosticsStore(
      projectRoot: p.join(temp.path, 'projA'),
      overrideDir: dir,
    );
    final b = DiagnosticsStore(
      projectRoot: p.join(temp.path, 'projB'),
      overrideDir: dir,
    );
    expect(a.path, isNot(b.path));

    a.save(<Diagnostic>[mk('/a.dart', DiagnosticSeverity.error)]);
    b.save(<Diagnostic>[
      mk('/b.dart', DiagnosticSeverity.warning),
      mk('/c.dart', DiagnosticSeverity.info),
    ]);
    expect(a.load(), hasLength(1));
    expect(b.load(), hasLength(2));
  });
}
