import 'dart:math' as math;

import 'package:utopia_tui/utopia_tui.dart';

import '../app/app_state.dart';
import '../app/commands/command.dart';
import '../app/commands/command_registry.dart';
import '../app/link_extractor.dart';
import '../app/transcript.dart';
import '../config/config.dart';
import '../ide/source_location.dart';
import '../version.dart';
import 'input_controller.dart';
import 'theme.dart';

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

/// One icon-button in the top bar. [activeWhenRunning] is true for actions
/// that only make sense while an app is live (reload/restart/stop). [onPress]
/// is the bound action — called when keyboard or (future) mouse triggers it.
class _IconButton {
  _IconButton({
    required this.label,
    required this.onPress,
    this.activeWhenRunning = false,
  });

  final String label;
  final bool activeWhenRunning;
  final void Function() onPress;

  // x range filled in during paint so a future mouse layer can hit-test it.
  int xStart = 0;
  int xEnd = 0;
}

/// Top-level TUI:
///   row 0:       icon bar (run / reload / restart / stop) + right-side info
///   1..bodyH-1:  transcript (full width, borderless)
///   bottom:      optional status block (toggled by /status)
///   penultimate: input prompt
///   last:        footer / hints
class FrunApp extends TuiApp {
  FrunApp({required this.state, required this.registry, required this.onQuit})
    : _input = InputController(editorMode: state.config.editorMode) {
    _buildIcons();
  }

  final AppState state;
  final CommandRegistry registry;
  final void Function() onQuit;

  final InputController _input;
  int _transcriptScroll = 0; // 0 = follow tail; higher = older lines visible
  int _focusedLinkIndex = -1;
  bool _pendingG = false; // vim 'gg' first-keystroke flag

  late final List<_IconButton> _icons;

  // Recomputed each build so onEvent can reuse it.
  List<_VisibleLink> _visibleLinks = const <_VisibleLink>[];
  int _lastBodyHeight = 10;

  void _buildIcons() {
    _icons = <_IconButton>[
      _IconButton(label: '▶ run', onPress: () => _runCmd('run', const [])),
      _IconButton(
        label: '↻ reload',
        activeWhenRunning: true,
        onPress: () => _runCmd('reload', const []),
      ),
      _IconButton(
        label: '⟲ restart',
        activeWhenRunning: true,
        onPress: () => _runCmd('restart', const []),
      ),
      _IconButton(
        label: '■ stop',
        activeWhenRunning: true,
        onPress: () => _runCmd('stop', const []),
      ),
    ];
  }

  void _runCmd(String name, List<String> args) {
    final command = registry.lookup(name);
    if (command == null) {
      state.transcript.error('Unknown command: /$name');
      return;
    }
    state.transcript.system('> /$name');
    command.run(args, state).then(_handleResult).catchError((Object e, _) {
      state.transcript.error('Command /$name failed: $e');
    });
  }

  @override
  void init(TuiContext context) {
    state.transcript.system('frun $frunVersion — type /help for commands.');
    state.transcript.info('Project: ${state.project.name} (${state.project.root})');
    if (state.project.hasVsCodeFolder) {
      state.transcript.info('Detected .vscode/ → launch configs available via /run.');
    }
  }

  @override
  Duration? get tickInterval => const Duration(milliseconds: 250);

  @override
  void onEvent(TuiEvent event, TuiContext context) {
    if (event is! TuiKeyEvent) return;
    if (state.quitRequested) return;

    if (_input.editorMode != state.config.editorMode) {
      _input.editorMode = state.config.editorMode;
    }

    if (_handleScroll(event)) return;

    if (event.code == TuiKeyCode.tab) {
      _cycleLink(forward: true);
      return;
    }

    if (event.code == TuiKeyCode.enter &&
        _input.text.isEmpty &&
        _focusedLinkIndex >= 0) {
      _openFocusedLink();
      return;
    }

    final action = _input.handle(event);
    if (action == InputAction.submit) {
      _submit();
    } else if (event.code == TuiKeyCode.printable) {
      _transcriptScroll = 0;
      _focusedLinkIndex = -1;
      // After every printable, see if a modifier-arrow tail just landed.
      _maybeConsumeModifierArrow();
    }
  }

  /// Detects `ESC [ 1 ; <mod> <ABCD>` sequences (Ctrl+Arrow, Ctrl+Shift+Arrow,
  /// Shift+Arrow). utopia_tui's parser eats `ESC [ 1` then emits the remaining
  /// bytes as three printable chars (`;`, `<mod>`, `<letter>`), which we
  /// detect as a trailing suffix on the input and roll back.
  void _maybeConsumeModifierArrow() {
    final text = _input.text;
    if (text.length < 3) return;
    final suffix = text.substring(text.length - 3);
    if (suffix[0] != ';') return;
    final mod = suffix[1];
    final dir = suffix[2];
    if (!_isModDigit(mod)) return;
    if (dir != 'A' && dir != 'B') return; // C/D are right/left, unused
    _input.removeLast(3);

    final pageBig = (_lastBodyHeight - 2).clamp(3, 200);
    final pageHalf = (pageBig ~/ 2).clamp(2, 200);
    final hasCtrlShift = mod == '6' || mod == '8';
    final hasCtrl = mod == '5' || mod == '7' || hasCtrlShift;
    final hasShift =
        mod == '2' || mod == '4' || mod == '6' || mod == '8' && !hasCtrlShift;

    int lines;
    if (hasCtrlShift) {
      lines = pageBig;
    } else if (hasCtrl) {
      lines = pageHalf;
    } else if (hasShift) {
      lines = 5;
    } else {
      lines = 1;
    }
    _scrollBy(dir == 'A' ? lines : -lines);
  }

  static bool _isModDigit(String s) {
    if (s.length != 1) return false;
    final c = s.codeUnitAt(0);
    return c >= 0x32 && c <= 0x39; // '2'..'9' (mod 2..8 are the real values)
  }

  /// Returns true if the key was consumed as a scroll command.
  bool _handleScroll(TuiKeyEvent event) {
    final pageBig = (_lastBodyHeight - 2).clamp(3, 200);
    final pageHalf = (pageBig ~/ 2).clamp(2, 200);

    switch (event.code) {
      case TuiKeyCode.arrowUp:
        _scrollBy(1);
        return true;
      case TuiKeyCode.arrowDown:
        _scrollBy(-1);
        return true;
      case TuiKeyCode.pageUp:
        _scrollBy(pageBig);
        return true;
      case TuiKeyCode.pageDown:
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

    switch (event.code) {
      case TuiKeyCode.ctrlU:
        _scrollBy(pageHalf);
        _pendingG = false;
        return true;
      case TuiKeyCode.ctrlD:
        _scrollBy(-pageHalf);
        _pendingG = false;
        return true;
      case TuiKeyCode.printable:
        final ch = event.char;
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
        _pendingG = false;
        return false;
      default:
        _pendingG = false;
        return false;
    }
  }

  void _scrollBy(int lines) {
    // The exact maxScroll depends on the wrapped row count, which the
    // renderer clamps again. Use a generous upper bound here so wrapping
    // doesn't cap scrolling artificially when many lines have wrapped.
    _transcriptScroll = (_transcriptScroll + lines).clamp(0, 1 << 30);
    _focusedLinkIndex = -1;
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
      _focusedLinkIndex =
          (_focusedLinkIndex + delta) % _visibleLinks.length;
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

  // ----- rendering --------------------------------------------------------

  @override
  void build(TuiContext context) {
    final w = context.width;
    final h = context.height;
    final theme = FrunTheme.fromConfig(state.config);

    if (w < 40 || h < 10) {
      context.surface.putText(0, 0, 'frun: terminal too small (${w}x$h)');
      return;
    }

    const iconBarH = 1;
    const inputH = 1;
    const footerH = 1;
    final statusH = state.showStatusPanel ? _statusHeight(h) : 0;
    final bodyH = h - iconBarH - inputH - footerH - statusH;
    _lastBodyHeight = bodyH;

    _paintIconBar(context, theme, w);
    _paintTranscript(context, theme, w, iconBarH, bodyH);
    if (state.showStatusPanel) {
      _paintStatus(context, theme, w, iconBarH + bodyH, statusH);
    }
    _paintInput(context, theme, w, h - footerH - inputH);
    _paintFooter(context, theme, w, h - footerH);
  }

  int _statusHeight(int totalHeight) {
    // 1 separator + 4 lines of stats — enough room for the essentials.
    const desired = 5;
    final available = totalHeight - 4; // leave room for icon bar / input / footer / 1+ transcript
    return desired.clamp(0, available.clamp(0, desired));
  }

  void _paintIconBar(TuiContext ctx, FrunTheme theme, int width) {
    final surface = ctx.surface;
    surface.clearRect(0, 0, width, 1);
    final running = state.runController.isRunning;

    var x = 0;
    for (final ic in _icons) {
      if (x + ic.label.length + 4 > width) break;
      final enabled = !ic.activeWhenRunning || running;
      final btn = ' ${ic.label} ';
      final btnStyle = enabled
          ? const TuiStyle(bg: 24, fg: 230, bold: true)
          : const TuiStyle(bg: 235, fg: 244);
      surface.putText(x, 0, '[', style: theme.dimStyle);
      surface.putText(x + 1, 0, btn, style: btnStyle);
      surface.putText(x + 1 + btn.length, 0, ']', style: theme.dimStyle);
      ic.xStart = x;
      ic.xEnd = x + 1 + btn.length + 1; // inclusive of right ]
      x += 1 + btn.length + 1 + 1; // brackets + label + 1 gap
    }

    final right = ' ${state.project.name}  '
        'dev:${state.selectedDeviceId ?? "—"}  '
        'ide:${state.config.ide.id} ';
    if (right.length + x + 1 < width) {
      surface.putText(width - right.length, 0, right, style: theme.dimStyle);
    }
  }

  void _paintTranscript(
    TuiContext ctx,
    FrunTheme theme,
    int width,
    int y,
    int height,
  ) {
    if (height <= 0 || width <= 0) return;
    final lines = state.transcript.lines;
    final displayRows = _layoutDisplayRows(lines, width);

    final visibleCount = height;
    final maxScroll =
        (displayRows.length - visibleCount).clamp(0, 1 << 30);
    if (_transcriptScroll > maxScroll) _transcriptScroll = maxScroll;
    final tail = _transcriptScroll;
    final endExclusive = displayRows.length - tail;
    final start = (endExclusive - visibleCount).clamp(0, displayRows.length);

    _visibleLinks = _collectVisibleLinks(lines, displayRows, start, endExclusive);
    if (_focusedLinkIndex >= _visibleLinks.length) {
      _focusedLinkIndex = _visibleLinks.isEmpty ? -1 : _visibleLinks.length - 1;
    }

    ctx.surface.clearRect(0, y, width, height);
    final focused = _focusedLinkIndex < 0 ? null : _visibleLinks[_focusedLinkIndex];

    for (var r = start; r < endExclusive && r < displayRows.length; r++) {
      final row = displayRows[r];
      final line = lines[row.lineIndex];
      final yRow = y + (r - start);
      ctx.surface.putTextClip(
        0,
        yRow,
        row.text,
        width,
        style: theme.forLevel(line.level),
      );

      if (focused != null && focused.transcriptLineIndex == row.lineIndex) {
        final link = focused.link;
        final rowStart = row.startCol;
        final rowEnd = rowStart + row.text.length;
        final overlapStart = math.max(link.start, rowStart);
        final overlapEnd = math.min(link.end, rowEnd);
        if (overlapEnd > overlapStart) {
          final substring = line.text.substring(overlapStart, overlapEnd);
          ctx.surface.putText(
            overlapStart - rowStart,
            yRow,
            substring,
            style: const TuiStyle(bold: true, bg: 240, fg: 226),
          );
        }
      }
    }
  }

  /// Soft-wraps every transcript line into one or more [_DisplayRow]s at the
  /// current panel [width]. Empty lines become a single empty row so blank
  /// lines stay visible.
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
    TuiContext ctx,
    FrunTheme theme,
    int width,
    int y,
    int height,
  ) {
    if (height <= 0) return;
    final surface = ctx.surface;
    surface.clearRect(0, y, width, height);

    // Separator line at the top of the status block.
    final sep = '─' * width;
    surface.putText(0, y, sep, style: theme.borderStyle);

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
      surface.putText(0, y + 1 + i, '$label:'.padRight(12),
          style: theme.titleStyle);
      surface.putTextClip(12, y + 1 + i, value, width - 12);
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

  void _paintInput(TuiContext ctx, FrunTheme theme, int width, int y) {
    final prompt = _input.isInserting ? '> ' : '· ';
    final usable = width - prompt.length;
    var visible = _input.text;
    var cursorOffset = _input.cursor;
    if (visible.length > usable) {
      final start = (cursorOffset - usable + 1).clamp(0, visible.length);
      visible = visible.substring(start);
      cursorOffset -= start;
    }
    ctx.surface.clearRect(0, y, width, 1);
    ctx.surface.putText(0, y, prompt, style: theme.promptStyle);
    ctx.surface.putTextClip(prompt.length, y, visible, usable);
    final cursorX = prompt.length + cursorOffset;
    if (cursorX < width) {
      final ch = (cursorOffset < visible.length) ? visible[cursorOffset] : ' ';
      ctx.surface.putText(
        cursorX,
        y,
        ch,
        style: const TuiStyle(bg: 244, fg: 16),
      );
    }
  }

  void _paintFooter(TuiContext ctx, FrunTheme theme, int width, int y) {
    final inputText = _input.text;
    final suggestions = inputText.startsWith('/')
        ? registry
              .suggestions(inputText.substring(1).split(' ').first)
              .take(6)
              .map((c) => '/${c.name}')
              .join('  ')
        : '';

    final String left;
    if (suggestions.isNotEmpty) {
      left = 'suggest: $suggestions';
    } else if (_visibleLinks.isNotEmpty) {
      left = _focusedLinkIndex >= 0
          ? 'link ${_focusedLinkIndex + 1}/${_visibleLinks.length}: enter open · tab cycle'
          : 'tab: focus link (${_visibleLinks.length}) · ↑↓ scroll · ^↑↓ half · ^⇧↑↓ page';
    } else {
      left = '↑↓ scroll · ^↑↓ half · ^⇧↑↓ page · /status · ctrl-c quit';
    }
    final modeLabel = state.config.editorMode == FrunEditorMode.vim
        ? 'vim:${_input.mode.name}'
        : 'normal';
    final right = '$modeLabel mode';
    TuiStatusBar(
      style: theme.statusBarStyle,
      left: left,
      right: right,
    ).paintSurface(ctx.surface, TuiRect(x: 0, y: y, width: width, height: 1));
  }
}
