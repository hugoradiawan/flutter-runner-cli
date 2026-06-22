import 'package:dart_tui/dart_tui.dart';
import 'package:frun/src/domain/value_objects/config_values.dart';
import 'package:frun/src/tui/input_controller.dart';
import 'package:frun/src/tui/vim/vim_engine.dart';
import 'package:frun/src/tui/vim/vim_mode.dart';
import 'package:frun/src/tui/vim/vim_state.dart';
import 'package:test/test.dart';

import 'test_support.dart';

void main() {
  group('Search prompt', () {
    test('/ captures draft until Enter, then fires runSearch', () {
      final b = InputController(editorMode: FrunEditorMode.vim);
      b.setText('alpha beta');
      final s = VimState()..mode = VimMode.normal;
      String? pat;
      bool? fwd;
      final e = VimEngine(
        state: s,
        viewport: (_) => (top: 0, height: 10),
        runExCmd: (_, __) {},
        runSearch: (p, f, _) {
          pat = p;
          fwd = f;
        },
      );
      e.handle(rune('/'), b);
      expect(s.mode, VimMode.search);
      for (final ch in 'bet'.split('')) {
        e.handle(rune(ch), b);
      }
      e.handle(key(KeyCode.enter), b);
      expect(pat, 'bet');
      expect(fwd, isTrue);
      expect(s.mode, VimMode.normal);
    });

    test('? goes backward', () {
      final b = InputController(editorMode: FrunEditorMode.vim);
      b.setText('alpha');
      final s = VimState()..mode = VimMode.normal;
      bool? fwd;
      final e = VimEngine(
        state: s,
        viewport: (_) => (top: 0, height: 10),
        runExCmd: (_, __) {},
        runSearch: (_, f, __) {
          fwd = f;
        },
      );
      e.handle(rune('?'), b);
      for (final ch in 'x'.split('')) {
        e.handle(rune(ch), b);
      }
      e.handle(key(KeyCode.enter), b);
      expect(fwd, isFalse);
    });

    test('Esc cancels search without firing', () {
      final b = InputController(editorMode: FrunEditorMode.vim);
      b.setText('a');
      final s = VimState()..mode = VimMode.normal;
      var fired = false;
      final e = VimEngine(
        state: s,
        viewport: (_) => (top: 0, height: 10),
        runExCmd: (_, __) {},
        runSearch: (_, __, ___) {
          fired = true;
        },
      );
      e.handle(rune('/'), b);
      e.handle(rune('x'), b);
      e.handle(key(KeyCode.escape), b);
      expect(fired, isFalse);
      expect(s.mode, VimMode.normal);
    });
  });
}

