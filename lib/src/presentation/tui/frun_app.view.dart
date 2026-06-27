part of 'frun_app.dart';

/// The top-level `view()` and its layout/sizing helpers.
mixin _ViewMixin on _FrunModelBase, _PaintMixin, _OverlayMixin {
  // ── View ───────────────────────────────────────────────────────────────

  @override
  View view() {
    final w = _width;
    final h = _height;

    if (w < 40 || h < 10) {
      _hits.clear();
      final canvas = Canvas(math.max(w, 40), math.max(h, 10));
      canvas.paint(0, 0, 'frun: terminal too small (${w}x$h)');
      return View(
        content: canvas.render(),
        altScreen: true,
        mouseMode: MouseMode.cellMotion,
      );
    }

    // Repaint gate: re-emit the last frame when nothing render-affecting
    // changed. Always repaint while drag-selecting (the selection extent moves
    // with the mouse and isn't in the signature) and at least once per
    // _maxSkippedFrames ticks as a self-heal.
    final sig = _viewSignature(w, h);
    if (!_mouseSelecting &&
        _lastViewContent != null &&
        sig == _lastViewSig &&
        _framesSinceFullPaint < _FrunModelBase._maxSkippedFrames) {
      _framesSinceFullPaint++;
      return View(
        content: _lastViewContent!,
        altScreen: true,
        mouseMode: MouseMode.cellMotion,
        cursor: _lastViewCursor,
      );
    }

    _hits.clear();
    final theme = FrunTheme.fromConfig(state.config);

    final inputH = _computeInputHeight();
    final inputBorderH = inputH > 0 ? 2 : 0;
    final totalInputH = inputH + inputBorderH;
    final infoBarH = _computeInfoBarHeight(w);
    final picker = _activePicker();
    final pickerH = _computePickerHeight(picker);
    final configEditorH = _computeConfigEditorHeight();
    final diagnosticsH = _computeDiagnosticsHeight();
    final statusH = state.showStatusPanel
        ? _statusHeight(
            h,
            infoBarH + pickerH + totalInputH + configEditorH + diagnosticsH,
          )
        : 0;
    final bodyH =
        h -
        totalInputH -
        statusH -
        infoBarH -
        pickerH -
        configEditorH -
        diagnosticsH;
    _lastBodyHeight = bodyH;
    _lastBodyY = 0;

    final canvas = Canvas(w, h);

    _paintTranscript(canvas, theme, w, 0, bodyH);
    if (state.showStatusPanel) {
      _paintStatus(canvas, theme, w, bodyH, statusH);
    }
    if (pickerH > 0 && picker != null) {
      _paintPicker(
        canvas,
        theme,
        picker,
        w,
        h - totalInputH - infoBarH - pickerH,
        pickerH,
      );
    }
    if (configEditorH > 0) {
      _paintConfigEditor(
        canvas,
        theme,
        w,
        h - totalInputH - infoBarH - pickerH - configEditorH,
        configEditorH,
      );
    }
    if (diagnosticsH > 0) {
      _paintDiagnosticsPanel(
        canvas,
        theme,
        w,
        h - totalInputH - infoBarH - diagnosticsH,
        diagnosticsH,
      );
    }
    _paintInfoBar(canvas, theme, w, h - totalInputH - infoBarH, infoBarH);
    _paintInput(canvas, theme, w, h - totalInputH, inputH);

    final showCursor = _shouldShowHardwareCursor();
    final inputCursor = showCursor
        ? _inputCursorPosition(w, h - totalInputH + 1, inputH)
        : null;

    final content = canvas.render();
    _lastViewSig = sig;
    _lastViewContent = content;
    _lastViewCursor = inputCursor;
    _framesSinceFullPaint = 0;

    return View(
      content: content,
      altScreen: true,
      mouseMode: MouseMode.cellMotion,
      cursor: inputCursor,
    );
  }

  /// Compact fingerprint of every piece of state that affects the rendered
  /// frame. When it is unchanged between ticks the paint is skipped. Identity
  /// hashes are used for collections/objects that are replaced wholesale on
  /// change (config, diagnostics, picker lists, sessions); content hashes for
  /// the free-text fields. Anything missed here self-heals within
  /// _maxSkippedFrames ticks via the forced repaint.
  String _viewSignature(int w, int h) {
    final rc = state.runController;
    final b = StringBuffer()
      ..write(w)
      ..write('x')
      ..write(h)
      ..write('|cfg:')
      ..write(identityHashCode(state.config))
      ..write('|tx:')
      ..write(identityHashCode(state.visibleTranscript))
      ..write('.')
      ..write(state.visibleTranscript.revision)
      ..write('|scr:')
      ..write(_transcriptScroll)
      ..write('|lnk:')
      ..write(_focusedLinkIndex)
      ..write('|in:')
      ..write(_input.text.hashCode)
      ..write('.')
      ..write(_input.cursor.row)
      ..write(',')
      ..write(_input.cursor.col)
      ..write('|vm:')
      ..write(_vimState.mode.index)
      ..write('|tc:')
      ..write(_tc.active ? 1 : 0)
      ..write('.')
      ..write(_tc.searchQuery.hashCode)
      ..write('.')
      ..write(_tc.row)
      ..write(',')
      ..write(_tc.col)
      ..write('|ov:')
      ..write(state.showStatusPanel ? 1 : 0)
      ..write(_configEditorActive ? 1 : 0)
      ..write('.')
      ..write(_configEditorRow)
      ..write('.')
      ..write(identityHashCode(_configDraft))
      ..write('|dg:')
      ..write(state.showDiagnosticsPanel ? 1 : 0)
      ..write('.')
      ..write(_diagSelectedIndex)
      ..write(',')
      ..write(_diagScrollOffset)
      ..write('.')
      ..write(state.diagnosticsFilter?.index ?? -1)
      ..write('.')
      ..write(state.diagnosticsSearch.hashCode)
      ..write('.')
      ..write(_diagSearching ? 1 : 0)
      ..write('|dx:')
      ..write(identityHashCode(state.diagnostics))
      ..write('.')
      ..write(state.diagnostics.length)
      ..write('.')
      ..write(state.deps.analysisServer != null ? 1 : 0)
      ..write(state.deps.analysisError != null ? 1 : 0)
      ..write('|pk:')
      ..write(identityHashCode(_activePicker()))
      ..write('.')
      ..write(_pickerSelectedIndex)
      ..write(',')
      ..write(_pickerScrollOffset)
      ..write(_pickerWasActive ? 1 : 0)
      ..write('|rc:')
      ..write(identityHashCode(rc.session))
      ..write('.')
      ..write(identityHashCode(rc.lastEntry))
      ..write('.')
      ..write(identityHashCode(rc.activeTab))
      ..write('|tabs:');
    for (final t in rc.tabs) {
      b
        ..write(t.id)
        ..write(t.isRunning ? '+' : '-');
    }
    return b.toString();
  }

  bool _shouldShowHardwareCursor() {
    // dart_tui 1.2.0's renderer does not honor Cursor.x/y — it only toggles
    // visibility. Returning true would leave the hardware cursor parked at
    // wherever the last cell write landed (usually the footer). We draw a
    // software cursor in _paintInput / _paintTranscript instead.
    return false;
  }

  int _computeInputHeight() {
    if (state.hasActivePicker) return 0;
    if (_configEditorActive) return 0;
    if (_vimState.mode == VimMode.exCmd || _vimState.mode == VimMode.search) {
      return 1;
    }
    final lines = _input.lines.length;
    return lines.clamp(1, _maxInputRows);
  }

  int _statusHeight(int totalHeight, int otherH) {
    const desired = 5;
    final available = totalHeight - 3 - otherH;
    return desired.clamp(0, available.clamp(0, desired));
  }

  Cursor? _inputCursorPosition(int width, int inputY, int inputH) {
    final mode = _vimState.mode;
    final shape = mode == VimMode.replace
        ? CursorShape.underline
        : (mode == VimMode.insert ||
                  state.config.editorMode == FrunEditorMode.normal
              ? CursorShape.bar
              : CursorShape.block);
    final prompt = _promptForMode();
    final cur = _input.cursor;
    final cursorRow = cur.row.clamp(0, inputH - 1);
    final usable = width - prompt.length;
    var cursorOffset = cur.col;
    final line = _input.lineAt(cur.row);
    if (line.length > usable) {
      final start = (cursorOffset - usable + 1).clamp(0, line.length);
      cursorOffset -= start;
    }
    final cursorX = prompt.length + cursorOffset;
    if (cursorX >= width) return null;
    return Cursor(x: cursorX, y: inputY + cursorRow, shape: shape);
  }
}
