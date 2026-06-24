import 'package:frun/src/domain/value_objects/config_values.dart';
import 'package:frun/src/presentation/tui/input_controller.dart';
import 'package:frun/src/presentation/tui/vim/operators.dart';
import 'package:frun/src/presentation/tui/vim/registers.dart';
import 'package:frun/src/presentation/tui/vim/vim_buffer.dart';
import 'package:test/test.dart';

InputController _buf(String text) {
  final c = InputController(editorMode: FrunEditorMode.vim);
  c.setText(text);
  c.cursor = const Pos(0, 0);
  return c;
}

void main() {
  group('Operators', () {
    test('delete charwise removes range and writes register', () {
      final b = _buf('hello world');
      final regs = RegisterBank();
      Operators.delete(b, const Range(Pos(0, 0), Pos(0, 4), RangeKind.charwise),
          regs);
      expect(b.text, ' world');
      expect(regs.read('"').text, 'hello');
    });

    test('yank does not mutate buffer', () {
      final b = _buf('hello');
      final regs = RegisterBank();
      Operators.yank(b, const Range(Pos(0, 0), Pos(0, 4), RangeKind.charwise),
          regs);
      expect(b.text, 'hello');
      expect(regs.read('"').text, 'hello');
      expect(regs.read('0').text, 'hello');
    });

    test('paste charwise after cursor', () {
      final b = _buf('ab');
      b.cursor = const Pos(0, 0);
      const entry = RegisterEntry('XY', RangeKind.charwise);
      Operators.paste(b, entry, before: false);
      expect(b.text, 'aXYb');
    });

    test('paste linewise inserts new line', () {
      final b = _buf('one\ntwo');
      b.cursor = const Pos(0, 0);
      const entry = RegisterEntry('mid', RangeKind.linewise);
      Operators.paste(b, entry, before: false);
      expect(b.text, 'one\nmid\ntwo');
    });

    test('toggleCase swaps cases', () {
      final b = _buf('AbC');
      Operators.toggleCase(b,
          const Range(Pos(0, 0), Pos(0, 2), RangeKind.charwise));
      expect(b.text, 'aBc');
    });

    test('indent / dedent shift lines by shiftwidth', () {
      final b = _buf('hi\nbye');
      Operators.indent(b,
          const Range(Pos(0, 0), Pos(1, 0), RangeKind.linewise), 2);
      expect(b.text, '  hi\n  bye');
      Operators.dedent(b,
          const Range(Pos(0, 0), Pos(1, 0), RangeKind.linewise), 2);
      expect(b.text, 'hi\nbye');
    });

    test('joinLines joins next line with space', () {
      final b = _buf('foo\nbar');
      Operators.joinLines(b, 1);
      expect(b.text, 'foo bar');
    });
  });
}

