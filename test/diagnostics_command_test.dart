import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:frun/src/data/datasources/dart_analyze_runner.dart';
import 'package:frun/src/data/datasources/diagnostics_store.dart';
import 'package:frun/src/data/repositories/diagnostics_repository_impl.dart';
import 'package:frun/src/domain/entities/app_config.dart';
import 'package:frun/src/domain/entities/diagnostic.dart';
import 'package:frun/src/domain/entities/flutter_project.dart';
import 'package:frun/src/presentation/app/app_state.dart';
import 'package:frun/src/presentation/app/commands/diagnostics_command.dart';
import 'package:frun/src/presentation/app/transcript.dart';
import 'package:frun/src/presentation/di/dependencies.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temp;
  late AppState state;

  AppState buildState(String projectRoot) => AppState(
    project: FlutterProjectEntity(
      root: projectRoot,
      name: 'demo',
      workspaceRoot: temp.path,
      watchRoot: temp.path,
      hasVsCodeFolder: false,
      hasZedFolder: false,
    ),
    config: AppConfigEntity.defaults(),
    deps: Dependencies(),
  );

  void wireRepo(
    AppState state, {
    required AnalyzeProcessRunner runAnalyze,
    Duration timeout = const Duration(seconds: 20),
  }) {
    state.deps.diagnosticsRepository = DiagnosticsRepositoryImpl(
      DiagnosticsStore(projectRoot: state.project.root),
      projectRoot: state.project.root,
      analyzeRunner: DartAnalyzeRunner(
        runProcess: runAnalyze,
        dartExecutable: 'dart',
        timeout: timeout,
      ),
    );
  }

  setUp(() {
    temp = Directory.systemTemp.createTempSync('frun_diag_cmd_');
    state = buildState(temp.path);
  });

  tearDown(() => temp.deleteSync(recursive: true));

  test('runs dart analyze once and opens the diagnostics panel', () async {
    var calls = 0;
    wireRepo(
      state,
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

    await DiagnosticsCommand().run(const [], state);
    expect(calls, 1);
    expect(state.showDiagnosticsPanel, isTrue);
    expect(state.diagnosticsRevision, 2);
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
    wireRepo(
      state,
      runAnalyze: (_, _, _, _) async =>
          ProcessResult(123, 0, '{"version":1,"diagnostics":[]}', ''),
    );
    await DiagnosticsCommand().run(['error'], state);
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
    final hidden = Directory(p.join(temp.path, '.dart_tool', 'generated'))
      ..createSync(recursive: true);
    File(
      p.join(hidden.path, 'generated.dart'),
    ).writeAsStringSync('// TODO: ignored generated file');

    wireRepo(
      state,
      runAnalyze: (_, _, _, _) async =>
          ProcessResult(123, 0, '{"version":1,"diagnostics":[]}', ''),
    );

    await DiagnosticsCommand().run(['todo'], state);
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
    expect(
      state.diagnostics.any(
        (d) => d.filePath.contains('${p.separator}.dart_tool'),
      ),
      isFalse,
    );
  });

  test('todo filter scans active project root instead of watch root', () async {
    final appRoot = p.join(temp.path, 'apps', 'demo');
    final appLib = Directory(p.join(appRoot, 'lib'))
      ..createSync(recursive: true);
    File(p.join(appLib.path, 'main.dart')).writeAsStringSync('// TODO: app');

    final siblingLib = Directory(p.join(temp.path, 'packages', 'shared', 'lib'))
      ..createSync(recursive: true);
    File(
      p.join(siblingLib.path, 'shared.dart'),
    ).writeAsStringSync('// TODO: sibling');

    state = buildState(appRoot);
    wireRepo(
      state,
      runAnalyze: (_, _, _, _) async =>
          ProcessResult(123, 0, '{"version":1,"diagnostics":[]}', ''),
    );

    await DiagnosticsCommand().run(['todo'], state);

    expect(state.diagnostics, hasLength(1));
    expect(state.diagnostics.single.code, 'todo');
    expect(state.diagnostics.single.filePath, p.join(appLib.path, 'main.dart'));
  });

  test('unknown arg warns and does not run analyzer', () async {
    var calls = 0;
    wireRepo(
      state,
      runAnalyze: (_, _, _, _) async {
        calls++;
        return ProcessResult(123, 0, '{}', '');
      },
    );
    await DiagnosticsCommand().run(['bogus'], state);
    expect(calls, 0);
    expect(
      state.transcript.lines.where((l) => l.level == TranscriptLevel.warn),
      isNotEmpty,
    );
  });

  test('parse failure warns and leaves the panel open', () async {
    wireRepo(
      state,
      runAnalyze: (_, _, _, _) async =>
          ProcessResult(123, 64, 'not json', 'bad args'),
    );
    await DiagnosticsCommand().run(const [], state);
    expect(state.showDiagnosticsPanel, isTrue);
    expect(state.diagnostics, isEmpty);
    expect(
      state.transcript.lines.where((l) => l.level == TranscriptLevel.warn),
      isNotEmpty,
    );
  });

  test('analyze timeout leaves current diagnostics visible', () async {
    wireRepo(
      state,
      timeout: const Duration(milliseconds: 1),
      runAnalyze: (_, _, _, _) => Completer<ProcessResult>().future,
    );

    await DiagnosticsCommand().run(const [], state);
    expect(state.showDiagnosticsPanel, isTrue);
    expect(
      state.transcript.lines.where(
        (l) => l.level == TranscriptLevel.warn && l.text.contains('timed out'),
      ),
      isNotEmpty,
    );
  });
}
