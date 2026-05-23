import 'package:frun/src/config/config.dart';
import 'package:frun/src/tui/input_controller.dart';
import 'package:test/test.dart';
import 'package:utopia_tui/utopia_tui.dart';

void main() {
  group('InputController normal editor mode', () {
    test('inserts printable characters and submits on Enter', () {
      final c = InputController(editorMode: FrunEditorMode.normal);
      _type(c, 'hi');
      expect(c.text, 'hi');
      final res = c.handle(const TuiKeyEvent(code: TuiKeyCode.enter));
      expect(res, InputAction.submit);
    });

    test('backspace deletes character behind cursor', () {
      final c = InputController(editorMode: FrunEditorMode.normal);
      _type(c, 'abc');
      c.handle(const TuiKeyEvent(code: TuiKeyCode.backspace));
      expect(c.text, 'ab');
    });

    test('Ctrl-U clears to beginning of line', () {
      final c = InputController(editorMode: FrunEditorMode.normal);
      _type(c, '/run lib/main.dart');
      c.handle(const TuiKeyEvent(code: TuiKeyCode.ctrlU));
      expect(c.text, '');
    });
  });

  group('InputController vim editor mode', () {
    test('starts in insert mode', () {
      final c = InputController(editorMode: FrunEditorMode.vim);
      expect(c.mode, VimMode.insert);
    });

    test('Escape switches to normal mode and steps cursor back', () {
      final c = InputController(editorMode: FrunEditorMode.vim);
      _type(c, 'foo');
      c.handle(const TuiKeyEvent(code: TuiKeyCode.escape));
      expect(c.mode, VimMode.normal);
      expect(c.cursor, 2);
    });

    test('h/l move the cursor in normal mode', () {
      final c = InputController(editorMode: FrunEditorMode.vim);
      _type(c, 'hello');
      c.handle(const TuiKeyEvent(code: TuiKeyCode.escape));
      c.handle(const TuiKeyEvent(code: TuiKeyCode.printable, char: 'h'));
      c.handle(const TuiKeyEvent(code: TuiKeyCode.printable, char: 'h'));
      expect(c.cursor, 2);
      c.handle(const TuiKeyEvent(code: TuiKeyCode.printable, char: 'l'));
      expect(c.cursor, 3);
    });

    test('0 and \$ jump to start/end', () {
      final c = InputController(editorMode: FrunEditorMode.vim);
      _type(c, 'abcdef');
      c.handle(const TuiKeyEvent(code: TuiKeyCode.escape));
      c.handle(const TuiKeyEvent(code: TuiKeyCode.printable, char: '0'));
      expect(c.cursor, 0);
      c.handle(const TuiKeyEvent(code: TuiKeyCode.printable, char: r'$'));
      expect(c.cursor, c.text.length);
    });

    test('dw deletes a word', () {
      final c = InputController(editorMode: FrunEditorMode.vim);
      _type(c, 'foo bar baz');
      c.handle(const TuiKeyEvent(code: TuiKeyCode.escape));
      c.handle(const TuiKeyEvent(code: TuiKeyCode.printable, char: '0'));
      c.handle(const TuiKeyEvent(code: TuiKeyCode.printable, char: 'd'));
      c.handle(const TuiKeyEvent(code: TuiKeyCode.printable, char: 'w'));
      expect(c.text, 'bar baz');
    });

    test('i re-enters insert mode', () {
      final c = InputController(editorMode: FrunEditorMode.vim);
      _type(c, 'foo');
      c.handle(const TuiKeyEvent(code: TuiKeyCode.escape));
      c.handle(const TuiKeyEvent(code: TuiKeyCode.printable, char: 'i'));
      expect(c.mode, VimMode.insert);
      c.handle(const TuiKeyEvent(code: TuiKeyCode.printable, char: 'X'));
      expect(c.text, contains('X'));
    });

    test('x deletes character under cursor', () {
      final c = InputController(editorMode: FrunEditorMode.vim);
      _type(c, 'abc');
      c.handle(const TuiKeyEvent(code: TuiKeyCode.escape));
      c.handle(const TuiKeyEvent(code: TuiKeyCode.printable, char: '0'));
      c.handle(const TuiKeyEvent(code: TuiKeyCode.printable, char: 'x'));
      expect(c.text, 'bc');
    });
  });
}

void _type(InputController c, String text) {
  for (final ch in text.split('')) {
    c.handle(TuiKeyEvent(code: TuiKeyCode.printable, char: ch));
  }
}
