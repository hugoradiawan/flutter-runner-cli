part of 'vim_engine.dart';

/// Mode transitions and the prompt-line modes (ex, search, replace).
extension _VimModes on VimEngine {
  // ── Mode transitions ─────────────────────────────────────────────────────

  void _enterNormal(VimBuffer buffer) {
    // Finalize an in-progress insert session for dot-repeat.
    if (_state.mode == VimMode.insert && _state.insertEntry != null) {
      final captured = _state.insertCapture?.toString() ?? '';
      final a = _state.lastAction;
      final block = _state.pendingBlockInsert;
      final isChangeOp =
          _state.insertEntry == 'c' &&
          a.operator == 'c' &&
          (a.kind == LastActionKind.operatorMotion ||
              a.kind == LastActionKind.operatorTextObject ||
              a.kind == LastActionKind.operatorDouble);
      if (block != null) {
        // Visual-block I/A: replicate the typed text onto the other block
        // rows. Only single-line captures replicate (vim behavior); `I`
        // skips rows shorter than the insert column, `A` pads them.
        _state.pendingBlockInsert = null;
        if (captured.isNotEmpty && !captured.contains('\n')) {
          for (
            var r = block.startRow + 1;
            r <= block.endRow && r < buffer.lineCount;
            r++
          ) {
            final len = buffer.rowLength(r);
            if (len < block.col) {
              if (!block.append) continue;
              buffer.insertAt(Pos(r, len), ' ' * (block.col - len));
            }
            buffer.insertAt(Pos(r, block.col), captured);
          }
        }
        a.clear();
      } else if (isChangeOp) {
        // `c{motion}` recorded the operator part when it ran; merge the
        // typed text so `.` replays delete + insert together.
        a.insertText = captured;
      } else {
        a
          ..clear()
          ..kind = LastActionKind.insertSession
          ..insertEntry = _state.insertEntry!
          ..insertText = captured
          ..count = 1;
      }
    }

    // Finalize a Replace-mode session: `{count}R` replays the overwrite
    // count-1 more times, and the capture becomes the dot-repeat payload.
    if (_state.mode == VimMode.replace) {
      final captured = _state.replaceCapture?.toString() ?? '';
      final n = _state.replaceSessionCount;
      if (captured.isNotEmpty && n > 1 && !captured.contains('\n')) {
        for (var i = 1; i < n; i++) {
          for (final ch in captured.split('')) {
            _overwriteChar(buffer, ch);
          }
        }
      }
      if (captured.isNotEmpty) {
        _state.lastAction
          ..clear()
          ..kind = LastActionKind.insertSession
          ..insertEntry = 'R'
          ..insertText = captured
          ..count = n;
      }
      _state.replaceCapture = null;
      _state.replaceStack.clear();
      _state.replaceSessionCount = 1;
    }
    _state.insertEntry = null;
    _state.insertCapture = null;
    buffer.exitInsertMode();
    final c = buffer.cursor;
    final len = buffer.rowLength(c.row);
    if (len > 0 && c.col >= len) {
      buffer.cursor = Pos(c.row, len - 1);
    } else if (c.col > 0 &&
        (_state.mode == VimMode.insert || _state.mode == VimMode.replace)) {
      buffer.cursor = Pos(c.row, c.col - 1);
    }
    _state.mode = VimMode.normal;
    _state.visualAnchor = null;
    buffer.selection = null;
    buffer.visualKind = VimMode.normal;
    _state.clearPending();
    buffer.onModeChanged(VimMode.normal);
  }

  /// [pushUndo] controls whether a snapshot is captured. Pass false when the
  /// caller already pushed before its own mutation (e.g. `o`, `c{motion}`).
  void _enterInsert(VimBuffer buffer, {String? entry, bool pushUndo = true}) {
    if (!buffer.isEditable) {
      // Read-only buffer (transcript cursor): `i` exits the cursor and
      // refocuses the editable input prompt. enterInsertMode() pops the
      // surface; the active-buffer computation in the host picks input
      // on the next tick.
      buffer.enterInsertMode();
      _state.mode = VimMode.insert;
      _state.visualAnchor = null;
      buffer.selection = null;
      buffer.visualKind = VimMode.normal;
      buffer.onModeChanged(VimMode.insert);
      return;
    }
    if (pushUndo && _state.mode != VimMode.insert) buffer.pushUndo();
    _state.mode = VimMode.insert;
    _state.visualAnchor = null;
    buffer.selection = null;
    buffer.visualKind = VimMode.normal;
    if (entry != null) {
      _state.insertEntry = entry;
      _state.insertCapture = StringBuffer();
    }
    buffer.enterInsertMode();
    buffer.onModeChanged(VimMode.insert);
  }

  void _enterVisual(VimBuffer buffer, VimMode kind) {
    if (kind != VimMode.visualChar &&
        kind != VimMode.visualLine &&
        kind != VimMode.visualBlock) {
      return;
    }
    _state.mode = kind;
    _state.visualAnchor = buffer.cursor;
    buffer.selection = Range(
      buffer.cursor,
      buffer.cursor,
      kind == VimMode.visualLine
          ? RangeKind.linewise
          : kind == VimMode.visualBlock
          ? RangeKind.blockwise
          : RangeKind.charwise,
    );
    buffer.visualKind = kind;
    buffer.onModeChanged(kind);
  }

  void _enterEx(VimBuffer buffer, {String initial = ''}) {
    _state.mode = VimMode.exCmd;
    _state.exDraft = initial;
    buffer.onModeChanged(VimMode.exCmd);
  }

  void _enterSearch(VimBuffer buffer, {required bool forward}) {
    _state.mode = VimMode.search;
    _state.searchDraft = '';
    _state.lastSearch = LastSearch('', forward);
    buffer.onModeChanged(VimMode.search);
  }

  // ── Ex-mode key handling ─────────────────────────────────────────────────

  void _handleExKey(TeaKey ke, VimBuffer buffer) {
    if (ke.code == KeyCode.escape) {
      _state.mode = VimMode.normal;
      _state.exDraft = '';
      buffer.onModeChanged(VimMode.normal);
      return;
    }
    if (ke.code == KeyCode.enter) {
      final cmd = ExParser.parse(_state.exDraft);
      _state.exDraft = '';
      _state.mode = VimMode.normal;
      buffer.onModeChanged(VimMode.normal);
      if (cmd != null) _runExCmd(cmd, buffer);
      return;
    }
    if (ke.code == KeyCode.backspace) {
      if (_state.exDraft.isNotEmpty) {
        _state.exDraft = _state.exDraft.substring(0, _state.exDraft.length - 1);
      } else {
        _state.mode = VimMode.normal;
        buffer.onModeChanged(VimMode.normal);
      }
      return;
    }
    if (ke.code == KeyCode.space) {
      _state.exDraft += ' ';
      return;
    }
    if (ke.code == KeyCode.rune && ke.modifiers.isEmpty) {
      _state.exDraft += ke.text;
    }
  }

  // ── Search-mode key handling ─────────────────────────────────────────────

  void _handleSearchKey(TeaKey ke, VimBuffer buffer) {
    if (ke.code == KeyCode.escape) {
      _state.mode = VimMode.normal;
      _state.searchDraft = '';
      _state.clearPending(); // aborts a `d/…` operator too
      buffer.onModeChanged(VimMode.normal);
      return;
    }
    if (ke.code == KeyCode.enter) {
      final pattern = _state.searchDraft;
      final dir = _state.lastSearch?.forward ?? true;
      _state.lastSearch = LastSearch(pattern, dir);
      _state.searchDraft = '';
      _state.mode = VimMode.normal;
      buffer.onModeChanged(VimMode.normal);
      if (pattern.isEmpty) {
        _state.clearPending();
        return;
      }
      if (_state.pendingOperator.isNotEmpty) {
        // `d/pattern<CR>` — operate from the cursor to the match.
        _operateToSearch(buffer, forward: dir);
        return;
      }
      _runSearch(pattern, dir, buffer);
      return;
    }
    if (ke.code == KeyCode.backspace) {
      if (_state.searchDraft.isNotEmpty) {
        _state.searchDraft = _state.searchDraft.substring(
          0,
          _state.searchDraft.length - 1,
        );
      } else {
        _state.mode = VimMode.normal;
        buffer.onModeChanged(VimMode.normal);
      }
      return;
    }
    if (ke.code == KeyCode.space) {
      _state.searchDraft += ' ';
      return;
    }
    if (ke.code == KeyCode.rune && ke.modifiers.isEmpty) {
      _state.searchDraft += ke.text;
    }
  }

  // ── Replace mode ─────────────────────────────────────────────────────────

  void _replaceTypedChar(VimBuffer buffer, String ch) {
    final p = buffer.cursor;
    final line = buffer.lineAt(p.row);
    _state.replaceStack.add((p, p.col < line.length ? line[p.col] : null));
    _state.replaceCapture?.write(ch);
    _overwriteChar(buffer, ch);
  }

  /// Overwrite the char at the cursor (append when past EOL) and advance.
  void _overwriteChar(VimBuffer buffer, String ch) {
    final p = buffer.cursor;
    if (p.col >= buffer.rowLength(p.row)) {
      buffer.insertAt(p, ch); // insertAt advances the cursor
      return;
    }
    buffer.replaceRange(
      Range(p, p, RangeKind.charwise),
      ch,
      RangeKind.charwise,
    );
    buffer.cursor = Pos(p.row, p.col + 1);
  }
}
