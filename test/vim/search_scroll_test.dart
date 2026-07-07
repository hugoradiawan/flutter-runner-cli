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

void main() {
  group('Scroll requests', () {
    test('zz/zt/zb emit center/top/bottom', () {
      final b = _buf('hello');
      final s = VimState()..mode = VimMode.normal;
      final seen = <VimScrollKind>[];
      final e = VimEngine(
        state: s,
        viewport: (_) => (top: 0, height: 10),
        runExCmd: (_, _) {},
        runSearch: (_, _, _) {},
        onScroll: (req, _) => seen.add(req.kind),
      );
      feed(e, b, 'zzztzb');
      expect(seen, [
        VimScrollKind.center,
        VimScrollKind.top,
        VimScrollKind.bottom,
      ]);
    });

    test('Ctrl-E and Ctrl-Y emit line scrolls with counts', () {
      final b = _buf('hello');
      final s = VimState()..mode = VimMode.normal;
      final seen = <int>[];
      final e = VimEngine(
        state: s,
        viewport: (_) => (top: 0, height: 10),
        runExCmd: (_, _) {},
        runSearch: (_, _, _) {},
        onScroll: (req, _) {
          expect(req.kind, VimScrollKind.lines);
          seen.add(req.lines);
        },
      );
      feed(e, b, '3');
      e.handle(ctrl('e'), b);
      e.handle(ctrl('y'), b);
      expect(seen, [3, -1]);
    });
  });

  group('Word search (* and #)', () {
    test('* searches word under cursor with word boundaries', () {
      final b = _buf('foo bar foo');
      final s = VimState()..mode = VimMode.normal;
      String? pattern;
      bool? forward;
      final e = VimEngine(
        state: s,
        viewport: (_) => (top: 0, height: 10),
        runExCmd: (_, _) {},
        runSearch: (p, f, _) {
          pattern = p;
          forward = f;
        },
      );
      feed(e, b, '*');
      expect(pattern, r'\bfoo\b');
      expect(forward, isTrue);
      expect(s.lastSearch?.pattern, r'\bfoo\b');
    });

    test('# searches backward', () {
      final b = _buf('foo bar');
      final s = VimState()..mode = VimMode.normal;
      bool? forward;
      final e = VimEngine(
        state: s,
        viewport: (_) => (top: 0, height: 10),
        runExCmd: (_, _) {},
        runSearch: (_, f, _) => forward = f,
      );
      feed(e, b, '#');
      expect(forward, isFalse);
    });

    test('g* searches without word boundaries', () {
      final b = _buf('foo bar');
      final s = VimState()..mode = VimMode.normal;
      String? pattern;
      final e = VimEngine(
        state: s,
        viewport: (_) => (top: 0, height: 10),
        runExCmd: (_, _) {},
        runSearch: (p, _, _) => pattern = p,
      );
      feed(e, b, 'g*');
      expect(pattern, 'foo');
    });

    test('* on punctuation scans forward to the next word', () {
      final b = _buf('== foo ==', cursor: const Pos(0, 0));
      final s = VimState()..mode = VimMode.normal;
      String? pattern;
      final e = VimEngine(
        state: s,
        viewport: (_) => (top: 0, height: 10),
        runExCmd: (_, _) {},
        runSearch: (p, _, _) => pattern = p,
      );
      feed(e, b, '*');
      expect(pattern, r'\bfoo\b');
    });
  });

  group('Operator + search motion', () {
    VimEngine engineWithSearchTo(VimState s, Pos target) => VimEngine(
      state: s,
      viewport: (_) => (top: 0, height: 10),
      runExCmd: (_, _) {},
      runSearch: (_, _, buf) => buf.cursor = target,
    );

    test('dn deletes from cursor to the next match (exclusive)', () {
      final b = _buf('abcdefghij');
      final s = VimState()
        ..mode = VimMode.normal
        ..lastSearch = const LastSearch('x', true);
      final e = engineWithSearchTo(s, const Pos(0, 8));
      feed(e, b, 'dn');
      expect(b.text, 'ij');
      expect(s.pendingOperator, isEmpty);
    });

    test('d/pattern<CR> operates to the match', () {
      final b = _buf('abcdefgh');
      final s = VimState()..mode = VimMode.normal;
      final e = engineWithSearchTo(s, const Pos(0, 5));
      feed(e, b, 'd/xy');
      e.handle(key(KeyCode.enter), b);
      expect(b.text, 'fgh');
      expect(s.mode, VimMode.normal);
    });

    test('Esc from d/ search aborts the operator', () {
      final b = _buf('abcdefgh');
      final s = VimState()..mode = VimMode.normal;
      final e = engineWithSearchTo(s, const Pos(0, 5));
      feed(e, b, 'd/xy');
      e.handle(esc(), b);
      expect(b.text, 'abcdefgh');
      expect(s.pendingOperator, isEmpty);
      feed(e, b, 'x');
      expect(b.text, 'bcdefgh');
    });

    test('dn with no match aborts', () {
      final b = _buf('abcd');
      final s = VimState()
        ..mode = VimMode.normal
        ..lastSearch = const LastSearch('x', true);
      final e = VimEngine(
        state: s,
        viewport: (_) => (top: 0, height: 10),
        runExCmd: (_, _) {},
        runSearch: (_, _, _) {}, // cursor unmoved = no match
      );
      feed(e, b, 'dn');
      expect(b.text, 'abcd');
      expect(s.pendingOperator, isEmpty);
    });
  });
}
