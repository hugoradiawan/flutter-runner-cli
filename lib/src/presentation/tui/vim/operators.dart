import 'registers.dart';
import 'vim_buffer.dart';

/// All operators expressed as pure functions on (buffer, range, registers).
/// Engine routes `[count]{op}[motion]` and `[count]{op}{textObject}` here.
class Operators {
  /// Delete a range. For linewise, also removes the trailing newline.
  static void delete(VimBuffer b, Range r, RegisterBank regs,
      {String register = '"'}) {
    if (!b.isEditable) return;
    final norm = r.normalized();
    final text = b.textInRange(norm);
    regs.delete(text, norm.kind, name: register);
    b.replaceRange(norm, '', norm.kind);
    // Cursor lands on the start of the deleted range.
    b.cursor = norm.start;
  }

  /// Yank without mutation.
  static void yank(VimBuffer b, Range r, RegisterBank regs,
      {String register = '"'}) {
    final norm = r.normalized();
    final text = b.textInRange(norm);
    regs.yank(text, norm.kind, name: register);
  }

  /// Delete + enter insert mode (the engine flips mode after this returns).
  static void change(VimBuffer b, Range r, RegisterBank regs,
      {String register = '"'}) {
    delete(b, r, regs, register: register);
  }

  /// `r{ch}` — replace a single character at the cursor with [ch].
  static void replaceChar(VimBuffer b, String ch) {
    if (!b.isEditable) return;
    final p = b.cursor;
    final line = b.lineAt(p.row);
    if (p.col >= line.length) return;
    final r = Range(p, p, RangeKind.charwise);
    b.replaceRange(r, ch, RangeKind.charwise);
  }

  /// `~` — toggle case at the cursor (and advance).
  static void toggleCase(VimBuffer b, Range r) {
    if (!b.isEditable) return;
    final norm = r.normalized();
    final text = b.textInRange(norm);
    final swapped = StringBuffer();
    for (final cu in text.codeUnits) {
      if (cu >= 0x41 && cu <= 0x5A) {
        swapped.writeCharCode(cu + 32);
      } else if (cu >= 0x61 && cu <= 0x7A) {
        swapped.writeCharCode(cu - 32);
      } else {
        swapped.writeCharCode(cu);
      }
    }
    b.replaceRange(norm, swapped.toString(), norm.kind);
  }

  static void toLower(VimBuffer b, Range r) {
    if (!b.isEditable) return;
    final norm = r.normalized();
    final t = b.textInRange(norm);
    b.replaceRange(norm, t.toLowerCase(), norm.kind);
  }

  static void toUpper(VimBuffer b, Range r) {
    if (!b.isEditable) return;
    final norm = r.normalized();
    final t = b.textInRange(norm);
    b.replaceRange(norm, t.toUpperCase(), norm.kind);
  }

  /// `>` — indent each line in range by [shiftWidth] spaces.
  static void indent(VimBuffer b, Range r, int shiftWidth) {
    if (!b.isEditable) return;
    final norm = r.normalized();
    final pad = ' ' * shiftWidth;
    for (var row = norm.start.row; row <= norm.end.row; row++) {
      final line = b.lineAt(row);
      b.replaceRange(
          Range(Pos(row, 0), Pos(row, line.isEmpty ? 0 : line.length - 1),
              RangeKind.linewise),
          pad + line,
          RangeKind.linewise);
    }
  }

  /// `<` — dedent each line in range by up to [shiftWidth] leading spaces.
  static void dedent(VimBuffer b, Range r, int shiftWidth) {
    if (!b.isEditable) return;
    final norm = r.normalized();
    for (var row = norm.start.row; row <= norm.end.row; row++) {
      final line = b.lineAt(row);
      var strip = 0;
      while (strip < shiftWidth && strip < line.length && line[strip] == ' ') {
        strip++;
      }
      if (strip == 0) continue;
      b.replaceRange(
          Range(Pos(row, 0), Pos(row, line.isEmpty ? 0 : line.length - 1),
              RangeKind.linewise),
          line.substring(strip),
          RangeKind.linewise);
    }
  }

  /// `p` / `P` — paste from register.
  static void paste(VimBuffer b, RegisterEntry entry,
      {required bool before}) {
    if (!b.isEditable || entry.isEmpty) return;
    final p = b.cursor;
    if (entry.kind == RangeKind.linewise) {
      final insertRow = before ? p.row : p.row + 1;
      final text = entry.text.endsWith('\n') ? entry.text : '${entry.text}\n';
      // Implemented as: split current line at row boundary, insert new lines.
      b.insertAt(Pos(insertRow, 0), text);
      b.cursor = Pos(insertRow, b.firstNonBlankCol(insertRow));
      return;
    }
    if (entry.kind == RangeKind.blockwise) {
      // Stripe each yanked row as a column starting at the cursor.
      final rows = entry.text.split('\n');
      final col = before ? p.col : p.col + 1;
      for (var i = 0; i < rows.length; i++) {
        final targetRow = p.row + i;
        if (targetRow >= b.lineCount) break;
        final line = b.lineAt(targetRow);
        if (line.length < col) {
          // Pad with spaces up to insertion column.
          b.insertAt(Pos(targetRow, line.length), ' ' * (col - line.length));
        }
        b.insertAt(Pos(targetRow, col), rows[i]);
      }
      b.cursor = Pos(p.row, col);
      return;
    }
    final at = before ? p : Pos(p.row, p.col + 1);
    b.insertAt(at, entry.text);
    // Vim leaves the cursor on the last char of the pasted text.
    final lines = entry.text.split('\n');
    if (lines.length == 1) {
      b.cursor = Pos(at.row, at.col + entry.text.length - 1);
    } else {
      b.cursor = Pos(at.row + lines.length - 1, lines.last.length - 1);
    }
  }

  /// `J` — join the line below into the current one with a single space.
  static void joinLines(VimBuffer b, int count) {
    if (!b.isEditable) return;
    for (var i = 0; i < count; i++) {
      final r = b.cursor.row;
      if (r + 1 >= b.lineCount) return;
      final cur = b.lineAt(r);
      final next = b.lineAt(r + 1).trimLeft();
      final joined = cur.isEmpty || next.isEmpty ? cur + next : '$cur $next';
      // Range covers current line end + next line.
      b.replaceRange(
          Range(Pos(r, 0), Pos(r + 1, b.rowLength(r + 1)), RangeKind.linewise),
          joined,
          RangeKind.linewise);
      b.cursor = Pos(r, cur.length);
    }
  }
}
