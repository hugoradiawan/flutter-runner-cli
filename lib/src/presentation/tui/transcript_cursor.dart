import 'vim/vim_buffer.dart';
import 'vim/vim_mode.dart';

class SearchMatch {
  const SearchMatch({
    required this.row,
    required this.col,
    required this.length,
  });
  final int row;
  final int col;
  final int length;
}

/// Visual cursor + selection + search state overlaid on the transcript when
/// the user is in vim mode and has popped out of the input line. Implements
/// [VimBuffer] (read-only) so the shared `VimEngine` can drive motions, yank,
/// search, marks, etc.
///
/// Row/col are *display-row* coordinates (post soft-wrap). The renderer keeps
/// the row list fresh and exposes it through [rowsProvider].
class TranscriptCursor extends VimBuffer {
  TranscriptCursor({required this.rowsProvider});

  /// Returns the list of display-row strings at paint time. Owned by the
  /// renderer; this buffer reads through it for every motion/operator call.
  final List<String> Function() rowsProvider;

  @override
  final String surfaceId = 'transcript';

  @override
  bool get isEditable => false;

  @override
  bool get isMultiLine => true;

  /// Active while the user is navigating the transcript with vim motions.
  /// When false, all other fields are dormant.
  bool active = false;

  Pos _cursor = const Pos(0, 0);
  Range? _selection;
  VimMode _visualKind = VimMode.normal;

  /// True between `/` / `?` and `Enter` — the input controller is bound to
  /// the search prompt instead of the command line.
  bool searchPromptOpen = false;

  /// Last-submitted search query. Empty string = no active search.
  String searchQuery = '';

  /// All match positions in display-row coordinates, recomputed whenever the
  /// scroll position or query changes.
  List<SearchMatch> matches = const [];

  /// Index into [matches] of the currently-highlighted match.
  int activeMatchIndex = -1;

  bool get hasSelection => _selection != null;

  void enter({required int initialRow, required int initialCol}) {
    active = true;
    _cursor = Pos(initialRow, initialCol);
    _selection = null;
    _visualKind = VimMode.normal;
  }

  void exit() {
    active = false;
    _selection = null;
    _visualKind = VimMode.normal;
    searchPromptOpen = false;
  }

  /// Compatibility helpers for renderer that still thinks in raw row/col.
  int get row => _cursor.row;
  int get col => _cursor.col;
  set row(int v) => _cursor = Pos(v, _cursor.col);
  set col(int v) => _cursor = Pos(_cursor.row, v);

  int? get anchorRow => _selection?.start.row;
  int? get anchorCol => _selection?.start.col;
  set anchorRow(int? v) {
    if (v == null) {
      _selection = null;
    } else {
      _selection = Range(
        Pos(v, _selection?.start.col ?? 0),
        _cursor,
        _selection?.kind ?? RangeKind.charwise,
      );
    }
  }

  set anchorCol(int? v) {
    if (v == null) {
      _selection = null;
    } else if (_selection != null) {
      _selection = Range(
        Pos(_selection!.start.row, v),
        _cursor,
        _selection!.kind,
      );
    }
  }

  void toggleSelection() {
    if (_selection != null) {
      _selection = null;
    } else {
      _selection = Range(_cursor, _cursor, RangeKind.charwise);
    }
  }

  /// Returns the inclusive (row, col) ordered pair: top-left first, bottom-right second.
  ({int row, int col, int row2, int col2})? selectionRange() {
    final s = _selection;
    if (s == null) return null;
    final norm = s.normalized();
    return (
      row: norm.start.row,
      col: norm.start.col,
      row2: norm.end.row,
      col2: norm.end.col,
    );
  }

  // ── VimBuffer surface ────────────────────────────────────────────────────

  @override
  int get lineCount => rowsProvider().length;

  @override
  String lineAt(int row) {
    final rows = rowsProvider();
    return (row >= 0 && row < rows.length) ? rows[row] : '';
  }

  @override
  Pos get cursor => _cursor;

  @override
  set cursor(Pos p) {
    final rows = rowsProvider();
    if (rows.isEmpty) {
      _cursor = const Pos(0, 0);
      return;
    }
    final r = p.row.clamp(0, rows.length - 1);
    final line = rows[r];
    final maxCol = line.isEmpty ? 0 : line.length - 1;
    _cursor = Pos(r, p.col.clamp(0, maxCol));
  }

  @override
  void replaceRange(Range r, String text, RangeKind kind) {
    // Read-only buffer.
  }

  @override
  String textInRange(Range r) {
    final rows = rowsProvider();
    if (rows.isEmpty) return '';
    final norm = r.normalized();
    if (norm.kind == RangeKind.linewise) {
      final out = <String>[];
      for (var i = norm.start.row; i <= norm.end.row && i < rows.length; i++) {
        out.add(rows[i]);
      }
      return out.join('\n');
    }
    if (norm.kind == RangeKind.charwise) {
      if (norm.start.row == norm.end.row) {
        final line = rows[norm.start.row];
        final endExclusive = (norm.end.col + 1).clamp(0, line.length);
        return line.substring(norm.start.col, endExclusive);
      }
      final buf = StringBuffer();
      for (var i = norm.start.row; i <= norm.end.row && i < rows.length; i++) {
        final line = rows[i];
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
    // Blockwise.
    final left = norm.start.col;
    final right = norm.end.col;
    final out = <String>[];
    for (var i = norm.start.row; i <= norm.end.row && i < rows.length; i++) {
      final line = rows[i];
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
    // Read-only buffer.
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
    // Transcript is read-only; "i" exits cursor mode back to input line.
    exit();
  }

  @override
  void exitInsertMode() {}

  @override
  void onModeChanged(VimMode mode) {
    if (mode == VimMode.visualChar ||
        mode == VimMode.visualLine ||
        mode == VimMode.visualBlock) {
      _visualKind = mode;
    } else if (mode == VimMode.normal) {
      _visualKind = VimMode.normal;
    }
  }

  @override
  bool tryCommandSubmit() => false;
}
