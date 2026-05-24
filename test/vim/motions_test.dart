import 'package:frun/src/config/config.dart';
import 'package:frun/src/tui/input_controller.dart';
import 'package:frun/src/tui/vim/motions.dart';
import 'package:frun/src/tui/vim/vim_buffer.dart';
import 'package:test/test.dart';

InputController _buf(String text) {
  final c = InputController(editorMode: FrunEditorMode.vim);
  c.setText(text);
  c.cursor = const Pos(0, 0);
  return c;
}

void main() {
  group('Motions', () {
    test('h/l clamp at line bounds', () {
      final b = _buf('hello');
      expect(Motions.right(b, 2).target, const Pos(0, 2));
      b.cursor = const Pos(0, 4);
      expect(Motions.right(b, 5).target, const Pos(0, 4));
      expect(Motions.left(b, 2).target, const Pos(0, 2));
    });

    test('w jumps to next word', () {
      final b = _buf('foo bar baz');
      expect(Motions.nextWordStart(b, 1).target, const Pos(0, 4));
      expect(Motions.nextWordStart(b, 2).target, const Pos(0, 8));
    });

    test('e jumps to end of word', () {
      final b = _buf('foo bar');
      expect(Motions.wordEnd(b, 1).target, const Pos(0, 2));
      expect(Motions.wordEnd(b, 2).target, const Pos(0, 6));
    });

    test('b retreats to previous word start', () {
      final b = _buf('foo bar baz');
      b.cursor = const Pos(0, 9);
      expect(Motions.prevWordStart(b, 1).target, const Pos(0, 8));
      expect(Motions.prevWordStart(b, 2).target, const Pos(0, 4));
    });

    test('0 and \$ jump to line ends', () {
      final b = _buf('abcdef');
      b.cursor = const Pos(0, 3);
      expect(Motions.lineStart(b).target, const Pos(0, 0));
      expect(Motions.lineEnd(b).target, const Pos(0, 5));
    });

    test('gg / G go to first / last line', () {
      final b = _buf('a\nb\nc\nd');
      b.cursor = const Pos(2, 0);
      expect(Motions.firstLine(b).target, const Pos(0, 0));
      expect(Motions.goLine(b, null).target, const Pos(3, 0));
      expect(Motions.goLine(b, 2).target, const Pos(1, 0));
    });

    test('f finds char to the right', () {
      final b = _buf('abcdef');
      final r = Motions.findChar(b, 'd', 1, forward: true, till: false);
      expect(r.target, const Pos(0, 3));
    });

    test('t stops before char', () {
      final b = _buf('abcdef');
      final r = Motions.findChar(b, 'd', 1, forward: true, till: true);
      expect(r.target, const Pos(0, 2));
    });

    test('% jumps to matching paren', () {
      final b = _buf('(foo)');
      b.cursor = const Pos(0, 0);
      expect(Motions.matchBracket(b).target, const Pos(0, 4));
      b.cursor = const Pos(0, 4);
      expect(Motions.matchBracket(b).target, const Pos(0, 0));
    });

    test('{/} navigate paragraphs', () {
      final b = _buf('a\nb\n\nc\nd\n\ne');
      b.cursor = const Pos(0, 0);
      final fwd = Motions.paragraph(b, 1, forward: true);
      expect(fwd.target.row, 2);
    });

    test('viewport top/middle/bottom', () {
      final b = _buf('1\n2\n3\n4\n5');
      expect(Motions.viewportTop(b, 1).target, const Pos(1, 0));
      expect(Motions.viewportMiddle(b, 0, 4).target, const Pos(2, 0));
      expect(Motions.viewportBottom(b, 0, 4).target, const Pos(3, 0));
    });
  });
}
