import 'package:dart_tui/dart_tui.dart';
import 'package:frun/src/data/datasources/isolate_manager.dart';
import 'package:frun/src/domain/entities/app_config.dart';
import 'package:frun/src/domain/entities/flutter_project.dart';
import 'package:frun/src/domain/value_objects/config_values.dart';
import 'package:frun/src/presentation/app/app_state.dart';
import 'package:frun/src/presentation/app/commands/command_registry.dart';
import 'package:frun/src/presentation/di/dependencies.dart';
import 'package:frun/src/presentation/tui/frun_app.dart';
import 'package:test/test.dart';

void main() {
  group('Transcript regex search', () {
    test('regex patterns match', () {
      final h = _harness();
      for (var i = 0; i < 30; i++) {
        h.state.transcript.info('line $i');
      }
      h.state.transcript.info('error at 42');
      h.model.view();
      h.key(KeyCode.escape); // transcript-cursor mode
      h.model.view();
      h.search(r'err.r at \d+');
      expect(_lastLine(h), isNot(contains('No matches')));
    });

    test('smartcase: lowercase matches case-insensitively', () {
      final h = _harness();
      h.state.transcript.info('CamelCase token');
      h.model.view();
      h.key(KeyCode.escape);
      h.model.view();
      h.search('camelcase');
      expect(_lastLine(h), isNot(contains('No matches')));
    });

    test('smartcase: uppercase in the pattern is case-sensitive', () {
      final h = _harness();
      h.state.transcript.info('camelcase token');
      h.model.view();
      h.key(KeyCode.escape);
      h.model.view();
      h.search('CAMELCASE');
      expect(_lastLine(h), contains('No matches'));
    });

    test('invalid regex falls back to a literal match', () {
      final h = _harness();
      h.state.transcript.info('call foo( now');
      h.model.view();
      h.key(KeyCode.escape);
      h.model.view();
      h.search('foo(');
      expect(_lastLine(h), isNot(contains('No matches')));
    });
  });

  group('Viewport scrolling (zz/zt/zb, Ctrl-E/Y)', () {
    test('zt, zz, zb order the scroll offsets top-to-bottom', () {
      final h = _harness();
      for (var i = 0; i < 60; i++) {
        h.state.transcript.info('line $i');
      }
      h.model.view();
      h.key(KeyCode.escape);
      h.model.view();
      // Move the cursor into the middle of the buffer so nothing clamps.
      h.keyRune('2');
      h.keyRune('0');
      h.keyRune('k');
      h.model.view();

      h.keyRune('z');
      h.keyRune('t');
      h.model.view();
      final zt = h.model.debugTranscriptScroll;

      h.keyRune('z');
      h.keyRune('z');
      h.model.view();
      final zz = h.model.debugTranscriptScroll;

      h.keyRune('z');
      h.keyRune('b');
      h.model.view();
      final zb = h.model.debugTranscriptScroll;

      expect(zb, greaterThan(zz));
      expect(zz, greaterThan(zt));
    });

    test('Ctrl-E scrolls down one line, Ctrl-Y back up', () {
      final h = _harness();
      for (var i = 0; i < 60; i++) {
        h.state.transcript.info('line $i');
      }
      h.model.view();
      h.key(KeyCode.escape);
      h.model.view();
      // Move mid-buffer first — zz at the bottom clamps the scroll to 0.
      h.keyRune('2');
      h.keyRune('0');
      h.keyRune('k');
      h.keyRune('z');
      h.keyRune('z');
      h.model.view();
      final base = h.model.debugTranscriptScroll;
      expect(base, greaterThan(0));

      h.ctrl('e');
      h.model.view();
      expect(h.model.debugTranscriptScroll, base - 1);

      h.ctrl('y');
      h.model.view();
      expect(h.model.debugTranscriptScroll, base);
    });
  });
}

String _lastLine(_Harness h) => h.state.transcript.lines.last.text;

_Harness _harness({int width = 80, int height = 20}) {
  final state = AppState(
    project: const FlutterProjectEntity(
      root: '.',
      name: 'test',
      workspaceRoot: '.',
      watchRoot: '.',
      hasVsCodeFolder: false,
      hasZedFolder: false,
    ),
    config: AppConfigEntity.defaults().copyWith(
      editorMode: FrunEditorMode.vim,
    ),
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

  void ctrl(String text) {
    model.update(
      KeyPressMsg(
        TeaKey(code: KeyCode.rune, text: text, modifiers: {KeyMod.ctrl}),
      ),
    );
  }

  void search(String pattern) {
    keyRune('/');
    for (final ch in pattern.split('')) {
      keyRune(ch);
    }
    key(KeyCode.enter);
  }
}
