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
      final canvas = _cellCanvas..reset(math.max(w, 40), math.max(h, 10));
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
    final sigUnchanged = _viewSignatureUnchanged(w, h);
    if (!_mouseSelecting &&
        _lastViewContent != null &&
        sigUnchanged &&
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
    final isolatesH = _computeIsolatesPanelHeight();
    final statusH = state.showStatusPanel
        ? _statusHeight(
            h,
            infoBarH +
                pickerH +
                totalInputH +
                configEditorH +
                diagnosticsH +
                isolatesH,
          )
        : 0;
    final bodyH =
        h -
        totalInputH -
        statusH -
        infoBarH -
        pickerH -
        configEditorH -
        diagnosticsH -
        isolatesH;
    _lastBodyHeight = bodyH;
    _lastBodyY = 0;

    final canvas = _cellCanvas..reset(w, h);

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
    if (isolatesH > 0) {
      _paintIsolatesPanel(
        canvas,
        theme,
        w,
        h - totalInputH - infoBarH - diagnosticsH - isolatesH,
        isolatesH,
      );
    }
    _paintInfoBar(canvas, theme, w, h - totalInputH - infoBarH, infoBarH);
    _paintInput(canvas, theme, w, h - totalInputH, inputH);

    final showCursor = _shouldShowHardwareCursor();
    final inputCursor = showCursor
        ? _inputCursorPosition(w, h - totalInputH + 1, inputH)
        : null;

    final content = canvas.render();
    _sigPrevious.setAll(0, _sigCurrent);
    _sigValid = true;
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
  /// frame, written into the preallocated [_sigCurrent] slots. Returns whether
  /// it matches the previous painted frame's signature (so the paint can be
  /// skipped). Identity hashes are used for collections/objects that are
  /// replaced wholesale on change (config, diagnostics, picker lists,
  /// sessions); content hashes for the free-text fields; monotonic revisions
  /// for the isolate list and diagnostics. Anything missed here self-heals
  /// within _maxSkippedFrames ticks via the forced repaint.
  bool _viewSignatureUnchanged(int w, int h) {
    final rc = state.runController;
    final transcript = state.visibleTranscript;
    var tabsHash = 0x345678;
    for (final t in rc.tabs) {
      tabsHash = 0x3fffffff & (tabsHash * 31 + t.id.hashCode);
      tabsHash = 0x3fffffff & (tabsHash * 31 + (t.isRunning ? 1 : 0));
    }
    final sig = _sigCurrent;
    var i = 0;
    sig[i++] = w;
    sig[i++] = h;
    sig[i++] = identityHashCode(state.config);
    sig[i++] = identityHashCode(transcript);
    sig[i++] = transcript.revision;
    sig[i++] = _transcriptScroll;
    sig[i++] = _focusedLinkIndex;
    sig[i++] = _input.text.hashCode;
    sig[i++] = _input.cursor.row;
    sig[i++] = _input.cursor.col;
    sig[i++] = _vimState.mode.index;
    sig[i++] = _tc.active ? 1 : 0;
    sig[i++] = _tc.searchQuery.hashCode;
    sig[i++] = _tc.row;
    sig[i++] = _tc.col;
    sig[i++] = state.showStatusPanel ? 1 : 0;
    sig[i++] = _configEditorActive ? 1 : 0;
    sig[i++] = _configEditorRow;
    sig[i++] = identityHashCode(_configDraft);
    sig[i++] = state.showDiagnosticsPanel ? 1 : 0;
    sig[i++] = state.showIsolatesPanel ? 1 : 0;
    sig[i++] = _diagSel.index;
    sig[i++] = _diagSel.scroll;
    sig[i++] = _isolateSel.index;
    sig[i++] = _isolateSel.scroll;
    sig[i++] = state.diagnosticsFilter?.index ?? -1;
    sig[i++] = state.diagnosticsSearch.hashCode;
    sig[i++] = _diagSearching ? 1 : 0;
    sig[i++] = state.diagnosticsRevision;
    sig[i++] = identityHashCode(state.diagnostics);
    sig[i++] = state.diagnostics.length;
    sig[i++] = identityHashCode(_activePicker());
    sig[i++] = _pickerSel.index;
    sig[i++] = _pickerSel.scroll;
    sig[i++] = _pickerWasActive ? 1 : 0;
    sig[i++] = identityHashCode(rc.session);
    sig[i++] = identityHashCode(rc.lastEntry);
    sig[i++] = identityHashCode(rc.activeTab);
    sig[i++] = rc.tabs.length;
    sig[i++] = tabsHash;
    sig[i++] = state.deps.isolateManager.revision;
    sig[i++] = state.deps.isolateManager.isConnected ? 1 : 0;
    // Vim mode-chip inputs: showcmd pendings and the macro-recording flag
    // (engine-internal state with no other host mirror — without these slots
    // the chip lags up to _maxSkippedFrames ticks).
    sig[i++] = Object.hash(
      _vimState.pendingOpCount,
      _vimState.pendingCount,
      _vimState.pendingOperator,
      _vimState.pendingG,
      _vimState.pendingZ,
      _vimState.pendingFind,
      _vimState.pendingRegister,
      _vimState.pendingMarkOp,
      _vimState.pendingReplaceChar,
    );
    sig[i++] = _vimState.macros.recording?.codeUnitAt(0) ?? 0;
    assert(i == _FrunModelBase._sigLength);

    if (!_sigValid) return false;
    final prev = _sigPrevious;
    for (var j = 0; j < _FrunModelBase._sigLength; j++) {
      if (sig[j] != prev[j]) return false;
    }
    return true;
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
    return _input.lineCount.clamp(1, _maxInputRows);
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
