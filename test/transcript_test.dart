import 'package:frun/src/presentation/app/transcript.dart';
import 'package:test/test.dart';

void main() {
  group('Transcript ring buffer', () {
    test('caps retained lines and evicts the oldest', () {
      final t = Transcript();
      const cap = 10000;
      const overflow = 5;
      for (var i = 0; i < cap + overflow; i++) {
        t.info('line $i');
      }

      final lines = t.lines;
      expect(lines.length, cap, reason: 'hard cap on retained lines');
      // Oldest `overflow` lines dropped; newest retained.
      expect(lines.first.text, 'line $overflow');
      expect(lines.last.text, 'line ${cap + overflow - 1}');
    });

    test('counts each split line toward the cap', () {
      final t = Transcript();
      // A single multi-line add expands to one TranscriptLine per row.
      t.info('a\nb\nc');
      expect(t.lines.map((l) => l.text), ['a', 'b', 'c']);
    });

    test('revision advances on every add and on clear', () {
      final t = Transcript();
      final r0 = t.revision;
      t.info('x');
      final r1 = t.revision;
      expect(r1, greaterThan(r0));
      t.clear();
      expect(t.revision, greaterThan(r1));
      expect(t.lines, isEmpty);
    });

    test('stays bounded under sustained appends well past the cap', () {
      final t = Transcript();
      for (var i = 0; i < 30000; i++) {
        t.info('msg $i');
      }
      expect(t.lines.length, 10000);
      expect(t.lines.last.text, 'msg 29999');
    });
  });
}
