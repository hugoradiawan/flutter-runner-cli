import 'package:dart_tui/dart_tui.dart';
import 'package:frun/src/data/datasources/isolate_manager.dart';
import 'package:frun/src/domain/entities/app_config.dart';
import 'package:frun/src/domain/entities/diagnostic.dart';
import 'package:frun/src/domain/entities/flutter_project.dart';
import 'package:frun/src/domain/value_objects/config_values.dart';
import 'package:frun/src/presentation/app/app_state.dart';
import 'package:frun/src/presentation/app/commands/command_registry.dart';
import 'package:frun/src/presentation/di/dependencies.dart';
import 'package:frun/src/presentation/tui/frun_app.dart';
import 'package:test/test.dart';

void main() {
  group('Vim mode chip', () {
    test('shows INSERT and flips to NORMAL on the very next frame', () {
      final h = _harness();
      h.type('x');
      expect(_plain(h.model.view().content), contains(' INSERT '));
      h.key(KeyCode.escape);
      // The next frame must repaint (mode is in the view signature) — a
      // stale INSERT chip here means the frame-skip gate lost the slot.
      expect(_plain(h.model.view().content), contains(' NORMAL '));
      h.keyRune('i');
      expect(_plain(h.model.view().content), contains(' INSERT '));
    });

    test('shows the recording flag while q is active', () {
      final h = _harness();
      h.type('x');
      h.key(KeyCode.escape);
      h.keyRune('q');
      h.keyRune('a');
      expect(_plain(h.model.view().content), contains('rec @a'));
      h.keyRune('q');
      expect(_plain(h.model.view().content), isNot(contains('rec @a')));
    });

    test('shows the pending showcmd (2d) and clears after the motion', () {
      final h = _harness();
      h.type('a b c');
      h.key(KeyCode.escape);
      h.keyRune('0');
      h.keyRune('2');
      h.keyRune('d');
      expect(_plain(h.model.view().content), contains('2d'));
      h.keyRune('w');
      expect(_plain(h.model.view().content), isNot(contains('2d')));
    });

    test('no chip outside vim editor mode', () {
      final h = _harness(editorMode: FrunEditorMode.normal);
      h.type('x');
      expect(_plain(h.model.view().content), isNot(contains(' INSERT ')));
    });
  });

  group('Diagnostics overlay vim nav', () {
    test('5j moves five issues; gg and G jump to the edges', () {
      final h = _harness();
      h.state.diagnostics = [
        for (var i = 0; i < 8; i++)
          DiagnosticEntity(
            filePath: 'lib/a.dart',
            line: i + 1,
            column: 1,
            severity: DiagnosticSeverity.error,
            message: 'broken $i',
          ),
      ];
      h.model.update(const ToggleDiagnosticsOverlayMsg());
      h.model.view();
      // Rows: [file header, issue×8] — issues at indexes 1..8. The initial
      // selection clamps onto the first issue (1), then moves five.
      h.keyRune('5');
      h.keyRune('j');
      expect(h.model.debugDiagSelectedIndex, 6);
      h.keyRune('G');
      expect(h.model.debugDiagSelectedIndex, 8);
      h.keyRune('g');
      h.keyRune('g');
      expect(h.model.debugDiagSelectedIndex, 1);
    });

    test('q closes the diagnostics panel', () {
      final h = _harness();
      h.state.diagnostics = const [
        DiagnosticEntity(
          filePath: 'lib/a.dart',
          line: 1,
          column: 1,
          severity: DiagnosticSeverity.error,
          message: 'broken',
        ),
      ];
      h.model.update(const ToggleDiagnosticsOverlayMsg());
      expect(h.state.showDiagnosticsPanel, isTrue);
      h.keyRune('q');
      expect(h.state.showDiagnosticsPanel, isFalse);
    });
  });
}

String _plain(String text) => text.replaceAll(RegExp(r'\x1B\[[0-9;]*m'), '');

_Harness _harness({
  int width = 100,
  int height = 20,
  FrunEditorMode editorMode = FrunEditorMode.vim,
}) {
  final state = AppState(
    project: const FlutterProjectEntity(
      root: '.',
      name: 'test',
      workspaceRoot: '.',
      watchRoot: '.',
      hasVsCodeFolder: false,
      hasZedFolder: false,
    ),
    config: AppConfigEntity.defaults().copyWith(editorMode: editorMode),
    deps: Dependencies(isolateManager: IsolateManager()),
  );
  final model = FrunModel(
    state: state,
    registry: CommandRegistry(),
    onQuit: () {},
  );
  model.update(WindowSizeMsg(width, height));
  return _Harness(state, model);
}

final class _Harness {
  _Harness(this.state, this.model);

  final AppState state;
  final FrunModel model;

  void keyRune(String text) {
    model.update(KeyPressMsg(TeaKey(code: KeyCode.rune, text: text)));
  }

  void key(KeyCode code) {
    model.update(KeyPressMsg(TeaKey(code: code)));
  }

  void type(String text) {
    for (final ch in text.split('')) {
      keyRune(ch);
    }
  }
}
