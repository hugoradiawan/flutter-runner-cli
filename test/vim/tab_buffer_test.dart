import 'package:frun/src/presentation/tui/vim/tab_buffer.dart';
import 'package:test/test.dart';

void main() {
  group('CallbackTabSwitchSink', () {
    test('next/previous call cycle with correct direction', () {
      bool? forwardSeen;
      final sink = CallbackTabSwitchSink(
        tabCount: () => 3,
        activeIndex: () => 0,
        setActiveIndex: (_) {},
        cycle: ({required bool forward}) => forwardSeen = forward,
      );
      sink.next();
      expect(forwardSeen, isTrue);
      sink.previous();
      expect(forwardSeen, isFalse);
    });

    test('goTo converts 1-based to 0-based', () {
      int? idx;
      final sink = CallbackTabSwitchSink(
        tabCount: () => 3,
        activeIndex: () => 0,
        setActiveIndex: (i) => idx = i,
        cycle: ({required bool forward}) {},
      );
      sink.goTo(2);
      expect(idx, 1);
    });

    test('goTo ignores zero/negative', () {
      int? idx;
      final sink = CallbackTabSwitchSink(
        tabCount: () => 3,
        activeIndex: () => 0,
        setActiveIndex: (i) => idx = i,
        cycle: ({required bool forward}) {},
      );
      sink.goTo(0);
      expect(idx, isNull);
    });
  });
}
