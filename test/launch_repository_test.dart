import 'dart:io';

import 'package:frun/src/data/repositories/launch_repository_impl.dart';
import 'package:frun/src/domain/entities/flutter_project.dart';
import 'package:frun/src/domain/entities/launch_entry.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temp;

  FlutterProjectEntity project() => FlutterProjectEntity(
    root: temp.path,
    name: 'demo',
    workspaceRoot: temp.path,
    watchRoot: temp.path,
    hasVsCodeFolder: true,
    hasZedFolder: false,
  );

  setUp(() {
    temp = Directory.systemTemp.createTempSync('frun_launch_repo_');
  });

  tearDown(() => temp.deleteSync(recursive: true));

  test('merges launch.json entries with scanned main() files', () async {
    Directory(p.join(temp.path, '.vscode')).createSync();
    File(p.join(temp.path, '.vscode', 'launch.json')).writeAsStringSync('''
{
  "configurations": [
    {"name": "dev", "type": "dart", "program": "lib/main.dart"}
  ]
}
''');
    final lib = Directory(p.join(temp.path, 'lib'))..createSync();
    File(p.join(lib.path, 'main.dart')).writeAsStringSync('void main() {}');
    File(
      p.join(lib.path, 'main_staging.dart'),
    ).writeAsStringSync('void main() {}');

    final result = await LaunchRepositoryImpl(
      project(),
    ).discoverLaunchEntries();

    expect(result.isSuccess, isTrue);
    final entries = result.fold((f) => fail(f.message), (e) => e);
    expect(entries.map((e) => e.name), contains('dev'));
    expect(
      entries.where((e) => e.source == LaunchEntrySource.mainScanner),
      isNotEmpty,
    );
    expect(
      entries.map((e) => p.basename(e.program)),
      containsAll(['main.dart', 'main_staging.dart']),
    );
  });

  test('returns empty when nothing is discoverable', () async {
    final result = await LaunchRepositoryImpl(
      project(),
    ).discoverLaunchEntries();
    expect(result.isSuccess, isTrue);
    expect(result.fold((f) => fail(f.message), (e) => e), isEmpty);
  });
}
