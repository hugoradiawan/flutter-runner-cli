import 'dart:io';

import 'package:frun/src/data/repositories/melos_repository_impl.dart';
import 'package:frun/src/domain/entities/flutter_project.dart';
import 'package:frun/src/domain/entities/melos_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('frun_melos_repo_'));
  tearDown(() => temp.deleteSync(recursive: true));

  FlutterProjectEntity projectAt(String root) => FlutterProjectEntity(
    root: root,
    name: 'workspace',
    workspaceRoot: root,
    watchRoot: root,
    hasVsCodeFolder: false,
    hasZedFolder: false,
  );

  void writePubspec(String content) =>
      File(p.join(temp.path, 'pubspec.yaml')).writeAsStringSync(content);

  test(
    'discoverCommands returns builtins + scripts for a melos workspace',
    () async {
      writePubspec('''
name: workspace
melos:
  scripts:
    analyze: dart analyze
''');

      final repo = MelosRepositoryImpl(projectAt(temp.path));
      final result = await repo.discoverCommands();
      final commands = result.fold(
        (f) => fail('unexpected failure: $f'),
        (c) => c,
      );

      final builtins = commands
          .where((c) => c.kind == MelosCommandKind.builtin)
          .toList();
      expect(builtins.map((c) => c.name), containsAll(['bootstrap', 'clean']));
      expect(commands.map((c) => c.name), contains('analyze'));
    },
  );

  test('discoverCommands returns empty list for a non-melos project', () async {
    writePubspec('name: solo\n');
    final repo = MelosRepositoryImpl(projectAt(temp.path));
    final result = await repo.discoverCommands();
    expect(result.fold((_) => null, (c) => c), isEmpty);
  });
}
