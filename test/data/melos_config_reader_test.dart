import 'dart:io';

import 'package:frun/src/data/services/melos_config_reader.dart';
import 'package:frun/src/domain/entities/melos_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('frun_melos_cfg_');
  });

  tearDown(() => temp.deleteSync(recursive: true));

  void write(String relPath, String content) {
    final file = File(p.join(temp.path, relPath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  test('returns null when not a melos workspace', () {
    write('pubspec.yaml', 'name: solo\n');
    expect(const MelosConfigReader().read(temp.path), isNull);
  });

  test('parses scripts from pubspec.yaml melos: section (String and Map)', () {
    write('pubspec.yaml', '''
name: workspace
melos:
  scripts:
    analyze:
      run: dart analyze
      description: Analyze all packages
    test: melos exec -- dart test
''');

    final ws = const MelosConfigReader().read(temp.path);
    expect(ws, isNotNull);
    expect(ws!.root, temp.path);

    final byName = {for (final c in ws.scripts) c.name: c};
    expect(byName.keys, containsAll(['analyze', 'test']));
    expect(byName['analyze']!.description, 'Analyze all packages');
    expect(byName['analyze']!.kind, MelosCommandKind.script);
    expect(byName['analyze']!.melosArgs, ['run', 'analyze']);
    expect(byName['test']!.description, 'melos exec -- dart test');
  });

  test('merges scripts from pubspec.yaml and melos.yaml, sorted by name', () {
    write('pubspec.yaml', '''
name: workspace
melos:
  scripts:
    test: dart test
''');
    write('melos.yaml', '''
name: workspace
scripts:
  format: dart format .
''');

    final ws = const MelosConfigReader().read(temp.path);
    expect(ws!.scripts.map((c) => c.name), ['format', 'test']);
  });

  test('walks up from a nested package dir to the melos root', () {
    write('pubspec.yaml', '''
name: workspace
melos:
  scripts:
    build: dart run build_runner build
''');
    final pkgDir = p.join(temp.path, 'packages', 'core');
    Directory(pkgDir).createSync(recursive: true);
    write(p.join('packages', 'core', 'pubspec.yaml'), 'name: core\n');

    final ws = const MelosConfigReader().read(pkgDir);
    expect(ws, isNotNull);
    expect(ws!.root, temp.path);
    expect(ws.scripts.single.name, 'build');
  });

  test('collapses multiline run: scalars into a single-line description', () {
    write('pubspec.yaml', r'''
name: workspace
melos:
  scripts:
    run:prod:debug:
      run: |
        melos exec -c 1 --scope=app -- \
          fvm flutter run --flavor prod --debug -t lib/main_prod.dart
''');

    final ws = const MelosConfigReader().read(temp.path);
    final desc = ws!.scripts.single.description;
    expect(desc, isNot(contains('\n')));
    expect(desc, startsWith('melos exec -c 1 --scope=app --'));
    expect(desc, contains('fvm flutter run --flavor prod'));
  });

  test('detects a melos.yaml-only workspace with no scripts', () {
    write('melos.yaml', 'name: workspace\npackages:\n  - packages/*\n');
    final ws = const MelosConfigReader().read(temp.path);
    expect(ws, isNotNull);
    expect(ws!.scripts, isEmpty);
  });
}
