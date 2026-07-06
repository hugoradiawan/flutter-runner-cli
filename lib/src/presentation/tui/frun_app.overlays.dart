part of 'frun_app.dart';

/// Overlay surfaces drawn above the transcript: the choice pickers (launch /
/// emulator / boot-mode / run-target), the config editor, and the tab info bar.
mixin _OverlayMixin on _FrunModelBase, _EngineMixin {
  // ── Pickers ────────────────────────────────────────────────────────────

  int _activePickerItemCount() {
    if (state.launchChoices.isNotEmpty) return state.launchChoices.length;
    if (state.emulatorChoices.isNotEmpty) return state.emulatorChoices.length;
    if (state.bootModeChoices.isNotEmpty) return state.bootModeChoices.length;
    if (state.runTargetChoices.isNotEmpty) return state.runTargetChoices.length;
    return 0;
  }

  Style _pickerSelectedChipStyle(_PickerKind kind, FrunTheme theme) {
    switch (kind) {
      case _PickerKind.launch:
        return theme.pickerChipSelectedStyle;
      case _PickerKind.emulator:
      case _PickerKind.bootMode:
        return theme.pickerEmulatorChipSelectedStyle;
      case _PickerKind.runTarget:
        return theme.pickerDeviceChipSelectedStyle;
    }
  }

  void _pickFromActivePicker(int idx) {
    if (state.launchChoices.isNotEmpty) {
      if (idx < 0 || idx >= state.launchChoices.length) return;
      final picked = state.launchChoices[idx];
      state.clearPickers();
      unawaited(state.runController.openRunTargetPicker(picked));
      return;
    }
    if (state.emulatorChoices.isNotEmpty) {
      if (idx < 0 || idx >= state.emulatorChoices.length) return;
      final picked = state.emulatorChoices[idx];
      state.setBootModePicker(picked.id);
      return;
    }
    if (state.bootModeChoices.isNotEmpty) {
      if (idx < 0 || idx >= state.bootModeChoices.length) return;
      final pendingId = state.pendingEmulatorId;
      if (pendingId == null) return;
      final coldBoot = idx == 1;
      state.clearPickers();
      _input.setText('emulators launch $pendingId${coldBoot ? ' cold' : ''}');
      _submit();
      return;
    }
    if (state.runTargetChoices.isNotEmpty) {
      if (idx < 0 || idx >= state.runTargetChoices.length) return;
      unawaited(
        state.runController.launchOnTarget(state.runTargetChoices[idx]),
      );
      return;
    }
  }

  _PickerSpec? _activePicker() {
    if (state.launchChoices.isNotEmpty) {
      return _PickerSpec(
        kind: _PickerKind.launch,
        itemCount: state.launchChoices.length,
        header: ' Run: pick an entry — click or press esc to close',
        moreHintFormat: 'run <index|name>',
      );
    }
    if (state.emulatorChoices.isNotEmpty) {
      return _PickerSpec(
        kind: _PickerKind.emulator,
        itemCount: state.emulatorChoices.length,
        header: ' Emulators: pick to launch — click or press esc to close',
        moreHintFormat: 'emulators launch <id>',
      );
    }
    if (state.bootModeChoices.isNotEmpty) {
      final id = state.pendingEmulatorId ?? '';
      return _PickerSpec(
        kind: _PickerKind.bootMode,
        itemCount: state.bootModeChoices.length,
        header: ' Boot mode for $id — click or press esc to close',
        moreHintFormat: 'emulators launch <id> [cold]',
      );
    }
    if (state.runTargetChoices.isNotEmpty) {
      return _PickerSpec(
        kind: _PickerKind.runTarget,
        itemCount: state.runTargetChoices.length,
        header: ' Run on: pick a device/emulator — click or press esc to close',
        moreHintFormat: 'run <index|name>',
      );
    }
    return null;
  }

  Style _pickerChipStyle(_PickerKind kind, FrunTheme theme) {
    switch (kind) {
      case _PickerKind.launch:
        return theme.pickerChipStyle;
      case _PickerKind.emulator:
      case _PickerKind.bootMode:
        return theme.pickerEmulatorChipStyle;
      case _PickerKind.runTarget:
        return theme.pickerDeviceChipStyle;
    }
  }

  Msg _pickerPickMsg(_PickerKind kind, int index) {
    switch (kind) {
      case _PickerKind.launch:
        return PickLaunchEntryMsg(index);
      case _PickerKind.emulator:
        return PickEmulatorMsg(index);
      case _PickerKind.bootMode:
        return PickBootModeMsg(index);
      case _PickerKind.runTarget:
        return PickRunTargetMsg(index);
    }
  }

  Msg _pickerCloseMsg(_PickerKind kind) {
    switch (kind) {
      case _PickerKind.launch:
        return const CloseLaunchPickerMsg();
      case _PickerKind.emulator:
        return const CloseEmulatorPickerMsg();
      case _PickerKind.bootMode:
        return const CloseBootModePickerMsg();
      case _PickerKind.runTarget:
        return const CloseRunTargetPickerMsg();
    }
  }

  String _pickerChipText(_PickerKind kind, int index) {
    switch (kind) {
      case _PickerKind.launch:
        final entry = state.launchChoices[index];
        final tags = <String>[
          if (entry.flutterMode != null) entry.flutterMode!,
          if (entry.deviceId != null) entry.deviceId!,
        ];
        final tail = tags.isEmpty ? '' : '  ${tags.join(' · ')}';
        return ' [$index] ${entry.name}$tail ';
      case _PickerKind.emulator:
        final e = state.emulatorChoices[index];
        final tags = <String>[
          e.id,
          if ((e.platformType ?? '').isNotEmpty) e.platformType!,
        ];
        return ' [$index] ${e.name}  ${tags.join(' · ')} ';
      case _PickerKind.bootMode:
        return index == 0
            ? ' [0] Quick Boot  (resume saved state) '
            : ' [1] Cold Boot   (fresh start) ';
      case _PickerKind.runTarget:
        final t = state.runTargetChoices[index];
        final tags = <String>[
          if (t.platform.isNotEmpty) t.platform,
          t.needsBoot ? 'emulator (boot)' : 'device',
        ];
        return ' [$index] ${t.name}  ${tags.join(' · ')} ';
    }
  }

  (List<_PickerChip>, int) _layoutPickerChips(_PickerSpec spec, int width) {
    final maxChipWidth = math.max(8, width - _pickerIndent * 2);

    final raws = <String>[];
    var widest = 0;
    for (var i = 0; i < spec.itemCount; i++) {
      final raw = _pickerChipText(spec.kind, i);
      raws.add(raw);
      if (raw.length > widest) widest = raw.length;
    }
    final uniformWidth = math.min(widest, maxChipWidth);

    final chips = <_PickerChip>[];
    for (var i = 0; i < spec.itemCount; i++) {
      final raw = raws[i];
      final String text;
      if (raw.length > uniformWidth) {
        text = '${raw.substring(0, uniformWidth - 1)}…';
      } else {
        text = raw.padRight(uniformWidth);
      }
      chips.add(_PickerChip(i, text));
    }
    return (chips, uniformWidth);
  }

  int _computePickerHeight(_PickerSpec? spec) {
    if (spec == null) return 0;
    final entries = spec.itemCount;
    final chipBlock = math.max(0, entries * 2 - 1);
    final desired = 1 + 1 + chipBlock + 1;
    final headroom = math.max(4, _height - 6);
    final maxBoxBlock = math.max(0, _maxPickerRows * 2 - 1);
    final maxByCap = 1 + 1 + maxBoxBlock + 1;
    return math.min(desired, math.min(maxByCap, headroom));
  }

  void _paintPicker(
    CellCanvas canvas,
    FrunTheme theme,
    _PickerSpec spec,
    int width,
    int y,
    int height,
  ) {
    if (height <= 0) return;

    final closeX = (width - _pickerCloseLabel.length).clamp(0, width);
    final titleMax = math.max(0, closeX - 1);
    _paintPanelTitle(canvas, theme, 0, y, spec.header, maxWidth: titleMax);
    if (closeX > titleMax || closeX > spec.header.length) {
      _paintHeaderAction(
        canvas,
        theme,
        _hits,
        closeX,
        y,
        _pickerCloseLabel.trim(),
        _pickerCloseMsg(spec.kind),
        danger: true,
      );
    }

    if (height < 3 || width < 4) return;
    final topY = y + 1;
    final innerStartY = y + 2;
    final innerEndY = y + height - 2;
    _paintPanelFrame(canvas, theme, width, topY, height - 1);

    final (chips, _) = _layoutPickerChips(spec, width);
    final innerH = innerEndY - innerStartY + 1;
    if (innerH <= 0) return;
    final maxVisible = (innerH + 1) ~/ 2;
    final totalHidden = math.max(0, chips.length - maxVisible);
    final visibleCount = totalHidden > 0
        ? math.max(0, maxVisible - 1)
        : chips.length;

    // Scroll to keep selected chip in view.
    if (visibleCount > 0) {
      if (_pickerSelectedIndex < _pickerScrollOffset) {
        _pickerScrollOffset = _pickerSelectedIndex;
      } else if (_pickerSelectedIndex >= _pickerScrollOffset + visibleCount) {
        _pickerScrollOffset = _pickerSelectedIndex - visibleCount + 1;
      }
      _pickerScrollOffset = _pickerScrollOffset.clamp(
        0,
        math.max(0, chips.length - visibleCount),
      );
    }

    final chipStyle = _pickerChipStyle(spec.kind, theme);
    final selectedStyle = _pickerSelectedChipStyle(spec.kind, theme);
    for (var i = 0; i < visibleCount; i++) {
      final chipIdx = _pickerScrollOffset + i;
      if (chipIdx >= chips.length) break;
      final rowY = innerStartY + i * 2;
      if (rowY > innerEndY) break;
      final style = chipIdx == _pickerSelectedIndex ? selectedStyle : chipStyle;
      canvas.paint(_pickerIndent, rowY, chips[chipIdx].text, style: style);
      _hits.add(
        x: _pickerIndent,
        y: rowY,
        w: chips[chipIdx].text.length,
        h: 1,
        msg: _pickerPickMsg(spec.kind, chips[chipIdx].index),
      );
    }
    final hidden =
        math.max(0, chips.length - _pickerScrollOffset - visibleCount) +
        _pickerScrollOffset;
    if (hidden > 0) {
      final rowY = innerStartY + visibleCount * 2;
      if (rowY <= innerEndY) {
        final more = ' +$hidden more - ${spec.moreHintFormat} to apply ';
        final maxLen = math.max(0, width - _pickerIndent * 2);
        canvas.paint(
          _pickerIndent,
          rowY,
          _clipCellText(more, maxLen),
          style: theme.panelSubtitleStyle,
        );
      }
    }
  }

  // ── Config editor ──────────────────────────────────────────────────────

  int _computeConfigEditorHeight() {
    if (!_configEditorActive) return 0;
    // header + top border + one row per entry + bottom border
    return 1 + 1 + _configEditorEntries.length + 1;
  }

  String _configEditorEntryValue(AppConfigEntity c, String key) {
    switch (key) {
      case 'ide':
        return c.ide.id;
      case 'editor_mode':
        return c.editorMode.id;
      case 'theme':
        return c.theme.id;
      case 'hot_reload_on_save':
        return c.hotReloadOnSave.toString();
      case 'open_devtools_on_launch':
        return c.openDevtoolsOnLaunch.id;
      case 'emulator_boot':
        return c.emulatorBoot.id;
      case 'verbose_errors':
        return c.verboseErrors.toString();
      case 'diagnostics_on_boot':
        return c.diagnosticsOnBoot.toString();
      case 'scrollback_lines':
        return c.scrollbackLines.toString();
      default:
        return '';
    }
  }

  AppConfigEntity _cycleConfigValue(AppConfigEntity c, String key, int delta) {
    switch (key) {
      case 'ide':
        const vals = FrunIde.values;
        final idx = (vals.indexOf(c.ide) + delta + vals.length) % vals.length;
        return c.copyWith(ide: vals[idx]);
      case 'editor_mode':
        const vals = FrunEditorMode.values;
        final idx =
            (vals.indexOf(c.editorMode) + delta + vals.length) % vals.length;
        return c.copyWith(editorMode: vals[idx]);
      case 'theme':
        const vals = FrunThemeMode.values;
        final idx = (vals.indexOf(c.theme) + delta + vals.length) % vals.length;
        return c.copyWith(theme: vals[idx]);
      case 'hot_reload_on_save':
        return c.copyWith(hotReloadOnSave: !c.hotReloadOnSave);
      case 'open_devtools_on_launch':
        const vals = FrunDevToolsAutoOpen.values;
        final idx =
            (vals.indexOf(c.openDevtoolsOnLaunch) + delta + vals.length) %
            vals.length;
        return c.copyWith(openDevtoolsOnLaunch: vals[idx]);
      case 'emulator_boot':
        const vals = FrunEmulatorBoot.values;
        final idx =
            (vals.indexOf(c.emulatorBoot) + delta + vals.length) % vals.length;
        return c.copyWith(emulatorBoot: vals[idx]);
      case 'verbose_errors':
        return c.copyWith(verboseErrors: !c.verboseErrors);
      case 'diagnostics_on_boot':
        return c.copyWith(diagnosticsOnBoot: !c.diagnosticsOnBoot);
      case 'scrollback_lines':
        var idx = _scrollbackPresets.indexOf(c.scrollbackLines);
        if (idx < 0) {
          // Off-preset (set via the `scrollback` command) — snap into the list
          // before stepping so ←/→ behaves predictably.
          idx = _scrollbackPresets.indexWhere((p) => p >= c.scrollbackLines);
          if (idx < 0) idx = _scrollbackPresets.length - 1;
        }
        final next =
            (idx + delta + _scrollbackPresets.length) %
            _scrollbackPresets.length;
        return c.copyWith(scrollbackLines: _scrollbackPresets[next]);
      default:
        return c;
    }
  }

  void _paintConfigEditor(
    CellCanvas canvas,
    FrunTheme theme,
    int width,
    int y,
    int height,
  ) {
    if (height <= 0 || _configDraft == null) return;

    final isVim = state.config.editorMode == FrunEditorMode.vim;
    final hint = isVim
        ? 'Config  jk navigate - hl cycle - enter apply - esc discard'
        : 'Config  arrows navigate - enter apply - esc discard';
    _paintPanelTitle(canvas, theme, 0, y, hint, maxWidth: width);

    if (height < 3) return;

    final topY = y + 1;
    final bottomY = y + height - 1;
    _paintPanelFrame(canvas, theme, width, topY, height - 1);

    for (var i = 0; i < _configEditorEntries.length; i++) {
      final rowY = topY + 1 + i;
      if (rowY >= bottomY) break;

      final entry = _configEditorEntries[i];
      final isSelected = i == _configEditorRow;
      final currentVal = _configEditorEntryValue(_configDraft!, entry.key);
      if (isSelected) {
        _paintSelectedRow(canvas, theme, 1, rowY, width - 2);
      }

      const keyWidth = 26;
      const indicatorWidth = 2;
      const innerGap = 1;
      const valGap = 2;

      final indicator = isSelected ? '► ' : '  ';
      final keyPadded = entry.displayLabel.padRight(keyWidth);

      const contentX = innerGap + indicatorWidth + keyWidth + valGap;

      if (isSelected) {
        canvas.paint(
          innerGap,
          rowY,
          indicator + keyPadded,
          style: theme.accentStyle,
          zIndex: 1,
        );
      } else {
        canvas.paint(innerGap, rowY, indicator + keyPadded);
      }

      if (contentX < width - 1) {
        if (isSelected && entry.values.isNotEmpty) {
          final chip = '◄ $currentVal ►';
          canvas.paint(
            contentX,
            rowY,
            chip,
            style: theme.pickerChipSelectedStyle,
            zIndex: 1,
          );
        } else {
          canvas.paint(contentX, rowY, currentVal, style: theme.valueStyle);
        }
      }
    }
  }

  // ── Diagnostics overlay ──────────────────────────────────────────────────

  /// The project diagnostics after applying the active category + text filters.
  List<DiagnosticEntity> _filteredDiagnostics() {
    var list = state.diagnostics;
    final f = state.diagnosticsFilter;
    if (f != null) {
      list = list.where((d) => d.category == f).toList(growable: false);
    }
    final q = state.diagnosticsSearch.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where(
            (d) =>
                d.message.toLowerCase().contains(q) ||
                d.filePath.toLowerCase().contains(q) ||
                (d.code?.toLowerCase().contains(q) ?? false),
          )
          .toList(growable: false);
    }
    return list;
  }

  /// Flatten the filtered diagnostics into file-header + issue rows.
  List<_DiagRow> _diagnosticRows() {
    final revision = state.diagnosticsRevision;
    final filter = state.diagnosticsFilter;
    final search = state.diagnosticsSearch;
    if (revision == _diagnosticRowsCacheRevision &&
        filter == _diagnosticRowsCacheFilter &&
        search == _diagnosticRowsCacheSearch) {
      return _diagnosticRowsCache;
    }

    final grouped = DiagnosticEntity.groupByFile(_filteredDiagnostics());
    final rows = <_DiagRow>[];
    grouped.forEach((file, items) {
      rows.add(_DiagRow.fileHeader(file, items.length));
      for (final d in items) {
        rows.add(_DiagRow.issue(d));
      }
    });
    _diagnosticRowsCacheRevision = revision;
    _diagnosticRowsCacheFilter = filter;
    _diagnosticRowsCacheSearch = search;
    _diagnosticRowsCache = rows;
    return rows;
  }

  /// Snap [_diagSelectedIndex] onto a valid issue row.
  void _clampDiagSelection(List<_DiagRow> rows) {
    if (rows.isEmpty) {
      _diagSelectedIndex = 0;
      return;
    }
    _diagSelectedIndex = _diagSelectedIndex.clamp(0, rows.length - 1);
    if (rows[_diagSelectedIndex].kind == _DiagRowKind.issue) return;
    for (var i = _diagSelectedIndex; i < rows.length; i++) {
      if (rows[i].kind == _DiagRowKind.issue) {
        _diagSelectedIndex = i;
        return;
      }
    }
    for (var i = _diagSelectedIndex; i >= 0; i--) {
      if (rows[i].kind == _DiagRowKind.issue) {
        _diagSelectedIndex = i;
        return;
      }
    }
  }

  /// Move the selection to the next/previous issue row, skipping file headers.
  void _moveDiagSelection(int delta) {
    final rows = _diagnosticRows();
    if (rows.isEmpty) return;
    _clampDiagSelection(rows);
    final step = delta >= 0 ? 1 : -1;
    var i = _diagSelectedIndex;
    for (var n = 0; n < rows.length; n++) {
      i += step;
      if (i < 0) i = rows.length - 1;
      if (i >= rows.length) i = 0;
      if (rows[i].kind == _DiagRowKind.issue) {
        _diagSelectedIndex = i;
        return;
      }
    }
  }

  /// Jump the selection to the first / last issue row (vim `gg` / `G`).
  void _diagSelectEdge({required bool first}) {
    final rows = _diagnosticRows();
    if (rows.isEmpty) return;
    if (first) {
      for (var i = 0; i < rows.length; i++) {
        if (rows[i].kind == _DiagRowKind.issue) {
          _diagSelectedIndex = i;
          return;
        }
      }
    } else {
      for (var i = rows.length - 1; i >= 0; i--) {
        if (rows[i].kind == _DiagRowKind.issue) {
          _diagSelectedIndex = i;
          return;
        }
      }
    }
  }

  /// The diagnostic under the current selection, if any.
  DiagnosticEntity? _selectedDiagnostic() {
    final rows = _diagnosticRows();
    if (rows.isEmpty) return null;
    _clampDiagSelection(rows);
    return rows[_diagSelectedIndex].diagnostic;
  }

  int _computeDiagnosticsHeight() {
    if (!state.showDiagnosticsPanel) return 0;
    // Don't stack on top of a picker or the config editor.
    if (state.hasActivePicker || _configEditorActive) return 0;
    final rows = _diagnosticRows().length;
    final body = math.max(1, rows); // at least one row for the empty state
    final desired = 1 + 1 + body + 1; // header + top border + body + bottom
    final headroom = math.max(4, _height - 6);
    const maxCap = 1 + 1 + _maxDiagnosticsRows + 1;
    return math.min(desired, math.min(maxCap, headroom));
  }

  void _paintDiagnosticsPanel(
    CellCanvas canvas,
    FrunTheme theme,
    int width,
    int y,
    int height,
  ) {
    if (height <= 0) return;
    final (e, w, i, t) = _diagCounts();

    // ── Header: title, clickable filter chips, search, close button ──
    var hx = _paintPanelTitle(canvas, theme, 0, y, 'Problems');
    hx = _paintDiagnosticsFilterChip(
      canvas,
      theme,
      hx,
      y,
      'all',
      null,
      state.diagnosticsFilter == null,
    );
    // Per-category chips are shown only when that category has problems.
    if (e > 0) {
      hx = _paintDiagnosticsFilterChip(
        canvas,
        theme,
        hx,
        y,
        '${_categoryIcon(DiagnosticCategory.error)} $e',
        DiagnosticCategory.error,
        state.diagnosticsFilter == DiagnosticCategory.error,
      );
    }
    if (w > 0) {
      hx = _paintDiagnosticsFilterChip(
        canvas,
        theme,
        hx,
        y,
        '${_categoryIcon(DiagnosticCategory.warning)} $w',
        DiagnosticCategory.warning,
        state.diagnosticsFilter == DiagnosticCategory.warning,
      );
    }
    if (i > 0) {
      hx = _paintDiagnosticsFilterChip(
        canvas,
        theme,
        hx,
        y,
        '${_categoryIcon(DiagnosticCategory.info)} $i',
        DiagnosticCategory.info,
        state.diagnosticsFilter == DiagnosticCategory.info,
      );
    }
    if (t > 0) {
      hx = _paintDiagnosticsFilterChip(
        canvas,
        theme,
        hx,
        y,
        '${_categoryIcon(DiagnosticCategory.todo)} $t',
        DiagnosticCategory.todo,
        state.diagnosticsFilter == DiagnosticCategory.todo,
      );
    }

    final closeX = (width - _pickerCloseLabel.length).clamp(0, width);
    final q = state.diagnosticsSearch;
    if (q.isNotEmpty) {
      final searchText = ' /$q';
      final maxSearch = closeX - hx - 1;
      if (maxSearch > 0) {
        canvas.paint(
          hx,
          y,
          _clipCellText(searchText, maxSearch),
          style: theme.searchActiveStyle,
        );
      }
    }
    if (closeX > hx) {
      _paintHeaderAction(
        canvas,
        theme,
        _hits,
        closeX,
        y,
        _pickerCloseLabel.trim(),
        const CloseDiagnosticsOverlayMsg(),
        danger: true,
      );
    }

    if (height < 3 || width < 4) return;

    // ── Borders ──
    final topY = y + 1;
    final innerStartY = y + 2;
    final innerEndY = y + height - 2;
    _paintPanelFrame(canvas, theme, width, topY, height - 1, strong: true);

    final innerH = innerEndY - innerStartY + 1;
    if (innerH <= 0) return;

    final rows = _diagnosticRows();
    if (rows.isEmpty) {
      final msg = state.diagnostics.isEmpty
          ? ' No problems detected. '
          : ' No problems match the filter (esc to close). ';
      canvas.paint(
        _pickerIndent,
        innerStartY,
        _clipText(msg, width - _pickerIndent * 2),
        style: theme.emptyStyle,
      );
      return;
    }

    _clampDiagSelection(rows);

    final maxVisible = innerH;
    final totalHidden = math.max(0, rows.length - maxVisible);
    final visibleCount = totalHidden > 0 ? maxVisible - 1 : rows.length;
    if (visibleCount > 0) {
      if (_diagSelectedIndex < _diagScrollOffset) {
        _diagScrollOffset = _diagSelectedIndex;
      } else if (_diagSelectedIndex >= _diagScrollOffset + visibleCount) {
        _diagScrollOffset = _diagSelectedIndex - visibleCount + 1;
      }
      _diagScrollOffset = _diagScrollOffset.clamp(
        0,
        math.max(0, rows.length - visibleCount),
      );
    }

    final maxText = width - 2;
    for (var r = 0; r < visibleCount; r++) {
      final idx = _diagScrollOffset + r;
      if (idx >= rows.length) break;
      final rowY = innerStartY + r;
      final row = rows[idx];
      if (row.kind == _DiagRowKind.fileHeader) {
        final text = ' ${_relativeDiagPath(row.file)}  (${row.count})';
        canvas.paint(
          1,
          rowY,
          _clipText(text, maxText),
          style: theme.panelSubtitleStyle,
        );
      } else {
        final d = row.diagnostic!;
        final selected = idx == _diagSelectedIndex;
        final glyph = _categoryIcon(d.category);
        final code = d.code != null ? '  ${d.code}' : '';
        final text = '   $glyph Ln${d.line} Col${d.column}  ${d.message}$code';
        final clipped = _clipText(text, maxText);
        final style = selected
            ? theme.selectedRowStyle
            : _categoryStyle(theme, d.category);
        if (selected) {
          _paintSelectedRow(canvas, theme, 1, rowY, width - 2);
        }
        canvas.paint(1, rowY, clipped, style: style, zIndex: 1);
        _hits.add(
          x: 1,
          y: rowY,
          w: clipped.length,
          h: 1,
          msg: JumpToDiagnosticMsg(d),
        );
      }
    }

    if (totalHidden > 0) {
      final rowY = innerStartY + visibleCount;
      if (rowY <= innerEndY) {
        final hiddenBelow = math.max(
          0,
          rows.length - _diagScrollOffset - visibleCount,
        );
        final keys = state.config.editorMode == FrunEditorMode.vim
            ? 'j/k move - gg/G ends - / filter - enter open'
            : 'arrows move - type to filter - enter open';
        final more = ' +$hiddenBelow more - $keys ';
        canvas.paint(
          _pickerIndent,
          rowY,
          _clipText(more, width - _pickerIndent * 2),
          style: theme.panelSubtitleStyle,
        );
      }
    }
  }

  int _paintDiagnosticsFilterChip(
    CellCanvas canvas,
    FrunTheme theme,
    int x,
    int y,
    String label,
    DiagnosticCategory? level,
    bool active,
  ) {
    final style = active
        ? theme.pickerChipSelectedStyle
        : (level == null
              ? theme.badgeNeutralStyle
              : _badgeStyleForCategory(theme, level));
    return _paintBadge(
      canvas,
      theme,
      x,
      y,
      label,
      style,
      hits: _hits,
      msg: SetDiagnosticsFilterMsg(level),
    );
  }

  String _relativeDiagPath(String file) {
    final root = state.project.root;
    if (p.isWithin(root, file)) return p.relative(file, from: root);
    return file;
  }

  /// Scroll the diagnostics list by a wheel notch, moving the selection so the
  /// painter keeps it in view.
  void _scrollDiagnosticsByWheel({required bool up}) {
    for (var n = 0; n < 3; n++) {
      _moveDiagSelection(up ? -1 : 1);
    }
  }

  String _clipText(String s, int max) {
    if (max <= 0) return '';
    if (s.length <= max) return s;
    if (max <= 1) return s.substring(0, max);
    return '${s.substring(0, max - 1)}…';
  }

  // ── Isolates panel ──────────────────────────────────────────────────────

  int _computeIsolatesPanelHeight() {
    if (!state.showIsolatesPanel) return 0;
    if (state.hasActivePicker || _configEditorActive) return 0;
    if (state.showDiagnosticsPanel) return 0;
    final rows = state.deps.isolateManager.isolates.length;
    final body = math.max(1, rows);
    final desired = 1 + 1 + body + 1;
    final headroom = math.max(4, _height - 6);
    const maxCap = 1 + 1 + _maxIsolateRows + 1;
    return math.min(desired, math.min(maxCap, headroom));
  }

  void _closeIsolatesPanel() {
    state.showIsolatesPanel = false;
    _isolatePendingG = false;
  }

  void _clampIsolateSelection(List<IsolateInfoEntity> rows) {
    if (rows.isEmpty) {
      _isolateSelectedIndex = 0;
      _isolateScrollOffset = 0;
      return;
    }
    _isolateSelectedIndex = _isolateSelectedIndex.clamp(0, rows.length - 1);
  }

  void _moveIsolateSelection(int delta) {
    final rows = state.deps.isolateManager.isolates;
    if (rows.isEmpty) return;
    _isolateSelectedIndex =
        (_isolateSelectedIndex + delta + rows.length) % rows.length;
    _isolatePendingG = false;
  }

  void _isolateSelectEdge({required bool first}) {
    final rows = state.deps.isolateManager.isolates;
    if (rows.isEmpty) return;
    _isolateSelectedIndex = first ? 0 : rows.length - 1;
    _isolatePendingG = false;
  }

  IsolateInfoEntity? _selectedIsolate() {
    final rows = state.deps.isolateManager.isolates;
    if (rows.isEmpty) return null;
    _clampIsolateSelection(rows);
    return rows[_isolateSelectedIndex];
  }

  void _scrollIsolatesByWheel({required bool up}) {
    for (var n = 0; n < 3; n++) {
      _moveIsolateSelection(up ? -1 : 1);
    }
  }

  Future<bool> _ensureIsolateService() async {
    final manager = state.deps.isolateManager;
    if (manager.isConnected) return true;
    if (state.runController.hasTabs) {
      await state.runController.ensureIsolatesForActiveTab();
    }
    if (manager.isConnected) return true;
    state.visibleTranscript.warn(
      'No VM service yet. Start the app with /run, then try /isolates.',
    );
    return false;
  }

  Future<void> _runIsolateAction(
    IsolatePanelAction action, {
    String? id,
  }) async {
    final manager = state.deps.isolateManager;
    if (action == IsolatePanelAction.start) {
      if (state.runController.hasTabs) {
        await state.runController.rerunActive();
      } else {
        _input.setText('run');
        _submit();
      }
      return;
    }
    try {
      if (action == IsolatePanelAction.refresh) {
        if (await _ensureIsolateService()) await manager.refresh();
        return;
      }

      final target = id ?? _selectedIsolate()?.id;
      if (target == null) {
        state.visibleTranscript.warn('No isolate selected.');
        return;
      }
      if (!(await _ensureIsolateService())) return;

      switch (action) {
        case IsolatePanelAction.pause:
          await manager.pause(target);
          await manager.refresh();
        case IsolatePanelAction.resume:
          await manager.resume(target);
          await manager.refresh();
        case IsolatePanelAction.step:
          await manager.resume(target, step: IsolateStepMode.over);
          await manager.refresh();
        case IsolatePanelAction.kill:
          await manager.kill(target);
          await manager.refresh();
        case IsolatePanelAction.stack:
          await _printIsolateStack(target);
        case IsolatePanelAction.start:
        case IsolatePanelAction.refresh:
          break;
      }
    } catch (e) {
      state.visibleTranscript.error('VM service call failed: $e');
    }
  }

  Future<void> _printIsolateStack(String id) async {
    try {
      final frames = await state.deps.isolateManager.stack(id);
      if (frames == null) {
        state.visibleTranscript.warn('No stack available.');
        return;
      }
      if (frames.isEmpty) {
        state.visibleTranscript.info('Stack empty for $id.');
        return;
      }
      state.visibleTranscript.system('Stack for $id:');
      for (var i = 0; i < frames.length && i < 30; i++) {
        final frame = frames[i];
        final script = frame.scriptUri ?? '';
        state.visibleTranscript.info('  #$i  ${frame.functionName}  $script');
      }
      final scriptUri = frames.first.scriptUri;
      if (scriptUri != null) {
        final loc = state.deps.vmUriResolver.resolve(scriptUri);
        if (loc != null) await openInIde(loc, state);
      }
    } catch (e) {
      state.visibleTranscript.error('Stack lookup failed: $e');
    }
  }

  IsolatePanelAction _defaultIsolateAction(IsolateInfoEntity iso) {
    return switch (iso.status) {
      IsolateStatus.paused => IsolatePanelAction.resume,
      IsolateStatus.running => IsolatePanelAction.pause,
      IsolateStatus.exited || IsolateStatus.unknown => IsolatePanelAction.stack,
    };
  }

  List<(String, IsolatePanelAction)> _isolateActionsFor(IsolateInfoEntity iso) {
    return switch (iso.status) {
      IsolateStatus.paused => <(String, IsolatePanelAction)>[
        ('resume', IsolatePanelAction.resume),
        ('step', IsolatePanelAction.step),
        ('stack', IsolatePanelAction.stack),
        ('kill', IsolatePanelAction.kill),
      ],
      IsolateStatus.running => <(String, IsolatePanelAction)>[
        ('pause', IsolatePanelAction.pause),
        ('stack', IsolatePanelAction.stack),
        ('kill', IsolatePanelAction.kill),
      ],
      IsolateStatus.exited ||
      IsolateStatus.unknown => <(String, IsolatePanelAction)>[
        ('stack', IsolatePanelAction.stack),
        ('kill', IsolatePanelAction.kill),
      ],
    };
  }

  Style _isolateStatusStyle(FrunTheme theme, IsolateStatus status) {
    return switch (status) {
      IsolateStatus.running => theme.successStyle,
      IsolateStatus.paused => theme.warnStyle,
      IsolateStatus.exited => theme.dimStyle,
      IsolateStatus.unknown => theme.dimStyle,
    };
  }

  String _shortIsolateId(String id) {
    if (id.length <= 18) return id;
    return '${id.substring(0, 9)}…${id.substring(id.length - 6)}';
  }

  int _paintIsolatePanelAction(
    CellCanvas canvas,
    FrunTheme theme,
    int x,
    int y,
    String label,
    IsolatePanelAction action, {
    String? id,
    bool stop = false,
  }) {
    final style = stop ? theme.buttonStopStyle : theme.buttonStyle;
    return _paintBadge(
      canvas,
      theme,
      x,
      y,
      label,
      style,
      hits: _hits,
      msg: IsolateActionMsg(action, id: id),
    );
  }

  void _paintIsolatesPanel(
    CellCanvas canvas,
    FrunTheme theme,
    int width,
    int y,
    int height,
  ) {
    if (height <= 0) return;
    final manager = state.deps.isolateManager;
    final rows = manager.isolates;
    _clampIsolateSelection(rows);

    final active = state.runController.activeTab;
    final app = active == null ? '(no app)' : active.label;
    var hx = _paintPanelTitle(
      canvas,
      theme,
      0,
      y,
      'Isolates',
      meta: _clipCellText(app, 24),
      maxWidth: math.max(0, width - 32),
    );
    if (hx + 20 < width) {
      hx = _paintIsolatePanelAction(
        canvas,
        theme,
        hx,
        y,
        state.runController.hasTabs ? 'rerun' : 'start',
        IsolatePanelAction.start,
      );
      hx = _paintIsolatePanelAction(
        canvas,
        theme,
        hx,
        y,
        'refresh',
        IsolatePanelAction.refresh,
      );
    }

    final closeX = (width - _pickerCloseLabel.length).clamp(0, width);
    if (closeX > hx) {
      _paintHeaderAction(
        canvas,
        theme,
        _hits,
        closeX,
        y,
        _pickerCloseLabel.trim(),
        const CloseIsolatesPanelMsg(),
        danger: true,
      );
    }

    if (height < 3 || width < 4) return;
    final topY = y + 1;
    final innerStartY = y + 2;
    final innerEndY = y + height - 2;
    _paintPanelFrame(canvas, theme, width, topY, height - 1, strong: true);

    final innerH = innerEndY - innerStartY + 1;
    if (innerH <= 0) return;
    if (rows.isEmpty) {
      final msg = manager.service == null
          ? ' No VM service yet. Use /run, then /isolates. '
          : ' No isolates connected. ';
      canvas.paint(
        _pickerIndent,
        innerStartY,
        _clipText(msg, width - _pickerIndent * 2),
        style: theme.emptyStyle,
      );
      return;
    }

    final totalHidden = math.max(0, rows.length - innerH);
    final visibleCount = totalHidden > 0 ? innerH - 1 : rows.length;
    if (visibleCount > 0) {
      if (_isolateSelectedIndex < _isolateScrollOffset) {
        _isolateScrollOffset = _isolateSelectedIndex;
      } else if (_isolateSelectedIndex >= _isolateScrollOffset + visibleCount) {
        _isolateScrollOffset = _isolateSelectedIndex - visibleCount + 1;
      }
      _isolateScrollOffset = _isolateScrollOffset.clamp(
        0,
        math.max(0, rows.length - visibleCount),
      );
    }

    for (var r = 0; r < visibleCount; r++) {
      final idx = _isolateScrollOffset + r;
      if (idx >= rows.length) break;
      final rowY = innerStartY + r;
      final iso = rows[idx];
      final selected = idx == _isolateSelectedIndex;
      final actions = _isolateActionsFor(iso);
      final actionTexts = actions.map((a) => ' ${a.$1} ').toList();
      final actionWidth = actionTexts.fold<int>(
        0,
        (sum, text) => sum + text.length + 1,
      );
      final actionX = width - 1 - actionWidth;
      final hasButtons = actionX > 28;
      final textMax = hasButtons ? actionX - 2 : width - 2;
      final reason = iso.pauseReason == null ? '' : ' ${iso.pauseReason}';
      final text =
          ' [$idx] ${iso.status.name.padRight(7)} ${iso.name}  ${_shortIsolateId(iso.id)}$reason';
      final style = selected
          ? theme.selectedRowStyle
          : _isolateStatusStyle(theme, iso.status);
      final clipped = _clipText(text, textMax);
      if (selected) {
        _paintSelectedRow(canvas, theme, 1, rowY, width - 2);
      }
      canvas.paint(1, rowY, clipped, style: style, zIndex: 1);
      _hits.add(
        x: 1,
        y: rowY,
        w: clipped.length,
        h: 1,
        msg: SelectIsolateMsg(idx),
      );

      if (!hasButtons) continue;
      var bx = actionX;
      for (var i = 0; i < actions.length; i++) {
        final (label, action) = actions[i];
        final buttonText = actionTexts[i];
        final stop = action == IsolatePanelAction.kill;
        final buttonStyle = stop ? theme.buttonStopStyle : theme.buttonStyle;
        canvas.paint(bx, rowY, buttonText, style: buttonStyle, zIndex: 1);
        _hits.add(
          x: bx,
          y: rowY,
          w: buttonText.length,
          h: 1,
          msg: IsolateActionMsg(action, id: iso.id),
        );
        bx += buttonText.length + 1;
      }
    }

    if (totalHidden > 0) {
      final rowY = innerStartY + visibleCount;
      if (rowY <= innerEndY) {
        final hiddenBelow = math.max(
          0,
          rows.length - _isolateScrollOffset - visibleCount,
        );
        final more =
            ' +$hiddenBelow more - j/k move - p pause - r resume - s step - k kill ';
        canvas.paint(
          _pickerIndent,
          rowY,
          _clipText(more, width - _pickerIndent * 2),
          style: theme.panelSubtitleStyle,
        );
      }
    }
  }

  // ── Info bar / tabs ────────────────────────────────────────────────────

  int _computeInfoBarHeight(int width) {
    final tabs = state.runController.tabs;
    if (tabs.isEmpty) return 1;
    final layout = _layoutTabRows(width);
    _tabRowsFrameCache = layout;
    _tabRowsFrameCacheWidth = width;
    return layout.$1.length.clamp(1, _maxInfoBarRows);
  }

  (List<List<_TabSegment>>, int) _layoutTabRows(int width) {
    final tabs = state.runController.tabs;
    final activeIndex = state.runController.activeIndex;
    final rowWidth = math.max(10, width);

    final segs = <_TabSegment>[];
    for (var i = 0; i < tabs.length; i++) {
      final t = tabs[i];
      final isActive = i == activeIndex;
      segs.add(_TabSegment(i, t, isActive, _tabSegmentWidth(i, t, isActive)));
    }

    final rows = <List<_TabSegment>>[<_TabSegment>[]];
    var curWidth = 0;
    for (var idx = 0; idx < segs.length; idx++) {
      final seg = segs[idx];
      final separator = rows.last.isEmpty ? 0 : 1;
      final wouldBe = curWidth + separator + seg.width;
      if (wouldBe > rowWidth) {
        if (rows.length >= _maxInfoBarRows) {
          return (rows, segs.length - idx);
        }
        rows.add(<_TabSegment>[]);
        curWidth = 0;
      }
      rows.last.add(seg);
      curWidth += (rows.last.length == 1 ? 0 : 1) + seg.width;
    }
    return (rows, 0);
  }

  int _tabSegmentWidth(int tabIndex, RunTab t, bool isActive) {
    final maxLabelChars = isActive ? 32 : 18;
    final shortLabel = t.label.length > maxLabelChars
        ? '${t.label.substring(0, maxLabelChars - 3)}...'
        : t.label;
    final marker = t.isRunning ? '' : ' x';
    final labelText = ' ${tabIndex + 1}: $shortLabel$marker ';
    final buttonCount = isActive && t.isRunning ? activeButtons.length : 0;
    return labelText.length + buttonCount * 3;
  }

  void _paintInfoBar(
    CellCanvas canvas,
    FrunTheme theme,
    int width,
    int y,
    int height,
  ) {
    final tabs = state.runController.tabs;

    if (tabs.isEmpty) {
      return;
    }

    final cached = _tabRowsFrameCache;
    _tabRowsFrameCache = null;
    final (rows, hidden) = cached != null && _tabRowsFrameCacheWidth == width
        ? cached
        : _layoutTabRows(width);
    final rowCount = math.min(rows.length, height);
    for (var r = 0; r < rowCount; r++) {
      final isLastRow = r == rowCount - 1;
      final row = rows[r];
      final rowY = y + r;
      var x = 0;

      for (var idx = 0; idx < row.length; idx++) {
        final seg = row[idx];
        if (idx > 0) x += 1;
        if (x >= width) break;
        final next = _paintTab(
          canvas,
          theme,
          x,
          rowY,
          width,
          seg.index,
          seg.tab,
          seg.isActive,
        );
        if (next == x) break;
        x = next;
      }

      if (isLastRow && hidden > 0) {
        final chip = '+$hidden>';
        if (x + 1 + chip.length <= width) {
          x += 1;
          canvas.paint(x, rowY, chip, style: theme.dimStyle);
          _hits.add(
            x: x,
            y: rowY,
            w: chip.length,
            h: 1,
            msg: const _CycleTabsForwardMsg(),
          );
        }
      }
    }
  }

  int _paintTab(
    CellCanvas canvas,
    FrunTheme theme,
    int x,
    int y,
    int stripWidth,
    int tabIndex,
    RunTab t,
    bool isActive,
  ) {
    final maxLabelChars = isActive ? 32 : 18;
    final shortLabel = t.label.length > maxLabelChars
        ? '${t.label.substring(0, maxLabelChars - 3)}...'
        : t.label;
    final marker = t.isRunning ? '' : ' off';
    final label = ' ${tabIndex + 1}  $shortLabel$marker ';

    final wantsButtons = isActive && t.isRunning;
    final allButtons = wantsButtons ? activeButtons : <_Button>[];

    final remaining = stripWidth - x;
    if (remaining < 3) return x;

    var displayLabel = label;
    var labelWidth = label.length;
    var buttons = allButtons;
    final reservedForButtons = buttons.length * 3;

    if (labelWidth + reservedForButtons > remaining) {
      buttons = const <_Button>[];
      if (labelWidth > remaining) {
        final maxLabel = remaining;
        if (maxLabel < 2) return x;
        final cutTo = math.min(label.length, maxLabel) - 1;
        if (cutTo < 1) return x;
        displayLabel = '${label.substring(0, cutTo)}.';
        labelWidth = displayLabel.length;
      }
    }

    final tabStyle = isActive
        ? theme.activeTabStyle
        : (t.isRunning ? theme.inactiveTabStyle : theme.exitedTabStyle);

    canvas.paint(x, y, displayLabel, style: tabStyle);
    _hits.add(x: x, y: y, w: labelWidth, h: 1, msg: SetActiveTabMsg(tabIndex));

    var cursor = x + labelWidth;

    for (final b in buttons) {
      final style = b.isStop ? theme.buttonStopStyle : theme.buttonStyle;
      canvas.paint(cursor, y, ' ${b.letter} ', style: style);
      _hits.add(x: cursor, y: y, w: 3, h: 1, msg: b.message(tabIndex));
      cursor += 3;
    }

    return cursor + 1;
  }
}
