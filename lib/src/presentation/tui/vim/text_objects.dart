import 'vim_buffer.dart';

/// `[A-Za-z0-9_]` membership without constructing a RegExp per character —
/// text objects call this for every character they walk past.
bool _isWordCh(String c) {
  if (c.isEmpty) return false;
  final u = c.codeUnitAt(0);
  return (u >= 0x61 && u <= 0x7a) || // a-z
      (u >= 0x41 && u <= 0x5a) || // A-Z
      (u >= 0x30 && u <= 0x39) || // 0-9
      u == 0x5f; // _
}

bool _isWORDCh(String c) => c.isNotEmpty && c != ' ' && c != '\t';

/// `[A-Za-z0-9]` on a single code unit (tag-name characters).
bool _isTagNameCh(int u) =>
    (u >= 0x61 && u <= 0x7a) ||
    (u >= 0x41 && u <= 0x5a) ||
    (u >= 0x30 && u <= 0x39);

/// Catalog of vim text objects. Each method returns a [Range] anchored at the
/// current cursor, or null if no object exists.
///
/// `inner: true` is the `i{X}` form (interior only). `inner: false` is `a{X}`
/// (interior + surrounding whitespace / delimiters).
class TextObjects {
  static Range? word(VimBuffer b, {required bool inner, bool bigWord = false}) {
    final r = b.cursor.row;
    final line = b.lineAt(r);
    if (line.isEmpty) return null;
    final c = b.cursor.col.clamp(0, line.length - 1);
    final isW = bigWord ? _isWORDCh : _isWordCh;
    int start;
    int end;
    if (isW(line[c])) {
      start = c;
      while (start > 0 && isW(line[start - 1])) {
        start--;
      }
      end = c;
      while (end + 1 < line.length && isW(line[end + 1])) {
        end++;
      }
    } else if (line[c] == ' ' || line[c] == '\t') {
      start = c;
      while (start > 0 && (line[start - 1] == ' ' || line[start - 1] == '\t')) {
        start--;
      }
      end = c;
      while (end + 1 < line.length &&
          (line[end + 1] == ' ' || line[end + 1] == '\t')) {
        end++;
      }
    } else {
      start = c;
      while (start > 0 &&
          !isW(line[start - 1]) &&
          line[start - 1] != ' ' &&
          line[start - 1] != '\t') {
        start--;
      }
      end = c;
      while (end + 1 < line.length &&
          !isW(line[end + 1]) &&
          line[end + 1] != ' ' &&
          line[end + 1] != '\t') {
        end++;
      }
    }
    if (!inner) {
      // Extend by trailing whitespace, else leading.
      var ex = end;
      while (ex + 1 < line.length &&
          (line[ex + 1] == ' ' || line[ex + 1] == '\t')) {
        ex++;
      }
      if (ex == end) {
        var sx = start;
        while (sx > 0 && (line[sx - 1] == ' ' || line[sx - 1] == '\t')) {
          sx--;
        }
        start = sx;
      } else {
        end = ex;
      }
    }
    return Range(Pos(r, start), Pos(r, end), RangeKind.charwise);
  }

  /// `i(` / `a(` and friends. Brackets must be on the same line for
  /// charwise scope, but we walk across lines for nesting depth.
  static Range? bracket(
    VimBuffer b,
    String open,
    String close, {
    required bool inner,
  }) {
    final cursor = b.cursor;
    // Scan backward for the unmatched `open`.
    Pos? openPos;
    var depth = 0;
    var r = cursor.row;
    var c = cursor.col;
    while (r >= 0) {
      final line = b.lineAt(r);
      while (c >= 0 && c < line.length) {
        final ch = line[c];
        if (ch == close && Pos(r, c) != cursor) {
          depth++;
        } else if (ch == open) {
          if (depth == 0) {
            openPos = Pos(r, c);
            break;
          }
          depth--;
        }
        c--;
      }
      if (openPos != null) break;
      r--;
      if (r < 0) break;
      c = b.rowLength(r) - 1;
    }
    if (openPos == null) return null;

    // Scan forward from openPos for matching close.
    Pos? closePos;
    depth = 0;
    r = openPos.row;
    c = openPos.col + 1;
    while (r < b.lineCount) {
      final line = b.lineAt(r);
      while (c < line.length) {
        final ch = line[c];
        if (ch == open) {
          depth++;
        } else if (ch == close) {
          if (depth == 0) {
            closePos = Pos(r, c);
            break;
          }
          depth--;
        }
        c++;
      }
      if (closePos != null) break;
      r++;
      c = 0;
    }
    if (closePos == null) return null;

    if (inner) {
      // Skip the open delimiter itself.
      final s = Pos(openPos.row, openPos.col + 1);
      var e = Pos(closePos.row, closePos.col - 1);
      if (e < s) e = s;
      return Range(s, e, RangeKind.charwise);
    }
    return Range(openPos, closePos, RangeKind.charwise);
  }

  /// `i"` / `a"` etc. Single-line only (mirrors vim).
  static Range? quote(VimBuffer b, String q, {required bool inner}) {
    final r = b.cursor.row;
    final line = b.lineAt(r);
    if (line.isEmpty) return null;
    final c = b.cursor.col.clamp(0, line.length - 1);
    // Find the two nearest quotes around c.
    var left = -1;
    for (var i = c; i >= 0; i--) {
      if (line[i] == q) {
        left = i;
        break;
      }
    }
    var right = -1;
    final searchFrom = left < c ? c : left + 1;
    for (var i = searchFrom; i < line.length; i++) {
      if (i == left) continue;
      if (line[i] == q) {
        right = i;
        break;
      }
    }
    if (left < 0 || right < 0) return null;
    if (inner) {
      if (right - left <= 1) {
        return Range(Pos(r, left + 1), Pos(r, left + 1), RangeKind.charwise);
      }
      return Range(Pos(r, left + 1), Pos(r, right - 1), RangeKind.charwise);
    }
    return Range(Pos(r, left), Pos(r, right), RangeKind.charwise);
  }

  /// `it` / `at` — XML/HTML tag block.
  static Range? tag(VimBuffer b, {required bool inner}) {
    final cursor = b.cursor;
    // Search backward for `<name…>`.
    Pos? openStart;
    Pos? openEnd;
    String? tagName;
    var r = cursor.row;
    var c = cursor.col;
    while (r >= 0) {
      final line = b.lineAt(r);
      while (c >= 0) {
        if (c < line.length &&
            line[c] == '<' &&
            c + 1 < line.length &&
            line[c + 1] != '/') {
          // parse tag name
          var j = c + 1;
          final nameStart = j;
          while (j < line.length && _isTagNameCh(line.codeUnitAt(j))) {
            j++;
          }
          if (j > nameStart) {
            // find closing >
            var k = j;
            while (k < line.length && line[k] != '>') {
              k++;
            }
            if (k < line.length) {
              tagName = line.substring(nameStart, j);
              openStart = Pos(r, c);
              openEnd = Pos(r, k);
              break;
            }
          }
        }
        c--;
      }
      if (openStart != null) break;
      r--;
      if (r < 0) break;
      c = b.rowLength(r) - 1;
    }
    if (openStart == null || openEnd == null || tagName == null) return null;

    // Search forward from openEnd for `</tagName>`.
    final closing = '</$tagName>';
    r = openEnd.row;
    c = openEnd.col + 1;
    Pos? closeStart;
    Pos? closeEnd;
    while (r < b.lineCount) {
      final line = b.lineAt(r);
      final idx = line.indexOf(closing, c);
      if (idx >= 0) {
        closeStart = Pos(r, idx);
        closeEnd = Pos(r, idx + closing.length - 1);
        break;
      }
      r++;
      c = 0;
    }
    if (closeStart == null || closeEnd == null) return null;

    if (inner) {
      return Range(
        Pos(openEnd.row, openEnd.col + 1),
        Pos(closeStart.row, closeStart.col - 1),
        RangeKind.charwise,
      );
    }
    return Range(openStart, closeEnd, RangeKind.charwise);
  }

  /// `ip` / `ap` — paragraph. Linewise.
  static Range? paragraph(VimBuffer b, {required bool inner}) {
    final cursor = b.cursor;
    if (b.lineCount == 0) return null;
    bool blank(int row) => b.lineAt(row).trim().isEmpty;
    var startRow = cursor.row;
    while (startRow > 0 && !blank(startRow - 1)) {
      startRow--;
    }
    var endRow = cursor.row;
    while (endRow + 1 < b.lineCount && !blank(endRow + 1)) {
      endRow++;
    }
    if (!inner) {
      while (endRow + 1 < b.lineCount && blank(endRow + 1)) {
        endRow++;
      }
    }
    return Range(
      Pos(startRow, 0),
      Pos(endRow, b.rowLength(endRow)),
      RangeKind.linewise,
    );
  }

  /// `is` / `as` — sentence. Best-effort: split on `.`, `!`, `?` + space.
  static Range? sentence(VimBuffer b, {required bool inner}) {
    final r = b.cursor.row;
    final line = b.lineAt(r);
    if (line.isEmpty) return null;
    final c = b.cursor.col.clamp(0, line.length - 1);
    var start = 0;
    for (var i = c - 1; i >= 0; i--) {
      if ((line[i] == '.' || line[i] == '!' || line[i] == '?') &&
          (i + 1 < line.length &&
              (line[i + 1] == ' ' || line[i + 1] == '\t'))) {
        start = i + 2;
        break;
      }
    }
    var end = line.length - 1;
    for (var i = c; i < line.length; i++) {
      if (line[i] == '.' || line[i] == '!' || line[i] == '?') {
        end = inner ? (i == 0 ? 0 : i - 1) : i;
        break;
      }
    }
    if (start > end) start = end;
    return Range(Pos(r, start), Pos(r, end), RangeKind.charwise);
  }
}
