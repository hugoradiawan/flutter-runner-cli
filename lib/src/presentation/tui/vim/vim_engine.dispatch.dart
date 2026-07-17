part of 'vim_engine.dart';

/// Keys the shared motion switch understands. When an operator is pending,
/// any key outside this set (and not a doubled operator) aborts it.
const Set<String> _motionKeys = {
  'h', 'l', 'j', 'k', 'w', 'W', 'e', 'E', 'b', 'B', '0', '^', r'$', //
  '%', '{', '}', 'G', 'H', 'M', 'L', 'f', 'F', 't', 'T', ';', ',',
};

/// Motions that push the current position onto the jumplist.
const Set<String> _jumpMotions = {'%', '{', '}', 'G', 'gg'};

/// The normal/visual parse loop and top-level key dispatch.
extension _VimDispatch on VimEngine {
  // ── Normal + visual parse loop ───────────────────────────────────────────

  void _handleNormalOrVisual(TeaKey ke, VimBuffer buffer) {
    // Special keys (arrows, page, etc.) translate to motions.
    if (ke.code != KeyCode.rune) {
      _handleNonRune(ke, buffer);
      return;
    }

    final mods = ke.modifiers;
    final ch = ke.text;

    // Ctrl-bindings first (Ctrl-O / Ctrl-I / Ctrl-D / Ctrl-U / Ctrl-V).
    if (mods.contains(KeyMod.ctrl)) {
      _handleCtrl(ch.toLowerCase(), buffer);
      return;
    }

    // f/F/t/T pending char — a real motion: works standalone, in visual,
    // and as an operator target (dfx, ct)).
    if (_state.pendingFind.isNotEmpty) {
      final pend = _state.pendingFind;
      _state.pendingFind = '';
      _state.lastFind = LastFind(
        ch,
        pend == 'f' || pend == 't',
        pend == 't' || pend == 'T',
      );
      _motionKey(buffer, pend, findCh: ch);
      return;
    }

    // {count}r{ch} replace; in visual modes r overwrites every selected cell.
    if (_state.pendingReplaceChar) {
      _state.pendingReplaceChar = false;
      if (_isVisual()) {
        final sel = buffer.selection?.normalized();
        if (sel != null && buffer.isEditable) {
          _state.lastAction.clear();
          buffer.pushUndo();
          _replaceSelection(buffer, sel, ch);
        }
        _exitVisual(buffer);
        return;
      }
      final count = _consumeCount();
      final c = buffer.cursor;
      // Vim aborts when fewer than count chars remain on the line.
      if (!buffer.isEditable || c.col + count > buffer.rowLength(c.row)) {
        return;
      }
      buffer.pushUndo();
      final range = Range(c, Pos(c.row, c.col + count - 1), RangeKind.charwise);
      buffer.replaceRange(range, ch * count, RangeKind.charwise);
      buffer.cursor = Pos(c.row, c.col + count - 1);
      _state.lastAction
        ..clear()
        ..kind = LastActionKind.replaceChar
        ..replaceCharCh = ch
        ..count = count;
      return;
    }

    // q{reg} — start recording. The register char is consumed silently
    // (recording starts empty, so it never lands on its own tape).
    if (_state.pendingMarkOp == 'q') {
      _state.pendingMarkOp = '';
      if (_isMacroRegister(ch)) _state.macros.start(ch);
      return;
    }

    // @{reg} / @@ — play a macro (count comes from `{count}@{reg}`).
    if (_state.pendingMarkOp == '@') {
      _state.pendingMarkOp = '';
      _playMacroRegister(ch, buffer);
      return;
    }

    // ZZ / ZQ — quit (frun has no per-buffer write, both map to quit).
    if (_state.pendingMarkOp == 'Z') {
      _state.pendingMarkOp = '';
      if (ch == 'Z' || ch == 'Q') {
        final cmd = ExParser.parse('q');
        if (cmd != null) _runExCmd(cmd, buffer);
      }
      return;
    }

    // m{a-zA-Z} set mark; '{a} jump to line; `{a} jump exact.
    if (_state.pendingMarkOp == 'm') {
      _state.marks.set(ch, buffer.surfaceId, buffer.cursor);
      _state.pendingMarkOp = '';
      return;
    }
    if (_state.pendingMarkOp == "'") {
      final mk = _state.marks.get(ch, buffer.surfaceId);
      _state.pendingMarkOp = '';
      if (mk != null) {
        _state.jumps.push(buffer.surfaceId, buffer.cursor);
        buffer.cursor = Pos(mk.pos.row, buffer.firstNonBlankCol(mk.pos.row));
      }
      return;
    }
    if (_state.pendingMarkOp == '`') {
      final mk = _state.marks.get(ch, buffer.surfaceId);
      _state.pendingMarkOp = '';
      if (mk != null) {
        _state.jumps.push(buffer.surfaceId, buffer.cursor);
        buffer.cursor = mk.pos;
      }
      return;
    }

    // Register selector: `"{a}`.
    if (_state.pendingRegister == '"' && _state.pendingRegister.length == 1) {
      // Already in "register pending" — this rune is the register name.
      _state.pendingRegister = ch;
      return;
    }
    if (ch == '"' &&
        _state.pendingOperator.isEmpty &&
        _state.pendingRegister.isEmpty) {
      _state.pendingRegister = '"';
      return;
    }

    // Count digits. `0` only continues a count already in progress; a bare
    // `0` is the line-start motion (also as an operator target: `d0`).
    if (_isDigit(ch) && (ch != '0' || _state.pendingCount > 0)) {
      _state.pendingCount = _state.pendingCount * 10 + int.parse(ch);
      return;
    }

    // Text-object detection (only when operator pending OR in visual).
    if (_state.pendingOperator.isNotEmpty || _isVisual()) {
      if (ch == 'i' || ch == 'a') {
        _state.pendingMarkOp =
            ch; // reuse field as "text-object inner/around prefix"
        return;
      }
    }
    if (_state.pendingMarkOp == 'i' || _state.pendingMarkOp == 'a') {
      final inner = _state.pendingMarkOp == 'i';
      _state.pendingMarkOp = '';
      final range = _resolveTextObject(buffer, ch, inner: inner);
      if (range != null) {
        _applyRangeFromMotionOrTextObject(
          buffer,
          range,
          textObject: ch,
          inner: inner,
        );
      } else {
        // Failed text object aborts the pending operator (vim behavior).
        _state.clearPending();
      }
      return;
    }

    // g-prefix chord.
    if (_state.pendingG) {
      _state.pendingG = false;
      _handleGChord(ch, buffer);
      return;
    }
    if (ch == 'g') {
      _state.pendingG = true;
      return;
    }

    // z-prefix chord (scroll positioning).
    if (_state.pendingZ) {
      _state.pendingZ = false;
      switch (ch) {
        case 'z':
          _onScroll?.call(const VimScrollRequest(VimScrollKind.center), buffer);
        case 't':
          _onScroll?.call(const VimScrollRequest(VimScrollKind.top), buffer);
        case 'b':
          _onScroll?.call(const VimScrollRequest(VimScrollKind.bottom), buffer);
      }
      return;
    }
    if (ch == 'z') {
      _state.pendingZ = true;
      return;
    }

    _dispatchTopLevel(ch, buffer);
  }

  void _handleNonRune(TeaKey ke, VimBuffer buffer) {
    final count = _consumeCount();
    switch (ke.code) {
      case KeyCode.left:
        _state.desiredCol = null;
        _applyMotion(buffer, Motions.left(buffer, count));
      case KeyCode.right:
        _state.desiredCol = null;
        _applyMotion(buffer, Motions.right(buffer, count));
      case KeyCode.up:
        _state.desiredCol ??= buffer.cursor.col;
        _applyMotion(
          buffer,
          Motions.up(buffer, count, wantCol: _state.desiredCol),
        );
      case KeyCode.down:
        _state.desiredCol ??= buffer.cursor.col;
        _applyMotion(
          buffer,
          Motions.down(buffer, count, wantCol: _state.desiredCol),
        );
      case KeyCode.home:
        _applyMotion(buffer, Motions.lineStart(buffer));
      case KeyCode.end:
        _applyMotion(buffer, Motions.lineEnd(buffer));
      case KeyCode.escape:
        _exitVisual(buffer);
        _state.clearPending();
      case KeyCode.enter:
        _applyMotion(buffer, Motions.down(buffer, 1));
      default:
        break;
    }
  }

  void _handleCtrl(String ch, VimBuffer buffer) {
    switch (ch) {
      case 'o':
        final jp = _state.jumps.back();
        if (jp != null) buffer.cursor = jp.pos;
      case 'i':
        // Ctrl-I is Tab; only treat as jumplist forward when explicitly ctrl.
        final jp = _state.jumps.forward();
        if (jp != null) buffer.cursor = jp.pos;
      case 'v':
        _toggleVisual(buffer, VimMode.visualBlock);
      case 'd':
        final vp = _viewport(buffer);
        _applyMotion(
          buffer,
          Motions.down(buffer, (vp.height ~/ 2).clamp(1, 100)),
        );
      case 'u':
        final vp = _viewport(buffer);
        _applyMotion(
          buffer,
          Motions.up(buffer, (vp.height ~/ 2).clamp(1, 100)),
        );
      case 'f':
        final vp = _viewport(buffer);
        _applyMotion(buffer, Motions.down(buffer, vp.height));
      case 'b':
        final vp = _viewport(buffer);
        _applyMotion(buffer, Motions.up(buffer, vp.height));
      case 'e':
        _onScroll?.call(
          VimScrollRequest(VimScrollKind.lines, _consumeCount()),
          buffer,
        );
      case 'y':
        _onScroll?.call(
          VimScrollRequest(VimScrollKind.lines, -_consumeCount()),
          buffer,
        );
      case 'r':
        buffer.redo();
        break;
      case 'c':
        _exitVisual(buffer);
        _state.clearPending();
      default:
        break;
    }
  }

  void _dispatchTopLevel(String ch, VimBuffer buffer) {
    final count = _state.pendingCount == 0 ? 1 : _state.pendingCount;
    final reg = _state.pendingRegister.length == 1
        ? _state.pendingRegister
        : '"';

    // Operator pending: only a motion (shared switch below), a doubled
    // operator (dd/yy/guu/…), or an f/t prefix may follow. Anything else
    // aborts the operator, matching vim.
    if (_state.pendingOperator.isNotEmpty) {
      if (_isDoubledOperatorKey(ch)) {
        _applyDoubledOperator(buffer, reg);
        return;
      }
      if (ch == 'n' || ch == 'N') {
        _operateToSearch(buffer, forward: ch == 'n');
        return;
      }
      if (ch == '/' || ch == '?') {
        // `d/pattern<CR>` — the operator stays pending through the search
        // prompt and applies on Enter (see _handleSearchKey).
        _enterSearch(buffer, forward: ch == '/');
        return;
      }
      if (!_motionKeys.contains(ch)) {
        _state.clearPending();
        return;
      }
    }

    switch (ch) {
      // Motions ────────────────────────────────────────────────────────────
      case 'h':
      case 'l':
      case 'j':
      case 'k':
      case 'w':
      case 'W':
      case 'e':
      case 'E':
      case 'b':
      case 'B':
      case '0':
      case '^':
      case r'$':
      case '%':
      case '{':
      case '}':
      case 'G':
      case 'H':
      case 'M':
      case 'L':
      case ';':
      case ',':
        _motionKey(buffer, ch);
      case 'f':
      case 'F':
      case 't':
      case 'T':
        // Collect the target char next; count and operator stay pending.
        _state.pendingFind = ch;
        return;
      case 'n':
        _repeatSearch(buffer, forward: true);
      case 'N':
        _repeatSearch(buffer, forward: false);
      case '*':
        _searchWord(buffer, forward: true, wholeWord: true);
      case '#':
        _searchWord(buffer, forward: false, wholeWord: true);

      // Edits / operators ──────────────────────────────────────────────────
      case 'i':
        _enterInsert(buffer, entry: 'i');
      case 'I':
        if (_state.mode == VimMode.visualBlock) {
          _beginBlockInsert(buffer, append: false);
          return;
        }
        buffer.cursor = Pos(
          buffer.cursor.row,
          buffer.firstNonBlankCol(buffer.cursor.row),
        );
        _enterInsert(buffer, entry: 'I');
      case 'a':
        final c = buffer.cursor;
        final len = buffer.rowLength(c.row);
        if (len > 0 && c.col < len) buffer.cursor = Pos(c.row, c.col + 1);
        _enterInsert(buffer, entry: 'a');
      case 'A':
        if (_state.mode == VimMode.visualBlock) {
          _beginBlockInsert(buffer, append: true);
          return;
        }
        buffer.cursor = Pos(
          buffer.cursor.row,
          buffer.rowLength(buffer.cursor.row),
        );
        _enterInsert(buffer, entry: 'A');
      case 'o':
        if (_isVisual()) {
          // Swap anchor and cursor so motions extend from the other end.
          final anchor = _state.visualAnchor;
          if (anchor != null) {
            _state.visualAnchor = buffer.cursor;
            buffer.cursor = anchor;
          }
          break;
        }
        if (buffer.isMultiLine && buffer.isEditable) {
          buffer.pushUndo();
          final r = buffer.cursor.row;
          buffer.insertAt(Pos(r + 1, 0), '\n');
          buffer.cursor = Pos(r + 1, 0);
          _enterInsert(buffer, entry: 'o', pushUndo: false);
        } else {
          _enterInsert(buffer, entry: 'o');
        }
      case 'O':
        if (buffer.isMultiLine && buffer.isEditable) {
          buffer.pushUndo();
          final r = buffer.cursor.row;
          buffer.insertAt(Pos(r, 0), '\n');
          buffer.cursor = Pos(r, 0);
          _enterInsert(buffer, entry: 'O', pushUndo: false);
        } else {
          _enterInsert(buffer, entry: 'O');
        }
      case 'x':
        if (buffer.isEditable) {
          buffer.pushUndo();
          for (var i = 0; i < count; i++) {
            final c = buffer.cursor;
            if (c.col < buffer.rowLength(c.row)) {
              final range = Range(c, c, RangeKind.charwise);
              Operators.delete(buffer, range, _state.registers, register: reg);
            }
          }
          _captureSingleEdit('x', count, reg);
        }
      case 'X':
        if (buffer.isEditable) {
          buffer.pushUndo();
          for (var i = 0; i < count; i++) {
            final c = buffer.cursor;
            if (c.col > 0) {
              final range = Range(
                Pos(c.row, c.col - 1),
                Pos(c.row, c.col - 1),
                RangeKind.charwise,
              );
              Operators.delete(buffer, range, _state.registers, register: reg);
            }
          }
          _captureSingleEdit('X', count, reg);
        }
      case 's':
        if (buffer.isEditable) {
          buffer.pushUndo();
          final c = buffer.cursor;
          final range = Range(c, c, RangeKind.charwise);
          Operators.delete(buffer, range, _state.registers, register: reg);
          _enterInsert(buffer, entry: 's', pushUndo: false);
        }
      case 'S':
        if (buffer.isEditable) {
          buffer.pushUndo();
          final r = buffer.cursor.row;
          final range = Range(
            Pos(r, 0),
            Pos(r, buffer.rowLength(r)),
            RangeKind.linewise,
          );
          Operators.delete(buffer, range, _state.registers, register: reg);
          _enterInsert(buffer, entry: 'S', pushUndo: false);
        }
      case 'D':
        if (buffer.isEditable) {
          buffer.pushUndo();
          final c = buffer.cursor;
          final len = buffer.rowLength(c.row);
          if (len > 0) {
            final range = Range(c, Pos(c.row, len - 1), RangeKind.charwise);
            Operators.delete(buffer, range, _state.registers, register: reg);
          }
          _captureSingleEdit('D', count, reg);
        }
      case 'C':
        if (buffer.isEditable) {
          buffer.pushUndo();
          final c = buffer.cursor;
          final len = buffer.rowLength(c.row);
          if (len > 0) {
            final range = Range(c, Pos(c.row, len - 1), RangeKind.charwise);
            Operators.delete(buffer, range, _state.registers, register: reg);
          }
          _enterInsert(buffer, entry: 'C', pushUndo: false);
        }
      case 'Y':
        _yankCurrentLine(buffer, count, reg);
      case 'p':
      case 'P':
        if (_isVisual()) {
          _visualPaste(buffer, reg);
          break;
        }
        if (!buffer.isEditable) break;
        buffer.pushUndo();
        Operators.paste(
          buffer,
          _state.registers.read(reg),
          before: ch == 'P',
          count: count,
        );
        _captureSingleEdit(ch, count, reg);
      case 'r':
        // Early return keeps the count pending for `{count}r{ch}`.
        _state.pendingReplaceChar = true;
        return;
      case 'R':
        if (!buffer.isEditable) break;
        buffer.pushUndo();
        _state.replaceStack.clear();
        _state.replaceCapture = StringBuffer();
        _state.replaceSessionCount = count;
        _state.mode = VimMode.replace;
        buffer.onModeChanged(VimMode.replace);
      case 'J':
        if (_isVisual()) {
          _visualJoin(buffer);
          break;
        }
        if (buffer.isEditable) {
          buffer.pushUndo();
          Operators.joinLines(buffer, count);
          _captureSingleEdit('J', count, reg);
        }
      case '~':
        if (_isVisual()) {
          _applyVisualOperator(buffer, '~', reg);
          break;
        }
        if (buffer.isEditable) {
          buffer.pushUndo();
          final c = buffer.cursor;
          final len = buffer.rowLength(c.row);
          if (len == 0) break;
          final end = (c.col + count - 1).clamp(0, len - 1);
          Operators.toggleCase(
            buffer,
            Range(c, Pos(c.row, end), RangeKind.charwise),
          );
          buffer.cursor = Pos(c.row, (end + 1).clamp(0, len - 1));
          _captureSingleEdit('~', count, reg);
        }
      case 'u':
        if (_isVisual()) {
          // Visual u/U are case operators, not undo.
          _applyVisualOperator(buffer, 'gu', reg);
          break;
        }
        if (buffer.undo()) {
          // OK
        }
      case 'U':
        if (_isVisual()) {
          _applyVisualOperator(buffer, 'gU', reg);
        }
      case '.':
        _replayLastAction(buffer);
      case 'v':
        _toggleVisual(buffer, VimMode.visualChar);
      case 'V':
        _toggleVisual(buffer, VimMode.visualLine);
      case 'd':
      case 'c':
      case 'y':
      case '>':
      case '<':
      case '=':
        if (_isVisual()) {
          _applyVisualOperator(buffer, ch, reg);
        } else {
          // Move the count typed so far aside so the motion's own count
          // accumulates separately (`2d3w` = 6 words).
          _state.pendingOperator = ch;
          _state.pendingOpCount = _state.pendingCount;
          _state.pendingCount = 0;
          return;
        }
      case 'm':
        _state.pendingMarkOp = 'm';
      case "'":
        _state.pendingMarkOp = "'";
      case '`':
        _state.pendingMarkOp = '`';

      // Macros
      case 'q':
        if (_state.macros.isRecording) {
          _state.macros.dropLast(); // the stopping q is not macro content
          _state.macros.stop();
        } else {
          _state.pendingMarkOp = 'q';
        }
        return;
      case '@':
        // Early return keeps the count pending for `{count}@{reg}`.
        _state.pendingMarkOp = '@';
        return;

      // Tab navigation
      case 'Z':
        // ZZ / ZQ — peek next char via pendingMarkOp.
        _state.pendingMarkOp = 'Z';
      // Command-line entry
      case ':':
        _enterEx(buffer);
      case '/':
        _enterSearch(buffer, forward: true);
      case '?':
        _enterSearch(buffer, forward: false);

      default:
        break;
    }
    _state.pendingCount = 0;
    _state.pendingRegister = '';
  }
}
