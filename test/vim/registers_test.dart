import 'package:frun/src/tui/vim/registers.dart';
import 'package:frun/src/tui/vim/vim_buffer.dart';
import 'package:test/test.dart';

void main() {
  group('RegisterBank', () {
    test('yank writes unnamed + 0', () {
      final r = RegisterBank(writer: (_) async => true, reader: () async => null);
      r.yank('hello', RangeKind.charwise);
      expect(r.read('"').text, 'hello');
      expect(r.read('0').text, 'hello');
    });

    test('delete rotates 1..9', () {
      final r = RegisterBank(writer: (_) async => true, reader: () async => null);
      r.delete('first', RangeKind.charwise);
      r.delete('second', RangeKind.charwise);
      r.delete('third', RangeKind.charwise);
      expect(r.read('1').text, 'third');
      expect(r.read('2').text, 'second');
      expect(r.read('3').text, 'first');
    });

    test('named uppercase appends', () {
      final r = RegisterBank(writer: (_) async => true, reader: () async => null);
      r.yank('foo', RangeKind.charwise, name: 'a');
      r.yank('bar', RangeKind.charwise, name: 'A');
      expect(r.read('a').text, 'foobar');
    });

    test('black-hole register discards', () {
      final r = RegisterBank(writer: (_) async => true, reader: () async => null);
      r.delete('gone', RangeKind.charwise, name: '_');
      expect(r.read('_').text, '');
      expect(r.read('0').text, '');
    });

    test('clipboard register writes through', () async {
      var captured = '';
      final r = RegisterBank(
        writer: (s) async {
          captured = s;
          return true;
        },
        reader: () async => 'pasted',
      );
      r.yank('zap', RangeKind.charwise, name: '+');
      await Future<void>.delayed(Duration.zero);
      expect(captured, 'zap');
      await r.refreshClipboard();
      expect(r.read('+').text, 'pasted');
    });
  });
}
