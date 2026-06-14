part of 'frun_app.dart';

/// The top-level `view()` and its layout/sizing helpers.
mixin _ViewMixin on _FrunModelBase, _PaintMixin, _OverlayMixin {
  // ── View ───────────────────────────────────────────────────────────────

  @override
  View view() {
    _hits.clear();
    final theme = FrunTheme.fromConfig(state.config);
    final w = _width;
    final h = _height;

    if (w < 40 || h < 10) {
      final canvas = Canvas(math.max(w, 40), math.max(h, 10));
      canvas.paint(0, 0, 'frun: terminal too small (${w}x$h)');
      return View(
        content: canvas.render(),
        altScreen: true,
        mouseMode: MouseMode.cellMotion,
      );
    }

    final inputH = _computeInputHeight();
    final inputBorderH = inputH > 0 ? 2 : 0;
    final totalInputH = inputH + inputBorderH;
    final infoBarH = _computeInfoBarHeight(w);
    final picker = _activePicker();
    final pickerH = _computePickerHeight(picker);
    final configEditorH = _computeConfigEditorHeight();
    final statusH = state.showStatusPanel ? _statusHeight(h, infoBarH + pickerH + totalInputH + configEditorH) : 0;
    final bodyH = h - totalInputH - statusH - infoBarH - pickerH - configEditorH;
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
    _paintInfoBar(canvas, theme, w, h - totalInputH - infoBarH, infoBarH);
    _paintInput(canvas, theme, w, h - totalInputH, inputH);

    final showCursor = _shouldShowHardwareCursor();
    final inputCursor = showCursor
        ? _inputCursorPosition(w, h - totalInputH + 1, inputH)
        : null;

    return View(
      content: canvas.render(),
      altScreen: true,
      mouseMode: MouseMode.cellMotion,
      cursor: inputCursor,
    );
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
        : (mode == VimMode.insert || state.config.editorMode == FrunEditorMode.normal
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
