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
  _ViewSignature _viewSignature(int w, int h) {
    final rc = state.runController;
    final transcript = state.visibleTranscript;
    var isolatesHash = 0x456789;
    for (final iso in state.deps.isolateManager.isolates) {
      isolatesHash = 0x3fffffff & (isolatesHash * 31 + iso.id.hashCode);
      isolatesHash = 0x3fffffff & (isolatesHash * 31 + iso.name.hashCode);
      isolatesHash = 0x3fffffff & (isolatesHash * 31 + iso.status.index);
      isolatesHash =
          0x3fffffff & (isolatesHash * 31 + (iso.pauseReason?.hashCode ?? 0));
    }
    var tabsHash = 0x345678;
    for (final t in rc.tabs) {
      tabsHash = 0x3fffffff & (tabsHash * 31 + t.id.hashCode);
      tabsHash = 0x3fffffff & (tabsHash * 31 + (t.isRunning ? 1 : 0));
    }
    return _ViewSignature(<int>[
      w,
      h,
      identityHashCode(state.config),
      identityHashCode(transcript),
      transcript.revision,
      _transcriptScroll,
      _focusedLinkIndex,
      _input.text.hashCode,
      _input.cursor.row,
      _input.cursor.col,
      _vimState.mode.index,
      _tc.active ? 1 : 0,
      _tc.searchQuery.hashCode,
      _tc.row,
      _tc.col,
      state.showStatusPanel ? 1 : 0,
      _configEditorActive ? 1 : 0,
      _configEditorRow,
      identityHashCode(_configDraft),
      state.showDiagnosticsPanel ? 1 : 0,
      state.showIsolatesPanel ? 1 : 0,
      _diagSelectedIndex,
      _diagScrollOffset,
      _isolateSelectedIndex,
      _isolateScrollOffset,
      state.diagnosticsFilter?.index ?? -1,
      state.diagnosticsSearch.hashCode,
      _diagSearching ? 1 : 0,
      state.diagnosticsRevision,
      identityHashCode(state.diagnostics),
      state.diagnostics.length,
      identityHashCode(_activePicker()),
      _pickerSelectedIndex,
      _pickerScrollOffset,
      _pickerWasActive ? 1 : 0,
      identityHashCode(rc.session),
      identityHashCode(rc.lastEntry),
      identityHashCode(rc.activeTab),
      rc.tabs.length,
      tabsHash,
      isolatesHash,
      state.deps.isolateManager.service == null ? 0 : 1,
    ]);
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
