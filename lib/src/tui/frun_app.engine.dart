part of 'frun_app.dart';

/// Vim-engine callbacks, transcript-cursor navigation, and command submission.
mixin _EngineMixin on _FrunModelBase {
  // ── Engine callbacks ───────────────────────────────────────────────────

  ({int top, int height}) _viewportFor(VimBuffer buffer) {
    if (identical(buffer, _tc)) {
      return (top: _lastVisibleStart, height: _lastBodyHeight);
    }
    return (top: 0, height: _input.lines.length);
  }

  void _runExCmd(ExCommand cmd, VimBuffer buffer) {
    // Substitute applies to input buffer regardless of where typed.
    if (cmd.name == 's' && cmd.substitute != null) {
      _applySubstitute(cmd.substitute!);
      return;
    }
    if (cmd.name == 'noh') {
      _tc.searchQuery = '';
      _tc.matches = const [];
      _tc.activeMatchIndex = -1;
      return;
    }
    if (cmd.name == 'reg') {
      state.transcript.system('-- Registers --');
      for (final e in _vimState.registers.all()) {
        state.transcript.info('"${e.key}  ${e.value.text.replaceAll('\n', '⏎')}');
      }
      return;
    }
    // First try the curated alias map (q→quit, wq→quit, h→help, etc.).
    // Then fall back to a direct slash-command lookup so :inspect, :devtools,
    // or any future /foo all work without needing an explicit alias entry.
    final slash = ExParser.toSlash(cmd.name) ?? cmd.name;
    final command = registry.lookup(slash);
    if (command == null) {
      state.visibleTranscript.error('Unknown ex command: :${cmd.name}');
      return;
    }
    final args = cmd.args.isEmpty
        ? const <String>[]
        : cmd.args.split(RegExp(r'\s+'));
    state.visibleTranscript
        .system(':${cmd.name}${cmd.args.isEmpty ? '' : ' ${cmd.args}'}');
    command.run(args, state).then(_handleResult).catchError((Object e, _) {
      state.visibleTranscript.error('Command :${cmd.name} failed: $e');
    });
  }

  void _applySubstitute(SubstituteSpec sub) {
    final lines = _input.lines.toList();
    if (lines.isEmpty) return;
    final pattern = RegExp(sub.pattern, caseSensitive: !sub.caseInsensitive);
    final newLines = <String>[];
    for (final line in lines) {
      newLines.add(sub.global
          ? line.replaceAll(pattern, sub.replacement)
          : line.replaceFirst(pattern, sub.replacement));
    }
    _input.setText(newLines.join('\n'));
    _vimState.lastSubstitutePattern = sub.pattern;
    _vimState.lastSubstituteReplacement = sub.replacement;
  }

  void _runSearch(String pattern, bool forward, VimBuffer buffer) {
    if (identical(buffer, _tc)) {
      _tc.searchQuery = pattern;
      _recomputeMatches();
      if (_tc.matches.isEmpty) {
        state.transcript.system('No matches for "$pattern".');
        return;
      }
      _tc.activeMatchIndex = 0;
      _jumpToActiveMatch();
      return;
    }
    // Search inside the input buffer — move cursor to first match.
    final needle = pattern.toLowerCase();
    final lines = _input.lines;
    final startRow = _input.cursor.row;
    final startCol = _input.cursor.col;
    for (var off = 0; off <= lines.length; off++) {
      final r = (forward ? startRow + off : startRow - off);
      if (r < 0 || r >= lines.length) continue;
      final hay = lines[r].toLowerCase();
      final from = (r == startRow) ? (forward ? startCol + 1 : 0) : 0;
      final idx = forward ? hay.indexOf(needle, from) : hay.lastIndexOf(needle, from);
      if (idx >= 0) {
        _input.cursor = Pos(r, idx);
        return;
      }
    }
  }

  void _switchTabFromVim(int? tabNumber, {required bool forward}) {
    final tabs = state.runController.tabs;
    if (tabs.isEmpty) return;
    if (tabNumber != null) {
      state.runController.setActiveIndex(tabNumber - 1);
    } else {
      state.runController.cycleActive(forward: forward);
    }
    _resetViewForNewTab();
  }

  // ── Vim transcript-cursor mode ─────────────────────────────────────────

  void _enterTranscriptCursor() {
    if (_lastDisplayRows.isEmpty) return;
    final endRow = _lastVisibleEnd - 1;
    final startCursor = endRow.clamp(_lastVisibleStart, _lastVisibleEnd - 1);
    final col = (_lastDisplayRows[startCursor].text.length - 1).clamp(0, 1 << 30);
    _tc.enter(initialRow: startCursor, initialCol: col);
    _vimState.mode = VimMode.normal;
  }

  void _recomputeMatches() {
    if (_tc.searchQuery.isEmpty) {
      _tc.matches = const [];
      _tc.activeMatchIndex = -1;
      return;
    }
    final needle = _tc.searchQuery.toLowerCase();
    final out = <SearchMatch>[];
    for (var i = 0; i < _lastDisplayRows.length; i++) {
      final hay = _lastDisplayRows[i].text.toLowerCase();
      var from = 0;
      while (from <= hay.length - needle.length) {
        final idx = hay.indexOf(needle, from);
        if (idx < 0) break;
        out.add(SearchMatch(row: i, col: idx, length: needle.length));
        from = idx + needle.length;
      }
    }
    _tc.matches = out;
    _tc.activeMatchIndex = out.isEmpty ? -1 : 0;
  }

  void _jumpToActiveMatch() {
    if (_tc.activeMatchIndex < 0 || _tc.activeMatchIndex >= _tc.matches.length) {
      return;
    }
    final m = _tc.matches[_tc.activeMatchIndex];
    _tc.cursor = Pos(m.row, m.col);
    _ensureCursorVisible();
  }

  void _ensureCursorVisible() {
    if (_lastDisplayRows.isEmpty) return;
    final visibleRowCount = _lastBodyHeight;
    if (visibleRowCount <= 0) return;
    final total = _lastDisplayRows.length;
    var scroll = _transcriptScroll;
    final endExclusive = total - scroll;
    final start = endExclusive - visibleRowCount;
    if (_tc.row >= endExclusive) {
      scroll = (total - _tc.row - 1).clamp(0, 1 << 30);
    } else if (_tc.row < start) {
      scroll = (total - _tc.row - visibleRowCount).clamp(0, 1 << 30);
    }
    _transcriptScroll = scroll.clamp(0, _maxScroll());
  }

  int _maxScroll() {
    final visibleRowCount = _lastBodyHeight;
    if (visibleRowCount <= 0) return 0;
    return (_lastDisplayRows.length - visibleRowCount).clamp(0, 1 << 30);
  }

  // ── Yank-feedback hook (engine writes via RegisterBank; we surface via
  //    `:reg`. For "+y/"*y we already kick off clipboard write inside the
  //    RegisterBank — nothing extra to do here.)
  // ───────────────────────────────────────────────────────────────────────

  // ── Command submission ─────────────────────────────────────────────────

  void _submit() {
    final line = _input.text.trim();
    _input.resetHistoryNavigation();
    _input.clear();
    _transcriptScroll = 0;
    _focusedLinkIndex = -1;
    if (line.isEmpty) return;
    _input.pushHistory(line);
    _historyStore.save(_input.cmdHistory.toList());

    // `:cmd` is reserved for the vim ex parser — routes through the same
    // alias surface used by `:` from normal mode.
    if (line.startsWith(':')) {
      final cmd = ExParser.parse(line.substring(1));
      if (cmd == null) {
        state.visibleTranscript.warn('Empty ex command.');
        return;
      }
      _runExCmd(cmd, _activeBuffer);
      return;
    }

    final parts = line.split(RegExp(r'\s+'));
    final rawName = parts.first;
    final args = parts.length > 1 ? parts.sublist(1) : const <String>[];
    final command = registry.lookup(rawName) ?? registry.lookup(rawName.toLowerCase());
    if (command == null) {
      state.visibleTranscript.error('Unknown command: $rawName. Type help.');
      return;
    }
    state.visibleTranscript.system('> $line');
    command.run(args, state).then(_handleResult).catchError((Object e, _) {
      state.visibleTranscript.error('Command $rawName failed: $e');
    });
  }

  void _handleResult(CommandResult result) {
    if (result.shouldQuit) {
      state.quitRequested = true;
      onQuit();
    }
  }
}
