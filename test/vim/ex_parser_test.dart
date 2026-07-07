import 'package:frun/src/presentation/tui/vim/ex_parser.dart';
import 'package:frun/src/presentation/tui/vim/vim_buffer.dart';
import 'package:test/test.dart';

void main() {
  group('ExParser', () {
    test('plain command', () {
      final c = ExParser.parse('q');
      expect(c!.name, 'q');
      expect(c.args, '');
      expect(c.bang, isFalse);
    });

    test('command with bang and args', () {
      final c = ExParser.parse('q! foo bar');
      expect(c!.name, 'q');
      expect(c.bang, isTrue);
      expect(c.args, 'foo bar');
    });

    test('substitute with global flag', () {
      final c = ExParser.parse('s/foo/bar/g');
      expect(c!.name, 's');
      expect(c.substitute!.pattern, 'foo');
      expect(c.substitute!.replacement, 'bar');
      expect(c.substitute!.global, isTrue);
    });

    test('substitute without flags', () {
      final c = ExParser.parse('s/foo/bar/');
      expect(c!.substitute!.flags, '');
      expect(c.substitute!.global, isFalse);
    });

    test('substitute with % range', () {
      final c = ExParser.parse('%s/foo/bar/g');
      expect(c!.name, 's');
      expect(c.rangeSpec, '%');
      expect(c.substitute!.pattern, 'foo');
    });

    test('alias maps q to /quit', () {
      expect(ExParser.toSlash('q'), 'quit');
      expect(ExParser.toSlash('qa'), 'quit');
      expect(ExParser.toSlash('wq'), 'quit');
      expect(ExParser.toSlash('reload'), 'reload');
    });

    test('numeric range spec is captured', () {
      final c = ExParser.parse('2,3s/a/b/');
      expect(c!.name, 's');
      expect(c.rangeSpec, '2,3');
    });
  });

  group('ExParser.resolveRange', () {
    (int, int)? resolve(
      String? spec, {
      int lineCount = 5,
      int cursorRow = 2,
      Pos? Function(String)? marks,
    }) => ExParser.resolveRange(
      spec,
      lineCount: lineCount,
      cursorRow: cursorRow,
      markLookup: marks,
    );

    test('null spec targets the cursor line only', () {
      expect(resolve(null), (2, 2));
    });

    test('% covers the whole buffer', () {
      expect(resolve('%'), (0, 4));
    });

    test('numeric range is 1-based inclusive', () {
      expect(resolve('2,3'), (1, 2));
    });

    test('. and \$ resolve to cursor and last line', () {
      expect(resolve(r'.,$'), (2, 4));
    });

    test('reversed bounds are normalized', () {
      expect(resolve('4,2'), (1, 3));
    });

    test('out-of-bounds rows clamp to the buffer', () {
      expect(resolve('1,99', lineCount: 3), (0, 2));
    });

    test("'<,'> resolves through the mark lookup", () {
      Pos? marks(String m) => switch (m) {
        '<' => const Pos(1, 0),
        '>' => const Pos(3, 4),
        _ => null,
      };
      expect(resolve("'<,'>", marks: marks), (1, 3));
    });

    test('missing mark yields null', () {
      expect(resolve("'a,'b", marks: (_) => null), isNull);
    });
  });
}
