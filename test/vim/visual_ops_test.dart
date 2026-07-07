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
  group('Visual case operators', () {
    test('v2l~ toggles case of the selection and exits visual', () {
      final b = _buf('abc');
      final s = VimState()..mode = VimMode.normal;
      feed(_engine(s), b, 'v2l~');
      expect(b.text, 'ABC');
      expect(s.mode, VimMode.normal);
    });

    test('vlu lowercases the selection', () {
      final b = _buf('ABC');
      final s = VimState()..mode = VimMode.normal;
      feed(_engine(s), b, 'vlu');
      expect(b.text, 'abC');
    });

    test('vlU uppercases the selection', () {
      final b = _buf('abc');
      final s = VimState()..mode = VimMode.normal;
      feed(_engine(s), b, 'vlU');
      expect(b.text, 'ABc');
    });

    test('gu in visual lowercases immediately', () {
      final b = _buf('ABCD');
      final s = VimState()..mode = VimMode.normal;
      feed(_engine(s), b, 'v2lgu');
      expect(b.text, 'abcD');
      expect(s.mode, VimMode.normal);
    });
  });

  group('Visual paste', () {
    test('vp replaces the selection with the register', () {
      final b = _buf('abcd');
      final s = VimState()..mode = VimMode.normal;
      s.registers.yank('XY', RangeKind.charwise);
      feed(_engine(s), b, 'vlp');
      expect(b.text, 'XYcd');
      expect(s.mode, VimMode.normal);
      // Replaced text lands in the unnamed register (vim behavior).
      expect(s.registers.read('"').text, 'ab');
    });

    test('vp on empty register is a no-op that exits visual', () {
      final b = _buf('abcd');
      final s = VimState()..mode = VimMode.normal;
      feed(_engine(s), b, 'vlp');
      expect(b.text, 'abcd');
      expect(s.mode, VimMode.normal);
    });
  });

  group('Visual join', () {
    test('VjJ joins the selected lines', () {
      final b = _buf('a\nb\nc');
      final s = VimState()..mode = VimMode.normal;
      feed(_engine(s), b, 'VjJ');
      expect(b.text, 'a b\nc');
      expect(s.mode, VimMode.normal);
    });
  });

  group('Visual replace', () {
    test('v2lrz overwrites every selected cell', () {
      final b = _buf('abcd');
      final s = VimState()..mode = VimMode.normal;
      feed(_engine(s), b, 'v2lrz');
      expect(b.text, 'zzzd');
      expect(s.mode, VimMode.normal);
    });

    test('blockwise r overwrites the rectangle only', () {
      final b = _buf('ab\ncd');
      final s = VimState()..mode = VimMode.normal;
      final e = _engine(s);
      e.handle(ctrl('v'), b);
      feed(e, b, 'jrz');
      expect(b.text, 'zb\nzd');
    });

    test('linewise r overwrites whole lines', () {
      final b = _buf('ab\ncde');
      final s = VimState()..mode = VimMode.normal;
      feed(_engine(s), b, 'Vjrx');
      expect(b.text, 'xx\nxxx');
    });
  });

  group('Visual o (swap ends)', () {
    test('o moves the cursor to the anchor and back', () {
      final b = _buf('abcdef', cursor: const Pos(0, 2));
      final s = VimState()..mode = VimMode.normal;
      final e = _engine(s);
      feed(e, b, 'v2l');
      expect(b.cursor, const Pos(0, 4));
      feed(e, b, 'o');
      expect(b.cursor, const Pos(0, 2));
      // Motions now extend from the swapped anchor.
      feed(e, b, 'h');
      expect(b.textInRange(b.selection!.normalized()), 'bcde');
    });
  });

  group('Visual-block insert', () {
    test('Ctrl-V jj I inserts on every block row', () {
      final b = _buf('aaa\nbbb\nccc');
      final s = VimState()..mode = VimMode.normal;
      final e = _engine(s);
      e.handle(ctrl('v'), b);
      feed(e, b, 'jjIX');
      e.handle(esc(), b);
      expect(b.text, 'Xaaa\nXbbb\nXccc');
      expect(s.mode, VimMode.normal);
    });

    test('I skips rows shorter than the block column', () {
      final b = _buf('abcd\nx\nefgh', cursor: const Pos(0, 2));
      final s = VimState()..mode = VimMode.normal;
      final e = _engine(s);
      e.handle(ctrl('v'), b);
      feed(e, b, 'jjIZ');
      e.handle(esc(), b);
      expect(b.text, 'abZcd\nx\nefZgh');
    });

    test('A appends past the block, padding short rows', () {
      final b = _buf('abc\nde\nfgh');
      final s = VimState()..mode = VimMode.normal;
      final e = _engine(s);
      e.handle(ctrl('v'), b);
      feed(e, b, 'jj2lAX');
      e.handle(esc(), b);
      expect(b.text, 'abcX\nde X\nfghX');
    });
  });

  group('Visual marks', () {
    test("'< and '> record the last selection on Esc", () {
      final b = _buf('hello world');
      final s = VimState()..mode = VimMode.normal;
      final e = _engine(s);
      feed(e, b, 've');
      e.handle(esc(), b);
      expect(s.marks.get('<', b.surfaceId)?.pos, const Pos(0, 0));
      expect(s.marks.get('>', b.surfaceId)?.pos, const Pos(0, 4));
    });

    test("'< and '> record on visual operator too", () {
      final b = _buf('hello world', cursor: const Pos(0, 6));
      final s = VimState()..mode = VimMode.normal;
      feed(_engine(s), b, 'vey');
      expect(s.marks.get('<', b.surfaceId)?.pos, const Pos(0, 6));
      expect(s.marks.get('>', b.surfaceId)?.pos, const Pos(0, 10));
    });
  });

  group('Visual c enters insert', () {
    test('vlc deletes the selection and stays in insert mode', () {
      final b = _buf('abcd');
      final s = VimState()..mode = VimMode.normal;
      final e = _engine(s);
      feed(e, b, 'vlc');
      expect(b.text, 'cd');
      expect(s.mode, VimMode.insert);
      feed(e, b, 'XY');
      e.handle(esc(), b);
      expect(b.text, 'XYcd');
    });
  });

  group('Counts on normal-mode edits', () {
    test('3p pastes the register three times', () {
      final b = _buf('ab');
      final s = VimState()..mode = VimMode.normal;
      s.registers.yank('X', RangeKind.charwise);
      feed(_engine(s), b, '3p');
      expect(b.text, 'aXXXb');
    });

    test('2p linewise duplicates the line twice', () {
      final b = _buf('one\ntwo');
      final s = VimState()..mode = VimMode.normal;
      s.registers.yank('mid', RangeKind.linewise);
      feed(_engine(s), b, '2p');
      expect(b.text, 'one\nmid\nmid\ntwo');
    });

    test('3~ toggles three chars and advances', () {
      final b = _buf('abcdef');
      final s = VimState()..mode = VimMode.normal;
      feed(_engine(s), b, '3~');
      expect(b.text, 'ABCdef');
      expect(b.cursor, const Pos(0, 3));
    });

    test('50% jumps to the middle of the buffer', () {
      final b = _buf('1\n2\n3\n4\n5\n6\n7\n8\n9\n10');
      final s = VimState()..mode = VimMode.normal;
      feed(_engine(s), b, '50%');
      expect(b.cursor.row, 4);
    });
  });
}
