part of 'frun_app.dart';

/// Keyboard handling: the main key router, the config-editor key handler,
/// insert dispatch, dot-repeat capture, and viewport scroll shortcuts.
mixin _KeyMixin on _FrunModelBase, _EngineMixin, _MouseMixin, _OverlayMixin {
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
          _vim.handle(KeyPressMsg(const TeaKey(code: KeyCode.escape)), _activeBuffer);
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

    // Config editor swallows all keys while active.
    if (_configEditorActive) {
      _handleConfigEditorKey(event);
      return;
    }

    // Picker keyboard handling: navigation, digit-pick, swallow everything else.
    if (state.hasActivePicker) {
      final count = _activePickerItemCount();
      if (count > 0) {
        final plain = ke.code == KeyCode.rune &&
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
        (_vimState.mode == VimMode.exCmd ||
            _vimState.mode == VimMode.search)) {
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
      if (ke.code == KeyCode.up && ke.modifiers.isEmpty &&
          _input.cursor.row == 0) {
        if (_input.navigateHistory(-1)) return;
      } else if (ke.code == KeyCode.down && ke.modifiers.isEmpty &&
          _input.cursor.row == _input.lineCount - 1) {
        if (_input.navigateHistory(1)) return;
      }
    }

    // History navigation: normal editor mode, Up/Down at buffer boundaries.
    if (state.config.editorMode == FrunEditorMode.normal) {
      if (ke.code == KeyCode.up && ke.modifiers.isEmpty &&
          _input.cursor.row == 0) {
        if (_input.navigateHistory(-1)) return;
      } else if (ke.code == KeyCode.down && ke.modifiers.isEmpty &&
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
        state.setConfig(_configDraft!);
        _configStore.save(_configDraft!);
      }
      _configEditorActive = false;
      _configDraft = null;
      return;
    }

    final count = _configEditorEntries.length;
    final plain = ke.code == KeyCode.rune &&
        !ke.modifiers.contains(KeyMod.ctrl) &&
        !ke.modifiers.contains(KeyMod.alt);

    final isUp = ke.code == KeyCode.up ||
        (plain && isVim && ke.text == 'k');
    final isDown = ke.code == KeyCode.down ||
        (plain && isVim && ke.text == 'j');
    final isLeft = ke.code == KeyCode.left ||
        (plain && isVim && ke.text == 'h');
    final isRight = ke.code == KeyCode.right ||
        (plain && isVim && ke.text == 'l');

    if (isUp) {
      _configEditorRow = (_configEditorRow - 1 + count) % count;
      return;
    }
    if (isDown) {
      _configEditorRow = (_configEditorRow + 1) % count;
      return;
    }
    if ((isLeft || isRight) && _configDraft != null) {
      final entry = _configEditorEntries[_configEditorRow];
      if (entry.values.isNotEmpty) {
        _configDraft = _cycleConfigValue(_configDraft!, entry.key, isRight ? 1 : -1);
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
    final plain = ke.code == KeyCode.rune &&
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
    if (ke.code == KeyCode.up) {
      _moveDiagSelection(-1);
      _diagPendingG = false;
      return;
    }
    if (ke.code == KeyCode.down) {
      _moveDiagSelection(1);
      _diagPendingG = false;
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

    // Vim navigation mode (not while typing a `/` search).
    if (vim && !_diagSearching) {
      if (ke.code == KeyCode.rune && ke.modifiers.contains(KeyMod.ctrl)) {
        final t = ke.text.toLowerCase();
        if (t == 'd') {
          for (var n = 0; n < 5; n++) {
            _moveDiagSelection(1);
          }
          return;
        }
        if (t == 'u') {
          for (var n = 0; n < 5; n++) {
            _moveDiagSelection(-1);
          }
          return;
        }
      }
      if (plain) {
        switch (ke.text) {
          case 'j':
            _moveDiagSelection(1);
            _diagPendingG = false;
          case 'k':
            _moveDiagSelection(-1);
            _diagPendingG = false;
          case 'l':
            _stepDiagnosticsFilter(1); // next category chip
            _diagPendingG = false;
          case 'h':
            _stepDiagnosticsFilter(-1); // previous category chip
            _diagPendingG = false;
          case 'G':
            _diagSelectEdge(first: false);
            _diagPendingG = false;
          case 'g':
            if (_diagPendingG) {
              _diagSelectEdge(first: true);
              _diagPendingG = false;
            } else {
              _diagPendingG = true;
            }
          case 'q':
            _closeDiagnosticsPanel();
          case '/':
            _diagSearching = true;
            state.diagnosticsSearch = '';
            _diagSelectedIndex = 0;
            _diagPendingG = false;
          default:
            _diagPendingG = false; // swallow other keys
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
    _diagPendingG = false;
    _diagSearching = false;
  }

  /// Move the active filter chip by [dir] (+1 next, -1 previous), wrapping over
  /// only the *visible* chips (`all` plus categories that have problems), and
  /// reset list position.
  void _stepDiagnosticsFilter(int dir) {
    final (e, w, i, t) = Diagnostic.counts(state.diagnostics);
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
