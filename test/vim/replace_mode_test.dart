import 'package:dart_tui/dart_tui.dart';
import 'package:frun/src/domain/value_objects/config_values.dart';
import 'package:frun/src/presentation/tui/input_controller.dart';
import 'package:frun/src/presentation/tui/vim/vim_buffer.dart';
import 'package:frun/src/presentation/tui/vim/vim_engine.dart';
import 'package:frun/src/presentation/tui/vim/vim_mode.dart';
import 'package:frun/src/presentation/tui/vim/vim_state.dart';
import 'package:test/test.dart';

import 'test_support.dart';

InputController _buf(String text, {Pos cursor = const Pos(0, 0)}) {
  final c = InputController(editorMode: FrunEditorMode.vim);
  c.setText(text);
  c.cursor = cursor;
  return c;
}

VimEngine _engine(VimState s) => VimEngine(
  state: s,
  viewport: (_) => (top: 0, height: 10),
  runExCmd: (_, _) {},
  runSearch: (_, _, _) {},
);

void main() {
  group('Replace mode (R)', () {
    test('typed chars overwrite and advance', () {
      final b = _buf('hello');
      final s = VimState()..mode = VimMode.normal;
      final e = _engine(s);
      feed(e, b, 'Rab');
      e.handle(esc(), b);
      expect(b.text, 'abllo');
      expect(b.cursor, const Pos(0, 1));
      expect(s.mode, VimMode.normal);
    });

    test('overwriting past EOL appends', () {
      final b = _buf('ab');
      final s = VimState()..mode = VimMode.normal;
      final e = _engine(s);
      feed(e, b, 'Rxyz');
      e.handle(esc(), b);
      expect(b.text, 'xyz');
    });

    test('backspace restores overwritten chars', () {
      final b = _buf('hello');
      final s = VimState()..mode = VimMode.normal;
      final e = _engine(s);
      feed(e, b, 'Rab');
      e.handle(key(KeyCode.backspace), b);
      e.handle(key(KeyCode.backspace), b);
      expect(b.text, 'hello');
      expect(b.cursor, const Pos(0, 0));
      e.handle(esc(), b);
      expect(b.text, 'hello');
    });

    test('backspace deletes chars that were appended past EOL', () {
      final b = _buf('a');
      final s = VimState()..mode = VimMode.normal;
      final e = _engine(s);
      feed(e, b, 'Rxy');
      expect(b.text, 'xy');
      e.handle(key(KeyCode.backspace), b);
      expect(b.text, 'x');
      e.handle(key(KeyCode.backspace), b);
      expect(b.text, 'a');
    });

    test('{count}R repeats the overwrite on Esc', () {
      final b = _buf('abcdef');
      final s = VimState()..mode = VimMode.normal;
      final e = _engine(s);
      feed(e, b, '3Rx');
      e.handle(esc(), b);
      expect(b.text, 'xxxdef');
    });

    test('. repeats an R session at the cursor', () {
      final b = _buf('hello world');
      final s = VimState()..mode = VimMode.normal;
      final e = _engine(s);
      feed(e, b, 'Rab');
      e.handle(esc(), b);
      expect(b.text, 'abllo world');
      feed(e, b, 'w.');
      expect(b.text, 'abllo abrld');
    });

    test('u undoes the whole R session', () {
      final b = _buf('hello');
      final s = VimState()..mode = VimMode.normal;
      final e = _engine(s);
      feed(e, b, 'Rabc');
      e.handle(esc(), b);
      expect(b.text, 'abclo');
      feed(e, b, 'u');
      expect(b.text, 'hello');
    });
  });
}
