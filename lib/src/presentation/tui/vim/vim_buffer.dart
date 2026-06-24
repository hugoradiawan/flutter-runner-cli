import 'vim_mode.dart';

/// 0-based (row, col) inside a buffer's line grid.
class Pos {
  const Pos(this.row, this.col);
  final int row;
  final int col;

  Pos copyWith({int? row, int? col}) => Pos(row ?? this.row, col ?? this.col);

  bool operator <(Pos other) =>
      row < other.row || (row == other.row && col < other.col);
  bool operator <=(Pos other) =>
      row < other.row || (row == other.row && col <= other.col);
  bool operator >(Pos other) =>
      row > other.row || (row == other.row && col > other.col);
  bool operator >=(Pos other) =>
      row > other.row || (row == other.row && col >= other.col);

  @override
  bool operator ==(Object other) =>
      other is Pos && other.row == row && other.col == col;
  @override
  int get hashCode => Object.hash(row, col);

  @override
  String toString() => '($row,$col)';
}

/// Whether a [Range] was produced by a charwise, linewise, or blockwise op.
/// Determines how `p`/`P` paste the contents.
enum RangeKind { charwise, linewise, blockwise }

/// Inclusive range expressed as a (start, end, kind) tuple. For linewise,
/// `col` is ignored. For blockwise, the rectangle is `[start.row..end.row] x
/// [start.col..end.col]`.
class Range {
  const Range(this.start, this.end, this.kind);
  final Pos start;
  final Pos end;
  final RangeKind kind;

  Range normalized() {
    if (start <= end) return this;
    return Range(end, start, kind);
  }

  bool get isEmpty => start == end && kind != RangeKind.linewise;

  @override
  String toString() => '$start..$end [$kind]';
}

/// A surface the vim engine can act on. Read-only surfaces (transcript, tabs)
/// throw / no-op on the edit ops; the engine filters those operators out at
/// parse time, so callers should not invoke them on read-only buffers.
abstract class VimBuffer {
  String get surfaceId; // 'input', 'transcript', 'tabs'
  bool get isEditable;
  bool get isMultiLine;

  int get lineCount;
  String lineAt(int row);
  int rowLength(int row) => lineAt(row).length;

  Pos get cursor;
  set cursor(Pos p);

  /// Replace [r] with [text]. For linewise, [text] is a list of whole lines
  /// joined by `\n`. For blockwise, [text] has `\n`-separated rows aligned to
  /// the rectangle's columns.
  void replaceRange(Range r, String text, RangeKind kind);

  /// The text covered by [r] (read-only, no mutation).
  String textInRange(Range r);

  /// Insert raw text at the current cursor (used by `p`/`P` for charwise).
  void insertAt(Pos at, String text);

  /// Current visual selection, or null when not in a visual mode.
  Range? get selection;
  set selection(Range? r);

  /// The most recent visual kind (mirrors the engine's mode); used by paint.
  VimMode get visualKind;
  set visualKind(VimMode m);

  /// Lifecycle hooks the engine calls so the surface can update its own
  /// peripheral state (cursor shape, prompt char, etc.).
  void enterInsertMode();
  void exitInsertMode();
  void onModeChanged(VimMode mode);

  /// Submit hook (insert-mode Enter on a single-line buffer = "send command").
  /// Returns true if the buffer "consumed" the submit and the engine should
  /// stop processing; false if the engine should treat Enter as a no-op edit.
  bool tryCommandSubmit() => false;

  /// Capture current state for undo. Engine calls this before any mutating
  /// command in normal/visual mode and before entering insert sessions.
  /// Read-only buffers no-op.
  void pushUndo() {}

  /// Pop the previous state from the undo stack and apply it; current state
  /// is pushed to redo. Returns true if a snapshot was popped.
  bool undo() => false;

  /// Inverse of [undo]. Returns true if a snapshot was popped.
  bool redo() => false;

  /// Where `gg` / `G` should land for `^` (first non-blank col on row).
  int firstNonBlankCol(int row) {
    final s = lineAt(row);
    for (var i = 0; i < s.length; i++) {
      final ch = s.codeUnitAt(i);
      if (ch != 0x20 && ch != 0x09) return i;
    }
    return 0;
  }
}
