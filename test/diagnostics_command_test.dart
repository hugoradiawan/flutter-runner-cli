import 'dart:io';

import 'package:frun/src/data/services/project_detector.dart';
import 'package:frun/src/domain/entities/app_config.dart';
import 'package:frun/src/domain/entities/diagnostic.dart';
import 'package:frun/src/presentation/app/app_state.dart';
import 'package:frun/src/presentation/app/commands/diagnostics_command.dart';
import 'package:frun/src/presentation/app/transcript.dart';
import 'package:frun/src/presentation/di/dependencies.dart';
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

  test('toggles the diagnostics panel', () async {
    final cmd = DiagnosticsCommand();
    expect(state.showDiagnosticsPanel, isFalse);
    await cmd.run(const [], state);
    expect(state.showDiagnosticsPanel, isTrue);
    await cmd.run(const [], state);
    expect(state.showDiagnosticsPanel, isFalse);
  });

  test('severity arg sets the filter and forces the panel open', () async {
    final cmd = DiagnosticsCommand();
    await cmd.run(['error'], state);
    expect(state.showDiagnosticsPanel, isTrue);
    expect(state.diagnosticsFilter, DiagnosticCategory.error);

    await cmd.run(['todo'], state);
    expect(state.diagnosticsFilter, DiagnosticCategory.todo);

    await cmd.run(['all'], state);
    expect(state.diagnosticsFilter, isNull);
    expect(state.showDiagnosticsPanel, isTrue);
  });

  test('unknown arg warns and leaves the panel state unchanged', () async {
    final cmd = DiagnosticsCommand();
    await cmd.run(['bogus'], state);
    expect(state.showDiagnosticsPanel, isFalse);
    expect(
      state.transcript.lines.where((l) => l.level == TranscriptLevel.warn),
      isNotEmpty,
    );
  });
}
