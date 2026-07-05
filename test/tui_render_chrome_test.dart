import 'package:dart_tui/dart_tui.dart';
import 'package:frun/src/data/models/launch_config.dart';
import 'package:frun/src/data/services/isolate_manager.dart';
import 'package:frun/src/data/services/project_detector.dart';
import 'package:frun/src/domain/entities/app_config.dart';
import 'package:frun/src/domain/entities/diagnostic.dart';
import 'package:frun/src/domain/value_objects/config_values.dart';
import 'package:frun/src/presentation/app/app_state.dart';
import 'package:frun/src/presentation/app/commands/command_registry.dart';
import 'package:frun/src/presentation/app/run_tab.dart';
import 'package:frun/src/presentation/di/dependencies.dart';
import 'package:frun/src/presentation/tui/frun_app.dart';
import 'package:test/test.dart';

void main() {
  test('diagnostics drawer keeps dense chrome inside terminal width', () {
    final h = _harness(width: 60, height: 18);
    h.state
      ..diagnostics = const <DiagnosticEntity>[
        DiagnosticEntity(
          filePath: 'lib/main.dart',
          line: 12,
          column: 8,
          severity: DiagnosticSeverity.error,
          message: 'Undefined name',
          code: 'undefined_identifier',
        ),
        DiagnosticEntity(
          filePath: 'lib/app/view.dart',
          line: 3,
          column: 1,
          severity: DiagnosticSeverity.warning,
          message: 'Unused import',
          code: 'unused_import',
        ),
      ]
      ..showDiagnosticsPanel = true;

    final plain = _plain(h.model.view().content);

    _expectBoundedRows(plain, 60);
    expect(plain, contains('Problems'));
    expect(plain, contains('all'));
    expect(plain, contains(' x '));
    expect(plain, contains('Undefined name'));
    expect(plain, contains('╭'));
  });

  test('isolates drawer aligns status text and action badges', () {
    final h = _harness(
      width: 82,
      height: 18,
      isolateManager: IsolateManager(
        isolates: <IsolateInfo>[
          IsolateInfo(
            id: 'isolates/1234567890abcdef',
            name: 'main',
            status: IsolateStatus.running,
          ),
        ],
      ),
    );
    h.state.showIsolatesPanel = true;

    final plain = _plain(h.model.view().content);

    _expectBoundedRows(plain, 82);
    expect(plain, contains('Isolates'));
    expect(plain, contains('main'));
    expect(plain, contains('pause'));
    expect(plain, contains('kill'));
    expect(plain, contains(' x '));
  });

  test('tab strip truncates long labels without row overflow', () {
    final h = _harness(width: 54, height: 14);
    h.state.runController.tabs.addAll(<RunTab>[
      _tab(1, 'very-long-debug-profile-alpha'),
      _tab(2, 'checkout-flow-with-long-device-name'),
      _tab(3, 'settings-with-extra-flavor-name'),
      _tab(4, 'admin-panel-release-candidate'),
    ]);
    h.state.runController.setActiveIndex(0);

    final plain = _plain(h.model.view().content);

    _expectBoundedRows(plain, 54);
    expect(plain, contains('1  very-long-debug-profile-alpha'));
    expect(plain, contains('off'));
  });

  test('light theme keeps command surface bounded', () {
    final h = _harness(
      width: 50,
      height: 12,
      config: AppConfigEntity.defaults().copyWith(theme: FrunThemeMode.light),
    );

    final plain = _plain(h.model.view().content);

    _expectBoundedRows(plain, 50);
    expect(plain, contains('╭'));
    expect(plain, contains('╰'));
    expect(plain, contains('>'));
  });
}

RunTab _tab(int id, String name) {
  return RunTab(
    id: id,
    entry: LaunchEntry(name: name, program: 'lib/$name.dart'),
    deviceId: 'pixel-8-pro-very-long-id',
  );
}

_Harness _harness({
  required int width,
  required int height,
  AppConfigEntity? config,
  IsolateManager? isolateManager,
}) {
  final state = AppState(
    project: FlutterProject(
      root: '.',
      name: 'test',
      workspaceRoot: '.',
      watchRoot: '.',
      hasVsCodeFolder: false,
      hasZedFolder: false,
    ),
    config: config ?? AppConfigEntity.defaults(),
    deps: Dependencies(isolateManager: isolateManager ?? IsolateManager()),
  );
  final model = FrunModel(
    state: state,
    registry: CommandRegistry(),
    onQuit: () {},
  );
  model.update(WindowSizeMsg(width, height));
  return _Harness(state, model);
}

String _plain(String content) {
  return content.replaceAll(RegExp(r'\x1B\[[0-9;]*m'), '');
}

void _expectBoundedRows(String content, int width) {
  for (final line in content.split('\n')) {
    expect(line.length, lessThanOrEqualTo(width), reason: line);
  }
}

final class _Harness {
  _Harness(this.state, this.model);

  final AppState state;
  final FrunModel model;
}
