import 'package:dart_tui/dart_tui.dart';
import 'package:frun/src/data/services/isolate_manager.dart';
import 'package:frun/src/domain/entities/app_config.dart';
import 'package:frun/src/domain/entities/flutter_project.dart';
import 'package:frun/src/domain/value_objects/config_values.dart';
import 'package:frun/src/presentation/app/app_state.dart';
import 'package:frun/src/presentation/app/commands/command_registry.dart';
import 'package:frun/src/presentation/di/dependencies.dart';
import 'package:frun/src/presentation/tui/frun_app.dart';
import 'package:test/test.dart';

void main() {
  group('viewport anchoring while output streams', () {
    test('wheel: scrolled-up viewport holds while streaming', () {
      final h = _harness();
      for (var i = 0; i < 60; i++) {
        h.state.transcript.info('line $i');
      }
      h.model.view();
      h.wheelUp();
      h.wheelUp();
      final before = _body(h.model.view().content);

      for (var burst = 0; burst < 12; burst++) {
        for (var j = 0; j <= burst % 3; j++) {
          h.state.transcript.info('new entry $burst-$j ${'x' * (burst * 9)}');
        }
        final now = _body(h.model.view().content);
        expect(now, before, reason: 'viewport moved after burst $burst');
      }
    });

    test('wheel: scrolled-up viewport holds while the ring trims', () {
      final h = _harness(scrollbackLines: 40);
      for (var i = 0; i < 40; i++) {
        h.state.transcript.info('line $i');
      }
      h.model.view();
      h.wheelUp();
      final before = _body(h.model.view().content);

      for (var i = 0; i < 8; i++) {
        h.state.transcript.info('overflow $i');
        final now = _body(h.model.view().content);
        expect(now, before, reason: 'viewport moved after overflow $i');
      }
    });

    test('arrow-key scroll: viewport holds while streaming', () {
      final h = _harness();
      for (var i = 0; i < 60; i++) {
        h.state.transcript.info('line $i');
      }
      h.model.view();
      h.key(KeyCode.up, shift: true);
      h.key(KeyCode.up, shift: true);
      h.key(KeyCode.up, shift: true);
      final before = _body(h.model.view().content);
      expect(h.model.debugTranscriptScroll, greaterThan(0));

      for (var i = 0; i < 10; i++) {
        h.state.transcript.info('new entry $i');
        final now = _body(h.model.view().content);
        expect(now, before, reason: 'viewport moved after entry $i');
      }
    });

    test('bottom-follow still tracks new output when not reading', () {
      final h = _harness();
      for (var i = 0; i < 30; i++) {
        h.state.transcript.info('line $i');
      }
      h.model.view();
      h.state.transcript.info('line 30');
      h.model.view();
      expect(h.model.debugTranscriptScroll, 0);
    });
  });

  group('transcript-cursor reading mode', () {
    test('scrolled-up viewport holds while streaming', () {
      final h = _harness(editorMode: FrunEditorMode.vim);
      for (var i = 0; i < 60; i++) {
        h.state.transcript.info('line $i');
      }
      h.model.view();
      h.key(KeyCode.escape); // empty input → transcript-cursor mode
      h.model.view();
      h.keyRune('u', ctrl: true);
      h.model.view();
      h.keyRune('u', ctrl: true);
      final before = h.model.view().content;

      for (var i = 0; i < 10; i++) {
        h.state.transcript.info('new entry $i');
        final now = h.model.view().content;
        expect(now, before, reason: 'frame changed after entry $i');
      }
    });

    test('viewport and cursor hold inside the bottom screen', () {
      // The cursor can sit inside the bottom screen with scroll == 0; new
      // output must not slide the text out from under the reader.
      final h = _harness(editorMode: FrunEditorMode.vim);
      for (var i = 0; i < 60; i++) {
        h.state.transcript.info('line $i');
      }
      h.model.view();
      h.key(KeyCode.escape);
      h.model.view();
      h.keyRune('k');
      h.keyRune('k');
      h.keyRune('k');
      final before = h.model.view().content;
      expect(h.model.debugTranscriptScroll, 0);

      for (var i = 0; i < 6; i++) {
        h.state.transcript.info('new entry $i');
        final now = h.model.view().content;
        expect(now, before, reason: 'frame changed after entry $i');
      }
      expect(h.model.debugTranscriptScroll, greaterThan(0));
    });

    test('viewport and cursor hold while the ring trims', () {
      final h = _harness(editorMode: FrunEditorMode.vim, scrollbackLines: 40);
      for (var i = 0; i < 40; i++) {
        h.state.transcript.info('line $i');
      }
      h.model.view();
      h.key(KeyCode.escape);
      h.model.view();
      h.keyRune('k');
      h.keyRune('k');
      h.keyRune('k');
      final before = h.model.view().content;

      // Every append also evicts a line off the top: the cursor's row index
      // shifts but must keep pointing at the same content.
      for (var i = 0; i < 6; i++) {
        h.state.transcript.info('overflow $i');
        final now = h.model.view().content;
        expect(now, before, reason: 'frame changed after overflow $i');
      }
    });

    test('scrolled-up viewport holds while the ring trims', () {
      final h = _harness(editorMode: FrunEditorMode.vim, scrollbackLines: 40);
      for (var i = 0; i < 40; i++) {
        h.state.transcript.info('line $i');
      }
      h.model.view();
      h.key(KeyCode.escape);
      h.model.view();
      h.keyRune('u', ctrl: true);
      h.model.view();
      h.keyRune('u', ctrl: true);
      final before = h.model.view().content;
      expect(h.model.debugTranscriptScroll, greaterThan(0));

      for (var i = 0; i < 6; i++) {
        h.state.transcript.info('overflow $i');
        final now = h.model.view().content;
        expect(now, before, reason: 'frame changed after overflow $i');
      }
    });
  });
}

// Transcript body rows only; the chrome below (info bar, input) may change
// legitimately in non-cursor tests.
String _body(String content) {
  final plain = content.replaceAll(RegExp(r'\x1B\[[0-9;]*m'), '');
  return plain.split('\n').take(14).join('\n');
}

_Harness _harness({
  int width = 80,
  int height = 20,
  int? scrollbackLines,
  FrunEditorMode? editorMode,
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
    config: editorMode == null
        ? AppConfigEntity.defaults()
        : AppConfigEntity.defaults().copyWith(editorMode: editorMode),
    deps: Dependencies(isolateManager: IsolateManager()),
  );
  if (scrollbackLines != null) {
    state.transcript.maxLines = scrollbackLines;
  }
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

  void wheelUp() {
    model.update(
      MouseWheelMsg(const Mouse(x: 0, y: 5, button: MouseButton.wheelUp)),
    );
  }

  void keyRune(String text, {bool ctrl = false}) {
    model.update(
      KeyPressMsg(
        TeaKey(
          code: KeyCode.rune,
          text: text,
          modifiers: ctrl ? const {KeyMod.ctrl} : const <KeyMod>{},
        ),
      ),
    );
  }

  void key(KeyCode code, {bool shift = false}) {
    model.update(
      KeyPressMsg(
        TeaKey(
          code: code,
          modifiers: shift ? const {KeyMod.shift} : const <KeyMod>{},
        ),
      ),
    );
  }
}
