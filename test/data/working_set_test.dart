import 'dart:io';

import 'package:frun/src/data/services/working_set.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('frun_ws_'));
  tearDown(() => temp.deleteSync(recursive: true));

  // Create a file under temp so the existence filter passes, and return its
  // repo-relative path with forward slashes (as git emits).
  String touch(String rel) {
    final abs = p.join(temp.path, p.joinAll(rel.split('/')));
    File(abs)
      ..createSync(recursive: true)
      ..writeAsStringSync('// x\n');
    return rel;
  }

  test('keeps only .dart paths across staged/unstaged/untracked prefixes', () {
    touch('features/youchat/lib/chat.page.dart');
    touch('app/lib/main.dart');
    touch('app/pubspec.yaml');
    const out = '''
 M features/youchat/lib/chat.page.dart
M  app/lib/main.dart
?? app/pubspec.yaml
''';
    final found = parseGitPorcelainDartFiles(
      out,
      temp.path,
    ).map(p.normalize).toSet();
    expect(
      found,
      contains(
        p.normalize(p.join(temp.path, 'features/youchat/lib/chat.page.dart')),
      ),
    );
    expect(
      found,
      contains(p.normalize(p.join(temp.path, 'app/lib/main.dart'))),
    );
    expect(found.any((f) => f.endsWith('.yaml')), isFalse);
  });

  test('resolves the new path of a rename and drops missing files', () {
    touch('lib/new_name.dart');
    const out = '''
R  lib/old_name.dart -> lib/new_name.dart
 D lib/deleted.dart
''';
    final found = parseGitPorcelainDartFiles(
      out,
      temp.path,
    ).map(p.normalize).toSet();
    expect(
      found,
      contains(p.normalize(p.join(temp.path, 'lib/new_name.dart'))),
    );
    // The deleted file no longer exists on disk → excluded.
    expect(found.any((f) => f.endsWith('deleted.dart')), isFalse);
    // The pre-rename path is not what exists → excluded.
    expect(found.any((f) => f.endsWith('old_name.dart')), isFalse);
  });

  test('empty / clean output yields nothing', () {
    expect(parseGitPorcelainDartFiles('', temp.path), isEmpty);
    expect(parseGitPorcelainDartFiles('\n\n', temp.path), isEmpty);
  });
}
