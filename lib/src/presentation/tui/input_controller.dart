import 'package:dart_tui/dart_tui.dart';

import '../../domain/value_objects/config_values.dart';
import 'vim/vim_buffer.dart';
import 'vim/vim_mode.dart';

/// What [InputController.insertKey] reports back so the engine can ask whether
/// a buffer wants to consume an Enter as "submit".
enum InputAction { none, submit }

/// Multi-line text buffer for the command prompt. Implements [VimBuffer] so
/// the shared `VimEngine` can drive it.
///
/// In `FrunEditorMode.normal`, the buffer always stays in `VimMode.insert`.
/// In `FrunEditorMode.vim`, Esc puts the engine into normal mode and from
/// there motions/operators apply.
class InputController extends VimBuffer {
  InputController({required FrunEditorMode editorMode})
      : _editorMode = editorMode {
    _mode = VimMode.insert;
  }

  @override
  final String surfaceId = 'input';

  @override
  bool get isEditable => true;

  @override
  bool get isMultiLine => true;

  // ── Buffer storage ───────────────────────────────────────────────────────

  List<String> _lines = <String>[''];
  Pos _cursor = const Pos(0, 0);

  // ── Undo / redo history ──────────────────────────────────────────────────

  final List<_Snap> _undoStack = <_Snap>[];
  final List<_Snap> _redoStack = <_Snap>[];
  static const int _maxHistory = 200;

  // ── Command history ──────────────────────────────────────────────────────

  final List<String> _cmdHistory = <String>[];
  int _historyIndex = -1;
  String _historySaved = '';
  static const int _maxCmdHistory = 500;

  // ── Mode + config ────────────────────────────────────────────────────────

  late VimMode _mode;
  FrunEditorMode _editorMode;
  VimMode _visualKind = VimMode.normal;
  Range? _selection;

  // ── Compat accessors used by paint/footer ────────────────────────────────

  String get text => _lines.join('\n');

  /// Flat character offset of the cursor in [text]. Used by the single-line
  /// footer hint; multi-line paint reads [Pos] directly via [cursor].
  int get cursorOffset {
    var n = 0;
    for (var r = 0; r < _cursor.row && r < _lines.length; r++) {
      n += _lines[r].length + 1; // +1 for the newline
    }
    return n + _cursor.col;
  }

  /// Read-only view of the buffer's lines.
  List<String> get lines => List<String>.unmodifiable(_lines);

  VimMode get mode => _mode;
  FrunEditorMode get editorMode => _editorMode;

  set editorMode(FrunEditorMode mode) {
    _editorMode = mode;
    if (mode == FrunEditorMode.normal) _mode = VimMode.insert;
  }

  /// True when typed runes should land in the buffer (insert/replace) rather
  /// than being eaten by the vim engine for navigation.
  bool get isInserting =>
      _editorMode == FrunEditorMode.normal ||
      _mode == VimMode.insert ||
      _mode == VimMode.replace;

  // ── Command history API ──────────────────────────────────────────────────

  List<String> get cmdHistory => List<String>.unmodifiable(_cmdHistory);

  void loadHistory(List<String> entries) {
    _cmdHistory
      ..clear()
      ..addAll(entries);
    if (_cmdHistory.length > _maxCmdHistory) {
      _cmdHistory.removeRange(0, _cmdHistory.length - _maxCmdHistory);
    }
  }

  void pushHistory(String cmd) {
    if (cmd.isEmpty) return;
    if (_cmdHistory.isNotEmpty && _cmdHistory.last == cmd) return;
    _cmdHistory.add(cmd);
    if (_cmdHistory.length > _maxCmdHistory) _cmdHistory.removeAt(0);
  }

  void resetHistoryNavigation() {
    _historyIndex = -1;
    _historySaved = '';
  }

  /// Navigate history. delta=-1 older (up), delta=+1 newer (down).
  /// Returns true when navigation occurred; caller should skip default handling.
  bool navigateHistory(int delta) {
    if (_cmdHistory.isEmpty) return false;
    if (_historyIndex == -1) {
      if (delta > 0) return false;
      _historySaved = text;
      _historyIndex = _cmdHistory.length - 1;
      setText(_cmdHistory[_historyIndex]);
      return true;
    }
    if (delta < 0) {
      if (_historyIndex > 0) _historyIndex--;
      setText(_cmdHistory[_historyIndex]);
      return true;
    }
    _historyIndex++;
    if (_historyIndex >= _cmdHistory.length) {
      _historyIndex = -1;
      setText(_historySaved);
      _historySaved = '';
      return true;
    }
    setText(_cmdHistory[_historyIndex]);
    return true;
  }

  // ── External buffer mutations (callable from button handlers) ────────────

  void clear() {
    _lines = <String>[''];
    _cursor = const Pos(0, 0);
    _selection = null;
  }

  void setText(String value) {
    _lines = value.isEmpty ? <String>[''] : value.split('\n');
    final last = _lines.length - 1;
    _cursor = Pos(last, _lines[last].length);
    _selection = null;
  }

  /// Removes the last [n] characters from the input buffer. Used by the
  /// modifier-arrow shim in case `dart_tui` ever needs it again.
  void removeLast(int n) {
    if (n <= 0) return;
    final joined = text;
    if (joined.isEmpty) return;
    final r = n.clamp(0, joined.length);
    setText(joined.substring(0, joined.length - r));
  }

  // ── Insert-mode key handler (engine routes here on passInsert) ───────────

  /// Apply [event] as an insert-mode key. Returns whether the buffer wants
  /// this Enter to act as a command submit (in which case the caller should
  /// invoke its submit hook instead of inserting a newline).
  InputAction insertKey(KeyMsg event) {
    final ke = event.keyEvent;
    final isCtrl = ke.modifiers.contains(KeyMod.ctrl);
    final isShift = ke.modifiers.contains(KeyMod.shift);

    switch (ke.code) {
      case KeyCode.enter:
        // Shift-Enter always inserts a newline. Plain Enter submits when the
        // buffer is single-line (preserves the "type /run + Enter" flow);
        // otherwise it inserts a newline.
        if (!isShift && _lines.length == 1) return InputAction.submit;
        _insertNewline();
      case KeyCode.backspace:
        _backspace();
      case KeyCode.delete:
        _forwardDelete();
      case KeyCode.left:
        _moveCol(-1);
      case KeyCode.right:
        _moveCol(1);
      case KeyCode.up:
        _moveRow(-1);
      case KeyCode.down:
        _moveRow(1);
      case KeyCode.home:
        _cursor = Pos(_cursor.row, 0);
      case KeyCode.end:
        _cursor = Pos(_cursor.row, _lines[_cursor.row].length);
      case KeyCode.rune:
        if (isCtrl) {
          final t = ke.text;
          if (t == 'a' || t == 'A') {
            _cursor = Pos(_cursor.row, 0);
          } else if (t == 'e' || t == 'E') {
            _cursor = Pos(_cursor.row, _lines[_cursor.row].length);
          } else if (t == 'u' || t == 'U') {
            final line = _lines[_cursor.row];
            _lines[_cursor.row] = line.substring(_cursor.col);
            _cursor = Pos(_cursor.row, 0);
          } else if (t == 'w' || t == 'W') {
            _deleteWordBackward();
          } else if (t == 'h' || t == 'H') {
            _backspace();
          } else if (t == 'j' || t == 'J') {
            _insertNewline();
          }
          break;
        }
        final ch = ke.text;
        if (ch.isNotEmpty && ch != '\n' && ch != '\r') {
          _insertText(ch);
        }
      case KeyCode.space:
        _insertText(' ');
      case KeyCode.tab:
        _insertText('  ');
      default:
        break;
    }
    return InputAction.none;
  }

  // ── Internal edits ───────────────────────────────────────────────────────

  void _insertText(String ch) {
    final line = _lines[_cursor.row];
    _lines[_cursor.row] =
        line.substring(0, _cursor.col) + ch + line.substring(_cursor.col);
    _cursor = Pos(_cursor.row, _cursor.col + ch.length);
  }

  void _insertNewline() {
    final line = _lines[_cursor.row];
    final left = line.substring(0, _cursor.col);
    final right = line.substring(_cursor.col);
    _lines[_cursor.row] = left;
    _lines.insert(_cursor.row + 1, right);
    _cursor = Pos(_cursor.row + 1, 0);
  }

  void _backspace() {
    if (_cursor.col > 0) {
      final line = _lines[_cursor.row];
      _lines[_cursor.row] =
          line.substring(0, _cursor.col - 1) + line.substring(_cursor.col);
      _cursor = Pos(_cursor.row, _cursor.col - 1);
      return;
    }
    if (_cursor.row == 0) return;
    final prev = _lines[_cursor.row - 1];
    final cur = _lines[_cursor.row];
    _lines[_cursor.row - 1] = prev + cur;
    _lines.removeAt(_cursor.row);
    _cursor = Pos(_cursor.row - 1, prev.length);
  }

  void _forwardDelete() {
    final line = _lines[_cursor.row];
    if (_cursor.col < line.length) {
      _lines[_cursor.row] =
          line.substring(0, _cursor.col) + line.substring(_cursor.col + 1);
      return;
    }
    if (_cursor.row + 1 < _lines.length) {
      final next = _lines[_cursor.row + 1];
      _lines[_cursor.row] = line + next;
      _lines.removeAt(_cursor.row + 1);
    }
  }

  void _deleteWordBackward() {
    if (_cursor.col == 0) {
      _backspace();
      return;
    }
    final line = _lines[_cursor.row];
    var i = _cursor.col;
    while (i > 0 && (line[i - 1] == ' ' || line[i - 1] == '\t')) {
      i--;
    }
    while (i > 0 && line[i - 1] != ' ' && line[i - 1] != '\t') {
      i--;
    }
    _lines[_cursor.row] = line.substring(0, i) + line.substring(_cursor.col);
    _cursor = Pos(_cursor.row, i);
  }

  void _moveCol(int delta) {
    final newCol = _cursor.col + delta;
    if (newCol >= 0 && newCol <= _lines[_cursor.row].length) {
      _cursor = Pos(_cursor.row, newCol);
      return;
    }
    if (delta < 0 && _cursor.row > 0) {
      _cursor = Pos(_cursor.row - 1, _lines[_cursor.row - 1].length);
    } else if (delta > 0 && _cursor.row + 1 < _lines.length) {
      _cursor = Pos(_cursor.row + 1, 0);
    }
  }

  void _moveRow(int delta) {
    final newRow = _cursor.row + delta;
    if (newRow < 0 || newRow >= _lines.length) return;
    final col = _cursor.col.clamp(0, _lines[newRow].length);
    _cursor = Pos(newRow, col);
  }

  Pos _clampPos(Pos p) {
    if (_lines.isEmpty) return const Pos(0, 0);
    final r = p.row.clamp(0, _lines.length - 1);
    final maxCol = _lines[r].length;
    final c = p.col.clamp(0, maxCol);
    return Pos(r, c);
  }

  // ── VimBuffer surface ────────────────────────────────────────────────────

  @override
  int get lineCount => _lines.length;

  @override
  String lineAt(int row) =>
      (row >= 0 && row < _lines.length) ? _lines[row] : '';

  @override
  Pos get cursor => _cursor;

  @override
  set cursor(Pos p) {
    _cursor = _clampPos(p);
  }

  @override
  void replaceRange(Range r, String text, RangeKind kind) {
    final norm = r.normalized();
    if (kind == RangeKind.linewise) {
      final startRow = norm.start.row.clamp(0, _lines.length - 1);
      final endRow = norm.end.row.clamp(0, _lines.length - 1);
      _lines.removeRange(startRow, endRow + 1);
      if (text.isNotEmpty) {
        final newLines = text.split('\n');
        if (newLines.isNotEmpty && newLines.last.isEmpty) {
          newLines.removeLast();
        }
        for (var i = newLines.length - 1; i >= 0; i--) {
          _lines.insert(startRow, newLines[i]);
        }
      }
      if (_lines.isEmpty) _lines.add('');
      _cursor = _clampPos(Pos(startRow, 0));
      return;
    }
    if (kind == RangeKind.charwise) {
      if (norm.start.row == norm.end.row) {
        final row = norm.start.row;
        final line = _lines[row];
        final endExclusive = (norm.end.col + 1).clamp(0, line.length);
        _lines[row] =
            line.substring(0, norm.start.col) + text + line.substring(endExclusive);
        _cursor = _clampPos(Pos(row, norm.start.col + text.length));
        return;
      }
      final startLine = _lines[norm.start.row];
      final endLine = _lines[norm.end.row];
      final head = startLine.substring(0, norm.start.col);
      final endExclusive = (norm.end.col + 1).clamp(0, endLine.length);
      final tail = endLine.substring(endExclusive);
      final replaced = (head + text + tail).split('\n');
      _lines.removeRange(norm.start.row, norm.end.row + 1);
      for (var i = replaced.length - 1; i >= 0; i--) {
        _lines.insert(norm.start.row, replaced[i]);
      }
      if (_lines.isEmpty) _lines.add('');
      _cursor = _clampPos(Pos(norm.start.row, norm.start.col + text.length));
      return;
    }
    // Blockwise: stripe the rectangle.
    final left = norm.start.col;
    final right = norm.end.col;
    final replacedLines = text.split('\n');
    for (var row = norm.start.row; row <= norm.end.row && row < _lines.length; row++) {
      final line = _lines[row];
      final padded = line.padRight(right + 1);
      final replacementForRow = (row - norm.start.row) < replacedLines.length
          ? replacedLines[row - norm.start.row]
          : '';
      _lines[row] = padded.substring(0, left) +
          replacementForRow +
          padded.substring((right + 1).clamp(0, padded.length));
    }
    _cursor = _clampPos(
        Pos(norm.start.row, left + (text.isEmpty ? 0 : text.length)));
  }

  @override
  String textInRange(Range r) {
    final norm = r.normalized();
    if (norm.kind == RangeKind.linewise) {
      final lines = <String>[];
      for (var i = norm.start.row;
          i <= norm.end.row && i < _lines.length;
          i++) {
        lines.add(_lines[i]);
      }
      return lines.join('\n');
    }
    if (norm.kind == RangeKind.charwise) {
      if (norm.start.row == norm.end.row) {
        final line = _lines[norm.start.row];
        final endExclusive = (norm.end.col + 1).clamp(0, line.length);
        return line.substring(norm.start.col, endExclusive);
      }
      final buf = StringBuffer();
      for (var i = norm.start.row;
          i <= norm.end.row && i < _lines.length;
          i++) {
        final line = _lines[i];
        if (i == norm.start.row) {
          buf.write(line.substring(norm.start.col));
        } else if (i == norm.end.row) {
          final endExclusive = (norm.end.col + 1).clamp(0, line.length);
          buf.write(line.substring(0, endExclusive));
        } else {
          buf.write(line);
        }
        if (i != norm.end.row) buf.write('\n');
      }
      return buf.toString();
    }
    final left = norm.start.col;
    final right = norm.end.col;
    final out = <String>[];
    for (var row = norm.start.row; row <= norm.end.row && row < _lines.length; row++) {
      final line = _lines[row];
      if (left >= line.length) {
        out.add('');
      } else {
        final endExclusive = (right + 1).clamp(0, line.length);
        out.add(line.substring(left, endExclusive));
      }
    }
    return out.join('\n');
  }

  @override
  void insertAt(Pos at, String text) {
    final p = _clampPos(at);
    if (text.isEmpty) return;
    if (!text.contains('\n')) {
      final line = _lines[p.row];
      _lines[p.row] = line.substring(0, p.col) + text + line.substring(p.col);
      _cursor = Pos(p.row, p.col + text.length);
      return;
    }
    final newLines = text.split('\n');
    final line = _lines[p.row];
    final head = line.substring(0, p.col);
    final tail = line.substring(p.col);
    _lines[p.row] = head + newLines.first;
    for (var i = 1; i < newLines.length; i++) {
      _lines.insert(p.row + i, newLines[i]);
    }
    final lastInsertedRow = p.row + newLines.length - 1;
    _lines[lastInsertedRow] = _lines[lastInsertedRow] + tail;
    _cursor = Pos(lastInsertedRow, newLines.last.length);
  }

  @override
  Range? get selection => _selection;
  @override
  set selection(Range? r) => _selection = r;

  @override
  VimMode get visualKind => _visualKind;
  @override
  set visualKind(VimMode m) => _visualKind = m;

  @override
  void enterInsertMode() {
    _mode = VimMode.insert;
  }

  @override
  void exitInsertMode() {
    _mode = VimMode.normal;
  }

  @override
  void onModeChanged(VimMode mode) {
    // The engine sets transient states (exCmd/search) we shouldn't latch.
    if (mode == VimMode.exCmd || mode == VimMode.search) return;
    _mode = mode;
  }

  @override
  bool tryCommandSubmit() => _lines.length == 1;

  @override
  void pushUndo() {
    _undoStack.add(_Snap(List<String>.from(_lines), _cursor));
    if (_undoStack.length > _maxHistory) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  @override
  bool undo() {
    if (_undoStack.isEmpty) return false;
    _redoStack.add(_Snap(List<String>.from(_lines), _cursor));
    final s = _undoStack.removeLast();
    _lines = List<String>.from(s.lines);
    if (_lines.isEmpty) _lines = <String>[''];
    _cursor = _clampPos(s.cursor);
    _selection = null;
    return true;
  }

  @override
  bool redo() {
    if (_redoStack.isEmpty) return false;
    _undoStack.add(_Snap(List<String>.from(_lines), _cursor));
    final s = _redoStack.removeLast();
    _lines = List<String>.from(s.lines);
    if (_lines.isEmpty) _lines = <String>[''];
    _cursor = _clampPos(s.cursor);
    _selection = null;
    return true;
  }
}

class _Snap {
  const _Snap(this.lines, this.cursor);
  final List<String> lines;
  final Pos cursor;
}
