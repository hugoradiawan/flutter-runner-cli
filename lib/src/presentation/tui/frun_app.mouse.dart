part of 'frun_app.dart';

/// Mouse handling: drag-to-select, auto-scroll, wheel, link hit-testing, and
/// scroll/link helpers.
mixin _MouseMixin on _FrunModelBase {
  // ── Mouse handling ─────────────────────────────────────────────────────

  void _updateAutoScroll(int mouseY) {
    if (!_mouseSelecting) {
      _autoScrollDirection = 0;
      return;
    }
    if (mouseY <= _lastBodyY) {
      _autoScrollDirection = 1;
    } else if (mouseY >= _lastBodyY + _lastBodyHeight - 1) {
      _autoScrollDirection = -1;
    } else {
      _autoScrollDirection = 0;
    }
  }

  void _applyAutoScroll() {
    if (_autoScrollDirection == 0 || _mouseAnchor == null) return;
    const speed = 3;
    _scrollBy(_autoScrollDirection * speed);
    final total = _displayRowsText.length;
    final newEnd = (total - _transcriptScroll).clamp(0, total);
    final newStart = (newEnd - _lastBodyHeight).clamp(0, total);
    final Pos newCursor;
    if (_autoScrollDirection > 0) {
      newCursor = Pos(newStart, 0);
    } else {
      final r = (newEnd - 1).clamp(0, total - 1);
      final line = r < total ? _displayRowsText[r] : '';
      newCursor = Pos(r, line.isEmpty ? 0 : line.length - 1);
    }
    _tc.cursor = newCursor;
    _tc.selection = Range(_mouseAnchor!, newCursor, RangeKind.charwise);
  }

  void _onMouseClick(Mouse mouse) {
    // Some terminals route wheel ticks as click events; forward to the wheel
    // handler so scroll works either way.
    if (mouse.button == MouseButton.wheelUp ||
        mouse.button == MouseButton.wheelDown) {
      _onMouseWheel(mouse);
      return;
    }
    final msg = _hits.hit(mouse.x, mouse.y);
    // The body registers a TickWakeMsg hit so any pointer activity wakes the
    // renderer; it must NOT preempt drag-to-select. Skip it here and fall
    // through to anchor selection.
    if (msg != null && msg is! TickWakeMsg) {
      update(msg);
      return;
    }
    if (mouse.button != MouseButton.left) return;
    if (!_isInsideBody(mouse)) return;
    final pos = _mouseToPos(mouse);
    if (pos == null) return;
    _autoScrollDirection = 0;
    _mouseAnchor = pos;
    _mouseSelecting = true;
    _mouseDragged = false;
    _mousePriorVimMode = _vimState.mode;
    _mousePriorTcActive = _tc.active;
  }

  void _onMouseMotion(Mouse mouse) {
    if (!_mouseSelecting) return;
    final anchor = _mouseAnchor;
    if (anchor == null) return;
    final pos = _mouseToPos(mouse);
    if (pos == null) return;
    if (!_tc.active) {
      _tc.enter(initialRow: anchor.row, initialCol: anchor.col);
      _vimState.mode = VimMode.normal;
    }
    _tc.cursor = pos;
    _tc.visualKind = VimMode.visualChar;
    _tc.selection = Range(anchor, _tc.cursor, RangeKind.charwise);
    _mouseDragged = true;
    _updateAutoScroll(mouse.y);
    if (_autoScrollDirection != 0) _applyAutoScroll();
  }

  void _onMouseRelease(Mouse mouse) {
    if (!_mouseSelecting) return;
    _autoScrollDirection = 0;
    final dragged = _mouseDragged;
    final priorMode = _mousePriorVimMode ?? VimMode.insert;
    final priorTcActive = _mousePriorTcActive;
    _mouseSelecting = false;
    _mouseAnchor = null;
    _mouseDragged = false;
    _mousePriorVimMode = null;
    if (!dragged) {
      // Plain click — if it landed on a file:line reference, jump to source.
      final pos = _mouseToPos(mouse);
      final openedLink = pos != null && _openLinkAtPos(pos);
      // Clear any selection and exit cursor mode if not previously active.
      _tc.selection = null;
      if (!priorTcActive && _tc.active) {
        _tc.exit();
        _vimState.mode = priorMode;
      }
      if (openedLink) unawaited(_openFocusedLink());
      return;
    }
    // Drag complete — keep selection highlighted so user can adjust it, then
    // press Ctrl+C to copy. Cursor mode stays active for keyboard adjustment.
  }

  bool _isInsideBody(Mouse mouse) {
    if (mouse.y < _lastBodyY || mouse.y >= _lastBodyY + _lastBodyHeight) {
      return false;
    }
    if (mouse.x < 0 || mouse.x >= _width) return false;
    return true;
  }

  /// Maps a terminal cell to a (display-row, col) inside the visible
  /// transcript window. Returns null when the click lands on an empty
  /// transcript or outside the laid-out rows.
  Pos? _mouseToPos(Mouse mouse) {
    if (_displayRowsText.isEmpty) return null;
    final offset = mouse.y - _lastBodyY;
    final maxRow = (_lastVisibleEnd - 1).clamp(0, _displayRowsText.length - 1);
    final minRow = _lastVisibleStart.clamp(0, _displayRowsText.length - 1);
    final row = (_lastVisibleStart + offset).clamp(minRow, maxRow);
    final line = _displayRowsText[row];
    final maxCol = line.isEmpty ? 0 : line.length - 1;
    final col = mouse.x.clamp(0, maxCol);
    return Pos(row, col);
  }

  void _onMouseWheel(Mouse mouse) {
    // Scroll regardless of pointer Y — when the user reaches for the wheel
    // they want the transcript to move, even if the cursor is hovering over
    // the input prompt or footer.
    switch (mouse.button) {
      case MouseButton.wheelUp:
        _scrollBy(3);
      case MouseButton.wheelDown:
        _scrollBy(-3);
      default:
        break;
    }
  }

  void _scrollBy(int lines) {
    final next = (_transcriptScroll + lines).clamp(0, _cachedMaxScroll());
    // Clamped no-op (wheel spam at the top/bottom edge): leave the scroll
    // offset and link focus untouched so the view signature stays unchanged
    // and the frame-skip gate re-emits the cached frame instead of repainting.
    if (next == _transcriptScroll) return;
    _transcriptScroll = next;
    _focusedLinkIndex = -1;
  }

  void _cycleLink({required bool forward}) {
    if (_visibleLinks.isEmpty) {
      _focusedLinkIndex = -1;
      return;
    }
    final delta = forward ? 1 : -1;
    if (_focusedLinkIndex < 0) {
      _focusedLinkIndex = forward ? 0 : _visibleLinks.length - 1;
    } else {
      _focusedLinkIndex = (_focusedLinkIndex + delta) % _visibleLinks.length;
      if (_focusedLinkIndex < 0) _focusedLinkIndex += _visibleLinks.length;
    }
  }

  /// Hit-tests a clicked transcript cell against the visible links. [pos] is a
  /// (display-row, display-col) from [_mouseToPos]; it is mapped back to a
  /// logical line offset via the row's [startCol] so links that wrap across
  /// rows are still hittable. Sets [_focusedLinkIndex] and returns true on hit.
  bool _openLinkAtPos(Pos pos) {
    if (pos.row < 0 || pos.row >= _lastDisplayRows.length) return false;
    final dr = _lastDisplayRows[pos.row];
    final logicalCol = dr.startCol + pos.col;
    for (var i = 0; i < _visibleLinks.length; i++) {
      final vl = _visibleLinks[i];
      if (vl.transcriptLineIndex != dr.lineIndex) continue;
      if (logicalCol >= vl.visStart && logicalCol < vl.visEnd) {
        _focusedLinkIndex = i;
        return true;
      }
    }
    return false;
  }

  Future<void> _openFocusedLink() async {
    if (_focusedLinkIndex < 0 || _focusedLinkIndex >= _visibleLinks.length) {
      return;
    }
    final ref = _visibleLinks[_focusedLinkIndex];
    final loc = state.deps.vmUriResolver.resolve(
      ref.link.uri.startsWith('package:')
          ? ref.link.uri
          : _toFileUri(ref.link.uri),
      projectRoot: state.project.root,
      line: ref.link.line,
      column: ref.link.column ?? 1,
    );
    if (loc == null) {
      state.transcript.warn('Could not resolve ${ref.link.uri} to a file.');
      return;
    }
    await openInIde(loc, state);
  }

  String _toFileUri(String pathLike) {
    // Windows absolute path (`C:\…` or `C:/…`) — encode as a proper file URI so
    // the drive letter survives. `/abs` and relative paths keep old behaviour.
    if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(pathLike)) {
      return Uri.file(pathLike, windows: true).toString();
    }
    if (pathLike.startsWith('/')) return 'file://$pathLike';
    return 'file://${state.project.root}/$pathLike';
  }
}
