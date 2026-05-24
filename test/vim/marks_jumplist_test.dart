import 'package:frun/src/tui/vim/jumplist.dart';
import 'package:frun/src/tui/vim/marks.dart';
import 'package:frun/src/tui/vim/vim_buffer.dart';
import 'package:test/test.dart';

void main() {
  group('MarkBank', () {
    test('local marks are surface-scoped', () {
      final m = MarkBank();
      m.set('a', 'input', const Pos(1, 2));
      m.set('a', 'transcript', const Pos(5, 0));
      expect(m.get('a', 'input')!.pos, const Pos(1, 2));
      expect(m.get('a', 'transcript')!.pos, const Pos(5, 0));
    });

    test('uppercase marks are global', () {
      final m = MarkBank();
      m.set('Z', 'input', const Pos(7, 1));
      expect(m.get('Z', 'transcript')!.surfaceId, 'input');
    });
  });

  group('JumpList', () {
    test('back/forward navigate history', () {
      final j = JumpList();
      j.push('input', const Pos(0, 0));
      j.push('input', const Pos(5, 0));
      j.push('input', const Pos(10, 0));
      expect(j.back()!.pos, const Pos(5, 0));
      expect(j.back()!.pos, const Pos(0, 0));
      expect(j.forward()!.pos, const Pos(5, 0));
    });

    test('push after back truncates the newer side', () {
      final j = JumpList();
      j.push('input', const Pos(0, 0));
      j.push('input', const Pos(5, 0));
      j.push('input', const Pos(10, 0));
      j.back();
      j.back();
      j.push('input', const Pos(20, 0));
      expect(j.forward(), isNull); // last is the new push
      expect(j.back()!.pos, const Pos(0, 0));
    });
  });
}
