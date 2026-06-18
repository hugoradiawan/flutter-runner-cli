import 'dart:io';

import 'package:frun/src/analysis/package_locator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('frun_pkgloc_'));
  tearDown(() => temp.deleteSync(recursive: true));

  void pkg(String rel) {
    final dir = Directory(p.join(temp.path, rel));
    dir.createSync(recursive: true);
    File(p.join(dir.path, 'pubspec.yaml'))
        .writeAsStringSync('name: ${p.basename(dir.path)}\n');
  }

  test('finds the root and nested monorepo packages', () {
    pkg('.'); // root pubspec
    pkg('app');
    pkg(p.join('features', 'youprofile'));
    pkg(p.join('cores', 'core'));

    final found = locatePackageRoots(temp.path).map(p.normalize).toSet();
    expect(found, contains(p.normalize(temp.path)));
    expect(found, contains(p.normalize(p.join(temp.path, 'app'))));
    expect(
      found,
      contains(p.normalize(p.join(temp.path, 'features', 'youprofile'))),
    );
    expect(found, contains(p.normalize(p.join(temp.path, 'cores', 'core'))));
  });

  test('prunes build/ and hidden .dart_tool/ ephemeral pubspecs', () {
    pkg('app');
    pkg(p.join('app', 'build', 'ephemeral'));
    pkg(p.join('app', '.dart_tool', 'x'));

    final found = locatePackageRoots(temp.path).map(p.normalize).toSet();
    expect(found, contains(p.normalize(p.join(temp.path, 'app'))));
    expect(found.any((f) => f.contains('build')), isFalse);
    expect(found.any((f) => f.contains('.dart_tool')), isFalse);
  });

  test('returns the root itself when no package is found', () {
    expect(locatePackageRoots(temp.path), [p.normalize(temp.path)]);
  });
}
