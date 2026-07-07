part of 'frun_app.dart';

/// Keyboard handling: the main key router, the config-editor key handler,
/// insert dispatch, dot-repeat capture, and viewport scroll shortcuts.
mixin _KeyMixin on _FrunModelBase, _EngineMixin, _MouseMixin, _OverlayMixin {
  // ── Macro playback ─────────────────────────────────────────────────────

  /// Reentrancy guards for `@` playback: a macro can invoke another macro
  /// (or itself), so cap both nesting depth and total replayed keys.
  static const int _macroDepthCap = 16;
  static const int _macroTotalKeyCap = 10000;
  int _macroDepth = 0;
  int _macroReplayedKeys = 0;

  /// Replay a recorded tape through the full key router, so replayed keys
  /// behave exactly like typed ones (insert capture, submit, overlays).
  void _playMacro(List<TeaKey> keys) {
    if (_macroDepth >= _macroDepthCap) return;
    if (_macroDepth == 0) _macroReplayedKeys = 0;
    _macroDepth++;
    _vimState.macros.replayDepth++;
    try {
      for (final k in keys) {
        if (++_macroReplayedKeys > _macroTotalKeyCap) break;
        _onKey(KeyPressMsg(k));
      }
    } finally {
      _vimState.macros.replayDepth--;
      _macroDepth--;
    }
  }

  // ── Key handling ───────────────────────────────────────────────────────

  void _onKey(KeyMsg event) {
    final ke = event.keyEvent;

    // Ctrl-G acts as a universal "Esc" alias.
    //
    // Windows ConPTY drops the bare 0x1B byte for the Esc key (dart_tui's
    // 10 ms lone-escape timer gets cancelled by follow-up input chunks),
    // and Ctrl-C is hijacked by PowerShell/cmd as SIGINT before it reaches
    // stdin — so Ctrl-G is the only chord guaranteed to flow through on
    // Windows. It mirrors Esc behaviour exactly.
    if (ke.code == KeyCode.rune &&
        ke.modifiers.contains(KeyMod.ctrl) &&
        (ke.text == 'g' || ke.text == 'G')) {
      if (state.showDiagnosticsPanel) {
        _closeDiagnosticsPanel();
        return;
      }
      if (state.showIsolatesPanel) {
        _closeIsolatesPanel();
        return;
      }
      if (_configEditorActive) {
        _configEditorActive = false;
        _configDraft = null;
        return;
      }
      final m = _vimState.mode;
      if (state.config.editorMode == FrunEditorMode.vim) {
        if (m == VimMode.insert && _input.text.isEmpty && !_tc.active) {
          _enterTranscriptCursor();
          return;
        }
        if (m != VimMode.normal) {
          _vim.handle(
            KeyPressMsg(const TeaKey(code: KeyCode.escape)),
            _activeBuffer,
          );
          return;
        }
      }
      // Normal editor mode (no vim) — clear input as a soft cancel.
      _input.clear();
      return;
    }

    // Ctrl+C — copy active selection if one exists; otherwise graceful quit.
    // On Windows the host shell usually consumes this before we see it, but on
    // POSIX it arrives.
    if (ke.code == KeyCode.rune &&
        ke.modifiers.contains(KeyMod.ctrl) &&
        (ke.text == 'c' || ke.text == 'C')) {
      if (_tc.active && _tc.selection != null) {
        final sel = _tc.selection!;
        final text = _tc.textInRange(sel);
        if (text.isNotEmpty) {
          unawaited(copyToClipboard(text));
          state.visibleTranscript.system('Copied ${text.length} chars.');
        }
        _tc.selection = null;
        _tc.exit();
        _vimState.mode = VimMode.insert;
        return;
      }
      final m = _vimState.mode;
      if (state.config.editorMode == FrunEditorMode.vim &&
          m != VimMode.insert &&
          m != VimMode.normal) {
        _vim.handle(event, _activeBuffer);
        return;
      }
      state.quitRequested = true;
      onQuit();
      return;
    }

    // Esc dismisses any open picker. Takes priority over vim/transcript-cursor
    // mode so a stray Esc doesn't strand the picker on screen.
    if (ke.code == KeyCode.escape && state.hasActivePicker) {
      state.clearPickers();
      return;
    }

    // Diagnostics overlay is modal while open: handle its keys, swallow rest.
    if (state.showDiagnosticsPanel) {
      _handleDiagnosticsKey(event);
      return;
    }

    // Isolate panel is modal while open: handle its keys, swallow rest.
    if (state.showIsolatesPanel) {
      _handleIsolatesKey(event);
      return;
    }

    // Config editor swallows all keys while active.
    if (_configEditorActive) {
      _handleConfigEditorKey(event);
      return;
    }

    // Picker keyboard handling: navigation, digit-pick, swallow everything else.
    if (state.hasActivePicker) {
      final count = _activePickerItemCount();
      if (count > 0) {
        final plain =
            ke.code == KeyCode.rune &&
            !ke.modifiers.contains(KeyMod.ctrl) &&
            !ke.modifiers.contains(KeyMod.alt);
        final isUp = ke.code == KeyCode.up || (plain && ke.text == 'k');
        final isDown = ke.code == KeyCode.down || (plain && ke.text == 'j');
        if (isUp) {
          _pickerSelectedIndex = (_pickerSelectedIndex - 1 + count) % count;
          return;
        }
        if (isDown) {
          _pickerSelectedIndex = (_pickerSelectedIndex + 1) % count;
          return;
        }
        if (ke.code == KeyCode.enter) {
          _pickFromActivePicker(_pickerSelectedIndex);
          return;
        }
        if (plain && ke.text.length == 1) {
          final code = ke.text.codeUnitAt(0);
          if (code >= 0x30 && code <= 0x39) {
            _pickFromActivePicker(code - 0x30);
            return;
          }
        }
      }
      // Swallow all other keys so they don't leak into the hidden input.
      return;
    }

    // In vim mode, while engine is in ex/search, route everything to it.
    if (state.config.editorMode == FrunEditorMode.vim &&
        (_vimState.mode == VimMode.exCmd || _vimState.mode == VimMode.search)) {
      _vim.handle(event, _activeBuffer);
      return;
    }

    // Pre-engine scroll shortcuts (arrows, page, shift/ctrl variants) so
    // they work in both normal and vim editor modes uniformly.
    if (_handleViewportScroll(event)) return;

    // Ctrl+T cycles tabs.
    if (ke.code == KeyCode.rune &&
        ke.modifiers.contains(KeyMod.ctrl) &&
        (ke.text == 't' || ke.text == 'T')) {
      if (state.runController.tabs.length >= 2) {
        state.runController.cycleActive(forward: true);
        _resetViewForNewTab();
      }
      return;
    }

    // Esc on empty input in vim insert mode → enter transcript cursor mode.
    if (ke.code == KeyCode.escape &&
        state.config.editorMode == FrunEditorMode.vim &&
        _vimState.mode == VimMode.insert &&
        _input.text.isEmpty &&
        !_tc.active) {
      _enterTranscriptCursor();
      return;
    }

    if (ke.code == KeyCode.tab && _vimState.mode == VimMode.insert) {
      // Only intercept Tab for link cycling when nothing is being typed.
      if (_input.text.isEmpty) {
        _cycleLink(forward: !ke.modifiers.contains(KeyMod.shift));
        return;
      }
    }

    if (ke.code == KeyCode.enter &&
        _input.text.isEmpty &&
        _focusedLinkIndex >= 0 &&
        _vimState.mode == VimMode.insert) {
      unawaited(_openFocusedLink());
      return;
    }

    // History navigation: vim insert mode, Up/Down at buffer boundaries.
    if (state.config.editorMode == FrunEditorMode.vim &&
        _vimState.mode == VimMode.insert &&
        !_tc.active) {
      if (ke.code == KeyCode.up &&
          ke.modifiers.isEmpty &&
          _input.cursor.row == 0) {
        if (_input.navigateHistory(-1)) return;
      } else if (ke.code == KeyCode.down &&
          ke.modifiers.isEmpty &&
          _input.cursor.row == _input.lineCount - 1) {
        if (_input.navigateHistory(1)) return;
      }
    }

    // History navigation: normal editor mode, Up/Down at buffer boundaries.
    if (state.config.editorMode == FrunEditorMode.normal) {
      if (ke.code == KeyCode.up &&
          ke.modifiers.isEmpty &&
          _input.cursor.row == 0) {
        if (_input.navigateHistory(-1)) return;
      } else if (ke.code == KeyCode.down &&
          ke.modifiers.isEmpty &&
          _input.cursor.row == _input.lineCount - 1) {
        if (_input.navigateHistory(1)) return;
      }
    }

    // Vim editor mode → engine first.
    if (state.config.editorMode == FrunEditorMode.vim) {
      final result = _vim.handle(event, _activeBuffer);
      if (result == KeyResult.consumed) {
        if (_tc.active) {
          _ensureCursorVisible();
        } else if (ke.code == KeyCode.rune) {
          _transcriptScroll = 0;
          _focusedLinkIndex = -1;
        }
        return;
      }
      // passInsert → route to active buffer's insert handler.
      _insertIntoActive(event);
      return;
    }

    // Normal editor mode → straight to input insert handler.
    final action = _input.insertKey(event);
    if (action == InputAction.submit) {
      _submit();
    } else if (ke.code == KeyCode.rune) {
      _transcriptScroll = 0;
      _focusedLinkIndex = -1;
    }
  }

  void _handleConfigEditorKey(KeyMsg event) {
    final ke = event.keyEvent;
    final isVim = state.config.editorMode == FrunEditorMode.vim;

    if (ke.code == KeyCode.escape) {
      _configEditorActive = false;
      _configDraft = null;
      return;
    }

    if (ke.code == KeyCode.enter) {
      if (_configDraft != null) {
        final draft = _configDraft!;
        state.setConfig(draft);
        unawaited(state.deps.saveConfigUseCase?.call(draft));
      }
      _configEditorActive = false;
      _configDraft = null;
      return;
    }

    final count = _configEditorEntries.length;
    switch (_configNav.interpret(ke, vim: isVim)) {
      case OverlayNavMove(:final delta):
        _configEditorRow = ((_configEditorRow + delta) % count + count) % count;
        return;
      case OverlayNavEdge(:final first):
        _configEditorRow = first ? 0 : count - 1;
        return;
      case OverlayNavClose():
        _configEditorActive = false;
        _configDraft = null;
        return;
      case OverlayNavHalfPage():
      case OverlayNavStartSearch():
      case OverlayNavConsumed():
        return;
      case null:
        break;
    }

    final plain =
        ke.code == KeyCode.rune &&
        !ke.modifiers.contains(KeyMod.ctrl) &&
        !ke.modifiers.contains(KeyMod.alt);
    final isLeft =
        ke.code == KeyCode.left || (plain && isVim && ke.text == 'h');
    final isRight =
        ke.code == KeyCode.right || (plain && isVim && ke.text == 'l');

    if ((isLeft || isRight) && _configDraft != null) {
      final entry = _configEditorEntries[_configEditorRow];
      if (entry.values.isNotEmpty) {
        _configDraft = _cycleConfigValue(
          _configDraft!,
          entry.key,
          isRight ? 1 : -1,
        );
      }
      return;
    }
  }

  /// Handle keys while the diagnostics overlay is open. The overlay is modal.
  ///
  /// Common to both editor modes: arrows navigate, Enter jumps, Tab cycles the
  /// filter, Esc closes. In **normal** mode bare text is a live filter. In
  /// **vim** mode `j/k` move, `gg`/`G` jump to ends, `Ctrl-d`/`Ctrl-u` half-page,
  /// `q` closes, and `/` enters search-typing (where text feeds the filter until
  /// Enter/Esc).
  void _handleDiagnosticsKey(KeyMsg event) {
    final ke = event.keyEvent;
    final vim = state.config.editorMode == FrunEditorMode.vim;
    final plain =
        ke.code == KeyCode.rune &&
        !ke.modifiers.contains(KeyMod.ctrl) &&
        !ke.modifiers.contains(KeyMod.alt) &&
        ke.text.isNotEmpty;

    if (ke.code == KeyCode.escape) {
      if (vim && _diagSearching) {
        _diagSearching = false; // leave search; keep the applied filter
        return;
      }
      _closeDiagnosticsPanel();
      return;
    }
    if (ke.code == KeyCode.enter) {
      if (vim && _diagSearching) {
        _diagSearching = false; // confirm search
        _diagSelectedIndex = 0;
        return;
      }
      final d = _selectedDiagnostic();
      if (d != null) {
        unawaited(_openDiagnostic(d));
        _closeDiagnosticsPanel();
      }
      return;
    }
    if (ke.code == KeyCode.tab) {
      _stepDiagnosticsFilter(1);
      return;
    }
    if (ke.code == KeyCode.backspace) {
      final s = state.diagnosticsSearch;
      if (s.isNotEmpty) {
        state.diagnosticsSearch = s.substring(0, s.length - 1);
        _diagSelectedIndex = 0;
      }
      return;
    }

    // Shared vim list navigation (arrows always; j/k/gg/G/counts/Ctrl-d/u
    // only outside `/` search-typing).
    switch (_diagNav.interpret(ke, vim: vim && !_diagSearching)) {
      case OverlayNavMove(:final delta):
        _moveDiagSelection(delta);
        return;
      case OverlayNavEdge(:final first):
        _diagSelectEdge(first: first);
        return;
      case OverlayNavHalfPage(:final down):
        final half = (_lastBodyHeight ~/ 2).clamp(1, 200);
        _moveDiagSelection(down ? half : -half);
        return;
      case OverlayNavClose():
        _closeDiagnosticsPanel();
        return;
      case OverlayNavStartSearch():
        _diagSearching = true;
        state.diagnosticsSearch = '';
        _diagSelectedIndex = 0;
        return;
      case OverlayNavConsumed():
        return;
      case null:
        break;
    }

    // Vim navigation mode: h/l step the category filter chips.
    if (vim && !_diagSearching) {
      if (plain) {
        switch (ke.text) {
          case 'l':
            _stepDiagnosticsFilter(1); // next category chip
          case 'h':
            _stepDiagnosticsFilter(-1); // previous category chip
          default:
            break; // swallow other keys
        }
      }
      return;
    }

    // Normal mode (or vim search-typing): bare text is a live filter.
    if (ke.code == KeyCode.space) {
      state.diagnosticsSearch += ' ';
      _diagSelectedIndex = 0;
      return;
    }
    if (plain) {
      state.diagnosticsSearch += ke.text;
      _diagSelectedIndex = 0;
      return;
    }
    // Swallow anything else so it doesn't leak into the hidden input.
  }

  void _closeDiagnosticsPanel() {
    state.showDiagnosticsPanel = false;
    _diagNav.reset();
    _diagSearching = false;
  }

  void _handleIsolatesKey(KeyMsg event) {
    final ke = event.keyEvent;
    final plain =
        ke.code == KeyCode.rune &&
        !ke.modifiers.contains(KeyMod.ctrl) &&
        !ke.modifiers.contains(KeyMod.alt) &&
        ke.text.isNotEmpty;

    if (ke.code == KeyCode.escape) {
      _closeIsolatesPanel();
      return;
    }
    if (ke.code == KeyCode.enter || ke.code == KeyCode.space) {
      final iso = _selectedIsolate();
      if (iso != null) {
        unawaited(_runIsolateAction(_defaultIsolateAction(iso), id: iso.id));
      }
      return;
    }

    // Shared vim list navigation (this panel always accepts vim keys).
    switch (_isolateNav.interpret(ke, vim: true)) {
      case OverlayNavMove(:final delta):
        _moveIsolateSelection(delta);
        return;
      case OverlayNavEdge(:final first):
        _isolateSelectEdge(first: first);
        return;
      case OverlayNavHalfPage(:final down):
        final half = (_lastBodyHeight ~/ 2).clamp(1, 200);
        _moveIsolateSelection(down ? half : -half);
        return;
      case OverlayNavClose():
        _closeIsolatesPanel();
        return;
      case OverlayNavStartSearch():
      case OverlayNavConsumed():
        return;
      case null:
        break;
    }

    if (!plain) return;

    switch (ke.text) {
      case 'R':
        unawaited(_runIsolateAction(IsolatePanelAction.start));
        return;
      case 'p':
        unawaited(_runIsolateAction(IsolatePanelAction.pause));
        return;
      case 'r':
        unawaited(_runIsolateAction(IsolatePanelAction.resume));
        return;
      case 's':
        unawaited(_runIsolateAction(IsolatePanelAction.step));
        return;
      case 't':
        unawaited(_runIsolateAction(IsolatePanelAction.stack));
        return;
      case 'K':
      case 'x':
        unawaited(_runIsolateAction(IsolatePanelAction.kill));
        return;
      default:
        return;
    }
  }

  /// Move the active filter chip by [dir] (+1 next, -1 previous), wrapping over
  /// only the *visible* chips (`all` plus categories that have problems), and
  /// reset list position.
  void _stepDiagnosticsFilter(int dir) {
    final (e, w, i, t) = DiagnosticEntity.counts(state.diagnostics);
    final order = <DiagnosticCategory?>[
      null,
      if (e > 0) DiagnosticCategory.error,
      if (w > 0) DiagnosticCategory.warning,
      if (i > 0) DiagnosticCategory.info,
      if (t > 0) DiagnosticCategory.todo,
    ];
    final cur = order.indexOf(state.diagnosticsFilter);
    final next = cur < 0
        ? (dir > 0 ? 0 : order.length - 1)
        : (cur + dir + order.length) % order.length;
    state.diagnosticsFilter = order[next];
    _diagSelectedIndex = 0;
    _diagScrollOffset = 0;
  }

  void _insertIntoActive(KeyMsg event) {
    if (_activeBuffer is InputController) {
      _captureForDotRepeat(event);
      final action = _input.insertKey(event);
      if (action == InputAction.submit) _submit();
      return;
    }
    // Read-only buffers (transcript/tab) ignore raw insert input.
  }

  /// Mirror typed runes into the vim engine's active insert-session capture
  /// buffer so `.` can replay the last insertion.
  void _captureForDotRepeat(KeyMsg event) {
    final cap = _vimState.insertCapture;
    if (cap == null) return;
    final ke = event.keyEvent;
    if (ke.modifiers.contains(KeyMod.ctrl) ||
        ke.modifiers.contains(KeyMod.alt)) {
      return;
    }
    switch (ke.code) {
      case KeyCode.rune:
        if (ke.text.isNotEmpty && ke.text != '\n' && ke.text != '\r') {
          cap.write(ke.text);
        }
      case KeyCode.space:
        cap.write(' ');
      case KeyCode.tab:
        cap.write('  ');
      default:
        break;
    }
  }

  bool _handleViewportScroll(KeyMsg event) {
    final ke = event.keyEvent;
    final pageBig = (_lastBodyHeight - 2).clamp(3, 200);
    final pageHalf = (pageBig ~/ 2).clamp(2, 200);

    switch (ke.code) {
      case KeyCode.up:
        if (ke.modifiers.contains(KeyMod.shift) &&
            ke.modifiers.contains(KeyMod.ctrl)) {
          _scrollBy(pageBig);
        } else if (ke.modifiers.contains(KeyMod.ctrl)) {
          _scrollBy(pageHalf);
        } else if (ke.modifiers.contains(KeyMod.shift)) {
          _scrollBy(5);
        } else if (_vimState.mode == VimMode.insert && !_tc.active) {
          // Plain Up while typing — let the input buffer move the cursor.
          return false;
        } else {
          _scrollBy(1);
        }
        return true;
      case KeyCode.down:
        if (ke.modifiers.contains(KeyMod.shift) &&
            ke.modifiers.contains(KeyMod.ctrl)) {
          _scrollBy(-pageBig);
        } else if (ke.modifiers.contains(KeyMod.ctrl)) {
          _scrollBy(-pageHalf);
        } else if (ke.modifiers.contains(KeyMod.shift)) {
          _scrollBy(-5);
        } else if (_vimState.mode == VimMode.insert && !_tc.active) {
          return false;
        } else {
          _scrollBy(-1);
        }
        return true;
      case KeyCode.pageUp:
        _scrollBy(pageBig);
        return true;
      case KeyCode.pageDown:
        _scrollBy(-pageBig);
        return true;
      default:
        break;
    }
    return false;
  }
}
