import 'package:dart_tui/dart_tui.dart';
import 'package:frun/src/presentation/tui/overlay_list_nav.dart';
import 'package:test/test.dart';

TeaKey _rune(String ch, {Set<KeyMod> mods = const {}}) =>
    TeaKey(code: KeyCode.rune, text: ch, modifiers: mods);

void main() {
  group('OverlayListNav', () {
    test('j/k move by one', () {
      final nav = OverlayListNav();
      expect(nav.interpret(_rune('j'), vim: true), isA<OverlayNavMove>());
      final up = nav.interpret(_rune('k'), vim: true) as OverlayNavMove;
      expect(up.delta, -1);
    });

    test('counts multiply movement (5j)', () {
      final nav = OverlayListNav();
      expect(nav.interpret(_rune('5'), vim: true), isA<OverlayNavConsumed>());
      final move = nav.interpret(_rune('j'), vim: true) as OverlayNavMove;
      expect(move.delta, 5);
    });

    test('gg goes to the first entry, G to the last', () {
      final nav = OverlayListNav();
      expect(nav.interpret(_rune('g'), vim: true), isA<OverlayNavConsumed>());
      final gg = nav.interpret(_rune('g'), vim: true) as OverlayNavEdge;
      expect(gg.first, isTrue);
      final last = nav.interpret(_rune('G'), vim: true) as OverlayNavEdge;
      expect(last.first, isFalse);
    });

    test('pending g is cancelled by another key', () {
      final nav = OverlayListNav();
      nav.interpret(_rune('g'), vim: true);
      expect(nav.interpret(_rune('x'), vim: true), isNull);
      // g again starts a fresh chord, not an immediate gg.
      expect(nav.interpret(_rune('g'), vim: true), isA<OverlayNavConsumed>());
    });

    test('Ctrl-d / Ctrl-u are half pages', () {
      final nav = OverlayListNav();
      final down =
          nav.interpret(_rune('d', mods: {KeyMod.ctrl}), vim: true)
              as OverlayNavHalfPage;
      expect(down.down, isTrue);
      final up =
          nav.interpret(_rune('u', mods: {KeyMod.ctrl}), vim: true)
              as OverlayNavHalfPage;
      expect(up.down, isFalse);
    });

    test('q closes, / starts search', () {
      final nav = OverlayListNav();
      expect(nav.interpret(_rune('q'), vim: true), isA<OverlayNavClose>());
      expect(
        nav.interpret(_rune('/'), vim: true),
        isA<OverlayNavStartSearch>(),
      );
    });

    test('arrows work even when vim is off', () {
      final nav = OverlayListNav();
      final down =
          nav.interpret(const TeaKey(code: KeyCode.down), vim: false)
              as OverlayNavMove;
      expect(down.delta, 1);
      // Letters are not navigation outside vim mode (they feed filters).
      expect(nav.interpret(_rune('j'), vim: false), isNull);
      expect(nav.interpret(_rune('q'), vim: false), isNull);
    });

    test('overlay-specific keys are left to the caller', () {
      final nav = OverlayListNav();
      expect(nav.interpret(_rune('h'), vim: true), isNull);
      expect(nav.interpret(_rune('l'), vim: true), isNull);
      expect(nav.interpret(_rune('R'), vim: true), isNull);
    });
  });
}
