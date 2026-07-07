import 'package:dart_tui/dart_tui.dart';
import 'package:frun/src/presentation/tui/input_controller.dart';
import 'package:frun/src/presentation/tui/vim/vim_buffer.dart';
import 'package:frun/src/presentation/tui/vim/vim_engine.dart';

KeyMsg rune(String ch, {Set<KeyMod> mods = const {}}) =>
    KeyPressMsg(TeaKey(code: KeyCode.rune, text: ch, modifiers: mods));

KeyMsg key(KeyCode code, {Set<KeyMod> mods = const {}}) =>
    KeyPressMsg(TeaKey(code: code, modifiers: mods));

KeyMsg esc() => key(KeyCode.escape);

KeyMsg ctrl(String ch) => rune(ch, mods: {KeyMod.ctrl});

void type(InputController c, String text) {
  for (final ch in text.split('')) {
    c.insertKey(rune(ch));
  }
}

/// Feed a normal-mode key sequence rune-by-rune through the engine, e.g.
/// `feed(e, b, '2d3w')`. Keys the engine declines (passInsert) are typed
/// into the buffer and mirrored into the insert-session capture, matching
/// what the host's _insertIntoActive does, so `cwfoo<Esc>` + `.` works.
void feed(VimEngine e, VimBuffer b, String keys) {
  for (final ch in keys.split('')) {
    final res = e.handle(rune(ch), b);
    if (res == KeyResult.passInsert && b is InputController) {
      e.state.insertCapture?.write(ch);
      b.insertKey(rune(ch));
    }
  }
}
