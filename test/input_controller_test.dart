import 'package:dart_tui/dart_tui.dart';
import 'package:frun/src/config/config.dart';
import 'package:frun/src/tui/input_controller.dart';
import 'package:test/test.dart';

KeyMsg _rune(String ch, {Set<KeyMod> mods = const {}}) =>
    KeyPressMsg(TeaKey(code: KeyCode.rune, text: ch, modifiers: mods));

KeyMsg _key(KeyCode code, {Set<KeyMod> mods = const {}}) =>
    KeyPressMsg(TeaKey(code: code, modifiers: mods));

void main() {
  group('InputController normal editor mode', () {
    test('inserts printable characters and submits on Enter', () {
      final c = InputController(editorMode: FrunEditorMode.normal);
      _type(c, 'hi');
      expect(c.text, 'hi');
      final res = c.handle(_key(KeyCode.enter));
      expect(res, InputAction.submit);
    });

    test('backspace deletes character behind cursor', () {
      final c = InputController(editorMode: FrunEditorMode.normal);
      _type(c, 'abc');
      c.handle(_key(KeyCode.backspace));
      expect(c.text, 'ab');
    });

    test('Ctrl-U clears to beginning of line', () {
      final c = InputController(editorMode: FrunEditorMode.normal);
      _type(c, '/run lib/main.dart');
      c.handle(_rune('u', mods: {KeyMod.ctrl}));
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
      c.handle(_key(KeyCode.escape));
      expect(c.mode, VimMode.normal);
      expect(c.cursor, 2);
    });

    test('h/l move the cursor in normal mode', () {
      final c = InputController(editorMode: FrunEditorMode.vim);
      _type(c, 'hello');
      c.handle(_key(KeyCode.escape));
      c.handle(_rune('h'));
      c.handle(_rune('h'));
      expect(c.cursor, 2);
      c.handle(_rune('l'));
      expect(c.cursor, 3);
    });

    test('0 and \$ jump to start/end', () {
      final c = InputController(editorMode: FrunEditorMode.vim);
      _type(c, 'abcdef');
      c.handle(_key(KeyCode.escape));
      c.handle(_rune('0'));
      expect(c.cursor, 0);
      c.handle(_rune(r'$'));
      expect(c.cursor, c.text.length);
    });

    test('dw deletes a word', () {
      final c = InputController(editorMode: FrunEditorMode.vim);
      _type(c, 'foo bar baz');
      c.handle(_key(KeyCode.escape));
      c.handle(_rune('0'));
      c.handle(_rune('d'));
      c.handle(_rune('w'));
      expect(c.text, 'bar baz');
    });

    test('i re-enters insert mode', () {
      final c = InputController(editorMode: FrunEditorMode.vim);
      _type(c, 'foo');
      c.handle(_key(KeyCode.escape));
      c.handle(_rune('i'));
      expect(c.mode, VimMode.insert);
      c.handle(_rune('X'));
      expect(c.text, contains('X'));
    });

    test('x deletes character under cursor', () {
      final c = InputController(editorMode: FrunEditorMode.vim);
      _type(c, 'abc');
      c.handle(_key(KeyCode.escape));
      c.handle(_rune('0'));
      c.handle(_rune('x'));
      expect(c.text, 'bc');
    });
  });
}

void _type(InputController c, String text) {
  for (final ch in text.split('')) {
    c.handle(_rune(ch));
  }
}
