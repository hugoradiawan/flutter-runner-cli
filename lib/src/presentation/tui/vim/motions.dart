import 'vim_buffer.dart';

/// Result of resolving a motion. [target] is where the cursor lands. [kind]
/// hints how an operator should interpret the range; [exclusive] flips
/// inclusive vs exclusive (vim's `w` is exclusive; `e` inclusive).
class MotionResult {
  const MotionResult(
    this.target, {
    this.kind = RangeKind.charwise,
    this.exclusive = true,
  });
  final Pos target;
  final RangeKind kind;
  final bool exclusive;
}

/// `[A-Za-z0-9_]` membership without constructing a RegExp per character —
/// word motions call this for every character they walk past, per keystroke.
bool _isWordCh(String c) {
  if (c.isEmpty) return false;
  final u = c.codeUnitAt(0);
  return (u >= 0x61 && u <= 0x7a) || // a-z
      (u >= 0x41 && u <= 0x5a) || // A-Z
      (u >= 0x30 && u <= 0x39) || // 0-9
      u == 0x5f; // _
}

bool _isWORDCh(String c) => c.isNotEmpty && c != ' ' && c != '\t';
bool _isSpace(String c) => c == ' ' || c == '\t';

class Motions {
  /// Move N chars right inside the current line.
  static MotionResult left(VimBuffer b, int n) {
    final c = b.cursor;
    final nc = (c.col - n).clamp(0, b.rowLength(c.row));
    return MotionResult(Pos(c.row, nc));
  }

  static MotionResult right(VimBuffer b, int n) {
    final c = b.cursor;
    final len = b.rowLength(c.row);
    final maxCol = len == 0 ? 0 : len - 1;
    final nc = (c.col + n).clamp(0, maxCol);
    return MotionResult(Pos(c.row, nc));
  }

  /// [wantCol] is vim's curswant: the column j/k aim for even when passing
  /// through shorter lines.
  static MotionResult down(VimBuffer b, int n, {int? wantCol}) {
    final c = b.cursor;
    final nr = (c.row + n).clamp(0, (b.lineCount - 1).clamp(0, 1 << 30));
    final len = b.rowLength(nr);
    return MotionResult(
      Pos(nr, (wantCol ?? c.col).clamp(0, (len - 1).clamp(0, 1 << 30))),
      kind: RangeKind.linewise,
    );
  }

  static MotionResult up(VimBuffer b, int n, {int? wantCol}) {
    final c = b.cursor;
    final nr = (c.row - n).clamp(0, (b.lineCount - 1).clamp(0, 1 << 30));
    final len = b.rowLength(nr);
    return MotionResult(
      Pos(nr, (wantCol ?? c.col).clamp(0, (len - 1).clamp(0, 1 << 30))),
      kind: RangeKind.linewise,
    );
  }

  static MotionResult lineStart(VimBuffer b) =>
      MotionResult(Pos(b.cursor.row, 0));

  static MotionResult firstNonBlank(VimBuffer b) =>
      MotionResult(Pos(b.cursor.row, b.firstNonBlankCol(b.cursor.row)));

  static MotionResult lineEnd(VimBuffer b) {
    final r = b.cursor.row;
    final len = b.rowLength(r);
    return MotionResult(Pos(r, len == 0 ? 0 : len - 1), exclusive: false);
  }

  static MotionResult lastNonBlank(VimBuffer b) {
    final r = b.cursor.row;
    final s = b.lineAt(r);
    for (var i = s.length - 1; i >= 0; i--) {
      if (!_isSpace(s[i])) return MotionResult(Pos(r, i), exclusive: false);
    }
    return MotionResult(Pos(r, 0));
  }

  /// `w` — to start of next word. `bigWord` for `W`.
  static MotionResult nextWordStart(
    VimBuffer b,
    int n, {
    bool bigWord = false,
  }) {
    var p = b.cursor;
    final isW = bigWord ? _isWORDCh : _isWordCh;
    for (var i = 0; i < n; i++) {
      p = _advanceWordStart(b, p, isW);
    }
    return MotionResult(p);
  }

  static Pos _advanceWordStart(
    VimBuffer b,
    Pos from,
    bool Function(String) isW,
  ) {
    var row = from.row;
    var col = from.col;
    while (row < b.lineCount) {
      final line = b.lineAt(row);
      if (col >= line.length) {
        if (row == b.lineCount - 1) {
          return Pos(row, line.isEmpty ? 0 : line.length - 1);
        }
        row++;
        col = 0;
        // empty line counts as a word boundary stop
        if (b.lineAt(row).isEmpty) return Pos(row, 0);
        continue;
      }
      final inWord = isW(line[col]);
      // Skip current word chars.
      if (inWord) {
        while (col < line.length && isW(line[col])) {
          col++;
        }
      } else if (_isSpace(line[col])) {
        // skip whitespace
      } else {
        // punctuation cluster — counts as a word; skip to next non-punct
        while (col < line.length && !isW(line[col]) && !_isSpace(line[col])) {
          col++;
        }
      }
      // Skip whitespace.
      while (col < line.length && _isSpace(line[col])) {
        col++;
      }
      if (col < line.length) return Pos(row, col);
      if (row == b.lineCount - 1) {
        return Pos(row, line.isEmpty ? 0 : line.length - 1);
      }
      row++;
      col = 0;
      if (b.lineAt(row).isEmpty) return Pos(row, 0);
    }
    return from;
  }

  /// `e` — to end of current/next word.
  static MotionResult wordEnd(VimBuffer b, int n, {bool bigWord = false}) {
    var p = b.cursor;
    final isW = bigWord ? _isWORDCh : _isWordCh;
    for (var i = 0; i < n; i++) {
      p = _advanceWordEnd(b, p, isW);
    }
    return MotionResult(p, exclusive: false);
  }

  static Pos _advanceWordEnd(VimBuffer b, Pos from, bool Function(String) isW) {
    var row = from.row;
    var col = from.col;
    while (row < b.lineCount) {
      var line = b.lineAt(row);
      // Step forward at least one cell, then run until end of word.
      if (col + 1 < line.length) {
        col++;
      } else {
        if (row == b.lineCount - 1) {
          return Pos(row, line.isEmpty ? 0 : line.length - 1);
        }
        row++;
        col = 0;
        line = b.lineAt(row);
        if (line.isEmpty) return Pos(row, 0);
      }
      // Skip whitespace.
      while (col < line.length && _isSpace(line[col])) {
        col++;
      }
      if (col >= line.length) continue;
      final inWord = isW(line[col]);
      if (inWord) {
        while (col + 1 < line.length && isW(line[col + 1])) {
          col++;
        }
      } else {
        while (col + 1 < line.length &&
            !isW(line[col + 1]) &&
            !_isSpace(line[col + 1])) {
          col++;
        }
      }
      return Pos(row, col);
    }
    return from;
  }

  /// `b` — to start of previous word.
  static MotionResult prevWordStart(
    VimBuffer b,
    int n, {
    bool bigWord = false,
  }) {
    var p = b.cursor;
    final isW = bigWord ? _isWORDCh : _isWordCh;
    for (var i = 0; i < n; i++) {
      p = _retreatWordStart(b, p, isW);
    }
    return MotionResult(p);
  }

  static Pos _retreatWordStart(
    VimBuffer b,
    Pos from,
    bool Function(String) isW,
  ) {
    var row = from.row;
    var col = from.col;
    while (true) {
      if (col == 0) {
        if (row == 0) return const Pos(0, 0);
        row--;
        final prev = b.lineAt(row);
        col = prev.isEmpty ? 0 : prev.length - 1;
        if (prev.isEmpty) return Pos(row, 0);
      } else {
        col--;
      }
      final line = b.lineAt(row);
      if (line.isEmpty) return Pos(row, 0);
      // Skip whitespace backwards.
      while (col > 0 && _isSpace(line[col])) {
        col--;
      }
      if (_isSpace(line[col])) continue;
      final inWord = isW(line[col]);
      if (inWord) {
        while (col > 0 && isW(line[col - 1])) {
          col--;
        }
      } else {
        while (col > 0 && !isW(line[col - 1]) && !_isSpace(line[col - 1])) {
          col--;
        }
      }
      return Pos(row, col);
    }
  }

  /// `ge` — to end of previous word.
  static MotionResult prevWordEnd(VimBuffer b, int n, {bool bigWord = false}) {
    var p = b.cursor;
    final isW = bigWord ? _isWORDCh : _isWordCh;
    for (var i = 0; i < n; i++) {
      p = _retreatWordEnd(b, p, isW);
    }
    return MotionResult(p, exclusive: false);
  }

  static Pos _retreatWordEnd(VimBuffer b, Pos from, bool Function(String) isW) {
    var row = from.row;
    var col = from.col;
    while (true) {
      if (col == 0) {
        if (row == 0) return const Pos(0, 0);
        row--;
        final prev = b.lineAt(row);
        col = prev.isEmpty ? 0 : prev.length - 1;
        if (prev.isEmpty) return Pos(row, 0);
        return Pos(row, col);
      }
      col--;
      final line = b.lineAt(row);
      while (col > 0 && _isSpace(line[col])) {
        col--;
      }
      if (!_isSpace(line[col])) return Pos(row, col);
    }
  }

  /// `gg` — to first line, first non-blank.
  static MotionResult firstLine(VimBuffer b) {
    return MotionResult(
      Pos(0, b.firstNonBlankCol(0)),
      kind: RangeKind.linewise,
    );
  }

  /// `G` (no count) — last line, first non-blank. With count `nG` → line n-1.
  static MotionResult goLine(VimBuffer b, int? n) {
    final row = n == null ? b.lineCount - 1 : (n - 1).clamp(0, b.lineCount - 1);
    return MotionResult(
      Pos(row, b.firstNonBlankCol(row)),
      kind: RangeKind.linewise,
    );
  }

  /// `f{ch}` — forward to nth occurrence of ch on current line.
  static MotionResult findChar(
    VimBuffer b,
    String ch,
    int n, {
    required bool forward,
    required bool till,
  }) {
    final r = b.cursor.row;
    final line = b.lineAt(r);
    var col = b.cursor.col;
    var hits = 0;
    if (forward) {
      var i = col + 1;
      while (i < line.length) {
        if (line[i] == ch) {
          hits++;
          if (hits == n) {
            col = till ? i - 1 : i;
            break;
          }
        }
        i++;
      }
    } else {
      var i = col - 1;
      while (i >= 0) {
        if (line[i] == ch) {
          hits++;
          if (hits == n) {
            col = till ? i + 1 : i;
            break;
          }
        }
        i--;
      }
    }
    // f/t are inclusive motions; F/T are exclusive (dFx must not delete the
    // char under the cursor).
    return MotionResult(Pos(r, col), exclusive: !forward);
  }

  /// `%` — jump to matching bracket.
  static MotionResult matchBracket(VimBuffer b) {
    final r = b.cursor.row;
    final line = b.lineAt(r);
    if (line.isEmpty) return MotionResult(b.cursor);
    // Find first bracket from cursor.
    const pairs = '()[]{}<>';
    var col = b.cursor.col;
    while (col < line.length && !pairs.contains(line[col])) {
      col++;
    }
    if (col >= line.length) return MotionResult(b.cursor);
    final open = line[col];
    final idx = pairs.indexOf(open);
    final isOpen = idx.isEven;
    final mate = pairs[isOpen ? idx + 1 : idx - 1];
    final dir = isOpen ? 1 : -1;
    var row = r;
    var c = col + dir;
    var depth = 1;
    while (row >= 0 && row < b.lineCount) {
      final ln = b.lineAt(row);
      while (c >= 0 && c < ln.length) {
        if (ln[c] == open) {
          depth++;
        } else if (ln[c] == mate) {
          depth--;
          if (depth == 0) return MotionResult(Pos(row, c), exclusive: false);
        }
        c += dir;
      }
      row += dir;
      if (row < 0 || row >= b.lineCount) break;
      c = dir > 0 ? 0 : b.rowLength(row) - 1;
    }
    return MotionResult(b.cursor);
  }

  /// `{` / `}` — paragraph boundaries (blank-line separated).
  static MotionResult paragraph(VimBuffer b, int n, {required bool forward}) {
    var row = b.cursor.row;
    final dir = forward ? 1 : -1;
    var remaining = n;
    while (remaining > 0) {
      row += dir;
      while (row >= 0 && row < b.lineCount && b.lineAt(row).trim().isNotEmpty) {
        row += dir;
      }
      if (row < 0) row = 0;
      if (row >= b.lineCount) row = b.lineCount - 1;
      remaining--;
      if (row == 0 || row == b.lineCount - 1) break;
    }
    return MotionResult(Pos(row, 0), kind: RangeKind.linewise);
  }

  /// The `[A-Za-z0-9_]` word under the cursor (scanning forward when the
  /// cursor sits on whitespace/punctuation, like vim's `*`).
  static String? wordUnderCursor(VimBuffer b) {
    final line = b.lineAt(b.cursor.row);
    if (line.isEmpty) return null;
    var col = b.cursor.col.clamp(0, line.length - 1);
    while (col < line.length && !_isWordCh(line[col])) {
      col++;
    }
    if (col >= line.length) return null;
    var start = col;
    while (start > 0 && _isWordCh(line[start - 1])) {
      start--;
    }
    var end = col;
    while (end + 1 < line.length && _isWordCh(line[end + 1])) {
      end++;
    }
    return line.substring(start, end + 1);
  }

  /// `H` / `M` / `L` — screen-relative positions. Caller provides viewport.
  /// `{count}H` lands count-1 lines below the top; `{count}L` above bottom.
  static MotionResult viewportTop(
    VimBuffer b,
    int viewportTop, [
    int count = 1,
  ]) => MotionResult(
    Pos((viewportTop + count - 1).clamp(0, b.lineCount - 1), 0),
    kind: RangeKind.linewise,
  );

  static MotionResult viewportMiddle(
    VimBuffer b,
    int viewportTop,
    int viewportHeight,
  ) {
    final mid = (viewportTop + viewportHeight ~/ 2).clamp(0, b.lineCount - 1);
    return MotionResult(Pos(mid, 0), kind: RangeKind.linewise);
  }

  static MotionResult viewportBottom(
    VimBuffer b,
    int viewportTop,
    int viewportHeight, [
    int count = 1,
  ]) {
    final bot = (viewportTop + viewportHeight - count).clamp(
      0,
      b.lineCount - 1,
    );
    return MotionResult(Pos(bot, 0), kind: RangeKind.linewise);
  }
}
