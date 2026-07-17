part of 'vim_engine.dart';

/// Operator plumbing: motions-as-ranges, text objects, visual operators.
extension _VimOperate on VimEngine {
  bool _isDoubledOperatorKey(String ch) {
    final op = _state.pendingOperator;
    if (op.isEmpty) return false;
    if (ch == op) return true; // dd yy cc >> << ==
    if (op.length == 2 && ch == op[1]) return true; // guu gUU
    if (op == '~' && ch == '~') return true; // g~~
    return false;
  }

  /// `{opCount}dd`-style linewise application; count is the product of the
  /// operator count and the doubled key's count (`2d3d` = 6 lines).
  void _applyDoubledOperator(VimBuffer buffer, String reg) {
    final op = _state.pendingOperator;
    final count = _effectiveCount(_state.pendingCount);
    if (!buffer.isEditable && op != 'y') {
      _state.clearPending();
      return;
    }
    _applyLinewiseOperator(buffer, op, count, reg);
    if (op != 'y') {
      _state.lastAction
        ..clear()
        ..kind = LastActionKind.operatorDouble
        ..operator = op
        ..count = count
        ..register = reg;
    }
    _state.clearPending();
  }

  int _effectiveCount(int motionCount) {
    final oc = _state.pendingOpCount == 0 ? 1 : _state.pendingOpCount;
    final mc = motionCount == 0 ? 1 : motionCount;
    return oc * mc;
  }

  /// Resolve a named motion to a target. [name] may be 2-char (`gg`, `ge`).
  /// [findCh] carries the f/t target char; [line] the explicit G/gg target.
  MotionResult? _namedMotion(
    String name,
    VimBuffer buffer,
    int count, {
    String findCh = '',
    int? line,
  }) {
    switch (name) {
      case 'h':
        return Motions.left(buffer, count);
      case 'l':
        return Motions.right(buffer, count);
      case 'j':
        return Motions.down(buffer, count, wantCol: _state.desiredCol);
      case 'k':
        return Motions.up(buffer, count, wantCol: _state.desiredCol);
      case 'w':
        return Motions.nextWordStart(buffer, count);
      case 'W':
        return Motions.nextWordStart(buffer, count, bigWord: true);
      case 'e':
        return Motions.wordEnd(buffer, count);
      case 'E':
        return Motions.wordEnd(buffer, count, bigWord: true);
      case 'b':
        return Motions.prevWordStart(buffer, count);
      case 'B':
        return Motions.prevWordStart(buffer, count, bigWord: true);
      case 'ge':
        return Motions.prevWordEnd(buffer, count);
      case 'gE':
        return Motions.prevWordEnd(buffer, count, bigWord: true);
      case '0':
        return Motions.lineStart(buffer);
      case '^':
        return Motions.firstNonBlank(buffer);
      case r'$':
        return Motions.lineEnd(buffer);
      case 'g_':
        return Motions.lastNonBlank(buffer);
      case '%':
        return Motions.matchBracket(buffer);
      case '{':
        return Motions.paragraph(buffer, count, forward: false);
      case '}':
        return Motions.paragraph(buffer, count, forward: true);
      case 'G':
        return Motions.goLine(buffer, line);
      case 'gg':
        return line == null
            ? Motions.firstLine(buffer)
            : Motions.goLine(buffer, line);
      case 'H':
        final vp = _viewport(buffer);
        return Motions.viewportTop(buffer, vp.top, count);
      case 'M':
        final vp = _viewport(buffer);
        return Motions.viewportMiddle(buffer, vp.top, vp.height);
      case 'L':
        final vp = _viewport(buffer);
        return Motions.viewportBottom(buffer, vp.top, vp.height, count);
      case 'f':
        return Motions.findChar(
          buffer,
          findCh,
          count,
          forward: true,
          till: false,
        );
      case 'F':
        return Motions.findChar(
          buffer,
          findCh,
          count,
          forward: false,
          till: false,
        );
      case 't':
        return Motions.findChar(
          buffer,
          findCh,
          count,
          forward: true,
          till: true,
        );
      case 'T':
        return Motions.findChar(
          buffer,
          findCh,
          count,
          forward: false,
          till: true,
        );
      case ';':
        final lf = _state.lastFind;
        if (lf == null) return null;
        return Motions.findChar(
          buffer,
          lf.ch,
          count,
          forward: lf.forward,
          till: lf.till,
        );
      case ',':
        final lf = _state.lastFind;
        if (lf == null) return null;
        return Motions.findChar(
          buffer,
          lf.ch,
          count,
          forward: !lf.forward,
          till: lf.till,
        );
      default:
        return null;
    }
  }

  /// Terminal handler for every motion key: computes the effective count,
  /// resolves the motion, and either moves/extends or feeds the pending
  /// operator. This is the single seam that makes `d`, `c`, `y`… work with
  /// every motion the engine knows.
  void _motionKey(VimBuffer buffer, String name, {String findCh = ''}) {
    final opPending = _state.pendingOperator.isNotEmpty;
    final motionCount = _state.pendingCount;
    _state.pendingCount = 0;

    // Curswant: j/k keep aiming for the column vertical movement started
    // at; any other motion resets it to the real cursor column.
    if (name == 'j' || name == 'k') {
      _state.desiredCol ??= buffer.cursor.col;
    } else {
      _state.desiredCol = null;
    }

    int count;
    int? line;
    if (name == 'G' || name == 'gg') {
      // Counts are a line target, not a multiplier (`d3G` → to line 3;
      // `2d3G` → line 6 per vim's count-multiplication rule).
      final oc = _state.pendingOpCount;
      line = (oc == 0 && motionCount == 0)
          ? null
          : (oc == 0 ? 1 : oc) * (motionCount == 0 ? 1 : motionCount);
      count = 1;
    } else {
      count = opPending
          ? _effectiveCount(motionCount)
          : (motionCount == 0 ? 1 : motionCount);
    }

    final MotionResult? motion;
    if (name == '%' && motionCount > 0) {
      // {count}% — jump to that percentage of the buffer, linewise.
      final row = ((motionCount * buffer.lineCount + 99) ~/ 100 - 1).clamp(
        0,
        buffer.lineCount - 1,
      );
      motion = MotionResult(
        Pos(row, buffer.firstNonBlankCol(row)),
        kind: RangeKind.linewise,
      );
    } else {
      motion = _namedMotion(name, buffer, count, findCh: findCh, line: line);
    }
    if (motion == null) {
      if (opPending) _state.clearPending();
      return;
    }
    // A find that doesn't move failed — abort the operator (vim beeps).
    const findNames = {'f', 'F', 't', 'T', ';', ','};
    if (findNames.contains(name) && motion.target == buffer.cursor) {
      if (opPending) _state.clearPending();
      return;
    }
    if (_jumpMotions.contains(name) && !opPending) {
      _state.jumps.push(buffer.surfaceId, buffer.cursor);
    }
    _applyMotionOrOperate(
      buffer,
      motion,
      dotMotion: name,
      findCh: findCh,
      usedCount: (name == 'G' || name == 'gg') ? (line ?? 0) : count,
    );
  }

  /// Apply a resolved motion: feed the pending operator if one is latched,
  /// otherwise move the cursor (extending the selection in visual modes).
  void _applyMotionOrOperate(
    VimBuffer buffer,
    MotionResult motion, {
    required String dotMotion,
    String findCh = '',
    int usedCount = 1,
  }) {
    final op = _state.pendingOperator;
    if (op.isEmpty || _isVisual()) {
      _applyMotion(buffer, motion);
      return;
    }
    if (!buffer.isEditable && op != 'y') {
      _state.clearPending();
      return;
    }
    final reg = _state.pendingRegister.length == 1
        ? _state.pendingRegister
        : '"';
    final range = _rangeFromMotion(buffer, buffer.cursor, motion);
    _runOperator(op, buffer, range, reg);
    if (op != 'y') {
      _state.lastAction
        ..clear()
        ..kind = LastActionKind.operatorMotion
        ..operator = op
        ..motion = dotMotion
        ..findCh = findCh
        ..motionCount = usedCount
        ..register = reg;
    }
    _state.clearPending();
  }

  /// The position one char before [p] (wrapping to the previous row's end).
  Pos _posBefore(VimBuffer buffer, Pos p) {
    if (p.col > 0) return Pos(p.row, p.col - 1);
    if (p.row > 0) {
      final len = buffer.rowLength(p.row - 1);
      return Pos(p.row - 1, len == 0 ? 0 : len - 1);
    }
    return p;
  }

  Range _rangeFromMotion(VimBuffer buffer, Pos from, MotionResult motion) {
    if (motion.kind == RangeKind.linewise) {
      return Range(
        Pos(from.row, 0),
        Pos(motion.target.row, 0),
        RangeKind.linewise,
      );
    }
    if (motion.exclusive) {
      final t = motion.target;
      if (t >= from) {
        // Forward exclusive: back the end off by one.
        return Range(
          from,
          Pos(t.row, (t.col - 1).clamp(0, 1 << 30)),
          RangeKind.charwise,
        );
      }
      // Backward exclusive: the cursor char itself is excluded (`db`, `dFx`
      // must not delete the char under the cursor).
      return Range(_posBefore(buffer, from), t, RangeKind.charwise);
    }
    return Range(from, motion.target, RangeKind.charwise);
  }

  Range? _resolveTextObject(
    VimBuffer buffer,
    String ch, {
    required bool inner,
  }) {
    switch (ch) {
      case 'w':
        return TextObjects.word(buffer, inner: inner);
      case 'W':
        return TextObjects.word(buffer, inner: inner, bigWord: true);
      case '(':
      case ')':
      case 'b':
        return TextObjects.bracket(buffer, '(', ')', inner: inner);
      case '[':
      case ']':
        return TextObjects.bracket(buffer, '[', ']', inner: inner);
      case '{':
      case '}':
      case 'B':
        return TextObjects.bracket(buffer, '{', '}', inner: inner);
      case '<':
      case '>':
        return TextObjects.bracket(buffer, '<', '>', inner: inner);
      case '"':
        return TextObjects.quote(buffer, '"', inner: inner);
      case "'":
        return TextObjects.quote(buffer, "'", inner: inner);
      case '`':
        return TextObjects.quote(buffer, '`', inner: inner);
      case 't':
        return TextObjects.tag(buffer, inner: inner);
      case 'p':
        return TextObjects.paragraph(buffer, inner: inner);
      case 's':
        return TextObjects.sentence(buffer, inner: inner);
      default:
        return null;
    }
  }

  void _applyRangeFromMotionOrTextObject(
    VimBuffer buffer,
    Range range, {
    String textObject = '',
    bool inner = false,
  }) {
    if (_isVisual()) {
      buffer.selection = range;
      buffer.cursor = range.end;
      return;
    }
    if (_state.pendingOperator.isEmpty) return;
    final op = _state.pendingOperator;
    if (!buffer.isEditable && op != 'y') {
      _state.clearPending();
      return;
    }
    final reg = _state.pendingRegister.length == 1
        ? _state.pendingRegister
        : '"';
    _runOperator(op, buffer, range, reg);
    if (op != 'y' && textObject.isNotEmpty) {
      _state.lastAction
        ..clear()
        ..kind = LastActionKind.operatorTextObject
        ..operator = op
        ..textObject = textObject
        ..textObjectInner = inner
        ..register = reg;
    }
    _state.clearPending();
  }

  void _runOperator(String op, VimBuffer buffer, Range range, String reg) {
    // yank is the only non-mutating operator; everything else snapshots.
    if (op != 'y' && op != '=') buffer.pushUndo();
    switch (op) {
      case 'd':
        Operators.delete(buffer, range, _state.registers, register: reg);
      case 'c':
        Operators.change(buffer, range, _state.registers, register: reg);
        _enterInsert(buffer, entry: 'c', pushUndo: false);
      case 'y':
        Operators.yank(buffer, range, _state.registers, register: reg);
      case '>':
        Operators.indent(buffer, range, _state.shiftWidth);
      case '<':
        Operators.dedent(buffer, range, _state.shiftWidth);
      case '=':
        // No language-aware reindent; treat as no-op.
        break;
      case '~':
        Operators.toggleCase(buffer, range);
      case 'gu':
        Operators.toLower(buffer, range);
      case 'gU':
        Operators.toUpper(buffer, range);
    }
  }

  void _applyLinewiseOperator(
    VimBuffer buffer,
    String op,
    int count,
    String reg,
  ) {
    final startRow = buffer.cursor.row;
    final endRow = (startRow + count - 1).clamp(0, buffer.lineCount - 1);
    final range = Range(
      Pos(startRow, 0),
      Pos(endRow, buffer.rowLength(endRow)),
      RangeKind.linewise,
    );
    _runOperator(op, buffer, range, reg);
  }

  void _yankCurrentLine(VimBuffer buffer, int count, String reg) {
    final startRow = buffer.cursor.row;
    final endRow = (startRow + count - 1).clamp(0, buffer.lineCount - 1);
    final range = Range(
      Pos(startRow, 0),
      Pos(endRow, buffer.rowLength(endRow)),
      RangeKind.linewise,
    );
    Operators.yank(buffer, range, _state.registers, register: reg);
  }

  void _applyVisualOperator(VimBuffer buffer, String op, String reg) {
    final sel = buffer.selection;
    if (sel == null) return;
    // Visual operations are not dot-repeatable (a stale record must not
    // merge with the insert session a visual `c` opens).
    _state.lastAction.clear();
    _saveVisualMarks(buffer);
    _runOperator(op, buffer, sel, reg);
    // `c` already switched to insert (and cleared the selection) — forcing
    // normal here would silently drop out of the change.
    if (_state.mode == VimMode.insert) return;
    _state.mode = VimMode.normal;
    _state.visualAnchor = null;
    buffer.selection = null;
    buffer.visualKind = VimMode.normal;
    buffer.onModeChanged(VimMode.normal);
  }

  /// Record `'<`/`'>` from the current selection (called on visual exit).
  void _saveVisualMarks(VimBuffer buffer) {
    final sel = buffer.selection?.normalized();
    if (sel == null) return;
    _state.marks.set('<', buffer.surfaceId, sel.start);
    _state.marks.set('>', buffer.surfaceId, sel.end);
  }

  /// Leave any visual mode, saving the `'<`/`'>` marks.
  void _exitVisual(VimBuffer buffer) {
    if (!_isVisual()) return;
    _saveVisualMarks(buffer);
    _state.mode = VimMode.normal;
    _state.visualAnchor = null;
    buffer.selection = null;
    buffer.visualKind = VimMode.normal;
    buffer.onModeChanged(VimMode.normal);
  }

  /// Visual `p`/`P`: the selection is replaced by the register contents.
  /// The deleted text lands in the unnamed register (vim behavior).
  void _visualPaste(VimBuffer buffer, String reg) {
    final sel = buffer.selection;
    if (sel == null || !buffer.isEditable) {
      _exitVisual(buffer);
      return;
    }
    final entry = _state.registers.read(reg);
    if (entry.isEmpty) {
      _exitVisual(buffer);
      return;
    }
    _state.lastAction.clear();
    _saveVisualMarks(buffer);
    buffer.pushUndo();
    Operators.delete(buffer, sel, _state.registers);
    Operators.paste(buffer, entry, before: true);
    _state.mode = VimMode.normal;
    _state.visualAnchor = null;
    buffer.selection = null;
    buffer.visualKind = VimMode.normal;
    buffer.onModeChanged(VimMode.normal);
  }

  /// Visual `J`: join every line the selection spans.
  void _visualJoin(VimBuffer buffer) {
    final sel = buffer.selection?.normalized();
    if (sel == null || !buffer.isEditable) {
      _exitVisual(buffer);
      return;
    }
    _state.lastAction.clear();
    _saveVisualMarks(buffer);
    buffer.pushUndo();
    final joins = (sel.end.row - sel.start.row).clamp(1, 1 << 30);
    buffer.cursor = Pos(sel.start.row, 0);
    Operators.joinLines(buffer, joins);
    _state.mode = VimMode.normal;
    _state.visualAnchor = null;
    buffer.selection = null;
    buffer.visualKind = VimMode.normal;
    buffer.onModeChanged(VimMode.normal);
  }

  /// Visual `r{ch}`: overwrite every selected cell, preserving newlines.
  void _replaceSelection(VimBuffer buffer, Range sel, String ch) {
    final startRow = sel.start.row;
    final endRow = sel.end.row;
    for (var r = startRow; r <= endRow && r < buffer.lineCount; r++) {
      final len = buffer.rowLength(r);
      if (len == 0) continue;
      int c0;
      int c1;
      switch (sel.kind) {
        case RangeKind.linewise:
          c0 = 0;
          c1 = len - 1;
        case RangeKind.blockwise:
          c0 = sel.start.col;
          c1 = sel.end.col;
          if (c0 > c1) {
            final t = c0;
            c0 = c1;
            c1 = t;
          }
          if (c0 >= len) continue;
          c1 = c1.clamp(0, len - 1);
        case RangeKind.charwise:
          c0 = r == startRow ? sel.start.col : 0;
          c1 = (r == endRow ? sel.end.col : len - 1).clamp(0, len - 1);
      }
      buffer.replaceRange(
        Range(Pos(r, c0), Pos(r, c1), RangeKind.charwise),
        ch * (c1 - c0 + 1),
        RangeKind.charwise,
      );
    }
    buffer.cursor = sel.start;
  }

  /// Visual-block `I`/`A`: enter insert on the block's top row; the typed
  /// text replicates onto the remaining rows when the session ends (see
  /// [_enterNormal]).
  void _beginBlockInsert(VimBuffer buffer, {required bool append}) {
    final sel = buffer.selection?.normalized();
    if (sel == null || !buffer.isEditable) {
      _exitVisual(buffer);
      return;
    }
    var c0 = sel.start.col;
    var c1 = sel.end.col;
    if (c0 > c1) {
      final t = c0;
      c0 = c1;
      c1 = t;
    }
    final col = append ? c1 + 1 : c0;
    _saveVisualMarks(buffer);
    buffer.pushUndo();
    _state.pendingBlockInsert = (
      startRow: sel.start.row,
      endRow: sel.end.row,
      col: col,
      append: append,
    );
    _state.mode = VimMode.normal;
    _state.visualAnchor = null;
    buffer.selection = null;
    buffer.visualKind = VimMode.normal;
    final len = buffer.rowLength(sel.start.row);
    if (append && len < col) {
      buffer.insertAt(Pos(sel.start.row, len), ' ' * (col - len));
    }
    buffer.cursor = Pos(sel.start.row, col);
    _enterInsert(buffer, entry: 'i', pushUndo: false);
  }

  void _applyMotion(VimBuffer buffer, MotionResult motion) {
    if (_isVisual()) {
      buffer.cursor = motion.target;
      // Extend selection.
      final anchor = _state.visualAnchor ?? buffer.cursor;
      final kind = _state.mode == VimMode.visualLine
          ? RangeKind.linewise
          : _state.mode == VimMode.visualBlock
          ? RangeKind.blockwise
          : RangeKind.charwise;
      buffer.selection = Range(anchor, motion.target, kind).normalized();
      return;
    }
    buffer.cursor = motion.target;
  }

  void _toggleVisual(VimBuffer buffer, VimMode kind) {
    if (_state.mode == kind) {
      _exitVisual(buffer);
      return;
    }
    _enterVisual(buffer, kind);
  }

  bool _isVisual() =>
      _state.mode == VimMode.visualChar ||
      _state.mode == VimMode.visualLine ||
      _state.mode == VimMode.visualBlock;

  int _consumeCount() {
    final n = _state.pendingCount == 0 ? 1 : _state.pendingCount;
    _state.pendingCount = 0;
    return n;
  }
}
