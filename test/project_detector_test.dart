import 'dart:io';

import 'package:frun/src/data/datasources/project_detector.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('ProjectDetector', () {
    late Directory temp;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('frun_detect_');
    });

    tearDown(() => temp.deleteSync(recursive: true));

    test('walks upward to find pubspec.yaml', () {
      _writeFlutterPubspec(temp.path, name: 'my_app');
      final nested = Directory(p.join(temp.path, 'lib', 'src', 'foo'))
        ..createSync(recursive: true);

      final result = ProjectDetector.detect(startDir: nested.path);
      expect(result.isOk, isTrue, reason: result.error);
      expect(result.project!.name, 'my_app');
      expect(result.project!.root, temp.absolute.path);
    });

    test('rejects pubspecs that do not depend on Flutter', () {
      File(p.join(temp.path, 'pubspec.yaml')).writeAsStringSync(
        'name: pure_dart_app\nenvironment:\n  sdk: ^3.0.0\n',
      );
      final result = ProjectDetector.detect(startDir: temp.path);
      expect(result.isOk, isFalse);
      expect(result.error, contains('does not depend on Flutter'));
    });

    test('fails when no pubspec found', () {
      final result = ProjectDetector.detect(startDir: temp.path);
      expect(result.isOk, isFalse);
      expect(result.error, contains('No pubspec.yaml found'));
    });

    test('detects .vscode and .zed presence', () {
      _writeFlutterPubspec(temp.path);
      Directory(p.join(temp.path, '.vscode')).createSync();
      final result = ProjectDetector.detect(startDir: temp.path);
      expect(result.project!.hasVsCodeFolder, isTrue);
      expect(result.project!.hasZedFolder, isFalse);
    });

    test('finds .vscode in an ancestor (monorepo case)', () {
      // temp/
      //   .vscode/
      //   apps/client/
      //     pubspec.yaml
      Directory(p.join(temp.path, '.vscode')).createSync();
      final clientDir = Directory(p.join(temp.path, 'apps', 'client'))
        ..createSync(recursive: true);
      _writeFlutterPubspec(clientDir.path, name: 'vio_client');

      final result = ProjectDetector.detect(startDir: clientDir.path);
      expect(result.isOk, isTrue, reason: result.error);
      final project = result.project!;
      expect(project.root, clientDir.absolute.path);
      expect(project.workspaceRoot, temp.absolute.path);
      expect(project.hasVsCodeFolder, isTrue);
      expect(project.launchJsonPath, p.join(temp.absolute.path, '.vscode', 'launch.json'));
    });

    test('workspaceRoot falls back to project root when no .vscode found', () {
      _writeFlutterPubspec(temp.path);
      final result = ProjectDetector.detect(startDir: temp.path);
      expect(result.project!.workspaceRoot, temp.absolute.path);
      expect(result.project!.hasVsCodeFolder, isFalse);
    });

    test('Dart workspace pubspec auto-selects the lone Flutter app', () {
      // temp/pubspec.yaml (workspace listing apps/client + packages/core)
      // temp/apps/client/pubspec.yaml (Flutter app, has lib/main.dart)
      // temp/packages/core/pubspec.yaml (Flutter library, no main)
      File(p.join(temp.path, 'pubspec.yaml')).writeAsStringSync('''
name: vio_workspace
environment:
  sdk: ">=3.8.0 <4.0.0"
workspace:
  - apps/client
  - packages/core
''');
      Directory(p.join(temp.path, '.vscode')).createSync();

      final clientDir = Directory(p.join(temp.path, 'apps', 'client'))
        ..createSync(recursive: true);
      File(p.join(clientDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: vio_client
environment:
  sdk: ">=3.5.0 <4.0.0"
dependencies:
  flutter:
    sdk: flutter
''');
      Directory(p.join(clientDir.path, 'lib')).createSync(recursive: true);
      File(p.join(clientDir.path, 'lib', 'main.dart'))
          .writeAsStringSync('void main() {}');

      final coreDir = Directory(p.join(temp.path, 'packages', 'core'))
        ..createSync(recursive: true);
      File(p.join(coreDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: vio_core
environment:
  sdk: ">=3.5.0 <4.0.0"
  flutter: ">=3.0.0"
''');

      final result = ProjectDetector.detect(startDir: temp.path);
      expect(result.isOk, isTrue, reason: result.error);
      expect(result.project!.name, 'vio_client');
      expect(result.project!.root, clientDir.absolute.path);
      expect(result.project!.workspaceRoot, temp.absolute.path);
      expect(result.project!.hasVsCodeFolder, isTrue);
    });

    test('melos workspace auto-selects the lone Flutter app via packages globs', () {
      // temp/pubspec.yaml (plain Dart, melos dev_dep, no `workspace:` key)
      // temp/melos.yaml (packages: app, cores/*, features/*)
      // temp/app/pubspec.yaml (Flutter app, lib/main_uat.dart)
      // temp/cores/foo/pubspec.yaml (Flutter lib, no main)
      // temp/features/bar/pubspec.yaml (Flutter lib, no main)
      File(p.join(temp.path, 'pubspec.yaml')).writeAsStringSync('''
name: youapp
environment:
  sdk: ">=3.8.0 <4.0.0"
dev_dependencies:
  melos: ^6.0.0
''');
      File(p.join(temp.path, 'melos.yaml')).writeAsStringSync('''
name: youapp
packages:
  - app
  - cores/*
  - features/*
''');

      final appDir = Directory(p.join(temp.path, 'app'))
        ..createSync(recursive: true);
      File(p.join(appDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: youapp2
dependencies:
  flutter:
    sdk: flutter
''');
      Directory(p.join(appDir.path, 'lib')).createSync(recursive: true);
      File(p.join(appDir.path, 'lib', 'main_uat.dart'))
          .writeAsStringSync('void main() {}');

      final coreDir = Directory(p.join(temp.path, 'cores', 'foo'))
        ..createSync(recursive: true);
      File(p.join(coreDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: foo_core
environment:
  flutter: ">=3.0.0"
dependencies:
  flutter:
    sdk: flutter
''');

      final featDir = Directory(p.join(temp.path, 'features', 'bar'))
        ..createSync(recursive: true);
      File(p.join(featDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: bar_feature
dependencies:
  flutter:
    sdk: flutter
''');

      final result = ProjectDetector.detect(startDir: temp.path);
      expect(result.isOk, isTrue, reason: result.error);
      expect(result.project!.name, 'youapp2');
      expect(result.project!.root, appDir.absolute.path);
    });

    test('fails with helpful message when no workspace and no melos.yaml', () {
      File(p.join(temp.path, 'pubspec.yaml')).writeAsStringSync(
        'name: pure_dart\nenvironment:\n  sdk: ^3.0.0\n',
      );
      final result = ProjectDetector.detect(startDir: temp.path);
      expect(result.isOk, isFalse);
      expect(result.error, contains('melos.yaml'));
    });

    test('reports ambiguity when a workspace has multiple Flutter apps', () {
      File(p.join(temp.path, 'pubspec.yaml')).writeAsStringSync('''
name: ws
environment:
  sdk: ">=3.8.0 <4.0.0"
workspace:
  - apps/client
  - apps/admin
''');
      for (final name in ['client', 'admin']) {
        final dir = Directory(p.join(temp.path, 'apps', name))
          ..createSync(recursive: true);
        File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: vio_$name
dependencies:
  flutter:
    sdk: flutter
''');
        Directory(p.join(dir.path, 'lib')).createSync(recursive: true);
        File(p.join(dir.path, 'lib', 'main.dart'))
            .writeAsStringSync('void main() {}');
      }
      final result = ProjectDetector.detect(startDir: temp.path);
      expect(result.isOk, isFalse);
      expect(result.error, contains('more than one Flutter app'));
      expect(result.error, contains('apps/client'));
      expect(result.error, contains('apps/admin'));
    });
  });
}

void _writeFlutterPubspec(String dir, {String name = 'app'}) {
  File(p.join(dir, 'pubspec.yaml')).writeAsStringSync('''
name: $name
environment:
  sdk: ^3.0.0
dependencies:
  flutter:
    sdk: flutter
''');
}
