import 'vim_buffer.dart';

class JumpEntry {
  const JumpEntry(this.surfaceId, this.pos);
  final String surfaceId;
  final Pos pos;
}

/// Bounded ring buffer with a cursor. `Ctrl-O` moves cursor older, `Ctrl-I`
/// moves it newer. New pushes truncate the "newer" side, matching vim.
class JumpList {
  JumpList({this.capacity = 100});
  final int capacity;
  final List<JumpEntry> _entries = <JumpEntry>[];
  int _cursor = -1;

  bool get isEmpty => _entries.isEmpty;

  /// Push a new jump. Truncates anything newer than the current cursor.
  void push(String surfaceId, Pos pos) {
    final last = _entries.isNotEmpty ? _entries.last : null;
    if (last != null && last.surfaceId == surfaceId && last.pos == pos) {
      _cursor = _entries.length - 1;
      return;
    }
    if (_cursor >= 0 && _cursor < _entries.length - 1) {
      _entries.removeRange(_cursor + 1, _entries.length);
    }
    _entries.add(JumpEntry(surfaceId, pos));
    if (_entries.length > capacity) _entries.removeAt(0);
    _cursor = _entries.length - 1;
  }

  JumpEntry? back() {
    if (_entries.isEmpty || _cursor <= 0) return null;
    _cursor--;
    return _entries[_cursor];
  }

  JumpEntry? forward() {
    if (_entries.isEmpty || _cursor >= _entries.length - 1) return null;
    _cursor++;
    return _entries[_cursor];
  }
}
