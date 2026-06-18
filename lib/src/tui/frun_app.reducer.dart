part of 'frun_app.dart';

/// Lifecycle (`init`) + the central reducer (`update`).
mixin _ReducerMixin on _FrunModelBase, _KeyMixin, _MouseMixin, _EngineMixin {
  // ── Lifecycle ──────────────────────────────────────────────────────────

  @override
  Cmd? init() {
    _input.loadHistory(_historyStore.load());
    state.transcript.system('frun $frunVersion — type help for commands.');
    state.transcript.info('Project: ${state.project.name} (${state.project.root})');
    if (state.project.hasVsCodeFolder) {
      state.transcript.info('Detected .vscode/ → launch configs available via run.');
    }
    if (state.config.editorMode == FrunEditorMode.vim) {
      _vimState.mode = VimMode.normal;
      state.transcript.info('Vim mode active — press i to type commands.');
    }
    return null;
  }

  // ── Reducer ────────────────────────────────────────────────────────────

  @override
  (Model, Cmd?) update(Msg msg) {
    if (state.quitRequested) return (this, () => quit());

    if (state.showConfigEditor && !_configEditorActive) {
      state.showConfigEditor = false;
      _configEditorActive = true;
      _configEditorRow = 0;
      _configDraft = state.config;
    }

    if (_input.editorMode != state.config.editorMode) {
      _input.editorMode = state.config.editorMode;
      if (state.config.editorMode == FrunEditorMode.normal) {
        _tc.exit();
        _vimState.mode = VimMode.insert;
      } else {
        // Switched into vim editor mode — start in normal.
        _tc.exit();
        _vimState.mode = VimMode.normal;
      }
    }

    if (msg is WindowSizeMsg) {
      _width = msg.width;
      _height = msg.height;
      return (this, null);
    }

    if (msg is TickMsg) {
      if (_autoScrollDirection != 0 && _mouseSelecting) {
        _applyAutoScroll();
        return (this, null);
      }
      // Windows ConPTY does not deliver SIGWINCH; dart_tui's resize watcher
      // never fires. Poll stdout dimensions and request a size refresh when
      // they change so the layout reflows on terminal resize.
      if (Platform.isWindows && stdout.hasTerminal) {
        try {
          final w = stdout.terminalColumns;
          final h = stdout.terminalLines;
          if (w != _width || h != _height) {
            return (this, () async => requestWindowSize());
          }
        } catch (_) {
          // ignore — fall through
        }
      }
      return (this, null);
    }

    if (msg is MouseClickMsg) {
      // Some terminals deliver wheel ticks as clicks; route those to the panel
      // scroller when the diagnostics overlay is open.
      final b = msg.mouse.button;
      if (state.showDiagnosticsPanel &&
          (b == MouseButton.wheelUp || b == MouseButton.wheelDown)) {
        _scrollDiagnosticsByWheel(up: b == MouseButton.wheelUp);
      } else {
        _onMouseClick(msg.mouse);
      }
      return (this, null);
    }

    if (msg is MouseMotionMsg) {
      _onMouseMotion(msg.mouse);
      return (this, null);
    }

    if (msg is MouseReleaseMsg) {
      _onMouseRelease(msg.mouse);
      return (this, null);
    }

    if (msg is MouseWheelMsg) {
      final b = msg.mouse.button;
      if (state.showDiagnosticsPanel &&
          (b == MouseButton.wheelUp || b == MouseButton.wheelDown)) {
        _scrollDiagnosticsByWheel(up: b == MouseButton.wheelUp);
      } else {
        _onMouseWheel(msg.mouse);
      }
      return (this, null);
    }

    if (msg is KeyMsg) {
      _onKey(msg);
      return (this, null);
    }

    if (msg is SetActiveTabMsg) {
      state.runController.setActiveIndex(msg.index);
      _resetViewForNewTab();
    } else if (msg is RerunTabMsg) {
      unawaited(state.runController.rerunTabByIndex(msg.index));
    } else if (msg is ReloadTabMsg) {
      final tabs = state.runController.tabs;
      if (msg.index >= 0 && msg.index < tabs.length) {
        unawaited(state.runController.hotReloadTab(tabs[msg.index]));
      }
    } else if (msg is RestartTabMsg) {
      final tabs = state.runController.tabs;
      if (msg.index >= 0 && msg.index < tabs.length) {
        unawaited(state.runController.hotRestartTab(tabs[msg.index]));
      }
    } else if (msg is StopTabMsg) {
      unawaited(state.runController.stopTabByIndex(msg.index));
    } else if (msg is RunButtonMsg) {
      _input.setText('run');
      _submit();
    } else if (msg is TranscriptLineClickMsg) {
      msg.action();
    } else if (msg is PickLaunchEntryMsg) {
      final entries = state.launchChoices;
      if (msg.index >= 0 && msg.index < entries.length) {
        final picked = entries[msg.index];
        state.clearPickers();
        unawaited(state.runController.openRunTargetPicker(picked));
      }
    } else if (msg is CloseLaunchPickerMsg) {
      state.clearPickers();
    } else if (msg is PickEmulatorMsg) {
      final emulators = state.emulatorChoices;
      if (msg.index >= 0 && msg.index < emulators.length) {
        final picked = emulators[msg.index];
        state.setBootModePicker(picked.id);
      }
    } else if (msg is CloseEmulatorPickerMsg) {
      state.clearPickers();
    } else if (msg is PickBootModeMsg) {
      final pendingId = state.pendingEmulatorId;
      if (pendingId != null) {
        final coldBoot = msg.index == 1;
        state.clearPickers();
        _input.setText('emulators launch $pendingId${coldBoot ? ' cold' : ''}');
        _submit();
      }
    } else if (msg is CloseBootModePickerMsg) {
      state.clearPickers();
    } else if (msg is PickRunTargetMsg) {
      final targets = state.runTargetChoices;
      if (msg.index >= 0 && msg.index < targets.length) {
        unawaited(state.runController.launchOnTarget(targets[msg.index]));
      }
    } else if (msg is CloseRunTargetPickerMsg) {
      state.pendingRunEntry = null;
      state.clearPickers();
    } else if (msg is _CycleTabsForwardMsg) {
      if (state.runController.tabs.length >= 2) {
        state.runController.cycleActive(forward: true);
        _resetViewForNewTab();
      }
    } else if (msg is ToggleDiagnosticsOverlayMsg) {
      state.showDiagnosticsPanel = !state.showDiagnosticsPanel;
      _diagPendingG = false;
      _diagSearching = false;
      if (state.showDiagnosticsPanel) {
        _diagSelectedIndex = 0;
        _diagScrollOffset = 0;
      }
    } else if (msg is CloseDiagnosticsOverlayMsg) {
      state.showDiagnosticsPanel = false;
      _diagPendingG = false;
      _diagSearching = false;
    } else if (msg is SetDiagnosticsFilterMsg) {
      state.diagnosticsFilter = msg.level;
      _diagSelectedIndex = 0;
      _diagScrollOffset = 0;
    } else if (msg is JumpToDiagnosticMsg) {
      unawaited(_openDiagnostic(msg.diagnostic));
      state.showDiagnosticsPanel = false;
    }

    final nowActive = state.hasActivePicker;
    if (nowActive && !_pickerWasActive) {
      _pickerSelectedIndex = 0;
      _pickerScrollOffset = 0;
    }
    _pickerWasActive = nowActive;

    return (this, null);
  }
}
