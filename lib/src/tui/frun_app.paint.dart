part of 'frun_app.dart';

/// Painters for the transcript body, the status panel, and the input prompt,
/// plus the display-row layout and visible-link collection they rely on.
mixin _PaintMixin on _FrunModelBase, _EngineMixin {
  // ── Paint helpers ──────────────────────────────────────────────────────

  void _paintTranscript(
    Canvas canvas,
    FrunTheme theme,
    int width,
    int y,
    int height,
  ) {
    if (height <= 0 || width <= 0) return;
    _hits.add(
      x: 0,
      y: y,
      w: width,
      h: height,
      msg: const TickWakeMsg(),
    );
    final lines = state.visibleTranscript.lines;
    final displayRows = _layoutDisplayRows(lines, width);
    _lastDisplayRows = displayRows;
    _displayRowsText = displayRows.map((r) => r.text).toList(growable: false);

    final visibleCount = height;
    final maxScroll = (displayRows.length - visibleCount).clamp(0, 1 << 30);
    if (_transcriptScroll > maxScroll) _transcriptScroll = maxScroll;
    final tail = _transcriptScroll;
    final endExclusive = displayRows.length - tail;
    final start = (endExclusive - visibleCount).clamp(0, displayRows.length);
    _lastVisibleStart = start;
    _lastVisibleEnd = endExclusive;

    if (_tc.searchQuery.isNotEmpty) _recomputeMatches();

    _visibleLinks = _collectVisibleLinks(lines, displayRows, start, endExclusive);
    if (_focusedLinkIndex >= _visibleLinks.length) {
      _focusedLinkIndex = _visibleLinks.isEmpty ? -1 : _visibleLinks.length - 1;
    }

    final focused = _focusedLinkIndex < 0 ? null : _visibleLinks[_focusedLinkIndex];
    final selection = _tc.selectionRange();
    final visualKind = _tc.visualKind;

    for (var r = start; r < endExclusive && r < displayRows.length; r++) {
      final row = displayRows[r];
      final line = lines[row.lineIndex];
      final yRow = y + (r - start);
      final baseStyle = line.onClick != null
          ? theme.accentStyle
          : theme.forLevel(line.level);
      canvas.paint(0, yRow, baseStyle.render(row.ansiPrefix + row.text));

      if (focused != null && focused.transcriptLineIndex == row.lineIndex) {
        final link = focused.link;
        final rowStart = row.startCol;
        final rowEnd = rowStart + row.text.length;
        final overlapStart = math.max(link.start, rowStart);
        final overlapEnd = math.min(link.end, rowEnd);
        if (overlapEnd > overlapStart) {
          final substring = line.text.substring(overlapStart, overlapEnd);
          canvas.paint(overlapStart - rowStart, yRow,
              theme.linkHighlightStyle.render(substring));
        }
      }

      // Search match highlights.
      for (var mi = 0; mi < _tc.matches.length; mi++) {
        final m = _tc.matches[mi];
        if (m.row != r) continue;
        final isActive = mi == _tc.activeMatchIndex;
        final style = isActive ? theme.searchActiveStyle : theme.searchMatchStyle;
        final text = row.text.substring(m.col, m.col + m.length);
        canvas.paint(m.col, yRow, style.render(text), zIndex: 2);
      }

      // Selection overlay (charwise / linewise / blockwise).
      if (selection != null && r >= selection.row && r <= selection.row2) {
        final selStyle = visualKind == VimMode.visualLine
            ? theme.visualLineStyle
            : visualKind == VimMode.visualBlock
                ? theme.visualBlockStyle
                : theme.selectionStyle;
        if (visualKind == VimMode.visualLine) {
          if (row.text.isNotEmpty) {
            canvas.paint(0, yRow, selStyle.render(row.text), zIndex: 3);
          }
        } else if (visualKind == VimMode.visualBlock) {
          final left = math.min(selection.col, selection.col2);
          final right = math.max(selection.col, selection.col2);
          final effRight = math.min(right + 1, row.text.length);
          if (effRight > left && left < row.text.length) {
            final sel = row.text.substring(left, effRight);
            canvas.paint(left, yRow, selStyle.render(sel), zIndex: 3);
          }
        } else {
          final lineStart = r == selection.row ? selection.col : 0;
          final lineEnd = r == selection.row2
              ? math.min(selection.col2 + 1, row.text.length)
              : row.text.length;
          if (lineEnd > lineStart) {
            final sel = row.text.substring(lineStart, lineEnd);
            canvas.paint(lineStart, yRow, selStyle.render(sel), zIndex: 3);
          }
        }
      }

      // Vim cursor cell (only when in transcript cursor mode).
      if (_tc.active && r == _tc.row) {
        final cell = (_tc.col < row.text.length) ? row.text[_tc.col] : ' ';
        canvas.paint(_tc.col, yRow, theme.cursorStyle.render(cell), zIndex: 4);
      }

      final onClick = line.onClick;
      if (onClick != null) {
        _hits.add(
          x: 0,
          y: yRow,
          w: width,
          h: 1,
          msg: TranscriptLineClickMsg(onClick),
        );
      }
    }
  }

  List<_DisplayRow> _layoutDisplayRows(List<TranscriptLine> lines, int width) {
    final out = <_DisplayRow>[];
    for (var i = 0; i < lines.length; i++) {
      final text = lines[i].text;
      if (text.isEmpty) {
        out.add(_DisplayRow(i, 0, ''));
        continue;
      }

      var rawPos = 0;
      var visCol = 0;
      var chunkRawStart = 0;
      var chunkAnsiPrefix = '';
      final activeSgr = <String>[];

      while (rawPos < text.length) {
        // CSI escape sequence (ESC [)?  Consume atomically — zero visual cols.
        if (text[rawPos] == '\x1b' &&
            rawPos + 1 < text.length &&
            text[rawPos + 1] == '[') {
          final seqStart = rawPos;
          rawPos += 2;
          while (rawPos < text.length) {
            final cu = text.codeUnitAt(rawPos);
            rawPos++;
            if (cu >= 0x40 && cu <= 0x7E) break; // CSI final byte
          }
          // Track SGR state so we can reopen colour on continuation rows.
          if (rawPos > 0 && text[rawPos - 1] == 'm') {
            _applyAnsiSgr(text.substring(seqStart + 2, rawPos - 1), activeSgr);
          }
          continue;
        }

        if (visCol == width) {
          out.add(_DisplayRow(
            i,
            chunkRawStart,
            text.substring(chunkRawStart, rawPos),
            ansiPrefix: chunkAnsiPrefix,
          ));
          chunkRawStart = rawPos;
          chunkAnsiPrefix =
              activeSgr.isEmpty ? '' : '\x1b[${activeSgr.join(';')}m';
          visCol = 0;
        }

        visCol++;
        rawPos++;
      }

      out.add(_DisplayRow(
        i,
        chunkRawStart,
        text.substring(chunkRawStart),
        ansiPrefix: chunkAnsiPrefix,
      ));
    }
    return out;
  }

  void _paintStatus(
    Canvas canvas,
    FrunTheme theme,
    int width,
    int y,
    int height,
  ) {
    if (height <= 0) return;
    final sep = '─' * width;
    canvas.paint(0, y, theme.borderStyle.render(sep));

    final session = state.runController.session;
    final entry = state.runController.lastEntry;
    final rows = <(String, String)>[
      ('Device', state.runController.activeTab?.deviceId ?? '(none)'),
      ('Launch', entry?.name ?? '—'),
      ('VM service', session?.vmServiceUri ?? '—'),
      ('DevTools', session?.devToolsUri ?? '—'),
    ];
    for (var i = 0; i < rows.length && i + 1 < height; i++) {
      final (label, value) = rows[i];
      canvas.paint(0, y + 1 + i, theme.titleStyle.render('$label:'.padRight(12)));
      final clipped = value.length > width - 12
          ? value.substring(0, width - 12)
          : value;
      canvas.paint(12, y + 1 + i, clipped);
    }
  }

  List<_VisibleLink> _collectVisibleLinks(
    List<TranscriptLine> lines,
    List<_DisplayRow> displayRows,
    int start,
    int endExclusive,
  ) {
    final seenLines = <int>{};
    for (var r = start; r < endExclusive && r < displayRows.length; r++) {
      seenLines.add(displayRows[r].lineIndex);
    }
    final sorted = seenLines.toList()..sort();
    final out = <_VisibleLink>[];
    for (final i in sorted) {
      for (final link in LinkExtractor.extract(lines[i].text)) {
        out.add(_VisibleLink(i, link));
      }
    }
    return out;
  }

  void _paintInput(Canvas canvas, FrunTheme theme, int width, int y, int height) {
    if (height <= 0) return;

    // Borders: top at y, content at y+1..y+height, bottom at y+height+1
    final horiz = '─' * (width - 2);
    canvas.paint(0, y, theme.borderStyle.render('┌$horiz┐'));
    canvas.paint(0, y + height + 1, theme.borderStyle.render('└$horiz┘'));
    final contentY = y + 1;

    // Ex/search prompt: single row, prefix + draft.
    if (_vimState.mode == VimMode.exCmd || _vimState.mode == VimMode.search) {
      canvas.paint(0, contentY, theme.borderStyle.render('│'));
      canvas.paint(width - 1, contentY, theme.borderStyle.render('│'));
      final prefix = _promptForMode();
      canvas.paint(1, contentY, theme.accentStyle.render(prefix));
      final draft = _vimState.mode == VimMode.exCmd
          ? _vimState.exDraft
          : _vimState.searchDraft;
      final usable = width - 2 - prefix.length;
      var visible = draft;
      if (visible.length > usable) {
        visible = visible.substring(visible.length - usable);
      }
      canvas.paint(1 + prefix.length, contentY, visible);
      final cx = 1 + prefix.length + visible.length;
      if (cx < width - 1) {
        canvas.paint(cx, contentY, theme.cursorStyle.render(' '), zIndex: 2);
      }
      return;
    }

    final prompt = _promptForMode();
    final rightInfo = _rightInputInfo();
    final lines = _input.lines;
    final cur = _input.cursor;
    final rowsToPaint = math.min(lines.length, height);

    for (var r = 0; r < rowsToPaint; r++) {
      final yRow = contentY + r;
      canvas.paint(0, yRow, theme.borderStyle.render('│'));
      canvas.paint(width - 1, yRow, theme.borderStyle.render('│'));

      final line = lines[r];
      if (r == 0) {
        canvas.paint(1, yRow, theme.promptStyle.render(prompt));
        // Run button at far right inside border
        final btnX = width - 1 - _runButtonLabel.length;
        canvas.paint(btnX, yRow, theme.buttonStyle.render(_runButtonLabel), zIndex: 1);
        _hits.add(x: btnX, y: yRow, w: _runButtonLabel.length, h: 1, msg: const RunButtonMsg());
        // Right info shifted left to make room for button
        final rightX = btnX - rightInfo.length;
        if (rightX > 1 + prompt.length) {
          canvas.paint(rightX, yRow, theme.dimStyle.render(rightInfo));
        }
        final usable = math.max(0, rightX - 1 - prompt.length);
        var visible = line;
        var cursorOffset = cur.col;
        if (visible.length > usable) {
          final start = (cursorOffset - usable + 1).clamp(0, visible.length);
          visible = visible.substring(start);
          cursorOffset -= start;
        }
        final clipped = visible.length > usable ? visible.substring(0, usable) : visible;
        canvas.paint(1 + prompt.length, yRow, clipped);
        final showSoftCursor = r == cur.row && !_tc.active;
        if (showSoftCursor) {
          final cx = 1 + prompt.length + cursorOffset;
          if (cx < rightX) {
            final ch = cursorOffset < visible.length ? visible[cursorOffset] : ' ';
            canvas.paint(cx, yRow, theme.cursorStyle.render(ch), zIndex: 2);
          }
        }
      } else {
        canvas.paint(1, yRow, theme.dimStyle.render('  '));
        final usable = math.max(0, width - 4); // │ + '  ' + text + │
        var visible = line;
        var cursorOffset = (r == cur.row) ? cur.col : 0;
        if (visible.length > usable) {
          final start = (cursorOffset - usable + 1).clamp(0, visible.length);
          visible = visible.substring(start);
          cursorOffset -= start;
        }
        final clipped = visible.length > usable ? visible.substring(0, usable) : visible;
        canvas.paint(3, yRow, clipped);
        final showSoftCursor = r == cur.row && !_tc.active;
        if (showSoftCursor) {
          final cx = 3 + cursorOffset;
          if (cx < width - 1) {
            final ch = cursorOffset < visible.length ? visible[cursorOffset] : ' ';
            canvas.paint(cx, yRow, theme.cursorStyle.render(ch), zIndex: 2);
          }
        }
      }
    }
  }

  String _rightInputInfo() {
    final tabCount = state.runController.tabs.length;
    final parts = <String>[
      state.project.name,
      state.config.ide.id,
      if (tabCount > 0) 'tabs:$tabCount',
    ];
    return ' ${parts.join('  ')} ';
  }
}
