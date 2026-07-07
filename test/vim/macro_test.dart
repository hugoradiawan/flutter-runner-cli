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

/// Engine + a minimal player that mimics the host's replay loop (re-feeding
/// keys through handle with replayDepth suppression).
(VimEngine, VimState) _engineWithPlayer(InputController b) {
  final s = VimState()..mode = VimMode.normal;
  late VimEngine e;
  void player(List<TeaKey> keys) {
    s.macros.replayDepth++;
    try {
      for (final k in keys) {
        final msg = KeyPressMsg(k);
        if (e.handle(msg, b) == KeyResult.passInsert) {
          s.insertCapture?.write(k.text);
          b.insertKey(msg);
        }
      }
    } finally {
      s.macros.replayDepth--;
    }
  }

  e = VimEngine(
    state: s,
    viewport: (_) => (top: 0, height: 10),
    runExCmd: (_, _) {},
    runSearch: (_, _, _) {},
    onPlayMacro: player,
  );
  return (e, s);
}

void main() {
  group('Macro recording', () {
    test('qa…q records the keys between, excluding the control keys', () {
      final b = _buf('foo bar baz');
      final (e, s) = _engineWithPlayer(b);
      feed(e, b, 'qadwq');
      expect(s.macros.isRecording, isFalse);
      final tape = s.macros.tape('a')!;
      expect(tape.map((k) => k.text).toList(), ['d', 'w']);
      // The recorded commands executed live while recording.
      expect(b.text, 'bar baz');
    });

    test('recording flag is active between q{reg} and q', () {
      final b = _buf('x');
      final (e, s) = _engineWithPlayer(b);
      feed(e, b, 'qa');
      expect(s.macros.isRecording, isTrue);
      expect(s.macros.recording, 'a');
      feed(e, b, 'q');
      expect(s.macros.isRecording, isFalse);
    });

    test('insert-mode keys are captured on the tape', () {
      final b = _buf('');
      final (e, s) = _engineWithPlayer(b);
      feed(e, b, 'qaihi');
      e.handle(esc(), b);
      feed(e, b, 'q');
      final tape = s.macros.tape('a')!;
      expect(tape.length, 4); // i h i Esc
      expect(b.text, 'hi');
    });
  });

  group('Macro playback', () {
    test('@a replays the tape', () {
      final b = _buf('a b c d');
      final (e, _) = _engineWithPlayer(b);
      feed(e, b, 'qadwq');
      expect(b.text, 'b c d');
      feed(e, b, '@a');
      expect(b.text, 'c d');
    });

    test('{count}@a multiplies playback', () {
      final b = _buf('a b c d e');
      final (e, _) = _engineWithPlayer(b);
      feed(e, b, 'qadwq');
      feed(e, b, '2@a');
      expect(b.text, 'd e');
    });

    test('@@ repeats the last played macro', () {
      final b = _buf('a b c d');
      final (e, _) = _engineWithPlayer(b);
      feed(e, b, 'qadwq@a@@');
      expect(b.text, 'd');
    });

    test('@ with an empty register is a no-op', () {
      final b = _buf('abc');
      final (e, _) = _engineWithPlayer(b);
      feed(e, b, '@z');
      expect(b.text, 'abc');
    });

    test('recording another macro captures @a, not its expansion', () {
      final b = _buf('a b c d');
      final (e, s) = _engineWithPlayer(b);
      feed(e, b, 'qadwq'); // a = dw
      feed(e, b, 'qb@aq'); // b invokes a
      final tapeB = s.macros.tape('b')!;
      expect(tapeB.map((k) => k.text).toList(), ['@', 'a']);
      // Both the recording pass and a's playback consumed a word each.
      expect(b.text, 'c d');
      feed(e, b, '@b');
      expect(b.text, 'd');
    });
  });
}
