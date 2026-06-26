import 'package:frun/src/domain/value_objects/config_values.dart';
import 'package:frun/src/presentation/tui/input_controller.dart';
import 'package:frun/src/presentation/tui/vim/text_objects.dart';
import 'package:frun/src/presentation/tui/vim/vim_buffer.dart';
import 'package:test/test.dart';

InputController _buf(String text) {
  final c = InputController(editorMode: FrunEditorMode.vim);
  c.setText(text);
  return c;
}

void main() {
  group('TextObjects', () {
    test('iw on a word selects the whole word', () {
      final b = _buf('hello world');
      b.cursor = const Pos(0, 1);
      final r = TextObjects.word(b, inner: true);
      expect(r, isNotNull);
      expect(b.textInRange(r!), 'hello');
    });

    test('aw extends to trailing whitespace', () {
      final b = _buf('hello world');
      b.cursor = const Pos(0, 1);
      final r = TextObjects.word(b, inner: false);
      expect(b.textInRange(r!), 'hello ');
    });

    test('i( selects inside parens', () {
      final b = _buf('foo(bar)baz');
      b.cursor = const Pos(0, 5);
      final r = TextObjects.bracket(b, '(', ')', inner: true);
      expect(b.textInRange(r!), 'bar');
    });

    test('a( includes the parens', () {
      final b = _buf('foo(bar)baz');
      b.cursor = const Pos(0, 5);
      final r = TextObjects.bracket(b, '(', ')', inner: false);
      expect(b.textInRange(r!), '(bar)');
    });

    test('i" selects inside quotes', () {
      final b = _buf('say "hi"');
      b.cursor = const Pos(0, 5);
      final r = TextObjects.quote(b, '"', inner: true);
      expect(b.textInRange(r!), 'hi');
    });

    test('it selects inside tag', () {
      final b = _buf('<b>hi</b>');
      b.cursor = const Pos(0, 4);
      final r = TextObjects.tag(b, inner: true);
      expect(b.textInRange(r!), 'hi');
    });

    test('ip selects paragraph linewise', () {
      final b = _buf('a\nb\nc\n\nd\ne');
      b.cursor = const Pos(1, 0);
      final r = TextObjects.paragraph(b, inner: true);
      expect(r, isNotNull);
      expect(r!.kind, RangeKind.linewise);
      expect(r.start.row, 0);
      expect(r.end.row, 2);
    });
  });
}
