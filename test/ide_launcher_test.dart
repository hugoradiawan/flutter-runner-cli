import 'package:frun/src/config/config.dart';
import 'package:frun/src/ide/ide_launcher.dart';
import 'package:frun/src/ide/source_location.dart';
import 'package:test/test.dart';

void main() {
  group('IdeLauncher.commandFor', () {
    const loc = SourceLocation(file: '/abs/lib/main.dart', line: 12, column: 4);

    test('builds `code -g file:line:col` for VS Code', () {
      final spec = IdeLauncher.commandFor(FrunIde.vscode, loc);
      expect(spec.executable, anyOf('code', 'code.cmd'));
      expect(spec.args, ['-g', '/abs/lib/main.dart:12:4']);
    });

    test('builds `zed file:line:col` for Zed', () {
      final spec = IdeLauncher.commandFor(FrunIde.zed, loc);
      expect(spec.executable, 'zed');
      expect(spec.args, ['/abs/lib/main.dart:12:4']);
      expect(spec.runInShell, isFalse);
    });
  });

  group('SourceLocation.fromVmServiceUri', () {
    test('parses file:/// URIs', () {
      final loc = SourceLocation.fromVmServiceUri(
        'file:///tmp/app/lib/main.dart',
        line: 7,
        column: 2,
      );
      expect(loc, isNotNull);
      expect(loc!.file, '/tmp/app/lib/main.dart');
      expect(loc.line, 7);
      expect(loc.column, 2);
    });

    test('rejects unsupported schemes without project root', () {
      expect(
        SourceLocation.fromVmServiceUri('dart:io/file.dart'),
        isNull,
      );
    });

    test('rejects package: URIs when no project root', () {
      expect(
        SourceLocation.fromVmServiceUri('package:foo/bar.dart'),
        isNull,
      );
    });
  });
}
