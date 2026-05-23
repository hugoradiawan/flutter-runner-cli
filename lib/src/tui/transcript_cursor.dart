/// Visual cursor + selection + search state overlaid on the transcript when
/// the user is in vim mode and has popped out of the input line (Esc on an
/// empty input). Lets the user position a caret on the log buffer, mark a
/// visual range, yank to the clipboard, and `/`-search for substrings.
class TranscriptCursor {
  /// Active while the user is navigating the transcript with vim motions.
  /// When false, all other fields are dormant.
  bool active = false;

  /// Cursor position in *display-row* coordinates (post-soft-wrap). The
  /// renderer maintains this; we just store it here so vim motions can
  /// update it between frames.
  int row = 0;
  int col = 0;

  /// Selection anchor. Non-null while the user is in visual mode (entered
  /// via `v`). The selected range is `[min(anchor, cursor), max(anchor, cursor)]`.
  int? anchorRow;
  int? anchorCol;

  /// True between `/` and `Enter` — the input controller is bound to the
  /// search prompt instead of the command line.
  bool searchPromptOpen = false;

  /// Last-submitted search query. Empty string = no active search.
  String searchQuery = '';

  /// All match positions in display-row coordinates, recomputed whenever the
  /// scroll position or query changes. Each entry is `(row, col, length)`.
  List<SearchMatch> matches = const [];

  /// Index into [matches] of the currently-highlighted match.
  int activeMatchIndex = -1;

  bool get hasSelection => anchorRow != null && anchorCol != null;

  void enter({required int initialRow, required int initialCol}) {
    active = true;
    row = initialRow;
    col = initialCol;
    anchorRow = null;
    anchorCol = null;
  }

  void exit() {
    active = false;
    anchorRow = null;
    anchorCol = null;
    searchPromptOpen = false;
  }

  void toggleSelection() {
    if (hasSelection) {
      anchorRow = null;
      anchorCol = null;
    } else {
      anchorRow = row;
      anchorCol = col;
    }
  }

  /// Returns the inclusive (row, col) ordered pair: top-left first, bottom-right second.
  ({int row, int col, int row2, int col2})? selectionRange() {
    if (!hasSelection) return null;
    final aRow = anchorRow!;
    final aCol = anchorCol!;
    if (aRow < row || (aRow == row && aCol <= col)) {
      return (row: aRow, col: aCol, row2: row, col2: col);
    }
    return (row: row, col: col, row2: aRow, col2: aCol);
  }
}

class SearchMatch {
  const SearchMatch({required this.row, required this.col, required this.length});
  final int row;
  final int col;
  final int length;
}
