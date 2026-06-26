import 'package:dart_tui/dart_tui.dart';
import 'package:frun/src/domain/value_objects/config_values.dart';
import 'package:frun/src/presentation/tui/input_controller.dart';
import 'package:frun/src/presentation/tui/vim/vim_buffer.dart';
import 'package:test/test.dart';

import 'vim/test_support.dart';

void main() {
  group('InputController insert handling', () {
    test('inserts printable characters and submits Enter on single line', () {
      final c = InputController(editorMode: FrunEditorMode.normal);
      type(c, 'hi');
      expect(c.text, 'hi');
      final res = c.insertKey(key(KeyCode.enter));
      expect(res, InputAction.submit);
    });

    test('backspace deletes character behind cursor', () {
      final c = InputController(editorMode: FrunEditorMode.normal);
      type(c, 'abc');
      c.insertKey(key(KeyCode.backspace));
      expect(c.text, 'ab');
    });

    test('Ctrl-U clears to beginning of line', () {
      final c = InputController(editorMode: FrunEditorMode.normal);
      type(c, '/run lib/main.dart');
      c.insertKey(rune('u', mods: const {KeyMod.ctrl}));
      expect(c.text, '');
    });

    test(
      'Shift-Enter inserts newline; plain Enter on multi-line inserts too',
      () {
        final c = InputController(editorMode: FrunEditorMode.normal);
        type(c, 'abc');
        c.insertKey(key(KeyCode.enter, mods: const {KeyMod.shift}));
        type(c, 'def');
        expect(c.text, 'abc\ndef');
        // Now buffer is multi-line; plain Enter should also insert newline.
        final res = c.insertKey(key(KeyCode.enter));
        expect(res, InputAction.none);
        expect(c.text, 'abc\ndef\n');
      },
    );

    test('insertAt with newline splits the line', () {
      final c = InputController(editorMode: FrunEditorMode.normal);
      type(c, 'hello');
      c.cursor = const Pos(0, 2);
      c.insertAt(const Pos(0, 2), '\n');
      expect(c.text, 'he\nllo');
      expect(c.cursor.row, 1);
      expect(c.cursor.col, 0);
    });

    test('replaceRange linewise removes a whole line', () {
      final c = InputController(editorMode: FrunEditorMode.normal);
      c.setText('one\ntwo\nthree');
      const r = Range(Pos(1, 0), Pos(1, 3), RangeKind.linewise);
      c.replaceRange(r, '', RangeKind.linewise);
      expect(c.text, 'one\nthree');
    });

    test('Ctrl-W deletes word backward', () {
      final c = InputController(editorMode: FrunEditorMode.normal);
      type(c, '/run lib');
      c.insertKey(rune('w', mods: const {KeyMod.ctrl}));
      expect(c.text, '/run ');
    });
  });

  group('VimBuffer compliance', () {
    test('textInRange returns the right slice', () {
      final c = InputController(editorMode: FrunEditorMode.vim);
      c.setText('hello world');
      const r = Range(Pos(0, 0), Pos(0, 4), RangeKind.charwise);
      expect(c.textInRange(r), 'hello');
    });

    test('linewise yank then paste appends a duplicate line below', () {
      final c = InputController(editorMode: FrunEditorMode.vim);
      c.setText('alpha\nbeta');
      c.cursor = const Pos(1, 0);
      const r = Range(Pos(1, 0), Pos(1, 4), RangeKind.linewise);
      final text = c.textInRange(r);
      expect(text, 'beta');
      // Insert below row 1 — append at end.
      c.insertAt(
        Pos(c.lineCount - 1, c.lineAt(c.lineCount - 1).length),
        '\n$text',
      );
      expect(c.text, 'alpha\nbeta\nbeta');
    });
  });
}
