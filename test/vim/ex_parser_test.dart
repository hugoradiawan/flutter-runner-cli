import 'package:frun/src/presentation/tui/vim/ex_parser.dart';
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
  });
}
