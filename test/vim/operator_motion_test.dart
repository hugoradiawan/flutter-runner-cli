import 'package:frun/src/domain/value_objects/config_values.dart';
import 'package:frun/src/presentation/tui/input_controller.dart';
import 'package:frun/src/presentation/tui/vim/ex_parser.dart';
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

VimEngine _engine(VimState s, {void Function(ExCommand)? onEx}) => VimEngine(
  state: s,
  viewport: (_) => (top: 0, height: 10),
  runExCmd: (c, _) => onEx?.call(c),
  runSearch: (_, _, _) {},
);

void main() {
  group('Operator + g-chord motions', () {
    test('dgg deletes linewise to first line', () {
      final b = _buf('a\nb\nc\nd', cursor: const Pos(1, 0));
      final s = VimState()..mode = VimMode.normal;
      feed(_engine(s), b, 'dgg');
      expect(b.text, 'c\nd');
    });

    test('dG deletes linewise to last line', () {
      final b = _buf('a\nb\nc\nd', cursor: const Pos(1, 0));
      final s = VimState()..mode = VimMode.normal;
      feed(_engine(s), b, 'dG');
      expect(b.text, 'a');
    });

    test('d2G deletes to line 2', () {
      final b = _buf('a\nb\nc\nd', cursor: const Pos(3, 0));
      final s = VimState()..mode = VimMode.normal;
      feed(_engine(s), b, 'd2G');
      expect(b.text, 'a');
    });

    test('yG yanks linewise to end without mutating', () {
      final b = _buf('a\nb\nc', cursor: const Pos(1, 0));
      final s = VimState()..mode = VimMode.normal;
      feed(_engine(s), b, 'yG');
      expect(b.text, 'a\nb\nc');
      expect(s.registers.read('"').text, 'b\nc');
      expect(s.registers.read('"').kind, RangeKind.linewise);
    });

    test('cgg changes to first line and enters insert', () {
      final b = _buf('a\nb\nc', cursor: const Pos(1, 0));
      final s = VimState()..mode = VimMode.normal;
      feed(_engine(s), b, 'cgg');
      expect(b.text, 'c');
      expect(s.mode, VimMode.insert);
    });

    test('dge deletes inclusive back to previous word end', () {
      final b = _buf('foo bar', cursor: const Pos(0, 4));
      final s = VimState()..mode = VimMode.normal;
      feed(_engine(s), b, 'dge');
      expect(b.text, 'foar');
    });
  });

  group('Operator + find motions', () {
    test('dfx deletes through x', () {
      final b = _buf('abcxdef');
      final s = VimState()..mode = VimMode.normal;
      feed(_engine(s), b, 'dfx');
      expect(b.text, 'def');
    });

    test('dtx deletes up to x', () {
      final b = _buf('abcxdef');
      final s = VimState()..mode = VimMode.normal;
      feed(_engine(s), b, 'dtx');
      expect(b.text, 'xdef');
    });

    test('dFx deletes back through x, keeping the cursor char', () {
      final b = _buf('abcxdef', cursor: const Pos(0, 5));
      final s = VimState()..mode = VimMode.normal;
      feed(_engine(s), b, 'dFx');
      expect(b.text, 'abcef');
    });

    test('dTx deletes back to just after x', () {
      final b = _buf('abcxdef', cursor: const Pos(0, 5));
      final s = VimState()..mode = VimMode.normal;
      feed(_engine(s), b, 'dTx');
      expect(b.text, 'abcxef');
    });

    test('d; repeats the last find as an operator target', () {
      final b = _buf('axbxcx');
      final s = VimState()..mode = VimMode.normal;
      final e = _engine(s);
      feed(e, b, 'fx');
      expect(b.cursor, const Pos(0, 1));
      feed(e, b, 'd;');
      expect(b.text, 'acx');
    });

    test('failed find aborts the operator without wedging', () {
      final b = _buf('hello');
      final s = VimState()..mode = VimMode.normal;
      final e = _engine(s);
      feed(e, b, 'dfz');
      expect(b.text, 'hello');
      expect(s.pendingOperator, isEmpty);
      feed(e, b, 'x');
      expect(b.text, 'ello');
    });
  });

  group('Counts', () {
    test('d0 deletes to line start', () {
      final b = _buf('hello', cursor: const Pos(0, 3));
      final s = VimState()..mode = VimMode.normal;
      feed(_engine(s), b, 'd0');
      expect(b.text, 'lo');
    });

    test('2d3w multiplies to six words', () {
      final b = _buf('a b c d e f g');
      final s = VimState()..mode = VimMode.normal;
      feed(_engine(s), b, '2d3w');
      expect(b.text, 'g');
    });

    test('2dd and d2d both delete two lines', () {
      final b1 = _buf('a\nb\nc\nd');
      final s1 = VimState()..mode = VimMode.normal;
      feed(_engine(s1), b1, '2dd');
      expect(b1.text, 'c\nd');

      final b2 = _buf('a\nb\nc\nd');
      final s2 = VimState()..mode = VimMode.normal;
      feed(_engine(s2), b2, 'd2d');
      expect(b2.text, 'c\nd');
    });

    test('2d3d multiplies to six lines', () {
      final b = _buf('1\n2\n3\n4\n5\n6\n7');
      final s = VimState()..mode = VimMode.normal;
      feed(_engine(s), b, '2d3d');
      expect(b.text, '7');
    });

    test('3fx lands on the third x', () {
      final b = _buf('axbxcxd');
      final s = VimState()..mode = VimMode.normal;
      feed(_engine(s), b, '3fx');
      expect(b.cursor, const Pos(0, 5));
    });

    test('2; repeats find with a count', () {
      final b = _buf('axbxcxdx');
      final s = VimState()..mode = VimMode.normal;
      final e = _engine(s);
      feed(e, b, 'fx');
      feed(e, b, '2;');
      expect(b.cursor, const Pos(0, 5));
    });

    test('3rz replaces three chars', () {
      final b = _buf('hello');
      final s = VimState()..mode = VimMode.normal;
      feed(_engine(s), b, '3rz');
      expect(b.text, 'zzzlo');
      expect(b.cursor, const Pos(0, 2));
    });

    test('r with count past end of line aborts', () {
      final b = _buf('ab');
      final s = VimState()..mode = VimMode.normal;
      feed(_engine(s), b, '5rz');
      expect(b.text, 'ab');
    });

    test('2H moves one line below viewport top', () {
      final b = _buf('1\n2\n3\n4\n5\n6');
      final s = VimState()..mode = VimMode.normal;
      feed(_engine(s), b, '2H');
      expect(b.cursor.row, 1);
    });

    test('dL deletes linewise to viewport bottom', () {
      final b = _buf('1\n2\n3\n4\n5\n6', cursor: const Pos(2, 0));
      final s = VimState()..mode = VimMode.normal;
      feed(_engine(s), b, 'dL');
      expect(b.text, '1\n2');
    });
  });

  group('Backward exclusive ranges', () {
    test('db keeps the char under the cursor', () {
      final b = _buf('foo bar', cursor: const Pos(0, 4));
      final s = VimState()..mode = VimMode.normal;
      feed(_engine(s), b, 'db');
      expect(b.text, 'bar');
    });

    test('dh deletes only the char left of the cursor', () {
      final b = _buf('abc', cursor: const Pos(0, 2));
      final s = VimState()..mode = VimMode.normal;
      feed(_engine(s), b, 'dh');
      expect(b.text, 'ac');
    });
  });

  group('Operator abort', () {
    test('non-motion key aborts a pending operator', () {
      final b = _buf('hello');
      final s = VimState()..mode = VimMode.normal;
      final e = _engine(s);
      feed(e, b, 'dp');
      expect(b.text, 'hello');
      expect(s.pendingOperator, isEmpty);
      feed(e, b, 'x');
      expect(b.text, 'ello');
    });

    test('failed text object aborts the operator', () {
      final b = _buf('hello');
      final s = VimState()..mode = VimMode.normal;
      final e = _engine(s);
      feed(e, b, 'di(');
      expect(b.text, 'hello');
      expect(s.pendingOperator, isEmpty);
    });
  });

  group('Dot repeat', () {
    test('. repeats dfx', () {
      final b = _buf('ax bx cx');
      final s = VimState()..mode = VimMode.normal;
      final e = _engine(s);
      feed(e, b, 'dfx');
      expect(b.text, ' bx cx');
      feed(e, b, '.');
      expect(b.text, ' cx');
    });

    test('. repeats d2w', () {
      final b = _buf('a b c d e');
      final s = VimState()..mode = VimMode.normal;
      final e = _engine(s);
      feed(e, b, 'd2w');
      expect(b.text, 'c d e');
      feed(e, b, '.');
      expect(b.text, 'e');
    });

    test('. repeats diw at the new cursor position', () {
      final b = _buf('foo bar baz');
      final s = VimState()..mode = VimMode.normal;
      final e = _engine(s);
      feed(e, b, 'diw');
      expect(b.text, ' bar baz');
      feed(e, b, 'w.');
      expect(b.text, '  baz');
    });

    test('. repeats ciw including the typed text', () {
      final b = _buf('foo bar');
      final s = VimState()..mode = VimMode.normal;
      final e = _engine(s);
      feed(e, b, 'ciwX');
      e.handle(esc(), b);
      expect(b.text, 'X bar');
      feed(e, b, 'w.');
      expect(b.text, 'X X');
    });

    test('. repeats 3rz with its count', () {
      final b = _buf('hello world');
      final s = VimState()..mode = VimMode.normal;
      final e = _engine(s);
      feed(e, b, '3rz');
      expect(b.text, 'zzzlo world');
      feed(e, b, 'w.');
      expect(b.text, 'zzzlo zzzld');
    });
  });

  group('Case operators via g-chord', () {
    test('guw lowercases a word', () {
      final b = _buf('HELLO WORLD');
      final s = VimState()..mode = VimMode.normal;
      feed(_engine(s), b, 'guw');
      expect(b.text, 'hello WORLD');
    });

    test('2guw lowercases two words', () {
      final b = _buf('AA BB CC');
      final s = VimState()..mode = VimMode.normal;
      feed(_engine(s), b, '2guw');
      expect(b.text, 'aa bb CC');
    });

    test('guu lowercases the whole line', () {
      final b = _buf('HeLLo WoRLD', cursor: const Pos(0, 3));
      final s = VimState()..mode = VimMode.normal;
      feed(_engine(s), b, 'guu');
      expect(b.text, 'hello world');
    });

    test('gUU uppercases the whole line', () {
      final b = _buf('hello');
      final s = VimState()..mode = VimMode.normal;
      feed(_engine(s), b, 'gUU');
      expect(b.text, 'HELLO');
    });

    test('g~~ toggles case of the whole line', () {
      final b = _buf('HeLLo');
      final s = VimState()..mode = VimMode.normal;
      feed(_engine(s), b, 'g~~');
      expect(b.text, 'hEllO');
    });
  });

  group('ZZ', () {
    test('ZZ runs :q through the ex pipeline', () {
      final b = _buf('x');
      final s = VimState()..mode = VimMode.normal;
      ExCommand? captured;
      final e = _engine(s, onEx: (c) => captured = c);
      feed(e, b, 'ZZ');
      expect(captured?.name, 'q');
    });
  });

  group('Named registers with operators', () {
    test('"add deletes into register a', () {
      final b = _buf('one\ntwo');
      final s = VimState()..mode = VimMode.normal;
      feed(_engine(s), b, '"add');
      expect(b.text, 'two');
      expect(s.registers.read('a').text, 'one');
    });

    test('"a3dw honors register and count together', () {
      final b = _buf('a b c d');
      final s = VimState()..mode = VimMode.normal;
      feed(_engine(s), b, '"a3dw');
      expect(b.text, 'd');
      expect(s.registers.read('a').text, 'a b c ');
    });
  });
}
