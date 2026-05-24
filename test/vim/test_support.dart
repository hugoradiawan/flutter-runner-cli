import 'package:dart_tui/dart_tui.dart';
import 'package:frun/src/tui/input_controller.dart';

KeyMsg rune(String ch, {Set<KeyMod> mods = const {}}) =>
    KeyPressMsg(TeaKey(code: KeyCode.rune, text: ch, modifiers: mods));

KeyMsg key(KeyCode code, {Set<KeyMod> mods = const {}}) =>
    KeyPressMsg(TeaKey(code: code, modifiers: mods));

void type(InputController c, String text) {
  for (final ch in text.split('')) {
    c.insertKey(rune(ch));
  }
}
