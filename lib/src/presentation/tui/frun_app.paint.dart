part of 'frun_app.dart';

/// Painters for the transcript body, the status panel, and the input prompt,
/// plus the display-row layout and visible-link collection they rely on.
mixin _PaintMixin on _FrunModelBase, _EngineMixin {
  // ── Paint helpers ──────────────────────────────────────────────────────

  void _paintTranscript(
    CellCanvas canvas,
    FrunTheme theme,
    int width,
    int y,
    int height,
  ) {
    if (height <= 0 || width <= 0) return;
    _hits.add(x: 0, y: y, w: width, h: height, msg: const TickWakeMsg());
    final transcript = state.visibleTranscript;
    final layout = _syncTranscriptLayout(transcript, width);
    final lines = layout.lines;
    final displayRows = layout.rows;

    // Keep the viewport anchored to the same content when the user has scrolled
    // up and new lines are appended at the bottom. _transcriptScroll is a tail
    // offset (rows hidden below the viewport); a bottom append grows the total
    // row count, which would otherwise slide the window forward and scroll the
    // content being read off the top. Compensate by growing the tail offset by
    // the appended row count. Using appended rows instead of total-row delta
    // matters when scrollback trimming removes old rows at the top while new
    // rows arrive at the bottom; total rows may stay flat, but the tail offset
    // still needs to grow to keep the same visible content. At the bottom
    // (offset == 0) the view keeps following new output — unless the user is
    // reading with the transcript cursor (vim navigation or an in-progress
    // drag selection), where sliding the text out from under them loses their
    // place even inside the bottom screen. Skip on width changes, where the
    // row count shifts from re-wrapping rather than new content.
    final total = displayRows.length;
    if (width == _lastLayoutWidth && (_transcriptScroll > 0 || _tc.active)) {
      final appendedRows = _layoutAppendedRowCount;
      if (appendedRows > 0) {
        _transcriptScroll += appendedRows;
      } else {
        final delta = total - _lastTotalRows;
        if (delta > 0) _transcriptScroll += delta;
      }
    }
    // Scrollback trim shifted every surviving row up; move row-anchored
    // reading state (cursor, selection, drag anchor) with the content.
    final droppedRows = _layoutDroppedRowCount;
    if (droppedRows > 0) {
      _tc.shiftRows(droppedRows);
      final anchor = _mouseAnchor;
      if (anchor != null) {
        _mouseAnchor = Pos(math.max(0, anchor.row - droppedRows), anchor.col);
      }
    }
    _lastTotalRows = total;
    _lastLayoutWidth = width;

    final visibleCount = height;
    final maxScroll = (displayRows.length - visibleCount).clamp(0, 1 << 30);
    if (_transcriptScroll > maxScroll) _transcriptScroll = maxScroll;
    final tail = _transcriptScroll;
    final endExclusive = displayRows.length - tail;
    final start = (endExclusive - visibleCount).clamp(0, displayRows.length);
    _lastVisibleStart = start;
    _lastVisibleEnd = endExclusive;

    if (_tc.searchQuery.isNotEmpty) {
      final searchFresh =
          identical(transcript, _searchCacheTranscript) &&
          transcript.revision == _searchCacheRevision &&
          width == _searchCacheWidth &&
          _tc.searchQuery == _searchCacheQuery;
      if (searchFresh) {
        _tc.matches = _searchCacheMatches;
        _searchMatchIndexesByRow = _searchCacheMatchIndexesByRow;
      } else {
        _recomputeMatches();
      }
    }

    _visibleLinks = _syncVisibleLinks(
      transcript,
      lines,
      displayRows,
      start,
      endExclusive,
      width,
    );
    if (_focusedLinkIndex >= _visibleLinks.length) {
      _focusedLinkIndex = _visibleLinks.isEmpty ? -1 : _visibleLinks.length - 1;
    }

    final focused = _focusedLinkIndex < 0
        ? null
        : _visibleLinks[_focusedLinkIndex];
    final selection = _tc.selectionRange();
    final visualKind = _tc.visualKind;

    final baseIndex = transcript.baseIndex;
    for (var r = start; r < endExclusive && r < displayRows.length; r++) {
      final row = displayRows[r];
      final line = lines[row.lineIndex - baseIndex];
      final yRow = y + (r - start);
      final baseStyle = line.onClick != null
          ? theme.accentStyle
          : theme.forLevel(line.level);
      // Rows on the layout fast path reuse the source string and are known
      // ANSI-free; other rows pay the escape parse once, then replay the
      // cached style runs on every subsequent frame.
      if (identical(row.rendered, row.text)) {
        canvas.paint(0, yRow, row.text, style: baseStyle);
      } else {
        var runs = row.runsCache;
        if (runs == null) {
          runs = row.runsCache = CellCanvas.parseAnsiRuns(row.rendered);
          _debugAnsiRunParses++;
          assert(
            (runs.isEmpty ? 0 : runs.last.end) == row.text.length,
            'style-run parse drifted from the row\'s visible text',
          );
        }
        canvas.paintRuns(0, yRow, row.text, runs, baseStyle: baseStyle);
      }

      if (focused != null && focused.transcriptLineIndex == row.lineIndex) {
        final rowStart = row.startCol;
        final rowEnd = rowStart + row.text.length;
        final overlapStart = math.max(focused.visStart, rowStart);
        final overlapEnd = math.min(focused.visEnd, rowEnd);
        if (overlapEnd > overlapStart) {
          canvas.paint(
            overlapStart - rowStart,
            yRow,
            row.text,
            style: theme.linkHighlightStyle,
            start: overlapStart - rowStart,
            end: overlapEnd - rowStart,
          );
        }
      }

      // Search match highlights.
      final matchIndexes = _searchMatchIndexesByRow[r];
      if (matchIndexes != null) {
        for (final mi in matchIndexes) {
          final m = _tc.matches[mi];
          final isActive = mi == _tc.activeMatchIndex;
          final style = isActive
              ? theme.searchActiveStyle
              : theme.searchMatchStyle;
          canvas.paint(
            m.col,
            yRow,
            row.text,
            style: style,
            zIndex: 2,
            start: m.col,
            end: m.col + m.length,
          );
        }
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
            canvas.paint(0, yRow, row.text, style: selStyle, zIndex: 3);
          }
        } else if (visualKind == VimMode.visualBlock) {
          final left = math.min(selection.col, selection.col2);
          final right = math.max(selection.col, selection.col2);
          final effRight = math.min(right + 1, row.text.length);
          if (effRight > left && left < row.text.length) {
            canvas.paint(
              left,
              yRow,
              row.text,
              style: selStyle,
              zIndex: 3,
              start: left,
              end: effRight,
            );
          }
        } else {
          final lineStart = r == selection.row ? selection.col : 0;
          final lineEnd = r == selection.row2
              ? math.min(selection.col2 + 1, row.text.length)
              : row.text.length;
          if (lineEnd > lineStart) {
            canvas.paint(
              lineStart,
              yRow,
              row.text,
              style: selStyle,
              zIndex: 3,
              start: lineStart,
              end: lineEnd,
            );
          }
        }
      }

      // Vim cursor cell (only when in transcript cursor mode).
      if (_tc.active && r == _tc.row) {
        if (_tc.col < row.text.length) {
          canvas.paint(
            _tc.col,
            yRow,
            row.text,
            style: theme.cursorStyle,
            zIndex: 4,
            start: _tc.col,
            end: _tc.col + 1,
          );
        } else {
          canvas.paint(_tc.col, yRow, ' ', style: theme.cursorStyle, zIndex: 4);
        }
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

  ({List<TranscriptLine> lines, List<_DisplayRow> rows}) _syncTranscriptLayout(
    Transcript transcript,
    int width,
  ) {
    if (identical(transcript, _layoutCacheTranscript) &&
        transcript.revision == _layoutCacheRevision &&
        width == _layoutCacheWidth) {
      _layoutAppendedRowCount = 0;
      _layoutDroppedRowCount = 0;
      return (lines: _lastLines, rows: _lastDisplayRows);
    }

    final lines = transcript.snapshot;
    final baseIndex = transcript.baseIndex;
    final sameTranscript = identical(transcript, _layoutCacheTranscript);
    final sameWidth = width == _layoutCacheWidth;
    final removed = baseIndex - _layoutCacheBaseIndex;
    final canIncrement =
        sameTranscript &&
        sameWidth &&
        removed >= 0 &&
        removed <= _layoutCacheLineCount &&
        _layoutCacheRevision >= 0;

    if (canIncrement) {
      final survivorCount = _layoutCacheLineCount - removed;
      if (survivorCount <= lines.length) {
        _layoutDroppedRowCount = 0;
        if (removed > 0) {
          // Rows carry absolute line indices, so eviction is just advancing
          // the head past rows whose line fell below the new baseIndex —
          // O(dropped rows), no survivor copy or re-index.
          var head = _rowsHead;
          while (head < _rowsBuffer.length &&
              _rowsBuffer[head].lineIndex < baseIndex) {
            head++;
          }
          _layoutDroppedRowCount = head - _rowsHead;
          _rowsHead = head;
          _compactRowBuffersIfNeeded();
        }

        if (survivorCount < lines.length) {
          final appended = _layoutDisplayRows(
            lines.sublist(survivorCount),
            width,
            startLineIndex: baseIndex + survivorCount,
          );
          _layoutAppendedRowCount = appended.length;
          _rowsBuffer.addAll(appended);
          for (final r in appended) {
            _rowTextsBuffer.add(r.text);
          }
        } else {
          _layoutAppendedRowCount = 0;
        }

        // Keep the per-line link cache aligned with the retained lines:
        // evicted lines advance the head (compacting once the dead prefix
        // outgrows the live region), appended lines get an unextracted slot.
        if (removed > 0) {
          _lineLinksHead += removed;
          if (_lineLinksHead > _lineLinksBuffer.length - _lineLinksHead) {
            _lineLinksBuffer.removeRange(0, _lineLinksHead);
            _lineLinksHead = 0;
          }
        }
        for (var i = survivorCount; i < lines.length; i++) {
          _lineLinksBuffer.add(null);
        }
        assert(
          _lineLinksBuffer.length - _lineLinksHead == lines.length,
          'line-link cache drifted from the transcript',
        );

        _lastLines = lines;
        _layoutCacheTranscript = transcript;
        _layoutCacheRevision = transcript.revision;
        _layoutCacheWidth = width;
        _layoutCacheBaseIndex = baseIndex;
        _layoutCacheLineCount = lines.length;
        return (lines: lines, rows: _lastDisplayRows);
      }
    }

    final rows = _layoutDisplayRows(lines, width, startLineIndex: baseIndex);
    _layoutAppendedRowCount = 0;
    _layoutDroppedRowCount = 0;
    _lastLines = lines;
    _rowsBuffer
      ..clear()
      ..addAll(rows);
    _rowTextsBuffer.clear();
    for (final r in rows) {
      _rowTextsBuffer.add(r.text);
    }
    _rowsHead = 0;
    _rowsBufferGeneration++;
    _debugRowBufferCopies++;
    _lineLinksBuffer
      ..clear()
      ..addAll(List<List<_VisibleLink>?>.filled(lines.length, null));
    _lineLinksHead = 0;
    _layoutCacheTranscript = transcript;
    _layoutCacheRevision = transcript.revision;
    _layoutCacheWidth = width;
    _layoutCacheBaseIndex = baseIndex;
    _layoutCacheLineCount = lines.length;
    return (lines: lines, rows: _lastDisplayRows);
  }

  /// Compact the evicted prefix out of the row buffers once it outgrows the
  /// live region, keeping head-advance eviction amortized O(1) per row.
  void _compactRowBuffersIfNeeded() {
    if (_rowsHead > _rowsBuffer.length - _rowsHead) {
      _rowsBuffer.removeRange(0, _rowsHead);
      _rowTextsBuffer.removeRange(0, _rowsHead);
      _rowsHead = 0;
      _rowsBufferGeneration++;
      _debugRowBufferCopies++;
    }
  }

  List<_DisplayRow> _layoutDisplayRows(
    List<TranscriptLine> lines,
    int width, {
    int startLineIndex = 0,
  }) {
    _debugLayoutBuilds++;
    final out = <_DisplayRow>[];
    for (var i = 0; i < lines.length; i++) {
      final lineIndex = startLineIndex + i;
      final text = lines[i].text;
      if (text.isEmpty) {
        out.add(_DisplayRow(lineIndex, 0, ''));
        continue;
      }

      // Fast path: a plain (no ANSI) line that fits the wrap width needs no
      // per-char scan and no soft-wrap — emit one row reusing the original
      // String for both `text` and `rendered` so the layout cache points back
      // at the transcript's existing chars instead of cloning them twice.
      if (text.length <= width && !text.contains('\x1b')) {
        out.add(_DisplayRow(lineIndex, 0, text, rendered: text));
        continue;
      }

      var rawPos = 0;
      var visCol = 0; // visible columns emitted in the current chunk
      var totalVis = 0; // visible columns emitted in the whole line so far
      var chunkRawStart = 0;
      var chunkVisStart = 0;
      var chunkAnsiPrefix = '';
      final activeSgr = <String>[];
      final visBuf = StringBuffer(); // visible (ANSI-stripped) chunk text

      void flush(int rawEnd) {
        out.add(
          _DisplayRow(
            lineIndex,
            chunkVisStart,
            visBuf.toString(),
            rendered: chunkAnsiPrefix + text.substring(chunkRawStart, rawEnd),
          ),
        );
      }

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
          flush(rawPos);
          chunkRawStart = rawPos;
          chunkVisStart = totalVis;
          chunkAnsiPrefix = activeSgr.isEmpty
              ? ''
              : '\x1b[${activeSgr.join(';')}m';
          visCol = 0;
          visBuf.clear();
        }

        visBuf.write(text[rawPos]);
        visCol++;
        totalVis++;
        rawPos++;
      }

      flush(text.length);
    }
    return out;
  }

  List<_VisibleLink> _syncVisibleLinks(
    Transcript transcript,
    List<TranscriptLine> lines,
    List<_DisplayRow> displayRows,
    int start,
    int endExclusive,
    int width,
  ) {
    if (identical(transcript, _visibleLinksCacheTranscript) &&
        transcript.revision == _visibleLinksCacheRevision &&
        width == _visibleLinksCacheWidth &&
        start == _visibleLinksCacheStart &&
        endExclusive == _visibleLinksCacheEnd) {
      return _visibleLinksCache;
    }

    final links = _collectVisibleLinks(
      lines,
      displayRows,
      start,
      endExclusive,
      transcript.baseIndex,
    );
    _debugVisibleLinkBuilds++;
    _visibleLinksCacheTranscript = transcript;
    _visibleLinksCacheRevision = transcript.revision;
    _visibleLinksCacheWidth = width;
    _visibleLinksCacheStart = start;
    _visibleLinksCacheEnd = endExclusive;
    _visibleLinksCache = links;
    return links;
  }

  void _paintStatus(
    CellCanvas canvas,
    FrunTheme theme,
    int width,
    int y,
    int height,
  ) {
    if (height <= 0) return;
    _paintDivider(canvas, theme, width, y, title: 'Status');

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
      canvas.paint(
        1,
        y + 1 + i,
        label.padRight(11),
        style: theme.panelSubtitleStyle,
      );
      final maxValue = math.max(0, width - 14);
      final clipped = _clipCellText(value, maxValue);
      final valueStyle = value == '—' || value == '(none)'
          ? theme.emptyStyle
          : theme.valueStyle;
      canvas.paint(13, y + 1 + i, clipped, style: valueStyle);
    }
  }

  List<_VisibleLink> _collectVisibleLinks(
    List<TranscriptLine> lines,
    List<_DisplayRow> displayRows,
    int start,
    int endExclusive,
    int baseIndex,
  ) {
    final out = <_VisibleLink>[];
    // Rows are laid out line by line, so lineIndex is non-decreasing across
    // the window — consecutive dedupe replaces the old Set + sort.
    var prevLine = -1;
    for (var r = start; r < endExclusive && r < displayRows.length; r++) {
      final lineIndex = displayRows[r].lineIndex;
      if (lineIndex == prevLine) continue;
      prevLine = lineIndex;
      final slot = _lineLinksHead + (lineIndex - baseIndex);
      var cached = _lineLinksBuffer[slot];
      cached ??= _lineLinksBuffer[slot] = _extractLineLinks(
        lineIndex,
        lines[lineIndex - baseIndex].text,
      );
      out.addAll(cached);
    }
    return out;
  }

  /// Extract links from one source line and map their raw offsets into
  /// visible-column space. Runs at most once per retained line — results are
  /// cached in `_lineLinksBuffer` for the line's lifetime, so scrolling never
  /// re-runs the regex. Regex matches are ordered and non-overlapping, so one
  /// left-to-right [_visibleWidths] scan maps every start/end offset.
  List<_VisibleLink> _extractLineLinks(int lineIndex, String src) {
    _debugLinkExtractions++;
    final links = LinkExtractor.extract(src);
    if (links.isEmpty) return const <_VisibleLink>[];
    final offsets = <int>[];
    for (final link in links) {
      offsets
        ..add(link.start)
        ..add(link.end);
    }
    final cols = _visibleWidths(src, offsets);
    final out = <_VisibleLink>[];
    for (var i = 0; i < links.length; i++) {
      out.add(_VisibleLink(lineIndex, links[i], cols[2 * i], cols[2 * i + 1]));
    }
    return out;
  }

  void _paintInput(
    CellCanvas canvas,
    FrunTheme theme,
    int width,
    int y,
    int height,
  ) {
    if (height <= 0) return;

    // Borders: top at y, content at y+1..y+height, bottom at y+height+1
    final horiz = '─' * (width - 2);
    canvas.paint(0, y, '╭$horiz╮', style: theme.inputBorderStyle);
    canvas.paint(0, y + height + 1, '╰$horiz╯', style: theme.inputBorderStyle);
    final contentY = y + 1;

    // Ex/search prompt: single row, prefix + draft.
    if (_vimState.mode == VimMode.exCmd || _vimState.mode == VimMode.search) {
      canvas.paint(0, contentY, '│', style: theme.inputBorderStyle);
      canvas.paint(width - 1, contentY, '│', style: theme.inputBorderStyle);
      final prefix = _promptForMode();
      canvas.paint(1, contentY, prefix, style: theme.accentStyle);
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
        canvas.paint(cx, contentY, ' ', style: theme.cursorStyle, zIndex: 2);
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
      canvas.paint(0, yRow, '│', style: theme.inputBorderStyle);
      canvas.paint(width - 1, yRow, '│', style: theme.inputBorderStyle);

      final line = lines[r];
      if (r == 0) {
        canvas.paint(1, yRow, prompt, style: theme.promptStyle);
        // Run button at far right inside border
        final btnX = width - 1 - _runButtonLabel.length;
        canvas.paint(
          btnX,
          yRow,
          _runButtonLabel,
          style: theme.buttonStyle,
          zIndex: 1,
        );
        _hits.add(
          x: btnX,
          y: yRow,
          w: _runButtonLabel.length,
          h: 1,
          msg: const RunButtonMsg(),
        );
        // Right info shifted left to make room for button
        final rightX = btnX - rightInfo.length;
        if (rightX > 1 + prompt.length) {
          canvas.paint(
            rightX,
            yRow,
            rightInfo,
            style: theme.panelSubtitleStyle,
          );
        }
        // Diagnostics counters sit just left of the right info, inside the box.
        // The input text must stop before whichever of them is leftmost.
        var leftEdge = rightX;
        leftEdge = _paintDiagnosticsCounters(
          canvas,
          theme,
          rightX,
          yRow,
          prompt.length,
        );
        final usable = math.max(0, leftEdge - 1 - prompt.length);
        var visible = line;
        var cursorOffset = cur.col;
        if (visible.length > usable) {
          final start = (cursorOffset - usable + 1).clamp(0, visible.length);
          visible = visible.substring(start);
          cursorOffset -= start;
        }
        final clipped = visible.length > usable
            ? visible.substring(0, usable)
            : visible;
        canvas.paint(1 + prompt.length, yRow, clipped);
        final showSoftCursor = r == cur.row && !_tc.active;
        if (showSoftCursor) {
          final cx = 1 + prompt.length + cursorOffset;
          if (cx < rightX) {
            final ch = cursorOffset < visible.length
                ? visible[cursorOffset]
                : ' ';
            canvas.paint(cx, yRow, ch, style: theme.cursorStyle, zIndex: 2);
          }
        }
      } else {
        canvas.paint(1, yRow, '  ', style: theme.panelSubtitleStyle);
        final usable = math.max(0, width - 4); // │ + '  ' + text + │
        var visible = line;
        var cursorOffset = (r == cur.row) ? cur.col : 0;
        if (visible.length > usable) {
          final start = (cursorOffset - usable + 1).clamp(0, visible.length);
          visible = visible.substring(start);
          cursorOffset -= start;
        }
        final clipped = visible.length > usable
            ? visible.substring(0, usable)
            : visible;
        canvas.paint(3, yRow, clipped);
        final showSoftCursor = r == cur.row && !_tc.active;
        if (showSoftCursor) {
          final cx = 3 + cursorOffset;
          if (cx < width - 1) {
            final ch = cursorOffset < visible.length
                ? visible[cursorOffset]
                : ' ';
            canvas.paint(cx, yRow, ch, style: theme.cursorStyle, zIndex: 2);
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

  /// Paint stored one-shot diagnostic counters just left of [rightX].
  /// No background analyzer is started here; the counters only reflect the last
  /// `/diagnostics` run.
  int _paintDiagnosticsCounters(
    CellCanvas canvas,
    FrunTheme theme,
    int rightX,
    int yRow,
    int promptLen,
  ) {
    final diags = state.diagnostics;
    if (diags.isEmpty) return rightX;
    final (e, w, i, t) = _diagCounts();
    final segs = <(String, Style)>[
      if (e > 0)
        (
          '${_categoryIcon(DiagnosticCategory.error)} $e',
          _badgeStyleForCategory(theme, DiagnosticCategory.error),
        ),
      if (w > 0)
        (
          '${_categoryIcon(DiagnosticCategory.warning)} $w',
          _badgeStyleForCategory(theme, DiagnosticCategory.warning),
        ),
      if (i > 0)
        (
          '${_categoryIcon(DiagnosticCategory.info)} $i',
          _badgeStyleForCategory(theme, DiagnosticCategory.info),
        ),
      if (t > 0)
        (
          '${_categoryIcon(DiagnosticCategory.todo)} $t',
          _badgeStyleForCategory(theme, DiagnosticCategory.todo),
        ),
    ];
    if (segs.isEmpty) return rightX;
    var totalW = 0;
    for (var s = 0; s < segs.length; s++) {
      totalW += _badgeWidth(segs[s].$1);
      if (s > 0) totalW += 1;
    }
    final countersX = rightX - totalW;
    if (countersX <= 1 + promptLen + 4) return rightX;
    var cx = countersX;
    for (var s = 0; s < segs.length; s++) {
      if (s > 0) cx += 1;
      canvas.paint(
        cx,
        yRow,
        _badgeText(segs[s].$1),
        style: segs[s].$2,
        zIndex: 1,
      );
      cx += _badgeWidth(segs[s].$1);
    }
    _hits.add(
      x: countersX,
      y: yRow,
      w: totalW,
      h: 1,
      msg: const ToggleDiagnosticsOverlayMsg(),
    );
    return countersX;
  }
}
