import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dart_tui/dart_tui.dart';

import '../app/app_state.dart';
import '../app/commands/command.dart';
import '../app/commands/command_registry.dart';
import '../app/link_extractor.dart';
import '../app/run_tab.dart';
import '../app/transcript.dart';
import '../config/config.dart';
import '../config/config_store.dart';
import '../config/history_store.dart';
import '../ide/source_location.dart';
import '../version.dart';
import 'clipboard.dart';
import 'hit_regions.dart';
import 'input_controller.dart';
import 'theme.dart';
import 'transcript_cursor.dart';
import 'vim/ex_parser.dart';
import 'vim/vim_buffer.dart';
import 'vim/vim_engine.dart';
import 'vim/vim_mode.dart';
import 'vim/vim_state.dart';

class _VisibleLink {
  _VisibleLink(this.transcriptLineIndex, this.link);
  final int transcriptLineIndex;
  final TranscriptLink link;
}

/// One row's worth of rendered text. A long transcript line wraps into
/// several `_DisplayRow`s; [startCol] is the offset into the source line so
/// the renderer can map link spans onto the right row.
class _DisplayRow {
  _DisplayRow(this.lineIndex, this.startCol, this.text, {this.ansiPrefix = ''});
  final int lineIndex;
  final int startCol;
  final String text;
  /// ANSI SGR codes active at the start of this row (accumulated from prior
  /// wrapped chunks). Prepended during rendering so colours survive wraps.
  final String ansiPrefix;
}

// ─── Domain messages dispatched by hit-regions and the entry layer ─────────

final class TickWakeMsg extends Msg {
  const TickWakeMsg();
}

final class SetActiveTabMsg extends Msg {
  const SetActiveTabMsg(this.index);
  final int index;
}

final class ReloadTabMsg extends Msg {
  const ReloadTabMsg(this.index);
  final int index;
}

final class RestartTabMsg extends Msg {
  const RestartTabMsg(this.index);
  final int index;
}

final class StopTabMsg extends Msg {
  const StopTabMsg(this.index);
  final int index;
}

final class RerunTabMsg extends Msg {
  const RerunTabMsg(this.index);
  final int index;
}

final class RunButtonMsg extends Msg {
  const RunButtonMsg();
}

final class TranscriptLineClickMsg extends Msg {
  TranscriptLineClickMsg(this.action);
  final void Function() action;
}

final class PickLaunchEntryMsg extends Msg {
  const PickLaunchEntryMsg(this.index);
  final int index;
}

final class CloseLaunchPickerMsg extends Msg {
  const CloseLaunchPickerMsg();
}

final class PickEmulatorMsg extends Msg {
  const PickEmulatorMsg(this.index);
  final int index;
}

final class CloseEmulatorPickerMsg extends Msg {
  const CloseEmulatorPickerMsg();
}

final class PickBootModeMsg extends Msg {
  const PickBootModeMsg(this.index);
  final int index;
}

final class CloseBootModePickerMsg extends Msg {
  const CloseBootModePickerMsg();
}

final class PickRunTargetMsg extends Msg {
  const PickRunTargetMsg(this.index);
  final int index;
}

final class CloseRunTargetPickerMsg extends Msg {
  const CloseRunTargetPickerMsg();
}

final class _CycleTabsForwardMsg extends Msg {
  const _CycleTabsForwardMsg();
}

/// Top-level TUI:
///   0..bodyH-1:  transcript (full width, borderless)
///   then:        optional status block (toggled by /status)
///   then:        info bar — tabs strip on the left, project/device/ide on the right
///   penultimate: input prompt (multi-line in vim mode)
///   last:        footer / hints
final class FrunModel extends TeaModel {
  FrunModel({
    required this.state,
    required this.registry,
    required this.onQuit,
    required ConfigStore configStore,
  }) : _configStore = configStore,
       _input = InputController(editorMode: state.config.editorMode) {
    _tc = TranscriptCursor(rowsProvider: () => _displayRowsText);
    _vim = VimEngine(
      state: _vimState,
      viewport: _viewportFor,
      runExCmd: _runExCmd,
      runSearch: _runSearch,
      onSubmit: _submit,
      onTabSwitch: _switchTabFromVim,
    );
  }

  final AppState state;
  final CommandRegistry registry;
  final void Function() onQuit;

  final ConfigStore _configStore;
  final InputController _input;

  bool _configEditorActive = false;
  int _configEditorRow = 0;
  FrunConfig? _configDraft;
  final HistoryStore _historyStore = HistoryStore();
  late final TranscriptCursor _tc;
  final HitRegions _hits = HitRegions();
  final VimState _vimState = VimState();
  late final VimEngine _vim;

  int _transcriptScroll = 0;
  int _focusedLinkIndex = -1;

  int _pickerSelectedIndex = 0;
  int _pickerScrollOffset = 0;
  bool _pickerWasActive = false;

  // Mouse-drag selection state. `_mouseAnchor` is captured on left-click
  // inside the transcript body when no hit-region intercepts; the selection
  // itself is materialised on the first MouseMotionMsg so a plain click
  // doesn't strand a zero-width range.
  bool _mouseSelecting = false;
  Pos? _mouseAnchor;
  bool _mouseDragged = false;
  // Captured at click-time so release can restore the prior input/cursor
  // mode regardless of whether the user was in vim normal, insert, or the
  // non-vim editor mode when the drag began.
  VimMode? _mousePriorVimMode;
  bool _mousePriorTcActive = false;
  int _autoScrollDirection = 0; // -1 = toward newer (down), +1 = toward older (up), 0 = none

  // Cached layout state, refreshed each view() call.
  List<_VisibleLink> _visibleLinks = const <_VisibleLink>[];
  List<_DisplayRow> _lastDisplayRows = const <_DisplayRow>[];
  List<String> _displayRowsText = const <String>[];
  int _lastVisibleStart = 0;
  int _lastVisibleEnd = 0;
  int _lastBodyHeight = 10;
  int _lastBodyY = 0;
  int _width = 80;
  int _height = 24;

  static const int _maxInputRows = 8;

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
      _onMouseClick(msg.mouse);
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
      _onMouseWheel(msg.mouse);
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
    }

    final nowActive = state.hasActivePicker;
    if (nowActive && !_pickerWasActive) {
      _pickerSelectedIndex = 0;
      _pickerScrollOffset = 0;
    }
    _pickerWasActive = nowActive;

    return (this, null);
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

  VimBuffer get _activeBuffer => _tc.active ? _tc : _input;

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

  // ── Mouse handling ─────────────────────────────────────────────────────

  void _updateAutoScroll(int mouseY) {
    if (!_mouseSelecting) {
      _autoScrollDirection = 0;
      return;
    }
    if (mouseY <= _lastBodyY) {
      _autoScrollDirection = 1;
    } else if (mouseY >= _lastBodyY + _lastBodyHeight - 1) {
      _autoScrollDirection = -1;
    } else {
      _autoScrollDirection = 0;
    }
  }

  void _applyAutoScroll() {
    if (_autoScrollDirection == 0 || _mouseAnchor == null) return;
    const speed = 3;
    _scrollBy(_autoScrollDirection * speed);
    final total = _displayRowsText.length;
    final newEnd = (total - _transcriptScroll).clamp(0, total);
    final newStart = (newEnd - _lastBodyHeight).clamp(0, total);
    final Pos newCursor;
    if (_autoScrollDirection > 0) {
      newCursor = Pos(newStart, 0);
    } else {
      final r = (newEnd - 1).clamp(0, total - 1);
      final line = r < total ? _displayRowsText[r] : '';
      newCursor = Pos(r, line.isEmpty ? 0 : line.length - 1);
    }
    _tc.cursor = newCursor;
    _tc.selection = Range(_mouseAnchor!, newCursor, RangeKind.charwise);
  }

  void _onMouseClick(Mouse mouse) {
    // Some terminals route wheel ticks as click events; forward to the wheel
    // handler so scroll works either way.
    if (mouse.button == MouseButton.wheelUp ||
        mouse.button == MouseButton.wheelDown) {
      _onMouseWheel(mouse);
      return;
    }
    final msg = _hits.hit(mouse.x, mouse.y);
    // The body registers a TickWakeMsg hit so any pointer activity wakes the
    // renderer; it must NOT preempt drag-to-select. Skip it here and fall
    // through to anchor selection.
    if (msg != null && msg is! TickWakeMsg) {
      update(msg);
      return;
    }
    if (mouse.button != MouseButton.left) return;
    if (!_isInsideBody(mouse)) return;
    final pos = _mouseToPos(mouse);
    if (pos == null) return;
    _autoScrollDirection = 0;
    _mouseAnchor = pos;
    _mouseSelecting = true;
    _mouseDragged = false;
    _mousePriorVimMode = _vimState.mode;
    _mousePriorTcActive = _tc.active;
  }

  void _onMouseMotion(Mouse mouse) {
    if (!_mouseSelecting) return;
    final anchor = _mouseAnchor;
    if (anchor == null) return;
    final pos = _mouseToPos(mouse);
    if (pos == null) return;
    if (!_tc.active) {
      _tc.enter(initialRow: anchor.row, initialCol: anchor.col);
      _vimState.mode = VimMode.normal;
    }
    _tc.cursor = pos;
    _tc.visualKind = VimMode.visualChar;
    _tc.selection = Range(anchor, _tc.cursor, RangeKind.charwise);
    _mouseDragged = true;
    _updateAutoScroll(mouse.y);
    if (_autoScrollDirection != 0) _applyAutoScroll();
  }

  void _onMouseRelease(Mouse mouse) {
    if (!_mouseSelecting) return;
    _autoScrollDirection = 0;
    final dragged = _mouseDragged;
    final priorMode = _mousePriorVimMode ?? VimMode.insert;
    final priorTcActive = _mousePriorTcActive;
    _mouseSelecting = false;
    _mouseAnchor = null;
    _mouseDragged = false;
    _mousePriorVimMode = null;
    if (!dragged) {
      // Plain click — clear any selection and exit cursor mode if not previously active.
      _tc.selection = null;
      if (!priorTcActive && _tc.active) {
        _tc.exit();
        _vimState.mode = priorMode;
      }
      return;
    }
    // Drag complete — keep selection highlighted so user can adjust it, then
    // press Ctrl+C to copy. Cursor mode stays active for keyboard adjustment.
  }

  bool _isInsideBody(Mouse mouse) {
    if (mouse.y < _lastBodyY || mouse.y >= _lastBodyY + _lastBodyHeight) {
      return false;
    }
    if (mouse.x < 0 || mouse.x >= _width) return false;
    return true;
  }

  /// Maps a terminal cell to a (display-row, col) inside the visible
  /// transcript window. Returns null when the click lands on an empty
  /// transcript or outside the laid-out rows.
  Pos? _mouseToPos(Mouse mouse) {
    if (_displayRowsText.isEmpty) return null;
    final offset = mouse.y - _lastBodyY;
    final maxRow = (_lastVisibleEnd - 1).clamp(0, _displayRowsText.length - 1);
    final minRow = _lastVisibleStart.clamp(0, _displayRowsText.length - 1);
    final row = (_lastVisibleStart + offset).clamp(minRow, maxRow);
    final line = _displayRowsText[row];
    final maxCol = line.isEmpty ? 0 : line.length - 1;
    final col = mouse.x.clamp(0, maxCol);
    return Pos(row, col);
  }

  void _onMouseWheel(Mouse mouse) {
    // Scroll regardless of pointer Y — when the user reaches for the wheel
    // they want the transcript to move, even if the cursor is hovering over
    // the input prompt or footer.
    switch (mouse.button) {
      case MouseButton.wheelUp:
        _scrollBy(3);
      case MouseButton.wheelDown:
        _scrollBy(-3);
      default:
        break;
    }
  }

  void _scrollBy(int lines) {
    _transcriptScroll = (_transcriptScroll + lines).clamp(0, 1 << 30);
    _focusedLinkIndex = -1;
  }

  void _resetViewForNewTab() {
    _transcriptScroll = 0;
    _focusedLinkIndex = -1;
    _tc.exit();
  }

  void _cycleLink({required bool forward}) {
    if (_visibleLinks.isEmpty) {
      _focusedLinkIndex = -1;
      return;
    }
    final delta = forward ? 1 : -1;
    if (_focusedLinkIndex < 0) {
      _focusedLinkIndex = forward ? 0 : _visibleLinks.length - 1;
    } else {
      _focusedLinkIndex = (_focusedLinkIndex + delta) % _visibleLinks.length;
      if (_focusedLinkIndex < 0) _focusedLinkIndex += _visibleLinks.length;
    }
  }

  Future<void> _openFocusedLink() async {
    if (_focusedLinkIndex < 0 || _focusedLinkIndex >= _visibleLinks.length) {
      return;
    }
    final ref = _visibleLinks[_focusedLinkIndex];
    final loc = SourceLocation.fromVmServiceUri(
      ref.link.uri.startsWith('package:')
          ? ref.link.uri
          : _toFileUri(ref.link.uri),
      projectRoot: state.project.root,
      line: ref.link.line,
      column: ref.link.column ?? 1,
    );
    if (loc == null) {
      state.transcript.warn('Could not resolve ${ref.link.uri} to a file.');
      return;
    }
    await state.ideLauncher.open(loc, state);
  }

  String _toFileUri(String pathLike) {
    if (pathLike.startsWith('/')) return 'file://$pathLike';
    return 'file://${state.project.root}/$pathLike';
  }

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

  String _promptForMode() {
    if (_vimState.mode == VimMode.exCmd) return ':';
    if (_vimState.mode == VimMode.search) {
      return (_vimState.lastSearch?.forward ?? true) ? '/' : '?';
    }
    if (state.config.editorMode == FrunEditorMode.vim &&
        _vimState.mode != VimMode.insert) {
      return '· ';
    }
    return '> ';
  }

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

  static const int _maxInfoBarRows = 6;
  static const int _maxPickerRows = 12;
  static const int _pickerIndent = 2;
  static const String _runButtonLabel = ' ► ';
  static const String _pickerCloseLabel = ' x ';

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
      unawaited(state.runController.launchOnTarget(state.runTargetChoices[idx]));
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
    Canvas canvas,
    FrunTheme theme,
    _PickerSpec spec,
    int width,
    int y,
    int height,
  ) {
    if (height <= 0) return;

    final header = spec.header;
    final headerClipped =
        header.length > width ? header.substring(0, width) : header;
    canvas.paint(0, y, theme.dimStyle.render(headerClipped));
    final closeX = (width - _pickerCloseLabel.length).clamp(0, width);
    if (closeX > headerClipped.length) {
      canvas.paint(closeX, y, theme.buttonStopStyle.render(_pickerCloseLabel));
      _hits.add(
        x: closeX,
        y: y,
        w: _pickerCloseLabel.length,
        h: 1,
        msg: _pickerCloseMsg(spec.kind),
      );
    }

    if (height < 3 || width < 4) return;
    final topY = y + 1;
    final bottomY = y + height - 1;
    final innerStartY = y + 2;
    final innerEndY = y + height - 2;
    final horizontal = '─' * (width - 2);
    canvas.paint(0, topY, theme.borderStyle.render('┌$horizontal┐'));
    canvas.paint(0, bottomY, theme.borderStyle.render('└$horizontal┘'));
    for (var r = innerStartY; r <= innerEndY; r++) {
      canvas.paint(0, r, theme.borderStyle.render('│'));
      canvas.paint(width - 1, r, theme.borderStyle.render('│'));
    }

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
      _pickerScrollOffset =
          _pickerScrollOffset.clamp(0, math.max(0, chips.length - visibleCount));
    }

    final chipStyle = _pickerChipStyle(spec.kind, theme);
    final selectedStyle = _pickerSelectedChipStyle(spec.kind, theme);
    for (var i = 0; i < visibleCount; i++) {
      final chipIdx = _pickerScrollOffset + i;
      if (chipIdx >= chips.length) break;
      final rowY = innerStartY + i * 2;
      if (rowY > innerEndY) break;
      final style = chipIdx == _pickerSelectedIndex ? selectedStyle : chipStyle;
      canvas.paint(_pickerIndent, rowY, style.render(chips[chipIdx].text));
      _hits.add(
        x: _pickerIndent,
        y: rowY,
        w: chips[chipIdx].text.length,
        h: 1,
        msg: _pickerPickMsg(spec.kind, chips[chipIdx].index),
      );
    }
    final hidden = math.max(0, chips.length - _pickerScrollOffset - visibleCount) +
        _pickerScrollOffset;
    if (hidden > 0) {
      final rowY = innerStartY + visibleCount * 2;
      if (rowY <= innerEndY) {
        final more = ' +$hidden more — ${spec.moreHintFormat} to apply ';
        final maxLen = math.max(0, width - _pickerIndent * 2);
        final clipped = more.length > maxLen ? more.substring(0, maxLen) : more;
        canvas.paint(_pickerIndent, rowY, theme.dimStyle.render(clipped));
      }
    }
  }

  int _computeConfigEditorHeight() {
    if (!_configEditorActive) return 0;
    // header + top border + one row per entry + bottom border
    return 1 + 1 + _configEditorEntries.length + 1;
  }

  static const _configEditorEntries = <_ConfigEditorEntry>[
    _ConfigEditorEntry('ide', ['vscode', 'zed', 'neovim'], label: 'IDE'),
    _ConfigEditorEntry('editor_mode', ['normal', 'vim'], label: 'Editor mode'),
    _ConfigEditorEntry('theme', ['dark', 'light'], label: 'Theme'),
    _ConfigEditorEntry('hot_reload_on_save', ['true', 'false'], label: 'Hot reload on save'),
    _ConfigEditorEntry('open_devtools_on_launch', ['ask', 'always', 'never'], label: 'Open devtools on launch'),
    _ConfigEditorEntry('emulator_boot', ['quick', 'cold'], label: 'Emulator boot'),
  ];

  String _configEditorEntryValue(FrunConfig c, String key) {
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
      default:
        return '';
    }
  }

  FrunConfig _cycleConfigValue(FrunConfig c, String key, int delta) {
    switch (key) {
      case 'ide':
        const vals = FrunIde.values;
        final idx = (vals.indexOf(c.ide) + delta + vals.length) % vals.length;
        return c.copyWith(ide: vals[idx]);
      case 'editor_mode':
        const vals = FrunEditorMode.values;
        final idx = (vals.indexOf(c.editorMode) + delta + vals.length) % vals.length;
        return c.copyWith(editorMode: vals[idx]);
      case 'theme':
        const vals = FrunThemeMode.values;
        final idx = (vals.indexOf(c.theme) + delta + vals.length) % vals.length;
        return c.copyWith(theme: vals[idx]);
      case 'hot_reload_on_save':
        return c.copyWith(hotReloadOnSave: !c.hotReloadOnSave);
      case 'open_devtools_on_launch':
        const vals = FrunDevToolsAutoOpen.values;
        final idx = (vals.indexOf(c.openDevtoolsOnLaunch) + delta + vals.length) % vals.length;
        return c.copyWith(openDevtoolsOnLaunch: vals[idx]);
      case 'emulator_boot':
        const vals = FrunEmulatorBoot.values;
        final idx = (vals.indexOf(c.emulatorBoot) + delta + vals.length) % vals.length;
        return c.copyWith(emulatorBoot: vals[idx]);
      default:
        return c;
    }
  }

  void _paintConfigEditor(
    Canvas canvas,
    FrunTheme theme,
    int width,
    int y,
    int height,
  ) {
    if (height <= 0 || _configDraft == null) return;

    final isVim = state.config.editorMode == FrunEditorMode.vim;
    final hint = isVim
        ? ' Config — jk navigate · hl cycle value · enter apply · esc discard'
        : ' Config — ↑↓ navigate · ←→ cycle value · enter apply · esc discard';
    final hintClipped = hint.length > width ? hint.substring(0, width) : hint;
    canvas.paint(0, y, theme.dimStyle.render(hintClipped));

    if (height < 3) return;

    final topY = y + 1;
    final bottomY = y + height - 1;
    final horiz = '─' * (width - 2);
    canvas.paint(0, topY, theme.borderStyle.render('┌$horiz┐'));
    canvas.paint(0, bottomY, theme.borderStyle.render('└$horiz┘'));

    for (var i = 0; i < _configEditorEntries.length; i++) {
      final rowY = topY + 1 + i;
      if (rowY >= bottomY) break;
      canvas.paint(0, rowY, theme.borderStyle.render('│'));
      canvas.paint(width - 1, rowY, theme.borderStyle.render('│'));

      final entry = _configEditorEntries[i];
      final isSelected = i == _configEditorRow;
      final currentVal = _configEditorEntryValue(_configDraft!, entry.key);

      const keyWidth = 26;
      const indicatorWidth = 2;
      const innerGap = 1;
      const valGap = 2;

      final indicator = isSelected ? '► ' : '  ';
      final keyPadded = entry.displayLabel.padRight(keyWidth);

      const contentX = innerGap + indicatorWidth + keyWidth + valGap;

      if (isSelected) {
        canvas.paint(innerGap, rowY, theme.accentStyle.render(indicator + keyPadded));
      } else {
        canvas.paint(innerGap, rowY, indicator + keyPadded);
      }

      if (contentX < width - 1) {
        if (isSelected && entry.values.isNotEmpty) {
          final chip = '◄ $currentVal ►';
          canvas.paint(contentX, rowY, theme.pickerChipSelectedStyle.render(chip));
        } else {
          canvas.paint(contentX, rowY, theme.dimStyle.render(currentVal));
        }
      }
    }
  }

  int _computeInfoBarHeight(int width) {
    final tabs = state.runController.tabs;
    if (tabs.isEmpty) return 1;
    final (rows, _) = _layoutTabRows(width);
    return rows.length.clamp(1, _maxInfoBarRows);
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
        ? '${t.label.substring(0, maxLabelChars - 1)}…'
        : t.label;
    final marker = t.isRunning ? '' : ' x';
    final labelText = ' ${tabIndex + 1}: $shortLabel$marker ';
    final buttonCount = isActive && t.isRunning ? activeButtons.length : 0;
    return labelText.length + buttonCount * 3;
  }

  void _paintInfoBar(Canvas canvas, FrunTheme theme, int width, int y, int height) {
    final tabs = state.runController.tabs;

    if (tabs.isEmpty) {
      return;
    }

    final (rows, hidden) = _layoutTabRows(width);
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
        final next = _paintTab(canvas, theme, x, rowY, width, seg.index, seg.tab, seg.isActive);
        if (next == x) break;
        x = next;
      }

      if (isLastRow && hidden > 0) {
        final chip = '+$hidden›';
        if (x + 1 + chip.length <= width) {
          x += 1;
          canvas.paint(x, rowY, theme.dimStyle.render(chip));
          _hits.add(x: x, y: rowY, w: chip.length, h: 1, msg: const _CycleTabsForwardMsg());
        }
      }
    }
  }

  int _paintTab(
    Canvas canvas,
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
        ? '${t.label.substring(0, maxLabelChars - 1)}…'
        : t.label;
    final marker = t.isRunning ? '' : ' x';
    final label = ' ${tabIndex + 1}: $shortLabel$marker ';

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
        displayLabel = '${label.substring(0, cutTo)}…';
        labelWidth = displayLabel.length;
      }
    }

    final tabStyle = isActive
        ? theme.activeTabStyle
        : (t.isRunning ? theme.inactiveTabStyle : theme.exitedTabStyle);

    canvas.paint(x, y, tabStyle.render(displayLabel));
    _hits.add(
      x: x,
      y: y,
      w: labelWidth,
      h: 1,
      msg: SetActiveTabMsg(tabIndex),
    );

    var cursor = x + labelWidth;

    for (final b in buttons) {
      final style = b.isStop ? theme.buttonStopStyle : theme.buttonStyle;
      canvas.paint(cursor, y, style.render(' ${b.letter} '));
      _hits.add(
        x: cursor,
        y: y,
        w: 3,
        h: 1,
        msg: b.message(tabIndex),
      );
      cursor += 3;
    }

    return cursor + 1;
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

// ── Per-tab button table ──────────────────────────────────────────────────

class _TabSegment {
  const _TabSegment(this.index, this.tab, this.isActive, this.width);
  final int index;
  final RunTab tab;
  final bool isActive;
  final int width;
}

class _PickerChip {
  const _PickerChip(this.index, this.text);
  final int index;
  final String text;
}

enum _PickerKind { launch, emulator, bootMode, runTarget }

class _PickerSpec {
  const _PickerSpec({
    required this.kind,
    required this.itemCount,
    required this.header,
    required this.moreHintFormat,
  });
  final _PickerKind kind;
  final int itemCount;
  final String header;
  final String moreHintFormat;
}

class _Button {
  const _Button(this.letter, this.message, {this.isStop = false});
  final String letter;
  final Msg Function(int index) message;
  final bool isStop;
}

const activeButtons = <_Button>[
  _Button('r', ReloadTabMsg.new),
  _Button('R', RestartTabMsg.new),
  _Button('S', StopTabMsg.new, isStop: true),
];

class _ConfigEditorEntry {
  const _ConfigEditorEntry(this.key, this.values, {this.label});
  final String key;
  final List<String> values;
  final String? label;
  String get displayLabel => label ?? key;
}

/// Updates [active] SGR parameter list from a raw SGR parameter string
/// (the text between `\x1b[` and `m`, e.g. `'1;33'` or `'0'`).
/// Handles reset codes, extended 256-colour, and truecolour sequences.
void _applyAnsiSgr(String params, List<String> active) {
  if (params.isEmpty || params == '0') {
    active.clear();
    return;
  }
  final parts = params.split(';');
  var j = 0;
  while (j < parts.length) {
    final p = parts[j];
    if (p == '0' || p.isEmpty) {
      active.clear();
      j++;
    } else if ((p == '38' || p == '48') && j + 1 < parts.length) {
      if (parts[j + 1] == '5' && j + 2 < parts.length) {
        active.add('$p;5;${parts[j + 2]}');
        j += 3;
      } else if (parts[j + 1] == '2' && j + 4 < parts.length) {
        active.add('$p;2;${parts[j + 2]};${parts[j + 3]};${parts[j + 4]}');
        j += 5;
      } else {
        active.add(p);
        j++;
      }
    } else {
      active.add(p);
      j++;
    }
  }
}

