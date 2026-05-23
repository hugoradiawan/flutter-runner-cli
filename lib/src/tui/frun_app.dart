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
import '../version.dart';
import 'clipboard.dart';
import 'hit_regions.dart';
import 'input_controller.dart';
import 'theme.dart';
import 'transcript_cursor.dart';

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

final class _CycleTabsForwardMsg extends Msg {
  const _CycleTabsForwardMsg();
}

/// Top-level TUI:
///   0..bodyH-1:  transcript (full width, borderless)
///   then:        optional status block (toggled by /status)
///   then:        info bar — tabs strip on the left, project/device/ide on the right
///   penultimate: input prompt
///   last:        footer / hints
final class FrunModel extends TeaModel {
  FrunModel({required this.state, required this.registry, required this.onQuit})
      : _input = InputController(editorMode: state.config.editorMode);

  final AppState state;
  final CommandRegistry registry;
  final void Function() onQuit;

  final InputController _input;
  final TranscriptCursor _tc = TranscriptCursor();
  final HitRegions _hits = HitRegions();

  int _transcriptScroll = 0;
  int _focusedLinkIndex = -1;
  bool _pendingG = false;

  // Cached layout state, refreshed each view() call.
  List<_VisibleLink> _visibleLinks = const <_VisibleLink>[];
  List<_DisplayRow> _lastDisplayRows = const <_DisplayRow>[];
  int _lastVisibleStart = 0;
  int _lastVisibleEnd = 0;
  int _lastBodyHeight = 10;
  int _lastBodyY = 0;
  int _width = 80;
  int _height = 24;

  // Search prompt scratchpad — separate from the command input so opening the
  // search doesn't clobber what the user was typing.
  String _searchDraft = '';

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
      if (state.config.editorMode == FrunEditorMode.normal) _tc.exit();
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

    // Domain messages from hit-regions:
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
      state.quitRequested = true;
      onQuit();
      return;
    }

    // Search prompt is modal — capture all keys until Enter/Esc.
    if (_tc.searchPromptOpen) {
      _handleSearchKey(ke);
      return;
    }

    // Transcript cursor mode (vim, after Esc-out-of-input) — captures most keys.
    if (_tc.active) {
      _handleTranscriptCursorKey(ke);
      return;
    }

    if (_handleScroll(event)) return;

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

    // Esc on empty input in vim mode → enter transcript cursor mode.
    if (ke.code == KeyCode.escape &&
        state.config.editorMode == FrunEditorMode.vim &&
        _input.mode == VimMode.insert &&
        _input.text.isEmpty) {
      _enterTranscriptCursor();
      return;
    }

    if (ke.code == KeyCode.tab) {
      _cycleLink(forward: !ke.modifiers.contains(KeyMod.shift));
      return;
    }

    if (ke.code == KeyCode.enter &&
        _input.text.isEmpty &&
        _focusedLinkIndex >= 0) {
      unawaited(_openFocusedLink());
      return;
    }

    final action = _input.handle(event);
    if (action == InputAction.submit) {
      _submit();
    } else if (ke.code == KeyCode.rune) {
      _transcriptScroll = 0;
      _focusedLinkIndex = -1;
    }
  }

  bool _handleScroll(KeyMsg event) {
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

    final isVimNormal = state.config.editorMode == FrunEditorMode.vim &&
        _input.mode == VimMode.normal;
    if (!isVimNormal) {
      _pendingG = false;
      return false;
    }

    if (ke.code == KeyCode.rune && ke.modifiers.contains(KeyMod.ctrl)) {
      if (ke.text == 'u' || ke.text == 'U') {
        _scrollBy(pageHalf);
        _pendingG = false;
        return true;
      }
      if (ke.text == 'd' || ke.text == 'D') {
        _scrollBy(-pageHalf);
        _pendingG = false;
        return true;
      }
    }

    if (ke.code == KeyCode.rune && ke.modifiers.isEmpty) {
      final ch = ke.text;
      if (ch == 'k') {
        _scrollBy(1);
        _pendingG = false;
        return true;
      }
      if (ch == 'j') {
        _scrollBy(-1);
        _pendingG = false;
        return true;
      }
      if (ch == 'G') {
        _transcriptScroll = 1 << 30;
        _scrollBy(0);
        _pendingG = false;
        return true;
      }
      if (ch == 'g') {
        if (_pendingG) {
          _transcriptScroll = 0;
          _focusedLinkIndex = -1;
          _pendingG = false;
        } else {
          _pendingG = true;
        }
        return true;
      }
    }

    _pendingG = false;
    return false;
  }

  // ── Vim transcript-cursor mode ─────────────────────────────────────────

  void _enterTranscriptCursor() {
    if (_lastDisplayRows.isEmpty) return;
    final endRow = _lastVisibleEnd - 1;
    final startCursor = endRow.clamp(_lastVisibleStart, _lastVisibleEnd - 1);
    final col = (_lastDisplayRows[startCursor].text.length - 1).clamp(0, 1 << 30);
    _tc.enter(initialRow: startCursor, initialCol: col);
  }

  void _handleTranscriptCursorKey(TeaKey ke) {
    if (ke.code == KeyCode.escape) {
      _tc.exit();
      return;
    }
    if (ke.code == KeyCode.rune && ke.text == 'i') {
      _tc.exit();
      return;
    }

    final pageHalf = (_lastBodyHeight ~/ 2).clamp(2, 200);

    if (ke.code == KeyCode.rune && ke.modifiers.contains(KeyMod.ctrl)) {
      if (ke.text == 'u' || ke.text == 'U') {
        _moveCursor(rowDelta: -pageHalf);
        return;
      }
      if (ke.text == 'd' || ke.text == 'D') {
        _moveCursor(rowDelta: pageHalf);
        return;
      }
    }

    if (ke.code == KeyCode.left) {
      _moveCursor(colDelta: -1);
      return;
    }
    if (ke.code == KeyCode.right) {
      _moveCursor(colDelta: 1);
      return;
    }
    if (ke.code == KeyCode.up) {
      _moveCursor(rowDelta: -1);
      return;
    }
    if (ke.code == KeyCode.down) {
      _moveCursor(rowDelta: 1);
      return;
    }

    if (ke.code != KeyCode.rune || ke.modifiers.isNotEmpty) return;
    final ch = ke.text;

    switch (ch) {
      case 'h':
        _moveCursor(colDelta: -1);
      case 'l':
        _moveCursor(colDelta: 1);
      case 'k':
        _moveCursor(rowDelta: -1);
      case 'j':
        _moveCursor(rowDelta: 1);
      case 'w':
        _moveCursorWord(forward: true);
      case 'b':
        _moveCursorWord(forward: false);
      case '0':
        _tc.col = 0;
      case r'$':
        _tc.col = _rowLength(_tc.row) - 1;
        if (_tc.col < 0) _tc.col = 0;
      case 'G':
        _tc.row = _lastDisplayRows.length - 1;
        _tc.col = 0;
        _ensureCursorVisible();
      case 'g':
        if (_pendingG) {
          _tc.row = 0;
          _tc.col = 0;
          _transcriptScroll = _maxScroll();
          _pendingG = false;
        } else {
          _pendingG = true;
        }
        return;
      case 'v':
        _tc.toggleSelection();
      case 'y':
        unawaited(_yankSelectionOrLine());
      case '/':
        _tc.searchPromptOpen = true;
        _searchDraft = '';
      case 'n':
        _jumpToMatch(forward: true);
      case 'N':
        _jumpToMatch(forward: false);
    }
    _pendingG = false;
  }

  void _moveCursor({int rowDelta = 0, int colDelta = 0}) {
    if (rowDelta != 0) {
      final max = math.max(0, _lastDisplayRows.length - 1);
      _tc.row = (_tc.row + rowDelta).clamp(0, max).toInt();
      final len = _rowLength(_tc.row);
      if (_tc.col >= len) _tc.col = math.max(0, len - 1);
    }
    if (colDelta != 0) {
      final len = _rowLength(_tc.row);
      _tc.col = (_tc.col + colDelta).clamp(0, math.max(0, len - 1)).toInt();
    }
    _ensureCursorVisible();
  }

  void _moveCursorWord({required bool forward}) {
    if (_lastDisplayRows.isEmpty) return;
    final row = _lastDisplayRows[_tc.row].text;
    var c = _tc.col;
    final step = forward ? 1 : -1;
    bool isWord(int i) =>
        i >= 0 && i < row.length && RegExp(r'[A-Za-z0-9_]').hasMatch(row[i]);
    if (forward) {
      while (c < row.length && isWord(c)) {
        c++;
      }
      while (c < row.length && !isWord(c)) {
        c++;
      }
      if (c >= row.length && _tc.row < _lastDisplayRows.length - 1) {
        _tc.row++;
        _tc.col = 0;
        _ensureCursorVisible();
        return;
      }
    } else {
      if (c > 0) c += step;
      while (c > 0 && !isWord(c)) {
        c--;
      }
      while (c > 0 && isWord(c - 1)) {
        c--;
      }
      if (c == 0 && _tc.col == 0 && _tc.row > 0) {
        _tc.row--;
        _tc.col = math.max(0, _rowLength(_tc.row) - 1);
        _ensureCursorVisible();
        return;
      }
    }
    _tc.col = c.clamp(0, math.max(0, row.length - 1));
  }

  int _rowLength(int rowIndex) {
    if (rowIndex < 0 || rowIndex >= _lastDisplayRows.length) return 0;
    return _lastDisplayRows[rowIndex].text.length;
  }

  void _ensureCursorVisible() {
    if (_lastDisplayRows.isEmpty) return;
    final visibleRowCount = _lastBodyHeight;
    if (visibleRowCount <= 0) return;

    // Scroll value: 0 = tail; higher = older. Visible window is
    //   displayRows[total - scroll - visibleRowCount .. total - scroll]
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

  Future<void> _yankSelectionOrLine() async {
    final range = _tc.selectionRange();
    String text;
    if (range != null) {
      text = _textBetween(range.row, range.col, range.row2, range.col2);
    } else {
      text = _lastDisplayRows.isEmpty
          ? ''
          : _lastDisplayRows[_tc.row].text;
    }
    if (text.isEmpty) return;
    final ok = await copyToClipboard(text);
    if (ok) {
      state.transcript.success('Copied ${text.length} chars to clipboard.');
    } else {
      state.transcript.warn(
        'Clipboard unavailable — install pbcopy / xclip / wl-copy.',
      );
    }
    _tc.anchorRow = null;
    _tc.anchorCol = null;
  }

  String _textBetween(int r1, int c1, int r2, int c2) {
    if (_lastDisplayRows.isEmpty) return '';
    final buf = StringBuffer();
    for (var r = r1; r <= r2 && r < _lastDisplayRows.length; r++) {
      final row = _lastDisplayRows[r].text;
      final start = r == r1 ? c1 : 0;
      final end = r == r2 ? math.min(c2 + 1, row.length) : row.length;
      if (end > start) buf.write(row.substring(start, end));
      if (r != r2) buf.write('\n');
    }
    return buf.toString();
  }

  void _handleSearchKey(TeaKey ke) {
    switch (ke.code) {
      case KeyCode.escape:
        _tc.searchPromptOpen = false;
        _searchDraft = '';
        return;
      case KeyCode.enter:
        _tc.searchPromptOpen = false;
        _tc.searchQuery = _searchDraft;
        _recomputeMatches();
        if (_tc.matches.isNotEmpty) {
          _tc.activeMatchIndex = 0;
          _jumpToActiveMatch();
        } else if (_tc.searchQuery.isNotEmpty) {
          state.transcript.system('No matches for "${_tc.searchQuery}".');
        }
        return;
      case KeyCode.backspace:
        if (_searchDraft.isNotEmpty) {
          _searchDraft = _searchDraft.substring(0, _searchDraft.length - 1);
        }
        return;
      case KeyCode.space:
        _searchDraft += ' ';
        return;
      case KeyCode.rune:
        if (ke.modifiers.isEmpty || ke.modifiers.containsOnly(KeyMod.shift)) {
          _searchDraft += ke.text;
        }
        return;
      default:
        return;
    }
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

  void _jumpToMatch({required bool forward}) {
    if (_tc.matches.isEmpty) return;
    if (_tc.activeMatchIndex < 0) {
      _tc.activeMatchIndex = forward ? 0 : _tc.matches.length - 1;
    } else {
      _tc.activeMatchIndex = forward
          ? (_tc.activeMatchIndex + 1) % _tc.matches.length
          : (_tc.activeMatchIndex - 1 + _tc.matches.length) %
              _tc.matches.length;
    }
    _jumpToActiveMatch();
  }

  void _jumpToActiveMatch() {
    if (_tc.activeMatchIndex < 0 ||
        _tc.activeMatchIndex >= _tc.matches.length) {
      return;
    }
    final m = _tc.matches[_tc.activeMatchIndex];
    _tc.row = m.row;
    _tc.col = m.col;
    _ensureCursorVisible();
  }

  // ── Mouse handling ─────────────────────────────────────────────────────

  void _onMouseClick(Mouse mouse) {
    final msg = _hits.hit(mouse.x, mouse.y);
    if (msg == null) return;
    // Re-enter the reducer so the resolved domain Msg gets processed by
    // the same switch above (state mutations + side effects).
    update(msg);
  }

  void _onMouseWheel(Mouse mouse) {
    // Only react when the wheel happens over the transcript body. Outside →
    // ignored so wheel scroll near tabs/input doesn't accidentally scroll.
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
    _pendingG = false;
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

    if (!line.startsWith('/')) {
      state.transcript.warn('Commands start with "/". Try /help.');
      return;
    }

    final parts = line.substring(1).split(RegExp(r'\s+'));
    final name = parts.first;
    final args = parts.length > 1 ? parts.sublist(1) : const <String>[];
    final command = registry.lookup(name);
    if (command == null) {
      state.transcript.error('Unknown command: /$name');
      return;
    }
    state.transcript.system('> $line');
    command.run(args, state).then(_handleResult).catchError((Object e, _) {
      state.transcript.error('Command /$name failed: $e');
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

    const inputH = 1;
    const footerH = 1;
    final infoBarH = _computeInfoBarHeight(w);
    final statusH = state.showStatusPanel ? _statusHeight(h, infoBarH) : 0;
    final bodyH = h - inputH - footerH - statusH - infoBarH;
    _lastBodyHeight = bodyH;
    _lastBodyY = 0;

    final canvas = Canvas(w, h);

    _paintTranscript(canvas, theme, w, 0, bodyH);
    if (state.showStatusPanel) {
      _paintStatus(canvas, theme, w, bodyH, statusH);
    }
    _paintInfoBar(canvas, theme, w, h - footerH - inputH - infoBarH, infoBarH);
    _paintInput(canvas, theme, w, h - footerH - inputH);
    _paintFooter(canvas, theme, w, h - footerH);

    final inputCursor = _input.isInserting && !_tc.active && !_tc.searchPromptOpen
        ? _inputCursorPosition(w, h - footerH - inputH)
        : null;

    return View(
      content: canvas.render(),
      altScreen: true,
      mouseMode: MouseMode.allMotion,
      cursor: inputCursor,
    );
  }

  int _statusHeight(int totalHeight, int infoBarH) {
    const desired = 5;
    final available = totalHeight - 3 - infoBarH;
    return desired.clamp(0, available.clamp(0, desired));
  }

  Cursor? _inputCursorPosition(int width, int inputY) {
    final prompt = _input.isInserting ? '> ' : '· ';
    final usable = width - prompt.length;
    var cursorOffset = _input.cursor;
    final visibleLen = _input.text.length;
    if (visibleLen > usable) {
      final start = (cursorOffset - usable + 1).clamp(0, visibleLen);
      cursorOffset -= start;
    }
    final cursorX = prompt.length + cursorOffset;
    if (cursorX >= width) return null;
    return Cursor(x: cursorX, y: inputY, shape: CursorShape.bar);
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
    final lines = state.visibleTranscript.lines;
    final displayRows = _layoutDisplayRows(lines, width);
    _lastDisplayRows = displayRows;

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

    final focused =
        _focusedLinkIndex < 0 ? null : _visibleLinks[_focusedLinkIndex];

    for (var r = start; r < endExclusive && r < displayRows.length; r++) {
      final row = displayRows[r];
      final line = lines[row.lineIndex];
      final yRow = y + (r - start);
      final baseStyle = theme.forLevel(line.level);
      canvas.paint(0, yRow, baseStyle.render(row.text));

      // Link highlight.
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
        final style =
            isActive ? theme.searchActiveStyle : theme.searchMatchStyle;
        final text = row.text.substring(m.col, m.col + m.length);
        canvas.paint(m.col, yRow, style.render(text), zIndex: 2);
      }

      // Selection overlay.
      final range = _tc.selectionRange();
      if (range != null && r >= range.row && r <= range.row2) {
        final lineStart = r == range.row ? range.col : 0;
        final lineEnd =
            r == range.row2 ? math.min(range.col2 + 1, row.text.length) : row.text.length;
        if (lineEnd > lineStart) {
          final sel = row.text.substring(lineStart, lineEnd);
          canvas.paint(
              lineStart, yRow, theme.selectionStyle.render(sel),
              zIndex: 3);
        }
      }

      // Vim cursor cell.
      if (_tc.active && r == _tc.row) {
        final cell = (_tc.col < row.text.length) ? row.text[_tc.col] : ' ';
        canvas.paint(_tc.col, yRow, theme.cursorStyle.render(cell), zIndex: 4);
      }
    }

    // Register the transcript body as the wheel-scrollable region.
    _hits.add(
      x: 0,
      y: y,
      w: width,
      h: height,
      msg: const TickWakeMsg(), // sentinel — clicks here do nothing, just blocks tab clicks
    );
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
  static const String _runLabel = '[+ Run]';

  String _rightInfoText() {
    final tabCount = state.runController.tabs.length;
    final tabsSegment = tabCount > 0 ? '  tabs:$tabCount' : '';
    return ' ${state.project.name}  '
        'dev:${state.selectedDeviceId ?? "—"}  '
        'ide:${state.config.ide.id}$tabsSegment ';
  }

  /// Plan how many info-bar rows are needed. Right-side info is always on
  /// the bottom row; tab segments wrap from the top, each row up to
  /// [width] - rightInfo - separator.
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
    // Tabs on every row share the same available width — keeps layout
    // predictable when terminal resizes mid-session.
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

      // Trailing chips + [+ Run] go on the LAST row only.
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
    // Hard cap so one verbose label can't starve the rest of the strip.
    final maxLabelChars = isActive ? 32 : 18;
    final shortLabel = t.label.length > maxLabelChars
        ? '${t.label.substring(0, maxLabelChars - 1)}…'
        : t.label;
    final marker = t.isRunning ? '' : ' x';
    final label = ' ${tabIndex + 1}: $shortLabel$marker ';

    // Buttons: ASCII-only so terminals never widen them to 2 cells. Each is
    // 3 cells (` X `) for trackpad-friendly hit targets.
    //   r = hot reload, R = hot restart, S = stop
    final wantsButtons = isActive && t.isRunning;
    final allButtons = wantsButtons ? activeButtons : <_Button>[];

    final remaining = stripWidth - x;
    if (remaining < 5) return x; // need at least `[ X ]`

    var displayLabel = label;
    var labelWidth = label.length;
    var buttons = allButtons;
    final reservedForButtons = buttons.length * 3;

    // Try to fit label + buttons + brackets. If not, drop buttons. If still
    // not, truncate label with `…`.
    if (1 + labelWidth + reservedForButtons + 1 > remaining) {
      buttons = const <_Button>[];
      if (1 + labelWidth + 1 > remaining) {
        // Truncate label. Need room for `[ … ]` minimum.
        final maxLabel = remaining - 2; // brackets
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

  void _paintInput(Canvas canvas, FrunTheme theme, int width, int y) {
    if (_tc.searchPromptOpen) {
      const prefix = '/';
      canvas.paint(0, y, theme.accentStyle.render(prefix));
      final usable = width - prefix.length;
      var visible = _searchDraft;
      if (visible.length > usable) {
        visible = visible.substring(visible.length - usable);
      }
      canvas.paint(prefix.length, y, visible);
      return;
    }

    final prompt = _input.isInserting ? '> ' : '· ';
    final usable = width - prompt.length;
    var visible = _input.text;
    var cursorOffset = _input.cursor;
    if (visible.length > usable) {
      final start = (cursorOffset - usable + 1).clamp(0, visible.length);
      visible = visible.substring(start);
      cursorOffset -= start;
    }
    canvas.paint(0, y, theme.promptStyle.render(prompt));
    final clipped = visible.length > usable ? visible.substring(0, usable) : visible;
    canvas.paint(prompt.length, y, clipped);

    // Software cursor for vim normal mode (no hardware cursor in non-insert).
    if (!_input.isInserting) {
      final cx = prompt.length + cursorOffset;
      if (cx < width) {
        final ch = cursorOffset < visible.length ? visible[cursorOffset] : ' ';
        canvas.paint(cx, y, theme.cursorStyle.render(ch), zIndex: 2);
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
    if (_tc.searchPromptOpen) {
      left = 'search: enter run · esc cancel';
    } else if (_tc.active) {
      final matchInfo = _tc.matches.isEmpty
          ? ''
          : ' · match ${_tc.activeMatchIndex + 1}/${_tc.matches.length}';
      left =
          'cursor mode · hjkl move · v select · y yank · / search · n/N next$matchInfo · esc exit';
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
        ? 'vim:${_input.mode.name}${_tc.active ? "/cursor" : ""}'
        : 'normal';
    final right = '$modeLabel mode';

    final bar = ' ' * width;
    canvas.paint(0, y, theme.statusBarStyle.render(bar));
    final leftClipped =
        left.length > width - right.length - 2 ? left.substring(0, width - right.length - 2) : left;
    canvas.paint(0, y, theme.statusBarStyle.render(leftClipped));
    canvas.paint(
        width - right.length, y, theme.statusBarStyle.render(right));
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

extension _ModSetExt on Set<KeyMod> {
  bool containsOnly(KeyMod m) => length == 1 && contains(m);
}
