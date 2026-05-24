import 'dart:async';
import 'dart:math' as math;

import 'package:dart_tui/dart_tui.dart';

import '../app/app_state.dart';
import '../app/commands/command.dart';
import '../app/commands/command_registry.dart';
import '../app/link_extractor.dart';
import '../app/run_tab.dart';
import '../app/transcript.dart';
import '../config/config.dart';
import '../ide/source_location.dart';
import '../project/launch_config.dart';
import '../version.dart';
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
  _DisplayRow(this.lineIndex, this.startCol, this.text);
  final int lineIndex;
  final int startCol;
  final String text;
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
  FrunModel({required this.state, required this.registry, required this.onQuit})
      : _input = InputController(editorMode: state.config.editorMode) {
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

  final InputController _input;
  late final TranscriptCursor _tc;
  final HitRegions _hits = HitRegions();
  final VimState _vimState = VimState();
  late final VimEngine _vim;

  int _transcriptScroll = 0;
  int _focusedLinkIndex = -1;

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
    state.transcript.system('frun $frunVersion — type /help for commands.');
    state.transcript.info('Project: ${state.project.name} (${state.project.root})');
    if (state.project.hasVsCodeFolder) {
      state.transcript.info('Detected .vscode/ → launch configs available via /run.');
    }
    return null;
  }

  // ── Reducer ────────────────────────────────────────────────────────────

  @override
  (Model, Cmd?) update(Msg msg) {
    if (state.quitRequested) return (this, () => quit());

    if (_input.editorMode != state.config.editorMode) {
      _input.editorMode = state.config.editorMode;
      if (state.config.editorMode == FrunEditorMode.normal) {
        _tc.exit();
        _vimState.mode = VimMode.insert;
      }
    }

    if (msg is WindowSizeMsg) {
      _width = msg.width;
      _height = msg.height;
      return (this, null);
    }

    if (msg is TickMsg) return (this, null);

    if (msg is MouseClickMsg) {
      _onMouseClick(msg.mouse);
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
      _input.setText('/run');
      _submit();
    } else if (msg is TranscriptLineClickMsg) {
      msg.action();
    } else if (msg is PickLaunchEntryMsg) {
      final entries = state.launchChoices;
      if (msg.index >= 0 && msg.index < entries.length) {
        final picked = entries[msg.index];
        state.launchChoices = const <LaunchEntry>[];
        unawaited(state.runController.launchEntry(picked));
      }
    } else if (msg is CloseLaunchPickerMsg) {
      state.launchChoices = const <LaunchEntry>[];
    } else if (msg is _CycleTabsForwardMsg) {
      if (state.runController.tabs.length >= 2) {
        state.runController.cycleActive(forward: true);
        _resetViewForNewTab();
      }
    }

    return (this, null);
  }

  // ── Key handling ───────────────────────────────────────────────────────

  void _onKey(KeyMsg event) {
    final ke = event.keyEvent;

    // Ctrl+C → graceful quit, matching legacy behaviour.
    if (ke.code == KeyCode.rune &&
        ke.modifiers.contains(KeyMod.ctrl) &&
        (ke.text == 'c' || ke.text == 'C')) {
      // In a vim sub-mode (visual/op-pending/ex/search) Ctrl-C cancels back
      // to normal rather than quitting; only quit when "really at rest".
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

    // Esc dismisses the `/run` launch picker if it's open. Takes priority
    // over vim/transcript-cursor mode so a stray Esc doesn't strand the
    // picker on screen.
    if (ke.code == KeyCode.escape && state.launchChoices.isNotEmpty) {
      state.launchChoices = const <LaunchEntry>[];
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

  void _insertIntoActive(KeyMsg event) {
    if (_activeBuffer is InputController) {
      final action = _input.insertKey(event);
      if (action == InputAction.submit) _submit();
      return;
    }
    // Read-only buffers (transcript/tab) ignore raw insert input.
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

  void _onMouseClick(Mouse mouse) {
    final msg = _hits.hit(mouse.x, mouse.y);
    if (msg == null) return;
    update(msg);
  }

  void _onMouseWheel(Mouse mouse) {
    if (mouse.y < _lastBodyY || mouse.y >= _lastBodyY + _lastBodyHeight) {
      return;
    }
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
    _input.clear();
    _transcriptScroll = 0;
    _focusedLinkIndex = -1;
    if (line.isEmpty) return;

    // `:cmd` typed in insert mode → route through ex parser so users get the
    // same vim-style alias surface they'd see by pressing `:` in normal mode.
    if (line.startsWith(':')) {
      final cmd = ExParser.parse(line.substring(1));
      if (cmd == null) {
        state.visibleTranscript.warn('Empty ex command.');
        return;
      }
      _runExCmd(cmd, _activeBuffer);
      return;
    }

    if (!line.startsWith('/')) {
      state.visibleTranscript
          .warn('Commands start with "/" or ":". Try /help.');
      return;
    }

    final parts = line.substring(1).split(RegExp(r'\s+'));
    final name = parts.first;
    final args = parts.length > 1 ? parts.sublist(1) : const <String>[];
    final command = registry.lookup(name);
    if (command == null) {
      state.visibleTranscript.error('Unknown command: /$name');
      return;
    }
    state.visibleTranscript.system('> $line');
    command.run(args, state).then(_handleResult).catchError((Object e, _) {
      state.visibleTranscript.error('Command /$name failed: $e');
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
        mouseMode: MouseMode.allMotion,
      );
    }

    final inputH = _computeInputHeight();
    const footerH = 1;
    final infoBarH = _computeInfoBarHeight(w);
    final pickerH = _computeLaunchPickerHeight(w);
    final statusH = state.showStatusPanel ? _statusHeight(h, infoBarH + pickerH + inputH) : 0;
    final bodyH = h - inputH - footerH - statusH - infoBarH - pickerH;
    _lastBodyHeight = bodyH;
    _lastBodyY = 0;

    final canvas = Canvas(w, h);

    _paintTranscript(canvas, theme, w, 0, bodyH);
    if (state.showStatusPanel) {
      _paintStatus(canvas, theme, w, bodyH, statusH);
    }
    if (pickerH > 0) {
      _paintLaunchPicker(
        canvas,
        theme,
        w,
        h - footerH - inputH - infoBarH - pickerH,
        pickerH,
      );
    }
    _paintInfoBar(canvas, theme, w, h - footerH - inputH - infoBarH, infoBarH);
    _paintInput(canvas, theme, w, h - footerH - inputH, inputH);
    _paintFooter(canvas, theme, w, h - footerH);

    final showCursor = _shouldShowHardwareCursor();
    final inputCursor = showCursor
        ? _inputCursorPosition(w, h - footerH - inputH, inputH)
        : null;

    return View(
      content: canvas.render(),
      altScreen: true,
      mouseMode: MouseMode.allMotion,
      cursor: inputCursor,
    );
  }

  bool _shouldShowHardwareCursor() {
    if (_tc.active) return false;
    if (_vimState.mode == VimMode.exCmd || _vimState.mode == VimMode.search) {
      return false;
    }
    return state.config.editorMode == FrunEditorMode.normal ||
        _vimState.mode == VimMode.insert ||
        _vimState.mode == VimMode.replace;
  }

  int _computeInputHeight() {
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
      canvas.paint(0, yRow, baseStyle.render(row.text));

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
      var pos = 0;
      while (pos < text.length) {
        final end = math.min(pos + width, text.length);
        out.add(_DisplayRow(i, pos, text.substring(pos, end)));
        pos = end;
      }
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
      ('Device', state.selectedDeviceId ?? '(none)'),
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
  static const String _runLabel = '[+ Run]';
  static const String _pickerCloseLabel = ' x ';

  String _rightInfoText() {
    final tabCount = state.runController.tabs.length;
    final tabsSegment = tabCount > 0 ? '  tabs:$tabCount' : '';
    return ' ${state.project.name}  '
        'dev:${state.selectedDeviceId ?? "—"}  '
        'ide:${state.config.ide.id}$tabsSegment ';
  }

  String _pickerChipText(int index, LaunchEntry entry) {
    final tags = <String>[
      if (entry.flutterMode != null) entry.flutterMode!,
      if (entry.deviceId != null) entry.deviceId!,
    ];
    final tail = tags.isEmpty ? '' : '  ${tags.join(' · ')}';
    return ' [$index] ${entry.name}$tail ';
  }

  (List<_PickerChip>, int) _layoutPickerChips(int width) {
    final entries = state.launchChoices;
    final maxChipWidth = math.max(8, width - _pickerIndent * 2);

    final raws = <String>[];
    var widest = 0;
    for (var i = 0; i < entries.length; i++) {
      final raw = _pickerChipText(i, entries[i]);
      raws.add(raw);
      if (raw.length > widest) widest = raw.length;
    }
    final uniformWidth = math.min(widest, maxChipWidth);

    final chips = <_PickerChip>[];
    for (var i = 0; i < entries.length; i++) {
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

  int _computeLaunchPickerHeight(int width) {
    if (state.launchChoices.isEmpty) return 0;
    final entries = state.launchChoices.length;
    final chipBlock = math.max(0, entries * 2 - 1);
    final desired = 1 + 1 + chipBlock + 1;
    final headroom = math.max(4, _height - 6);
    final maxBoxBlock = math.max(0, _maxPickerRows * 2 - 1);
    final maxByCap = 1 + 1 + maxBoxBlock + 1;
    return math.min(desired, math.min(maxByCap, headroom));
  }

  void _paintLaunchPicker(
    Canvas canvas,
    FrunTheme theme,
    int width,
    int y,
    int height,
  ) {
    if (height <= 0 || state.launchChoices.isEmpty) return;

    const header = ' Run: pick an entry — click or press esc to close';
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
        msg: const CloseLaunchPickerMsg(),
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

    final (chips, _) = _layoutPickerChips(width);
    final innerH = innerEndY - innerStartY + 1;
    if (innerH <= 0) return;
    final maxVisible = (innerH + 1) ~/ 2;
    final hidden = math.max(0, chips.length - maxVisible);
    final visibleCount = hidden > 0
        ? math.max(0, maxVisible - 1)
        : chips.length;

    for (var i = 0; i < visibleCount; i++) {
      final rowY = innerStartY + i * 2;
      if (rowY > innerEndY) break;
      canvas.paint(
        _pickerIndent,
        rowY,
        theme.pickerChipStyle.render(chips[i].text),
      );
      _hits.add(
        x: _pickerIndent,
        y: rowY,
        w: chips[i].text.length,
        h: 1,
        msg: PickLaunchEntryMsg(chips[i].index),
      );
    }
    if (hidden > 0) {
      final rowY = innerStartY + visibleCount * 2;
      if (rowY <= innerEndY) {
        final more = ' +$hidden more — /run <index|name> to launch ';
        final maxLen = math.max(0, width - _pickerIndent * 2);
        final clipped = more.length > maxLen ? more.substring(0, maxLen) : more;
        canvas.paint(_pickerIndent, rowY, theme.dimStyle.render(clipped));
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
    final rightInfoWidth = _rightInfoText().length;
    final rowWidth = math.max(10, width - rightInfoWidth - 1);

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
    return 1 + labelText.length + buttonCount * 3 + 1;
  }

  void _paintInfoBar(Canvas canvas, FrunTheme theme, int width, int y, int height) {
    final tabs = state.runController.tabs;
    final rightInfo = _rightInfoText();
    final rightX = (width - rightInfo.length).clamp(0, width);
    final bottomY = y + height - 1;
    canvas.paint(rightX, bottomY, theme.dimStyle.render(rightInfo));

    if (tabs.isEmpty) {
      if (rightX >= _runLabel.length + 1) {
        canvas.paint(0, bottomY, theme.buttonStyle.render(_runLabel), zIndex: 1);
        _hits.add(
          x: 0,
          y: bottomY,
          w: _runLabel.length,
          h: 1,
          msg: const RunButtonMsg(),
        );
      }
      return;
    }

    final (rows, hidden) = _layoutTabRows(width);
    final rowCount = math.min(rows.length, height);
    for (var r = 0; r < rowCount; r++) {
      final isLastRow = r == rowCount - 1;
      final row = rows[r];
      final rowY = y + r;
      final rowWidth = isLastRow ? rightX : width;
      var x = 0;
      for (var idx = 0; idx < row.length; idx++) {
        final seg = row[idx];
        if (idx > 0) x += 1;
        if (x >= rowWidth) break;
        final next = _paintTab(canvas, theme, x, rowY, rowWidth, seg.index,
            seg.tab, seg.isActive);
        if (next == x) break;
        x = next;
      }

      if (isLastRow) {
        if (hidden > 0) {
          final chip = '+$hidden›';
          if (x + 1 + chip.length <= rowWidth) {
            x += 1;
            canvas.paint(x, rowY, theme.dimStyle.render(chip));
            _hits.add(
              x: x,
              y: rowY,
              w: chip.length,
              h: 1,
              msg: const _CycleTabsForwardMsg(),
            );
            x += chip.length;
          }
        }
        if (x + 1 + _runLabel.length <= rowWidth) {
          x += 1;
          canvas.paint(x, rowY, theme.buttonStyle.render(_runLabel), zIndex: 1);
          _hits.add(
            x: x,
            y: rowY,
            w: _runLabel.length,
            h: 1,
            msg: const RunButtonMsg(),
          );
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
    if (remaining < 5) return x;

    var displayLabel = label;
    var labelWidth = label.length;
    var buttons = allButtons;
    final reservedForButtons = buttons.length * 3;

    if (1 + labelWidth + reservedForButtons + 1 > remaining) {
      buttons = const <_Button>[];
      if (1 + labelWidth + 1 > remaining) {
        final maxLabel = remaining - 2;
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

    canvas.paint(x, y, theme.dimStyle.render('['));
    canvas.paint(x + 1, y, tabStyle.render(displayLabel));
    _hits.add(
      x: x + 1,
      y: y,
      w: labelWidth,
      h: 1,
      msg: SetActiveTabMsg(tabIndex),
    );

    var cursor = x + 1 + labelWidth;

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

    canvas.paint(cursor, y, theme.dimStyle.render(']'));
    return cursor + 2;
  }

  void _paintInput(Canvas canvas, FrunTheme theme, int width, int y, int height) {
    // Ex/search prompt: single row, prefix + draft.
    if (_vimState.mode == VimMode.exCmd ||
        _vimState.mode == VimMode.search) {
      final prefix = _promptForMode();
      canvas.paint(0, y, theme.accentStyle.render(prefix));
      final draft = _vimState.mode == VimMode.exCmd
          ? _vimState.exDraft
          : _vimState.searchDraft;
      final usable = width - prefix.length;
      var visible = draft;
      if (visible.length > usable) {
        visible = visible.substring(visible.length - usable);
      }
      canvas.paint(prefix.length, y, visible);
      return;
    }

    final prompt = _promptForMode();
    final usable = width - prompt.length;
    final lines = _input.lines;
    final cur = _input.cursor;
    final rowsToPaint = math.min(lines.length, height);

    for (var r = 0; r < rowsToPaint; r++) {
      final yRow = y + r;
      final line = lines[r];
      // Only paint prompt on the first row.
      if (r == 0) {
        canvas.paint(0, yRow, theme.promptStyle.render(prompt));
      } else {
        canvas.paint(0, yRow, theme.dimStyle.render('  '));
      }
      var visible = line;
      var cursorOffset = (r == cur.row) ? cur.col : 0;
      if (visible.length > usable) {
        final start = (cursorOffset - usable + 1).clamp(0, visible.length);
        visible = visible.substring(start);
        cursorOffset -= start;
      }
      final clipped = visible.length > usable ? visible.substring(0, usable) : visible;
      canvas.paint(prompt.length, yRow, clipped);

      // Software cursor for vim normal/visual.
      if (state.config.editorMode == FrunEditorMode.vim &&
          r == cur.row &&
          !_tc.active &&
          (_vimState.mode == VimMode.normal ||
              _vimState.mode == VimMode.visualChar ||
              _vimState.mode == VimMode.visualLine ||
              _vimState.mode == VimMode.visualBlock)) {
        final cx = prompt.length + cursorOffset;
        if (cx < width) {
          final ch = cursorOffset < visible.length ? visible[cursorOffset] : ' ';
          canvas.paint(cx, yRow, theme.cursorStyle.render(ch), zIndex: 2);
        }
      }
    }
  }

  void _paintFooter(Canvas canvas, FrunTheme theme, int width, int y) {
    final inputText = _input.text;
    final suggestions = inputText.startsWith('/')
        ? registry
            .suggestions(inputText.substring(1).split(' ').first)
            .take(6)
            .map((c) => '/${c.name}')
            .join('  ')
        : '';

    final tabHint = state.runController.tabs.length >= 2 ? ' · ^t next tab' : '';
    final String left;
    if (state.launchChoices.isNotEmpty) {
      left = 'launch picker · click a button · /run <index|name> · esc cancel';
    } else if (_vimState.mode == VimMode.search) {
      left = 'search: enter run · esc cancel';
    } else if (_vimState.mode == VimMode.exCmd) {
      left = 'ex: enter run · esc cancel';
    } else if (_tc.active) {
      final matchInfo = _tc.matches.isEmpty
          ? ''
          : ' · match ${_tc.activeMatchIndex + 1}/${_tc.matches.length}';
      left = 'cursor mode · hjkl move · v/V/^v select · y yank · / search · n/N next$matchInfo · esc exit';
    } else if (suggestions.isNotEmpty) {
      left = 'suggest: $suggestions';
    } else if (_visibleLinks.isNotEmpty) {
      left = _focusedLinkIndex >= 0
          ? 'link ${_focusedLinkIndex + 1}/${_visibleLinks.length}: enter open · tab cycle$tabHint'
          : 'tab: focus link (${_visibleLinks.length}) · ↑↓ scroll$tabHint';
    } else {
      left = '↑↓ scroll · ^↑↓ half · esc cursor · click tabs$tabHint · ^c quit';
    }

    final modeLabel = state.config.editorMode == FrunEditorMode.vim
        ? _vimModeLabel()
        : 'normal mode';

    final bar = ' ' * width;
    canvas.paint(0, y, theme.statusBarStyle.render(bar));
    final right = modeLabel;
    final leftClipped = left.length > width - right.length - 2
        ? left.substring(0, width - right.length - 2)
        : left;
    canvas.paint(0, y, theme.statusBarStyle.render(leftClipped));
    canvas.paint(width - right.length, y, theme.statusBarStyle.render(right));
  }

  String _vimModeLabel() {
    final base = _vimState.mode.label;
    final pendingBits = <String>[];
    if (_vimState.pendingRegister.length == 1) {
      pendingBits.add('"${_vimState.pendingRegister}');
    }
    if (_vimState.pendingCount > 0) {
      pendingBits.add(_vimState.pendingCount.toString());
    }
    if (_vimState.pendingOperator.isNotEmpty) {
      pendingBits.add(_vimState.pendingOperator);
    }
    if (_tc.active) pendingBits.add('cursor');
    final tail = pendingBits.isEmpty ? '' : ' ${pendingBits.join('')}';
    return '$base$tail';
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

