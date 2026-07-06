import 'dart:io';

import 'package:frun/src/data/services/todo_diagnostics.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('frun_todo_idx_');
  });

  tearDown(() => temp.deleteSync(recursive: true));

  test('todo index updates and removes a single changed file', () {
    final lib = Directory(p.join(temp.path, 'lib'))..createSync();
    final main = File(p.join(lib.path, 'main.dart'));
    final other = File(p.join(lib.path, 'other.dart'));
    main.writeAsStringSync('// TODO: first');
    other.writeAsStringSync('// FIXME: second');

    final index = TodoDiagnosticsIndex(root: temp.path)..refreshAll();
    expect(
      index.diagnostics.map((d) => d.code),
      containsAll(['todo', 'fixme']),
    );

    main.writeAsStringSync('// no marker');
    index.updateFile(main.path);
    expect(
      index.diagnostics.map((d) => d.filePath),
      isNot(contains(main.path)),
    );
    expect(index.diagnostics.map((d) => d.code), ['fixme']);

    other.deleteSync();
    index.removeFile(other.path);
    expect(index.diagnostics, isEmpty);
  });

  test('scan skips excluded directories', () {
    final lib = Directory(p.join(temp.path, 'lib'))..createSync();
    File(p.join(lib.path, 'main.dart')).writeAsStringSync('// TODO: keep');
    Directory(p.join(temp.path, 'build')).createSync();
    File(
      p.join(temp.path, 'build', 'gen.dart'),
    ).writeAsStringSync('// TODO: skip');

    final found = scanDartTodoDiagnostics(root: temp.path);
    expect(found, hasLength(1));
    expect(found.single.filePath, contains('main.dart'));
  });
}
