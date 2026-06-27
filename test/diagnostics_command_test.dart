import 'dart:convert';
import 'dart:io';

import 'package:frun/src/data/services/project_detector.dart';
import 'package:frun/src/domain/entities/app_config.dart';
import 'package:frun/src/domain/entities/diagnostic.dart';
import 'package:frun/src/presentation/app/app_state.dart';
import 'package:frun/src/presentation/app/commands/diagnostics_command.dart';
import 'package:frun/src/presentation/app/transcript.dart';
import 'package:frun/src/presentation/di/dependencies.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temp;
  late AppState state;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('frun_diag_cmd_');
    state = AppState(
      project: FlutterProject(
        root: temp.path,
        name: 'demo',
        workspaceRoot: temp.path,
        watchRoot: temp.path,
        hasVsCodeFolder: false,
        hasZedFolder: false,
      ),
      config: AppConfigEntity.defaults(),
      deps: Dependencies(),
    );
  });

  tearDown(() => temp.deleteSync(recursive: true));

  test('runs dart analyze once and opens the diagnostics panel', () async {
    var calls = 0;
    final cmd = DiagnosticsCommand(
      dartExecutable: 'dart',
      runAnalyze: (executable, arguments, workingDirectory, runInShell) async {
        calls++;
        expect(executable, 'dart');
        expect(arguments, ['analyze', '--format=json', '--no-fatal-warnings']);
        expect(workingDirectory, temp.path);
        return ProcessResult(
          123,
          1,
          json.encode({
            'version': 1,
            'diagnostics': [
              {
                'code': 'unused_import',
                'severity': 'WARNING',
                'problemMessage': 'Unused import.',
                'location': {
                  'file': 'lib/main.dart',
                  'range': {
                    'start': {'line': 3, 'column': 1},
                  },
                },
              },
            ],
          }),
          '',
        );
      },
    );

    await cmd.run(const [], state);
    expect(calls, 1);
    expect(state.showDiagnosticsPanel, isTrue);
    expect(state.diagnosticsFilter, isNull);
    expect(state.diagnosticsSearch, isEmpty);
    expect(state.diagnostics, hasLength(1));
    expect(state.diagnostics.single.severity, DiagnosticSeverity.warning);
    expect(state.diagnostics.single.code, 'unused_import');
    expect(
      state.diagnostics.single.filePath,
      p.normalize(p.join(temp.path, 'lib/main.dart')),
    );
  });

  test('severity arg sets the filter after analysis', () async {
    final cmd = DiagnosticsCommand(
      dartExecutable: 'dart',
      runAnalyze: (_, _, _, _) async =>
          ProcessResult(123, 0, '{"version":1,"diagnostics":[]}', ''),
    );
    await cmd.run(['error'], state);
    expect(state.showDiagnosticsPanel, isTrue);
    expect(state.diagnosticsFilter, DiagnosticCategory.error);
  });

  test('todo filter includes scanned review markers', () async {
    final lib = Directory(p.join(temp.path, 'lib'))..createSync();
    File(p.join(lib.path, 'main.dart')).writeAsStringSync('''
void main() {
  // TODO: wire this up
  print('ok'); // FIXME handle failures
}
''');
    Directory(p.join(temp.path, 'build')).createSync();
    File(
      p.join(temp.path, 'build', 'generated.dart'),
    ).writeAsStringSync('// TODO: ignored generated file');

    final cmd = DiagnosticsCommand(
      dartExecutable: 'dart',
      runAnalyze: (_, _, _, _) async =>
          ProcessResult(123, 0, '{"version":1,"diagnostics":[]}', ''),
    );

    await cmd.run(['todo'], state);
    expect(state.showDiagnosticsPanel, isTrue);
    expect(state.diagnosticsFilter, DiagnosticCategory.todo);
    expect(state.diagnostics, hasLength(2));
    expect(
      state.diagnostics.every((d) => d.category == DiagnosticCategory.todo),
      isTrue,
    );
    expect(
      state.diagnostics.map((d) => d.code),
      containsAll(['todo', 'fixme']),
    );
    expect(
      state.diagnostics.any((d) => d.filePath.contains('${p.separator}build')),
      isFalse,
    );
  });

  test('unknown arg warns and does not run analyzer', () async {
    var calls = 0;
    final cmd = DiagnosticsCommand(
      dartExecutable: 'dart',
      runAnalyze: (_, _, _, _) async {
        calls++;
        return ProcessResult(123, 0, '{}', '');
      },
    );
    await cmd.run(['bogus'], state);
    expect(calls, 0);
    expect(
      state.transcript.lines.where((l) => l.level == TranscriptLevel.warn),
      isNotEmpty,
    );
  });

  test('parse failure warns and leaves the panel closed', () async {
    final cmd = DiagnosticsCommand(
      dartExecutable: 'dart',
      runAnalyze: (_, _, _, _) async =>
          ProcessResult(123, 64, 'not json', 'bad args'),
    );
    await cmd.run(const [], state);
    expect(state.showDiagnosticsPanel, isFalse);
    expect(state.diagnostics, isEmpty);
    expect(
      state.transcript.lines.where((l) => l.level == TranscriptLevel.warn),
      isNotEmpty,
    );
  });
}
