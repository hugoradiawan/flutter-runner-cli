import 'dart:async';
import 'dart:io';

import 'package:frun/src/data/services/dart_file_watcher.dart';
import 'package:frun/src/data/services/live_diagnostics.dart';
import 'package:frun/src/domain/entities/diagnostic.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

DiagnosticEntity _diag(String path, {String? code, int line = 1}) =>
    DiagnosticEntity(
      filePath: p.normalize(path),
      line: line,
      column: 1,
      severity: DiagnosticSeverity.info,
      message: code ?? 'm',
      code: code,
    );

void main() {
  late Directory temp;
  late StreamController<List<DiagnosticEntity>> analyzer;
  List<DiagnosticEntity> snapshot = const <DiagnosticEntity>[];

  setUp(() {
    temp = Directory.systemTemp.createTempSync('frun_live_diag_');
    analyzer = StreamController<List<DiagnosticEntity>>.broadcast();
    snapshot = const <DiagnosticEntity>[];
  });

  tearDown(() async {
    await analyzer.close();
    temp.deleteSync(recursive: true);
  });

  LiveDiagnosticsCoordinator build({
    Future<List<DiagnosticEntity>> Function(String root)? scanTodos,
  }) => LiveDiagnosticsCoordinator(
    projectRoot: temp.path,
    watchRoot: temp.path,
    analyzerDiagnostics: analyzer.stream,
    analyzerSnapshot: () => snapshot,
    scanTodos: scanTodos ?? (_) async => const <DiagnosticEntity>[],
    watchFiles: false,
  );

  test('analyzer bursts publish merged with current todos', () async {
    final scanDone = Completer<List<DiagnosticEntity>>();
    final coordinator = build(scanTodos: (_) => scanDone.future);
    final emissions = <List<DiagnosticEntity>>[];
    coordinator.merged.listen(emissions.add);
    coordinator.start();

    final analyzerDiag = _diag(
      p.join(temp.path, 'lib', 'a.dart'),
      code: 'unused_import',
    );
    analyzer.add([analyzerDiag]);
    await pumpEventQueue();
    expect(emissions, hasLength(1));
    expect(emissions.single, [analyzerDiag]);
    expect(coordinator.todoReady, isFalse);

    // The initial scan lands: publishes snapshot + todos.
    snapshot = [analyzerDiag];
    scanDone.complete([
      _diag(p.join(temp.path, 'lib', 'b.dart'), code: 'todo'),
    ]);
    await pumpEventQueue();

    expect(coordinator.todoReady, isTrue);
    expect(emissions, hasLength(2));
    expect(emissions.last.map((d) => d.code), ['unused_import', 'todo']);

    await coordinator.dispose();
  });

  test('file changes before the scan lands are replayed after it', () async {
    final lib = Directory(p.join(temp.path, 'lib'))..createSync();
    final newFile = File(p.join(lib.path, 'late.dart'))
      ..writeAsStringSync('// TODO: added during scan');

    final scanDone = Completer<List<DiagnosticEntity>>();
    final coordinator = build(scanTodos: (_) => scanDone.future);
    coordinator.start();

    // Change arrives while the initial scan is still running.
    coordinator.handleDartFileChanged(newFile.path, DartFileChangeType.add);
    expect(coordinator.todos, isEmpty);

    scanDone.complete(const <DiagnosticEntity>[]);
    await pumpEventQueue();

    expect(coordinator.todoReady, isTrue);
    expect(coordinator.todos, hasLength(1));
    expect(coordinator.todos.single.code, 'todo');

    await coordinator.dispose();
  });

  test('changes outside the project root are ignored', () async {
    final outside = Directory.systemTemp.createTempSync('frun_live_out_');
    addTearDown(() => outside.deleteSync(recursive: true));
    final foreign = File(p.join(outside.path, 'x.dart'))
      ..writeAsStringSync('// TODO: foreign');

    final coordinator = build();
    coordinator.start();
    await pumpEventQueue();
    expect(coordinator.todoReady, isTrue);

    coordinator.handleDartFileChanged(foreign.path, DartFileChangeType.add);
    expect(coordinator.todos, isEmpty);

    await coordinator.dispose();
  });

  test('remove events drop a file from the todo set', () async {
    final lib = Directory(p.join(temp.path, 'lib'))..createSync();
    final file = File(p.join(lib.path, 'a.dart'))
      ..writeAsStringSync('// FIXME: here');

    final coordinator = build(
      scanTodos: (root) async => [_diag(file.path, code: 'fixme')],
    );
    coordinator.start();
    await pumpEventQueue();
    expect(coordinator.todos, hasLength(1));

    file.deleteSync();
    coordinator.handleDartFileChanged(file.path, DartFileChangeType.remove);
    expect(coordinator.todos, isEmpty);

    await coordinator.dispose();
  });

  test('scan failure surfaces on warnings', () async {
    final coordinator = build(scanTodos: (_) async => throw StateError('boom'));
    final warnings = <String>[];
    coordinator.warnings.listen(warnings.add);
    coordinator.start();
    await pumpEventQueue();

    expect(warnings, hasLength(1));
    expect(warnings.single, contains('TODO diagnostics scan failed'));
    expect(coordinator.todoReady, isFalse);

    await coordinator.dispose();
  });
}
