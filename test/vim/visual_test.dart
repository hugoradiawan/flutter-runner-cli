import 'package:dart_tui/dart_tui.dart';
import 'package:frun/src/config/config.dart';
import 'package:frun/src/tui/input_controller.dart';
import 'package:frun/src/tui/vim/ex_parser.dart';
import 'package:frun/src/tui/vim/vim_buffer.dart';
import 'package:frun/src/tui/vim/vim_engine.dart';
import 'package:frun/src/tui/vim/vim_mode.dart';
import 'package:frun/src/tui/vim/vim_state.dart';
import 'package:test/test.dart';

import 'test_support.dart';

VimEngine _engine(VimState s) => VimEngine(
      state: s,
      viewport: (_) => (top: 0, height: 10),
      runExCmd: (_, __) {},
      runSearch: (_, __, ___) {},
    );

void main() {
  group('Visual mode', () {
    test('v then l extends charwise selection', () {
      final b = InputController(editorMode: FrunEditorMode.vim);
      b.setText('hello');
      b.cursor = const Pos(0, 0);
      final s = VimState()..mode = VimMode.normal;
      final e = _engine(s);
      e.handle(rune('v'), b);
      expect(s.mode, VimMode.visualChar);
      e.handle(rune('l'), b);
      e.handle(rune('l'), b);
      final sel = b.selection!.normalized();
      expect(b.textInRange(sel), 'hel');
    });

    test('V selects whole line linewise', () {
      final b = InputController(editorMode: FrunEditorMode.vim);
      b.setText('foo\nbar');
      final s = VimState()..mode = VimMode.normal;
      final e = _engine(s);
      e.handle(rune('V'), b);
      expect(s.mode, VimMode.visualLine);
      expect(b.selection!.kind, RangeKind.linewise);
    });

    test('d in visual deletes selection and returns to normal', () {
      final b = InputController(editorMode: FrunEditorMode.vim);
      b.setText('hello world');
      b.cursor = const Pos(0, 0);
      final s = VimState()..mode = VimMode.normal;
      final e = _engine(s);
      e.handle(rune('v'), b);
      for (var i = 0; i < 4; i++) {
        e.handle(rune('l'), b);
      }
      e.handle(rune('d'), b);
      expect(s.mode, VimMode.normal);
      expect(b.text, ' world');
    });

    test('y in visual yanks to unnamed register', () {
      final b = InputController(editorMode: FrunEditorMode.vim);
      b.setText('alpha beta');
      b.cursor = const Pos(0, 0);
      final s = VimState()..mode = VimMode.normal;
      final e = _engine(s);
      e.handle(rune('v'), b);
      for (var i = 0; i < 4; i++) {
        e.handle(rune('l'), b);
      }
      e.handle(rune('y'), b);
      expect(s.registers.read('"').text, 'alpha');
    });
  });

  group('Operator + motion', () {
    test('dw deletes a word', () {
      final b = InputController(editorMode: FrunEditorMode.vim);
      b.setText('foo bar baz');
      b.cursor = const Pos(0, 0);
      final s = VimState()..mode = VimMode.normal;
      final e = _engine(s);
      e.handle(rune('d'), b);
      e.handle(rune('w'), b);
      expect(b.text, 'bar baz');
    });

    test('diw deletes inner word', () {
      final b = InputController(editorMode: FrunEditorMode.vim);
      b.setText('foo bar baz');
      b.cursor = const Pos(0, 5);
      final s = VimState()..mode = VimMode.normal;
      final e = _engine(s);
      e.handle(rune('d'), b);
      e.handle(rune('i'), b);
      e.handle(rune('w'), b);
      expect(b.text, 'foo  baz');
    });

    test('counts: 3dw deletes 3 words', () {
      final b = InputController(editorMode: FrunEditorMode.vim);
      b.setText('a b c d e');
      b.cursor = const Pos(0, 0);
      final s = VimState()..mode = VimMode.normal;
      final e = _engine(s);
      e.handle(rune('3'), b);
      e.handle(rune('d'), b);
      e.handle(rune('w'), b);
      expect(b.text, 'd e');
    });
  });

  group('Insert mode entry', () {
    test('i then typing inserts text', () {
      final b = InputController(editorMode: FrunEditorMode.vim);
      b.setText('xy');
      final s = VimState()..mode = VimMode.normal;
      final e = _engine(s);
      final res = e.handle(rune('i'), b);
      expect(res, KeyResult.consumed);
      expect(s.mode, VimMode.insert);
      final res2 = e.handle(rune('Z'), b);
      expect(res2, KeyResult.passInsert);
    });
  });

  group('Ex parser integration', () {
    test('engine collects exDraft and emits ExCommand', () {
      final b = InputController(editorMode: FrunEditorMode.vim);
      b.setText('hello');
      final s = VimState()..mode = VimMode.normal;
      ExCommand? captured;
      final e = VimEngine(
        state: s,
        viewport: (_) => (top: 0, height: 10),
        runExCmd: (c, _) => captured = c,
        runSearch: (_, __, ___) {},
      );
      e.handle(rune(':'), b);
      for (final ch in 'q'.split('')) {
        e.handle(rune(ch), b);
      }
      e.handle(key(KeyCode.enter), b);
      expect(captured!.name, 'q');
    });
  });
}
