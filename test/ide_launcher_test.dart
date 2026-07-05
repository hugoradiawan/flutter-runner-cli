import 'package:frun/src/data/services/ide_launcher.dart';
import 'package:frun/src/data/services/package_config_uri_resolver.dart';
import 'package:frun/src/domain/value_objects/config_values.dart';
import 'package:frun/src/domain/value_objects/source_location.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('DesktopIdeLauncher.commandFor', () {
    const loc = SourceLocation(file: '/abs/lib/main.dart', line: 12, column: 4);

    test('builds `code -g file:line:col` for VS Code', () {
      final spec = DesktopIdeLauncher.commandFor(FrunIde.vscode, loc);
      expect(spec.executable, anyOf('code', 'code.cmd'));
      expect(spec.args, ['-g', '/abs/lib/main.dart:12:4']);
    });

    test('builds `zed file:line:col` for Zed', () {
      final spec = DesktopIdeLauncher.commandFor(FrunIde.zed, loc);
      expect(spec.executable, 'zed');
      expect(spec.args, ['/abs/lib/main.dart:12:4']);
      expect(spec.runInShell, isFalse);
    });

    test('builds remote-send for Neovim', () {
      final spec = DesktopIdeLauncher.commandFor(
        FrunIde.neovim,
        loc,
        nvimServer: r'\\.\pipe\nvim.1234.0',
      );
      expect(spec.executable, 'nvim');
      expect(spec.args[0], '--server');
      expect(spec.args[1], r'\\.\pipe\nvim.1234.0');
      expect(spec.args[2], '--remote-send');
      expect(spec.args[3], contains('cursor(12,4)'));
      expect(spec.args[3], contains(':edit /abs/lib/main.dart'));
      expect(spec.runInShell, isFalse);
    });
  });

  group('FrunIde.fromString', () {
    test('parses neovim', () {
      expect(FrunIde.fromString('neovim'), FrunIde.neovim);
    });
  });

  group('PackageConfigUriResolver.resolve', () {
    const resolver = PackageConfigUriResolver();

    test('parses file:/// URIs', () {
      final loc = resolver.resolve(
        'file:///tmp/app/lib/main.dart',
        line: 7,
        column: 2,
      );
      expect(loc, isNotNull);
      // toFilePath() yields native separators (e.g. `\tmp\...` on Windows);
      // compare with p.equals so the assertion holds on every platform.
      expect(p.equals(loc!.file, '/tmp/app/lib/main.dart'), isTrue);
      expect(loc.line, 7);
      expect(loc.column, 2);
    });

    test('rejects unsupported schemes without project root', () {
      expect(resolver.resolve('dart:io/file.dart'), isNull);
    });

    test('rejects package: URIs when no project root', () {
      expect(resolver.resolve('package:foo/bar.dart'), isNull);
    });
  });
}
