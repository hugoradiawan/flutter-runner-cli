import 'package:frun/src/project/launch_config.dart';
import 'package:test/test.dart';

void main() {
  group('LaunchConfigParser', () {
    test('returns only type=dart entries', () {
      const jsonc = r'''
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "dev",
      "type": "dart",
      "program": "lib/main_dev.dart",
      "flutterMode": "debug",
      "flavor": "dev",
      "args": ["--foo"],
      "toolArgs": ["--web-renderer=canvaskit"]
    },
    {
      "name": "ignore",
      "type": "node"
    }
  ]
}
''';
      final entries = LaunchConfigParser.parse(jsonc);
      expect(entries, hasLength(1));
      final e = entries.single;
      expect(e.name, 'dev');
      expect(e.program, 'lib/main_dev.dart');
      expect(e.flutterMode, 'debug');
      expect(e.flavor, 'dev');
      expect(e.args, ['--foo']);
      expect(e.toolArgs, ['--web-renderer=canvaskit']);
    });

    test('tolerates // comments, /* */ comments, and trailing commas', () {
      const jsonc = r'''
// top
{
  "version": "0.2.0",
  /* block
     comment */
  "configurations": [
    {
      "name": "prod",
      "type": "dart",
      "program": "lib/main_prod.dart", // trailing line comment
    },
  ],
}
''';
      final entries = LaunchConfigParser.parse(jsonc);
      expect(entries, hasLength(1));
      expect(entries.single.program, 'lib/main_prod.dart');
    });

    test('returns empty on malformed json', () {
      final entries = LaunchConfigParser.parse('{ this is not json }');
      expect(entries, isEmpty);
    });

    test('returns empty when configurations is missing', () {
      final entries = LaunchConfigParser.parse('{}');
      expect(entries, isEmpty);
    });

    test('captures cwd and deviceId, substitutes \$workspaceFolder', () {
      const jsonc = r'''
{
  "configurations": [
    {
      "name": "Vio Client (macOS)",
      "type": "dart",
      "program": "lib/main.dart",
      "cwd": "${workspaceFolder}/apps/client",
      "deviceId": "macos",
      "toolArgs": [
        "--dart-define-from-file=${workspaceFolder}/apps/client/config/dev.json"
      ]
    }
  ]
}
''';
      final entries = LaunchConfigParser.parse(
        jsonc,
        workspaceFolder: '/abs/workspace',
      );
      expect(entries, hasLength(1));
      final e = entries.single;
      expect(e.cwd, '/abs/workspace/apps/client');
      expect(e.deviceId, 'macos');
      expect(
        e.toolArgs.single,
        '--dart-define-from-file=/abs/workspace/apps/client/config/dev.json',
      );
    });

    test('skips non-dart types (e.g. node-terminal)', () {
      const jsonc = r'''
{
  "configurations": [
    {"name": "Vio Client", "type": "dart", "program": "lib/main.dart"},
    {"name": "Capture Perf", "type": "node-terminal", "command": "echo hi"}
  ]
}
''';
      final entries = LaunchConfigParser.parse(jsonc);
      expect(entries, hasLength(1));
      expect(entries.single.name, 'Vio Client');
    });
  });
}
