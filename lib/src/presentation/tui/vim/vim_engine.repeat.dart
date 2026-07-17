part of 'vim_engine.dart';

/// A register name a macro can record into: a-z or 0-9.
bool _isMacroRegister(String ch) {
  if (ch.length != 1) return false;
  final u = ch.codeUnitAt(0);
  return (u >= 0x61 && u <= 0x7a) || (u >= 0x30 && u <= 0x39); // a-z 0-9
}

/// g-chords, macros, search repetition, and dot-repeat replay.
extension _VimRepeat on VimEngine {
  void _handleGChord(String ch, VimBuffer buffer) {
    switch (ch) {
      // Motions — routed through _motionKey so a pending operator applies
      // (`dgg`, `yG`-via-gg, `dge`, …).
      case 'g':
        _motionKey(buffer, 'gg');
        return;
      case 'e':
        _motionKey(buffer, 'ge');
        return;
      case 'E':
        _motionKey(buffer, 'gE');
        return;
      case '_':
        _motionKey(buffer, 'g_');
        return;
      // Case operators — apply immediately on a visual selection, otherwise
      // latch like d/c/y (count moves aside for `2guw`-style products).
      case 'u':
      case 'U':
      case '~':
        final op = ch == '~' ? '~' : 'g$ch';
        if (_isVisual()) {
          _applyVisualOperator(buffer, op, '"');
        } else {
          _state.pendingOperator = op;
          _state.pendingOpCount = _state.pendingCount;
          _state.pendingCount = 0;
        }
        return;
      case 't':
        _onTabSwitch?.call(
          _state.pendingCount == 0 ? null : _state.pendingCount,
          forward: true,
        );
      case 'T':
        _onTabSwitch?.call(
          _state.pendingCount == 0 ? null : _state.pendingCount,
          forward: false,
        );
      case '*':
        _searchWord(buffer, forward: true, wholeWord: false);
        return;
      case '#':
        _searchWord(buffer, forward: false, wholeWord: false);
        return;
      case 'd':
      case 'D':
        // gd/gD: go to declaration — no semantic context; no-op.
        break;
      case 'J':
        Operators.joinLines(buffer, _consumeCount());
      default:
        break;
    }
    _state.pendingCount = 0;
  }

  // ── Macros ───────────────────────────────────────────────────────────────

  /// `{count}@{reg}` / `{count}@@` — hand the tape to the host player, which
  /// re-feeds the keys through its full key router (with reentrancy caps).
  void _playMacroRegister(String ch, VimBuffer buffer) {
    final count = _consumeCount();
    final reg = ch == '@' ? _state.macros.lastPlayed : ch;
    if (reg.isEmpty || !_isMacroRegister(reg)) return;
    final tape = _state.macros.tape(reg);
    if (tape == null || tape.isEmpty) return;
    _state.macros.lastPlayed = reg;
    final player = _onPlayMacro;
    if (player == null) return;
    player(<TeaKey>[for (var i = 0; i < count; i++) ...tape]);
  }

  void _repeatSearch(VimBuffer buffer, {required bool forward}) {
    final ls = _state.lastSearch;
    if (ls == null || ls.pattern.isEmpty) return;
    final dir = forward ? ls.forward : !ls.forward;
    _runSearch(ls.pattern, dir, buffer);
  }

  /// `*` / `#` (and `g*` / `g#`): search for the word under the cursor.
  void _searchWord(
    VimBuffer buffer, {
    required bool forward,
    required bool wholeWord,
  }) {
    final word = Motions.wordUnderCursor(buffer);
    if (word == null) return;
    final escaped = RegExp.escape(word);
    final pattern = wholeWord ? '\\b$escaped\\b' : escaped;
    _state.lastSearch = LastSearch(pattern, forward);
    _runSearch(pattern, forward, buffer);
  }

  /// Operator + `n`/`N`: apply the operator from the cursor to the next
  /// match of the last search (exclusive), e.g. `dn`.
  void _operateToSearch(VimBuffer buffer, {required bool forward}) {
    final op = _state.pendingOperator;
    if (!buffer.isEditable && op != 'y') {
      _state.clearPending();
      return;
    }
    final from = buffer.cursor;
    _repeatSearch(buffer, forward: forward);
    final to = buffer.cursor;
    if (to == from) {
      _state.clearPending();
      return;
    }
    buffer.cursor = from;
    _applyMotionOrOperate(
      buffer,
      MotionResult(to, exclusive: true),
      dotMotion: forward ? 'n' : 'N',
    );
  }

  // ── Dot-repeat ───────────────────────────────────────────────────────────

  void _captureSingleEdit(String key, int count, String reg) {
    _state.lastAction
      ..clear()
      ..kind = LastActionKind.singleEdit
      ..singleEdit = key
      ..count = count
      ..register = reg;
  }

  /// Replay [_state.lastAction]. Insertion sessions reinsert captured text
  /// programmatically rather than re-entering live insert mode.
  void _replayLastAction(VimBuffer buffer) {
    final a = _state.lastAction;
    if (a.kind == LastActionKind.none) return;
    if (!buffer.isEditable) return;
    switch (a.kind) {
      case LastActionKind.none:
        return;
      case LastActionKind.operatorMotion:
        if (a.motion == 'n' || a.motion == 'N') {
          _state.pendingOperator = a.operator;
          _state.pendingRegister = a.register == '"' ? '' : a.register;
          _operateToSearch(buffer, forward: a.motion == 'n');
          return;
        }
        final line = (a.motion == 'G' || a.motion == 'gg')
            ? (a.motionCount == 0 ? null : a.motionCount)
            : null;
        final count = a.motionCount == 0 ? 1 : a.motionCount;
        final m = _namedMotion(
          a.motion,
          buffer,
          count,
          findCh: a.findCh,
          line: line,
        );
        if (m == null) return;
        const findNames = {'f', 'F', 't', 'T', ';', ','};
        if (findNames.contains(a.motion) && m.target == buffer.cursor) return;
        _replayOperator(buffer, a, _rangeFromMotion(buffer, buffer.cursor, m));
      case LastActionKind.operatorDouble:
        final startRow = buffer.cursor.row;
        final endRow = (startRow + a.count - 1).clamp(0, buffer.lineCount - 1);
        _replayOperator(
          buffer,
          a,
          Range(
            Pos(startRow, 0),
            Pos(endRow, buffer.rowLength(endRow)),
            RangeKind.linewise,
          ),
        );
      case LastActionKind.operatorTextObject:
        final range = _resolveTextObject(
          buffer,
          a.textObject,
          inner: a.textObjectInner,
        );
        if (range != null) _replayOperator(buffer, a, range);
      case LastActionKind.singleEdit:
        _replaySingleEdit(buffer, a);
      case LastActionKind.replaceChar:
        final count = a.count;
        final c = buffer.cursor;
        if (c.col + count > buffer.rowLength(c.row)) return;
        buffer.pushUndo();
        buffer.replaceRange(
          Range(c, Pos(c.row, c.col + count - 1), RangeKind.charwise),
          a.replaceCharCh * count,
          RangeKind.charwise,
        );
        buffer.cursor = Pos(c.row, c.col + count - 1);
      case LastActionKind.insertSession:
        _replayInsertSession(buffer, a);
    }
  }

  /// Run a recorded operator over [range]. `c` is replayed as delete +
  /// reinsert of the captured text instead of re-entering live insert mode.
  void _replayOperator(VimBuffer buffer, LastAction a, Range range) {
    if (a.operator == 'c') {
      buffer.pushUndo();
      Operators.change(buffer, range, _state.registers, register: a.register);
      if (a.insertText.isNotEmpty) {
        buffer.insertAt(buffer.cursor, a.insertText);
        final c = buffer.cursor;
        if (c.col > 0) buffer.cursor = Pos(c.row, c.col - 1);
      }
      return;
    }
    _runOperator(a.operator, buffer, range, a.register);
  }

  void _replaySingleEdit(VimBuffer buffer, LastAction a) {
    final count = a.count;
    final reg = a.register;
    buffer.pushUndo();
    switch (a.singleEdit) {
      case 'x':
        for (var i = 0; i < count; i++) {
          final c = buffer.cursor;
          if (c.col < buffer.rowLength(c.row)) {
            Operators.delete(
              buffer,
              Range(c, c, RangeKind.charwise),
              _state.registers,
              register: reg,
            );
          }
        }
      case 'X':
        for (var i = 0; i < count; i++) {
          final c = buffer.cursor;
          if (c.col > 0) {
            Operators.delete(
              buffer,
              Range(
                Pos(c.row, c.col - 1),
                Pos(c.row, c.col - 1),
                RangeKind.charwise,
              ),
              _state.registers,
              register: reg,
            );
          }
        }
      case 'D':
        final c = buffer.cursor;
        final len = buffer.rowLength(c.row);
        if (len > 0) {
          Operators.delete(
            buffer,
            Range(c, Pos(c.row, len - 1), RangeKind.charwise),
            _state.registers,
            register: reg,
          );
        }
      case 'J':
        Operators.joinLines(buffer, count);
      case 'p':
        Operators.paste(
          buffer,
          _state.registers.read(reg),
          before: false,
          count: count,
        );
      case 'P':
        Operators.paste(
          buffer,
          _state.registers.read(reg),
          before: true,
          count: count,
        );
      case '~':
        final c = buffer.cursor;
        final len = buffer.rowLength(c.row);
        if (len == 0) break;
        final end = (c.col + count - 1).clamp(0, len - 1);
        Operators.toggleCase(
          buffer,
          Range(c, Pos(c.row, end), RangeKind.charwise),
        );
        buffer.cursor = Pos(c.row, (end + 1).clamp(0, len - 1));
    }
  }

  void _replayInsertSession(VimBuffer buffer, LastAction a) {
    buffer.pushUndo();
    // Reposition cursor matching the original entry key.
    switch (a.insertEntry) {
      case 'I':
        buffer.cursor = Pos(
          buffer.cursor.row,
          buffer.firstNonBlankCol(buffer.cursor.row),
        );
      case 'a':
        final c = buffer.cursor;
        final len = buffer.rowLength(c.row);
        if (len > 0 && c.col < len) buffer.cursor = Pos(c.row, c.col + 1);
      case 'A':
        buffer.cursor = Pos(
          buffer.cursor.row,
          buffer.rowLength(buffer.cursor.row),
        );
      case 'o':
        if (buffer.isMultiLine) {
          final r = buffer.cursor.row;
          buffer.insertAt(Pos(r + 1, 0), '\n');
          buffer.cursor = Pos(r + 1, 0);
        }
      case 'O':
        if (buffer.isMultiLine) {
          final r = buffer.cursor.row;
          buffer.insertAt(Pos(r, 0), '\n');
          buffer.cursor = Pos(r, 0);
        }
      case 's':
        final c = buffer.cursor;
        Operators.delete(
          buffer,
          Range(c, c, RangeKind.charwise),
          _state.registers,
          register: a.register,
        );
      case 'S':
        final r = buffer.cursor.row;
        Operators.delete(
          buffer,
          Range(Pos(r, 0), Pos(r, buffer.rowLength(r)), RangeKind.linewise),
          _state.registers,
          register: a.register,
        );
      case 'C':
        final c = buffer.cursor;
        final len = buffer.rowLength(c.row);
        if (len > 0) {
          Operators.delete(
            buffer,
            Range(c, Pos(c.row, len - 1), RangeKind.charwise),
            _state.registers,
            register: a.register,
          );
        }
      case 'R':
        for (var i = 0; i < a.count; i++) {
          for (final ch in a.insertText.split('')) {
            _overwriteChar(buffer, ch);
          }
        }
        final cr = buffer.cursor;
        if (cr.col > 0) buffer.cursor = Pos(cr.row, cr.col - 1);
        return;
      case 'i':
      case 'c':
        break;
    }
    if (a.insertText.isNotEmpty) {
      buffer.insertAt(buffer.cursor, a.insertText);
    }
    // Land cursor at the end of the inserted text minus one (vim semantics).
    final c = buffer.cursor;
    if (c.col > 0) buffer.cursor = Pos(c.row, c.col - 1);
  }
}
