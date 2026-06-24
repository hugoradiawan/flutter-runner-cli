import 'vim_buffer.dart';

class Mark {
  const Mark(this.surfaceId, this.pos);
  final String surfaceId;
  final Pos pos;
}

/// Per-engine mark store. Lowercase `a-z` are buffer-local (keyed by
/// `(surfaceId, name)`); uppercase `A-Z` are global (keyed by name only).
class MarkBank {
  final Map<String, Mark> _local = <String, Mark>{};
  final Map<String, Mark> _global = <String, Mark>{};

  void set(String name, String surfaceId, Pos pos) {
    if (name.isEmpty) return;
    if (_isUpper(name)) {
      _global[name] = Mark(surfaceId, pos);
    } else {
      _local['$surfaceId:$name'] = Mark(surfaceId, pos);
    }
  }

  Mark? get(String name, String surfaceId) {
    if (_isUpper(name)) return _global[name];
    return _local['$surfaceId:$name'];
  }

  bool _isUpper(String n) =>
      n.length == 1 && n.codeUnitAt(0) >= 0x41 && n.codeUnitAt(0) <= 0x5A;
}
