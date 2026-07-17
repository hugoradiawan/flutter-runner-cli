import 'package:dart_tui/dart_tui.dart';

import 'ex_parser.dart';
import 'motions.dart';
import 'operators.dart';
import 'text_objects.dart';
import 'vim_buffer.dart';
import 'vim_mode.dart';
import 'vim_state.dart';

/// Outcome of feeding a key to the engine.
enum KeyResult {
  /// The engine consumed the key — caller should not act further.
  consumed,

  /// Engine declined; caller should pass the key to the buffer's insert handler.
  passInsert,
}

typedef ViewportProvider = ({int top, int height}) Function(VimBuffer);
typedef ExCmdRunner = void Function(ExCommand cmd, VimBuffer buffer);
typedef SearchRunner =
    void Function(String pattern, bool forward, VimBuffer buffer);
typedef SubmitHandler = void Function();
typedef TabSwitcher = void Function(int? tabNumber, {required bool forward});
typedef ScrollRequester =
    void Function(VimScrollRequest request, VimBuffer buffer);
typedef MacroPlayer = void Function(List<TeaKey> keys);

/// Viewport request emitted by zz/zt/zb and Ctrl-E/Ctrl-Y. The engine has no
/// scroll offset of its own — the host owns the viewport and interprets this.
enum VimScrollKind { center, top, bottom, lines }

class VimScrollRequest {
  const VimScrollRequest(this.kind, [this.lines = 0]);
  final VimScrollKind kind;

  /// For [VimScrollKind.lines]: positive scrolls the view down (Ctrl-E),
  /// negative up (Ctrl-Y).
  final int lines;
}

/// `\d` on a single-char key without constructing a RegExp per keystroke.
bool _isDigit(String ch) =>
    ch.length == 1 && ch.codeUnitAt(0) >= 0x30 && ch.codeUnitAt(0) <= 0x39;

/// The single source of vim truth. Handles normal, visual (all three),
/// op-pending, replace, ex, search. Insert-mode typing flows through to the
/// buffer; the engine intercepts only special keys (Esc, Ctrl-{h,w,r,o},
/// etc.).
class VimEngine {
  VimEngine({
    required VimState state,
    required ViewportProvider viewport,
    required ExCmdRunner runExCmd,
    required SearchRunner runSearch,
    SubmitHandler? onSubmit,
    TabSwitcher? onTabSwitch,
    ScrollRequester? onScroll,
    MacroPlayer? onPlayMacro,
  }) : _state = state,
       _viewport = viewport,
       _runExCmd = runExCmd,
       _runSearch = runSearch,
       _onSubmit = onSubmit,
       _onTabSwitch = onTabSwitch,
       _onScroll = onScroll,
       _onPlayMacro = onPlayMacro;

  final VimState _state;
  final ViewportProvider _viewport;
  final ExCmdRunner _runExCmd;
  final SearchRunner _runSearch;
  final SubmitHandler? _onSubmit;
  final TabSwitcher? _onTabSwitch;
  final ScrollRequester? _onScroll;
  final MacroPlayer? _onPlayMacro;

  VimState get state => _state;

  KeyResult handle(KeyMsg event, VimBuffer buffer) {
    final ke = event.keyEvent;

    // Record every key the engine sees while a macro is being recorded.
    // Macro-control keys (`q` stop, register names) un-record themselves.
    if (event is KeyPressMsg) _state.macros.append(ke);

    // Ex-mode: collect chars into exDraft until Enter/Esc.
    if (_state.mode == VimMode.exCmd) {
      _handleExKey(ke, buffer);
      return KeyResult.consumed;
    }
    // Search-mode: same as ex but submits to SearchRunner.
    if (_state.mode == VimMode.search) {
      _handleSearchKey(ke, buffer);
      return KeyResult.consumed;
    }

    // Insert mode: engine handles only Esc and a few Ctrl bindings; rest
    // passes through to the buffer.
    if (_state.mode == VimMode.insert) {
      if (ke.code == KeyCode.escape) {
        _enterNormal(buffer);
        return KeyResult.consumed;
      }
      if (ke.code == KeyCode.rune && ke.modifiers.contains(KeyMod.ctrl)) {
        final t = ke.text;
        if (t == 'c' || t == 'C') {
          _enterNormal(buffer);
          return KeyResult.consumed;
        }
        if (t == 'r' || t == 'R') {
          // Ctrl-R{reg} pastes register — defer the next char.
          _state.pendingMarkOp = 'ctrl-r';
          return KeyResult.consumed;
        }
      }
      if (_state.pendingMarkOp == 'ctrl-r' && ke.code == KeyCode.rune) {
        final entry = _state.registers.read(ke.text);
        if (!entry.isEmpty) buffer.insertAt(buffer.cursor, entry.text);
        _state.pendingMarkOp = '';
        return KeyResult.consumed;
      }
      if (ke.code == KeyCode.enter && buffer.tryCommandSubmit()) {
        _onSubmit?.call();
        return KeyResult.consumed;
      }
      return KeyResult.passInsert;
    }

    // Replace mode: typed chars overwrite, backspace restores, Esc exits.
    if (_state.mode == VimMode.replace) {
      if (ke.code == KeyCode.escape) {
        _enterNormal(buffer);
        return KeyResult.consumed;
      }
      if (ke.code == KeyCode.backspace) {
        if (_state.replaceStack.isNotEmpty) {
          final (pos, old) = _state.replaceStack.removeLast();
          final r = Range(pos, pos, RangeKind.charwise);
          buffer.replaceRange(r, old ?? '', RangeKind.charwise);
          buffer.cursor = pos;
          final cap = _state.replaceCapture;
          if (cap != null && cap.length > 0) {
            final s = cap.toString();
            _state.replaceCapture = StringBuffer(s.substring(0, s.length - 1));
          }
        } else if (buffer.cursor.col > 0) {
          // Past the session start vim just moves left.
          buffer.cursor = Pos(buffer.cursor.row, buffer.cursor.col - 1);
        }
        return KeyResult.consumed;
      }
      if (ke.code == KeyCode.space) {
        _replaceTypedChar(buffer, ' ');
        return KeyResult.consumed;
      }
      if (ke.code == KeyCode.rune && ke.modifiers.isEmpty) {
        _replaceTypedChar(buffer, ke.text);
        return KeyResult.consumed;
      }
      return KeyResult.consumed;
    }

    // Normal + visual modes share the parse loop.
    _handleNormalOrVisual(ke, buffer);
    return KeyResult.consumed;
  }

  // ── Mode transitions ─────────────────────────────────────────────────────

  void _enterNormal(VimBuffer buffer) {
    // Finalize an in-progress insert session for dot-repeat.
    if (_state.mode == VimMode.insert && _state.insertEntry != null) {
      final captured = _state.insertCapture?.toString() ?? '';
      final a = _state.lastAction;
      final block = _state.pendingBlockInsert;
      final isChangeOp =
          _state.insertEntry == 'c' &&
          a.operator == 'c' &&
          (a.kind == LastActionKind.operatorMotion ||
              a.kind == LastActionKind.operatorTextObject ||
              a.kind == LastActionKind.operatorDouble);
      if (block != null) {
        // Visual-block I/A: replicate the typed text onto the other block
        // rows. Only single-line captures replicate (vim behavior); `I`
        // skips rows shorter than the insert column, `A` pads them.
        _state.pendingBlockInsert = null;
        if (captured.isNotEmpty && !captured.contains('\n')) {
          for (
            var r = block.startRow + 1;
            r <= block.endRow && r < buffer.lineCount;
            r++
          ) {
            final len = buffer.rowLength(r);
            if (len < block.col) {
              if (!block.append) continue;
              buffer.insertAt(Pos(r, len), ' ' * (block.col - len));
            }
            buffer.insertAt(Pos(r, block.col), captured);
          }
        }
        a.clear();
      } else if (isChangeOp) {
        // `c{motion}` recorded the operator part when it ran; merge the
        // typed text so `.` replays delete + insert together.
        a.insertText = captured;
      } else {
        a
          ..clear()
          ..kind = LastActionKind.insertSession
          ..insertEntry = _state.insertEntry!
          ..insertText = captured
          ..count = 1;
      }
    }

    // Finalize a Replace-mode session: `{count}R` replays the overwrite
    // count-1 more times, and the capture becomes the dot-repeat payload.
    if (_state.mode == VimMode.replace) {
      final captured = _state.replaceCapture?.toString() ?? '';
      final n = _state.replaceSessionCount;
      if (captured.isNotEmpty && n > 1 && !captured.contains('\n')) {
        for (var i = 1; i < n; i++) {
          for (final ch in captured.split('')) {
            _overwriteChar(buffer, ch);
          }
        }
      }
      if (captured.isNotEmpty) {
        _state.lastAction
          ..clear()
          ..kind = LastActionKind.insertSession
          ..insertEntry = 'R'
          ..insertText = captured
          ..count = n;
      }
      _state.replaceCapture = null;
      _state.replaceStack.clear();
      _state.replaceSessionCount = 1;
    }
    _state.insertEntry = null;
    _state.insertCapture = null;
    buffer.exitInsertMode();
    final c = buffer.cursor;
    final len = buffer.rowLength(c.row);
    if (len > 0 && c.col >= len) {
      buffer.cursor = Pos(c.row, len - 1);
    } else if (c.col > 0 &&
        (_state.mode == VimMode.insert || _state.mode == VimMode.replace)) {
      buffer.cursor = Pos(c.row, c.col - 1);
    }
    _state.mode = VimMode.normal;
    _state.visualAnchor = null;
    buffer.selection = null;
    buffer.visualKind = VimMode.normal;
    _state.clearPending();
    buffer.onModeChanged(VimMode.normal);
  }

  /// [pushUndo] controls whether a snapshot is captured. Pass false when the
  /// caller already pushed before its own mutation (e.g. `o`, `c{motion}`).
  void _enterInsert(VimBuffer buffer, {String? entry, bool pushUndo = true}) {
    if (!buffer.isEditable) {
      // Read-only buffer (transcript cursor): `i` exits the cursor and
      // refocuses the editable input prompt. enterInsertMode() pops the
      // surface; the active-buffer computation in the host picks input
      // on the next tick.
      buffer.enterInsertMode();
      _state.mode = VimMode.insert;
      _state.visualAnchor = null;
      buffer.selection = null;
      buffer.visualKind = VimMode.normal;
      buffer.onModeChanged(VimMode.insert);
      return;
    }
    if (pushUndo && _state.mode != VimMode.insert) buffer.pushUndo();
    _state.mode = VimMode.insert;
    _state.visualAnchor = null;
    buffer.selection = null;
    buffer.visualKind = VimMode.normal;
    if (entry != null) {
      _state.insertEntry = entry;
      _state.insertCapture = StringBuffer();
    }
    buffer.enterInsertMode();
    buffer.onModeChanged(VimMode.insert);
  }

  void _enterVisual(VimBuffer buffer, VimMode kind) {
    if (kind != VimMode.visualChar &&
        kind != VimMode.visualLine &&
        kind != VimMode.visualBlock) {
      return;
    }
    _state.mode = kind;
    _state.visualAnchor = buffer.cursor;
    buffer.selection = Range(
      buffer.cursor,
      buffer.cursor,
      kind == VimMode.visualLine
          ? RangeKind.linewise
          : kind == VimMode.visualBlock
          ? RangeKind.blockwise
          : RangeKind.charwise,
    );
    buffer.visualKind = kind;
    buffer.onModeChanged(kind);
  }

  void _enterEx(VimBuffer buffer, {String initial = ''}) {
    _state.mode = VimMode.exCmd;
    _state.exDraft = initial;
    buffer.onModeChanged(VimMode.exCmd);
  }

  void _enterSearch(VimBuffer buffer, {required bool forward}) {
    _state.mode = VimMode.search;
    _state.searchDraft = '';
    _state.lastSearch = LastSearch('', forward);
    buffer.onModeChanged(VimMode.search);
  }

  // ── Ex-mode key handling ─────────────────────────────────────────────────

  void _handleExKey(TeaKey ke, VimBuffer buffer) {
    if (ke.code == KeyCode.escape) {
      _state.mode = VimMode.normal;
      _state.exDraft = '';
      buffer.onModeChanged(VimMode.normal);
      return;
    }
    if (ke.code == KeyCode.enter) {
      final cmd = ExParser.parse(_state.exDraft);
      _state.exDraft = '';
      _state.mode = VimMode.normal;
      buffer.onModeChanged(VimMode.normal);
      if (cmd != null) _runExCmd(cmd, buffer);
      return;
    }
    if (ke.code == KeyCode.backspace) {
      if (_state.exDraft.isNotEmpty) {
        _state.exDraft = _state.exDraft.substring(0, _state.exDraft.length - 1);
      } else {
        _state.mode = VimMode.normal;
        buffer.onModeChanged(VimMode.normal);
      }
      return;
    }
    if (ke.code == KeyCode.space) {
      _state.exDraft += ' ';
      return;
    }
    if (ke.code == KeyCode.rune && ke.modifiers.isEmpty) {
      _state.exDraft += ke.text;
    }
  }

  // ── Search-mode key handling ─────────────────────────────────────────────

  void _handleSearchKey(TeaKey ke, VimBuffer buffer) {
    if (ke.code == KeyCode.escape) {
      _state.mode = VimMode.normal;
      _state.searchDraft = '';
      _state.clearPending(); // aborts a `d/…` operator too
      buffer.onModeChanged(VimMode.normal);
      return;
    }
    if (ke.code == KeyCode.enter) {
      final pattern = _state.searchDraft;
      final dir = _state.lastSearch?.forward ?? true;
      _state.lastSearch = LastSearch(pattern, dir);
      _state.searchDraft = '';
      _state.mode = VimMode.normal;
      buffer.onModeChanged(VimMode.normal);
      if (pattern.isEmpty) {
        _state.clearPending();
        return;
      }
      if (_state.pendingOperator.isNotEmpty) {
        // `d/pattern<CR>` — operate from the cursor to the match.
        _operateToSearch(buffer, forward: dir);
        return;
      }
      _runSearch(pattern, dir, buffer);
      return;
    }
    if (ke.code == KeyCode.backspace) {
      if (_state.searchDraft.isNotEmpty) {
        _state.searchDraft = _state.searchDraft.substring(
          0,
          _state.searchDraft.length - 1,
        );
      } else {
        _state.mode = VimMode.normal;
        buffer.onModeChanged(VimMode.normal);
      }
      return;
    }
    if (ke.code == KeyCode.space) {
      _state.searchDraft += ' ';
      return;
    }
    if (ke.code == KeyCode.rune && ke.modifiers.isEmpty) {
      _state.searchDraft += ke.text;
    }
  }

  // ── Replace mode ─────────────────────────────────────────────────────────

  void _replaceTypedChar(VimBuffer buffer, String ch) {
    final p = buffer.cursor;
    final line = buffer.lineAt(p.row);
    _state.replaceStack.add((p, p.col < line.length ? line[p.col] : null));
    _state.replaceCapture?.write(ch);
    _overwriteChar(buffer, ch);
  }

  /// Overwrite the char at the cursor (append when past EOL) and advance.
  void _overwriteChar(VimBuffer buffer, String ch) {
    final p = buffer.cursor;
    if (p.col >= buffer.rowLength(p.row)) {
      buffer.insertAt(p, ch); // insertAt advances the cursor
      return;
    }
    buffer.replaceRange(
      Range(p, p, RangeKind.charwise),
      ch,
      RangeKind.charwise,
    );
    buffer.cursor = Pos(p.row, p.col + 1);
  }

  // ── Normal + visual parse loop ───────────────────────────────────────────

  void _handleNormalOrVisual(TeaKey ke, VimBuffer buffer) {
    // Special keys (arrows, page, etc.) translate to motions.
    if (ke.code != KeyCode.rune) {
      _handleNonRune(ke, buffer);
      return;
    }

    final mods = ke.modifiers;
    final ch = ke.text;

    // Ctrl-bindings first (Ctrl-O / Ctrl-I / Ctrl-D / Ctrl-U / Ctrl-V).
    if (mods.contains(KeyMod.ctrl)) {
      _handleCtrl(ch.toLowerCase(), buffer);
      return;
    }

    // f/F/t/T pending char — a real motion: works standalone, in visual,
    // and as an operator target (dfx, ct)).
    if (_state.pendingFind.isNotEmpty) {
      final pend = _state.pendingFind;
      _state.pendingFind = '';
      _state.lastFind = LastFind(
        ch,
        pend == 'f' || pend == 't',
        pend == 't' || pend == 'T',
      );
      _motionKey(buffer, pend, findCh: ch);
      return;
    }

    // {count}r{ch} replace; in visual modes r overwrites every selected cell.
    if (_state.pendingReplaceChar) {
      _state.pendingReplaceChar = false;
      if (_isVisual()) {
        final sel = buffer.selection?.normalized();
        if (sel != null && buffer.isEditable) {
          _state.lastAction.clear();
          buffer.pushUndo();
          _replaceSelection(buffer, sel, ch);
        }
        _exitVisual(buffer);
        return;
      }
      final count = _consumeCount();
      final c = buffer.cursor;
      // Vim aborts when fewer than count chars remain on the line.
      if (!buffer.isEditable || c.col + count > buffer.rowLength(c.row)) {
        return;
      }
      buffer.pushUndo();
      final range = Range(c, Pos(c.row, c.col + count - 1), RangeKind.charwise);
      buffer.replaceRange(range, ch * count, RangeKind.charwise);
      buffer.cursor = Pos(c.row, c.col + count - 1);
      _state.lastAction
        ..clear()
        ..kind = LastActionKind.replaceChar
        ..replaceCharCh = ch
        ..count = count;
      return;
    }

    // q{reg} — start recording. The register char is consumed silently
    // (recording starts empty, so it never lands on its own tape).
    if (_state.pendingMarkOp == 'q') {
      _state.pendingMarkOp = '';
      if (_isMacroRegister(ch)) _state.macros.start(ch);
      return;
    }

    // @{reg} / @@ — play a macro (count comes from `{count}@{reg}`).
    if (_state.pendingMarkOp == '@') {
      _state.pendingMarkOp = '';
      _playMacroRegister(ch, buffer);
      return;
    }

    // ZZ / ZQ — quit (frun has no per-buffer write, both map to quit).
    if (_state.pendingMarkOp == 'Z') {
      _state.pendingMarkOp = '';
      if (ch == 'Z' || ch == 'Q') {
        final cmd = ExParser.parse('q');
        if (cmd != null) _runExCmd(cmd, buffer);
      }
      return;
    }

    // m{a-zA-Z} set mark; '{a} jump to line; `{a} jump exact.
    if (_state.pendingMarkOp == 'm') {
      _state.marks.set(ch, buffer.surfaceId, buffer.cursor);
      _state.pendingMarkOp = '';
      return;
    }
    if (_state.pendingMarkOp == "'") {
      final mk = _state.marks.get(ch, buffer.surfaceId);
      _state.pendingMarkOp = '';
      if (mk != null) {
        _state.jumps.push(buffer.surfaceId, buffer.cursor);
        buffer.cursor = Pos(mk.pos.row, buffer.firstNonBlankCol(mk.pos.row));
      }
      return;
    }
    if (_state.pendingMarkOp == '`') {
      final mk = _state.marks.get(ch, buffer.surfaceId);
      _state.pendingMarkOp = '';
      if (mk != null) {
        _state.jumps.push(buffer.surfaceId, buffer.cursor);
        buffer.cursor = mk.pos;
      }
      return;
    }

    // Register selector: `"{a}`.
    if (_state.pendingRegister == '"' && _state.pendingRegister.length == 1) {
      // Already in "register pending" — this rune is the register name.
      _state.pendingRegister = ch;
      return;
    }
    if (ch == '"' &&
        _state.pendingOperator.isEmpty &&
        _state.pendingRegister.isEmpty) {
      _state.pendingRegister = '"';
      return;
    }

    // Count digits. `0` only continues a count already in progress; a bare
    // `0` is the line-start motion (also as an operator target: `d0`).
    if (_isDigit(ch) && (ch != '0' || _state.pendingCount > 0)) {
      _state.pendingCount = _state.pendingCount * 10 + int.parse(ch);
      return;
    }

    // Text-object detection (only when operator pending OR in visual).
    if (_state.pendingOperator.isNotEmpty || _isVisual()) {
      if (ch == 'i' || ch == 'a') {
        _state.pendingMarkOp =
            ch; // reuse field as "text-object inner/around prefix"
        return;
      }
    }
    if (_state.pendingMarkOp == 'i' || _state.pendingMarkOp == 'a') {
      final inner = _state.pendingMarkOp == 'i';
      _state.pendingMarkOp = '';
      final range = _resolveTextObject(buffer, ch, inner: inner);
      if (range != null) {
        _applyRangeFromMotionOrTextObject(
          buffer,
          range,
          textObject: ch,
          inner: inner,
        );
      } else {
        // Failed text object aborts the pending operator (vim behavior).
        _state.clearPending();
      }
      return;
    }

    // g-prefix chord.
    if (_state.pendingG) {
      _state.pendingG = false;
      _handleGChord(ch, buffer);
      return;
    }
    if (ch == 'g') {
      _state.pendingG = true;
      return;
    }

    // z-prefix chord (scroll positioning).
    if (_state.pendingZ) {
      _state.pendingZ = false;
      switch (ch) {
        case 'z':
          _onScroll?.call(const VimScrollRequest(VimScrollKind.center), buffer);
        case 't':
          _onScroll?.call(const VimScrollRequest(VimScrollKind.top), buffer);
        case 'b':
          _onScroll?.call(const VimScrollRequest(VimScrollKind.bottom), buffer);
      }
      return;
    }
    if (ch == 'z') {
      _state.pendingZ = true;
      return;
    }

    _dispatchTopLevel(ch, buffer);
  }

  void _handleNonRune(TeaKey ke, VimBuffer buffer) {
    final count = _consumeCount();
    switch (ke.code) {
      case KeyCode.left:
        _state.desiredCol = null;
        _applyMotion(buffer, Motions.left(buffer, count));
      case KeyCode.right:
        _state.desiredCol = null;
        _applyMotion(buffer, Motions.right(buffer, count));
      case KeyCode.up:
        _state.desiredCol ??= buffer.cursor.col;
        _applyMotion(
          buffer,
          Motions.up(buffer, count, wantCol: _state.desiredCol),
        );
      case KeyCode.down:
        _state.desiredCol ??= buffer.cursor.col;
        _applyMotion(
          buffer,
          Motions.down(buffer, count, wantCol: _state.desiredCol),
        );
      case KeyCode.home:
        _applyMotion(buffer, Motions.lineStart(buffer));
      case KeyCode.end:
        _applyMotion(buffer, Motions.lineEnd(buffer));
      case KeyCode.escape:
        _exitVisual(buffer);
        _state.clearPending();
      case KeyCode.enter:
        _applyMotion(buffer, Motions.down(buffer, 1));
      default:
        break;
    }
  }

  void _handleCtrl(String ch, VimBuffer buffer) {
    switch (ch) {
      case 'o':
        final jp = _state.jumps.back();
        if (jp != null) buffer.cursor = jp.pos;
      case 'i':
        // Ctrl-I is Tab; only treat as jumplist forward when explicitly ctrl.
        final jp = _state.jumps.forward();
        if (jp != null) buffer.cursor = jp.pos;
      case 'v':
        _toggleVisual(buffer, VimMode.visualBlock);
      case 'd':
        final vp = _viewport(buffer);
        _applyMotion(
          buffer,
          Motions.down(buffer, (vp.height ~/ 2).clamp(1, 100)),
        );
      case 'u':
        final vp = _viewport(buffer);
        _applyMotion(
          buffer,
          Motions.up(buffer, (vp.height ~/ 2).clamp(1, 100)),
        );
      case 'f':
        final vp = _viewport(buffer);
        _applyMotion(buffer, Motions.down(buffer, vp.height));
      case 'b':
        final vp = _viewport(buffer);
        _applyMotion(buffer, Motions.up(buffer, vp.height));
      case 'e':
        _onScroll?.call(
          VimScrollRequest(VimScrollKind.lines, _consumeCount()),
          buffer,
        );
      case 'y':
        _onScroll?.call(
          VimScrollRequest(VimScrollKind.lines, -_consumeCount()),
          buffer,
        );
      case 'r':
        buffer.redo();
        break;
      case 'c':
        _exitVisual(buffer);
        _state.clearPending();
      default:
        break;
    }
  }

  void _dispatchTopLevel(String ch, VimBuffer buffer) {
    final count = _state.pendingCount == 0 ? 1 : _state.pendingCount;
    final reg = _state.pendingRegister.length == 1
        ? _state.pendingRegister
        : '"';

    // Operator pending: only a motion (shared switch below), a doubled
    // operator (dd/yy/guu/…), or an f/t prefix may follow. Anything else
    // aborts the operator, matching vim.
    if (_state.pendingOperator.isNotEmpty) {
      if (_isDoubledOperatorKey(ch)) {
        _applyDoubledOperator(buffer, reg);
        return;
      }
      if (ch == 'n' || ch == 'N') {
        _operateToSearch(buffer, forward: ch == 'n');
        return;
      }
      if (ch == '/' || ch == '?') {
        // `d/pattern<CR>` — the operator stays pending through the search
        // prompt and applies on Enter (see _handleSearchKey).
        _enterSearch(buffer, forward: ch == '/');
        return;
      }
      if (!_motionKeys.contains(ch)) {
        _state.clearPending();
        return;
      }
    }

    switch (ch) {
      // Motions ────────────────────────────────────────────────────────────
      case 'h':
      case 'l':
      case 'j':
      case 'k':
      case 'w':
      case 'W':
      case 'e':
      case 'E':
      case 'b':
      case 'B':
      case '0':
      case '^':
      case r'$':
      case '%':
      case '{':
      case '}':
      case 'G':
      case 'H':
      case 'M':
      case 'L':
      case ';':
      case ',':
        _motionKey(buffer, ch);
      case 'f':
      case 'F':
      case 't':
      case 'T':
        // Collect the target char next; count and operator stay pending.
        _state.pendingFind = ch;
        return;
      case 'n':
        _repeatSearch(buffer, forward: true);
      case 'N':
        _repeatSearch(buffer, forward: false);
      case '*':
        _searchWord(buffer, forward: true, wholeWord: true);
      case '#':
        _searchWord(buffer, forward: false, wholeWord: true);

      // Edits / operators ──────────────────────────────────────────────────
      case 'i':
        _enterInsert(buffer, entry: 'i');
      case 'I':
        if (_state.mode == VimMode.visualBlock) {
          _beginBlockInsert(buffer, append: false);
          return;
        }
        buffer.cursor = Pos(
          buffer.cursor.row,
          buffer.firstNonBlankCol(buffer.cursor.row),
        );
        _enterInsert(buffer, entry: 'I');
      case 'a':
        final c = buffer.cursor;
        final len = buffer.rowLength(c.row);
        if (len > 0 && c.col < len) buffer.cursor = Pos(c.row, c.col + 1);
        _enterInsert(buffer, entry: 'a');
      case 'A':
        if (_state.mode == VimMode.visualBlock) {
          _beginBlockInsert(buffer, append: true);
          return;
        }
        buffer.cursor = Pos(
          buffer.cursor.row,
          buffer.rowLength(buffer.cursor.row),
        );
        _enterInsert(buffer, entry: 'A');
      case 'o':
        if (_isVisual()) {
          // Swap anchor and cursor so motions extend from the other end.
          final anchor = _state.visualAnchor;
          if (anchor != null) {
            _state.visualAnchor = buffer.cursor;
            buffer.cursor = anchor;
          }
          break;
        }
        if (buffer.isMultiLine && buffer.isEditable) {
          buffer.pushUndo();
          final r = buffer.cursor.row;
          buffer.insertAt(Pos(r + 1, 0), '\n');
          buffer.cursor = Pos(r + 1, 0);
          _enterInsert(buffer, entry: 'o', pushUndo: false);
        } else {
          _enterInsert(buffer, entry: 'o');
        }
      case 'O':
        if (buffer.isMultiLine && buffer.isEditable) {
          buffer.pushUndo();
          final r = buffer.cursor.row;
          buffer.insertAt(Pos(r, 0), '\n');
          buffer.cursor = Pos(r, 0);
          _enterInsert(buffer, entry: 'O', pushUndo: false);
        } else {
          _enterInsert(buffer, entry: 'O');
        }
      case 'x':
        if (buffer.isEditable) {
          buffer.pushUndo();
          for (var i = 0; i < count; i++) {
            final c = buffer.cursor;
            if (c.col < buffer.rowLength(c.row)) {
              final range = Range(c, c, RangeKind.charwise);
              Operators.delete(buffer, range, _state.registers, register: reg);
            }
          }
          _captureSingleEdit('x', count, reg);
        }
      case 'X':
        if (buffer.isEditable) {
          buffer.pushUndo();
          for (var i = 0; i < count; i++) {
            final c = buffer.cursor;
            if (c.col > 0) {
              final range = Range(
                Pos(c.row, c.col - 1),
                Pos(c.row, c.col - 1),
                RangeKind.charwise,
              );
              Operators.delete(buffer, range, _state.registers, register: reg);
            }
          }
          _captureSingleEdit('X', count, reg);
        }
      case 's':
        if (buffer.isEditable) {
          buffer.pushUndo();
          final c = buffer.cursor;
          final range = Range(c, c, RangeKind.charwise);
          Operators.delete(buffer, range, _state.registers, register: reg);
          _enterInsert(buffer, entry: 's', pushUndo: false);
        }
      case 'S':
        if (buffer.isEditable) {
          buffer.pushUndo();
          final r = buffer.cursor.row;
          final range = Range(
            Pos(r, 0),
            Pos(r, buffer.rowLength(r)),
            RangeKind.linewise,
          );
          Operators.delete(buffer, range, _state.registers, register: reg);
          _enterInsert(buffer, entry: 'S', pushUndo: false);
        }
      case 'D':
        if (buffer.isEditable) {
          buffer.pushUndo();
          final c = buffer.cursor;
          final len = buffer.rowLength(c.row);
          if (len > 0) {
            final range = Range(c, Pos(c.row, len - 1), RangeKind.charwise);
            Operators.delete(buffer, range, _state.registers, register: reg);
          }
          _captureSingleEdit('D', count, reg);
        }
      case 'C':
        if (buffer.isEditable) {
          buffer.pushUndo();
          final c = buffer.cursor;
          final len = buffer.rowLength(c.row);
          if (len > 0) {
            final range = Range(c, Pos(c.row, len - 1), RangeKind.charwise);
            Operators.delete(buffer, range, _state.registers, register: reg);
          }
          _enterInsert(buffer, entry: 'C', pushUndo: false);
        }
      case 'Y':
        _yankCurrentLine(buffer, count, reg);
      case 'p':
      case 'P':
        if (_isVisual()) {
          _visualPaste(buffer, reg);
          break;
        }
        if (!buffer.isEditable) break;
        buffer.pushUndo();
        Operators.paste(
          buffer,
          _state.registers.read(reg),
          before: ch == 'P',
          count: count,
        );
        _captureSingleEdit(ch, count, reg);
      case 'r':
        // Early return keeps the count pending for `{count}r{ch}`.
        _state.pendingReplaceChar = true;
        return;
      case 'R':
        if (!buffer.isEditable) break;
        buffer.pushUndo();
        _state.replaceStack.clear();
        _state.replaceCapture = StringBuffer();
        _state.replaceSessionCount = count;
        _state.mode = VimMode.replace;
        buffer.onModeChanged(VimMode.replace);
      case 'J':
        if (_isVisual()) {
          _visualJoin(buffer);
          break;
        }
        if (buffer.isEditable) {
          buffer.pushUndo();
          Operators.joinLines(buffer, count);
          _captureSingleEdit('J', count, reg);
        }
      case '~':
        if (_isVisual()) {
          _applyVisualOperator(buffer, '~', reg);
          break;
        }
        if (buffer.isEditable) {
          buffer.pushUndo();
          final c = buffer.cursor;
          final len = buffer.rowLength(c.row);
          if (len == 0) break;
          final end = (c.col + count - 1).clamp(0, len - 1);
          Operators.toggleCase(
            buffer,
            Range(c, Pos(c.row, end), RangeKind.charwise),
          );
          buffer.cursor = Pos(c.row, (end + 1).clamp(0, len - 1));
          _captureSingleEdit('~', count, reg);
        }
      case 'u':
        if (_isVisual()) {
          // Visual u/U are case operators, not undo.
          _applyVisualOperator(buffer, 'gu', reg);
          break;
        }
        if (buffer.undo()) {
          // OK
        }
      case 'U':
        if (_isVisual()) {
          _applyVisualOperator(buffer, 'gU', reg);
        }
      case '.':
        _replayLastAction(buffer);
      case 'v':
        _toggleVisual(buffer, VimMode.visualChar);
      case 'V':
        _toggleVisual(buffer, VimMode.visualLine);
      case 'd':
      case 'c':
      case 'y':
      case '>':
      case '<':
      case '=':
        if (_isVisual()) {
          _applyVisualOperator(buffer, ch, reg);
        } else {
          // Move the count typed so far aside so the motion's own count
          // accumulates separately (`2d3w` = 6 words).
          _state.pendingOperator = ch;
          _state.pendingOpCount = _state.pendingCount;
          _state.pendingCount = 0;
          return;
        }
      case 'm':
        _state.pendingMarkOp = 'm';
      case "'":
        _state.pendingMarkOp = "'";
      case '`':
        _state.pendingMarkOp = '`';

      // Macros
      case 'q':
        if (_state.macros.isRecording) {
          _state.macros.dropLast(); // the stopping q is not macro content
          _state.macros.stop();
        } else {
          _state.pendingMarkOp = 'q';
        }
        return;
      case '@':
        // Early return keeps the count pending for `{count}@{reg}`.
        _state.pendingMarkOp = '@';
        return;

      // Tab navigation
      case 'Z':
        // ZZ / ZQ — peek next char via pendingMarkOp.
        _state.pendingMarkOp = 'Z';
      // Command-line entry
      case ':':
        _enterEx(buffer);
      case '/':
        _enterSearch(buffer, forward: true);
      case '?':
        _enterSearch(buffer, forward: false);

      default:
        break;
    }
    _state.pendingCount = 0;
    _state.pendingRegister = '';
  }

  /// Keys the shared motion switch understands. When an operator is pending,
  /// any key outside this set (and not a doubled operator) aborts it.
  static const Set<String> _motionKeys = {
    'h', 'l', 'j', 'k', 'w', 'W', 'e', 'E', 'b', 'B', '0', '^', r'$', //
    '%', '{', '}', 'G', 'H', 'M', 'L', 'f', 'F', 't', 'T', ';', ',',
  };

  /// Motions that push the current position onto the jumplist.
  static const Set<String> _jumpMotions = {'%', '{', '}', 'G', 'gg'};

  bool _isDoubledOperatorKey(String ch) {
    final op = _state.pendingOperator;
    if (op.isEmpty) return false;
    if (ch == op) return true; // dd yy cc >> << ==
    if (op.length == 2 && ch == op[1]) return true; // guu gUU
    if (op == '~' && ch == '~') return true; // g~~
    return false;
  }

  /// `{opCount}dd`-style linewise application; count is the product of the
  /// operator count and the doubled key's count (`2d3d` = 6 lines).
  void _applyDoubledOperator(VimBuffer buffer, String reg) {
    final op = _state.pendingOperator;
    final count = _effectiveCount(_state.pendingCount);
    if (!buffer.isEditable && op != 'y') {
      _state.clearPending();
      return;
    }
    _applyLinewiseOperator(buffer, op, count, reg);
    if (op != 'y') {
      _state.lastAction
        ..clear()
        ..kind = LastActionKind.operatorDouble
        ..operator = op
        ..count = count
        ..register = reg;
    }
    _state.clearPending();
  }

  int _effectiveCount(int motionCount) {
    final oc = _state.pendingOpCount == 0 ? 1 : _state.pendingOpCount;
    final mc = motionCount == 0 ? 1 : motionCount;
    return oc * mc;
  }

  /// Resolve a named motion to a target. [name] may be 2-char (`gg`, `ge`).
  /// [findCh] carries the f/t target char; [line] the explicit G/gg target.
  MotionResult? _namedMotion(
    String name,
    VimBuffer buffer,
    int count, {
    String findCh = '',
    int? line,
  }) {
    switch (name) {
      case 'h':
        return Motions.left(buffer, count);
      case 'l':
        return Motions.right(buffer, count);
      case 'j':
        return Motions.down(buffer, count, wantCol: _state.desiredCol);
      case 'k':
        return Motions.up(buffer, count, wantCol: _state.desiredCol);
      case 'w':
        return Motions.nextWordStart(buffer, count);
      case 'W':
        return Motions.nextWordStart(buffer, count, bigWord: true);
      case 'e':
        return Motions.wordEnd(buffer, count);
      case 'E':
        return Motions.wordEnd(buffer, count, bigWord: true);
      case 'b':
        return Motions.prevWordStart(buffer, count);
      case 'B':
        return Motions.prevWordStart(buffer, count, bigWord: true);
      case 'ge':
        return Motions.prevWordEnd(buffer, count);
      case 'gE':
        return Motions.prevWordEnd(buffer, count, bigWord: true);
      case '0':
        return Motions.lineStart(buffer);
      case '^':
        return Motions.firstNonBlank(buffer);
      case r'$':
        return Motions.lineEnd(buffer);
      case 'g_':
        return Motions.lastNonBlank(buffer);
      case '%':
        return Motions.matchBracket(buffer);
      case '{':
        return Motions.paragraph(buffer, count, forward: false);
      case '}':
        return Motions.paragraph(buffer, count, forward: true);
      case 'G':
        return Motions.goLine(buffer, line);
      case 'gg':
        return line == null
            ? Motions.firstLine(buffer)
            : Motions.goLine(buffer, line);
      case 'H':
        final vp = _viewport(buffer);
        return Motions.viewportTop(buffer, vp.top, count);
      case 'M':
        final vp = _viewport(buffer);
        return Motions.viewportMiddle(buffer, vp.top, vp.height);
      case 'L':
        final vp = _viewport(buffer);
        return Motions.viewportBottom(buffer, vp.top, vp.height, count);
      case 'f':
        return Motions.findChar(
          buffer,
          findCh,
          count,
          forward: true,
          till: false,
        );
      case 'F':
        return Motions.findChar(
          buffer,
          findCh,
          count,
          forward: false,
          till: false,
        );
      case 't':
        return Motions.findChar(
          buffer,
          findCh,
          count,
          forward: true,
          till: true,
        );
      case 'T':
        return Motions.findChar(
          buffer,
          findCh,
          count,
          forward: false,
          till: true,
        );
      case ';':
        final lf = _state.lastFind;
        if (lf == null) return null;
        return Motions.findChar(
          buffer,
          lf.ch,
          count,
          forward: lf.forward,
          till: lf.till,
        );
      case ',':
        final lf = _state.lastFind;
        if (lf == null) return null;
        return Motions.findChar(
          buffer,
          lf.ch,
          count,
          forward: !lf.forward,
          till: lf.till,
        );
      default:
        return null;
    }
  }

  /// Terminal handler for every motion key: computes the effective count,
  /// resolves the motion, and either moves/extends or feeds the pending
  /// operator. This is the single seam that makes `d`, `c`, `y`… work with
  /// every motion the engine knows.
  void _motionKey(VimBuffer buffer, String name, {String findCh = ''}) {
    final opPending = _state.pendingOperator.isNotEmpty;
    final motionCount = _state.pendingCount;
    _state.pendingCount = 0;

    // Curswant: j/k keep aiming for the column vertical movement started
    // at; any other motion resets it to the real cursor column.
    if (name == 'j' || name == 'k') {
      _state.desiredCol ??= buffer.cursor.col;
    } else {
      _state.desiredCol = null;
    }

    int count;
    int? line;
    if (name == 'G' || name == 'gg') {
      // Counts are a line target, not a multiplier (`d3G` → to line 3;
      // `2d3G` → line 6 per vim's count-multiplication rule).
      final oc = _state.pendingOpCount;
      line = (oc == 0 && motionCount == 0)
          ? null
          : (oc == 0 ? 1 : oc) * (motionCount == 0 ? 1 : motionCount);
      count = 1;
    } else {
      count = opPending
          ? _effectiveCount(motionCount)
          : (motionCount == 0 ? 1 : motionCount);
    }

    final MotionResult? motion;
    if (name == '%' && motionCount > 0) {
      // {count}% — jump to that percentage of the buffer, linewise.
      final row = ((motionCount * buffer.lineCount + 99) ~/ 100 - 1).clamp(
        0,
        buffer.lineCount - 1,
      );
      motion = MotionResult(
        Pos(row, buffer.firstNonBlankCol(row)),
        kind: RangeKind.linewise,
      );
    } else {
      motion = _namedMotion(name, buffer, count, findCh: findCh, line: line);
    }
    if (motion == null) {
      if (opPending) _state.clearPending();
      return;
    }
    // A find that doesn't move failed — abort the operator (vim beeps).
    const findNames = {'f', 'F', 't', 'T', ';', ','};
    if (findNames.contains(name) && motion.target == buffer.cursor) {
      if (opPending) _state.clearPending();
      return;
    }
    if (_jumpMotions.contains(name) && !opPending) {
      _state.jumps.push(buffer.surfaceId, buffer.cursor);
    }
    _applyMotionOrOperate(
      buffer,
      motion,
      dotMotion: name,
      findCh: findCh,
      usedCount: (name == 'G' || name == 'gg') ? (line ?? 0) : count,
    );
  }

  /// Apply a resolved motion: feed the pending operator if one is latched,
  /// otherwise move the cursor (extending the selection in visual modes).
  void _applyMotionOrOperate(
    VimBuffer buffer,
    MotionResult motion, {
    required String dotMotion,
    String findCh = '',
    int usedCount = 1,
  }) {
    final op = _state.pendingOperator;
    if (op.isEmpty || _isVisual()) {
      _applyMotion(buffer, motion);
      return;
    }
    if (!buffer.isEditable && op != 'y') {
      _state.clearPending();
      return;
    }
    final reg = _state.pendingRegister.length == 1
        ? _state.pendingRegister
        : '"';
    final range = _rangeFromMotion(buffer, buffer.cursor, motion);
    _runOperator(op, buffer, range, reg);
    if (op != 'y') {
      _state.lastAction
        ..clear()
        ..kind = LastActionKind.operatorMotion
        ..operator = op
        ..motion = dotMotion
        ..findCh = findCh
        ..motionCount = usedCount
        ..register = reg;
    }
    _state.clearPending();
  }

  /// The position one char before [p] (wrapping to the previous row's end).
  Pos _posBefore(VimBuffer buffer, Pos p) {
    if (p.col > 0) return Pos(p.row, p.col - 1);
    if (p.row > 0) {
      final len = buffer.rowLength(p.row - 1);
      return Pos(p.row - 1, len == 0 ? 0 : len - 1);
    }
    return p;
  }

  Range _rangeFromMotion(VimBuffer buffer, Pos from, MotionResult motion) {
    if (motion.kind == RangeKind.linewise) {
      return Range(
        Pos(from.row, 0),
        Pos(motion.target.row, 0),
        RangeKind.linewise,
      );
    }
    if (motion.exclusive) {
      final t = motion.target;
      if (t >= from) {
        // Forward exclusive: back the end off by one.
        return Range(
          from,
          Pos(t.row, (t.col - 1).clamp(0, 1 << 30)),
          RangeKind.charwise,
        );
      }
      // Backward exclusive: the cursor char itself is excluded (`db`, `dFx`
      // must not delete the char under the cursor).
      return Range(_posBefore(buffer, from), t, RangeKind.charwise);
    }
    return Range(from, motion.target, RangeKind.charwise);
  }

  Range? _resolveTextObject(
    VimBuffer buffer,
    String ch, {
    required bool inner,
  }) {
    switch (ch) {
      case 'w':
        return TextObjects.word(buffer, inner: inner);
      case 'W':
        return TextObjects.word(buffer, inner: inner, bigWord: true);
      case '(':
      case ')':
      case 'b':
        return TextObjects.bracket(buffer, '(', ')', inner: inner);
      case '[':
      case ']':
        return TextObjects.bracket(buffer, '[', ']', inner: inner);
      case '{':
      case '}':
      case 'B':
        return TextObjects.bracket(buffer, '{', '}', inner: inner);
      case '<':
      case '>':
        return TextObjects.bracket(buffer, '<', '>', inner: inner);
      case '"':
        return TextObjects.quote(buffer, '"', inner: inner);
      case "'":
        return TextObjects.quote(buffer, "'", inner: inner);
      case '`':
        return TextObjects.quote(buffer, '`', inner: inner);
      case 't':
        return TextObjects.tag(buffer, inner: inner);
      case 'p':
        return TextObjects.paragraph(buffer, inner: inner);
      case 's':
        return TextObjects.sentence(buffer, inner: inner);
      default:
        return null;
    }
  }

  void _applyRangeFromMotionOrTextObject(
    VimBuffer buffer,
    Range range, {
    String textObject = '',
    bool inner = false,
  }) {
    if (_isVisual()) {
      buffer.selection = range;
      buffer.cursor = range.end;
      return;
    }
    if (_state.pendingOperator.isEmpty) return;
    final op = _state.pendingOperator;
    if (!buffer.isEditable && op != 'y') {
      _state.clearPending();
      return;
    }
    final reg = _state.pendingRegister.length == 1
        ? _state.pendingRegister
        : '"';
    _runOperator(op, buffer, range, reg);
    if (op != 'y' && textObject.isNotEmpty) {
      _state.lastAction
        ..clear()
        ..kind = LastActionKind.operatorTextObject
        ..operator = op
        ..textObject = textObject
        ..textObjectInner = inner
        ..register = reg;
    }
    _state.clearPending();
  }

  void _runOperator(String op, VimBuffer buffer, Range range, String reg) {
    // yank is the only non-mutating operator; everything else snapshots.
    if (op != 'y' && op != '=') buffer.pushUndo();
    switch (op) {
      case 'd':
        Operators.delete(buffer, range, _state.registers, register: reg);
      case 'c':
        Operators.change(buffer, range, _state.registers, register: reg);
        _enterInsert(buffer, entry: 'c', pushUndo: false);
      case 'y':
        Operators.yank(buffer, range, _state.registers, register: reg);
      case '>':
        Operators.indent(buffer, range, _state.shiftWidth);
      case '<':
        Operators.dedent(buffer, range, _state.shiftWidth);
      case '=':
        // No language-aware reindent; treat as no-op.
        break;
      case '~':
        Operators.toggleCase(buffer, range);
      case 'gu':
        Operators.toLower(buffer, range);
      case 'gU':
        Operators.toUpper(buffer, range);
    }
  }

  void _applyLinewiseOperator(
    VimBuffer buffer,
    String op,
    int count,
    String reg,
  ) {
    final startRow = buffer.cursor.row;
    final endRow = (startRow + count - 1).clamp(0, buffer.lineCount - 1);
    final range = Range(
      Pos(startRow, 0),
      Pos(endRow, buffer.rowLength(endRow)),
      RangeKind.linewise,
    );
    _runOperator(op, buffer, range, reg);
  }

  void _yankCurrentLine(VimBuffer buffer, int count, String reg) {
    final startRow = buffer.cursor.row;
    final endRow = (startRow + count - 1).clamp(0, buffer.lineCount - 1);
    final range = Range(
      Pos(startRow, 0),
      Pos(endRow, buffer.rowLength(endRow)),
      RangeKind.linewise,
    );
    Operators.yank(buffer, range, _state.registers, register: reg);
  }

  void _applyVisualOperator(VimBuffer buffer, String op, String reg) {
    final sel = buffer.selection;
    if (sel == null) return;
    // Visual operations are not dot-repeatable (a stale record must not
    // merge with the insert session a visual `c` opens).
    _state.lastAction.clear();
    _saveVisualMarks(buffer);
    _runOperator(op, buffer, sel, reg);
    // `c` already switched to insert (and cleared the selection) — forcing
    // normal here would silently drop out of the change.
    if (_state.mode == VimMode.insert) return;
    _state.mode = VimMode.normal;
    _state.visualAnchor = null;
    buffer.selection = null;
    buffer.visualKind = VimMode.normal;
    buffer.onModeChanged(VimMode.normal);
  }

  /// Record `'<`/`'>` from the current selection (called on visual exit).
  void _saveVisualMarks(VimBuffer buffer) {
    final sel = buffer.selection?.normalized();
    if (sel == null) return;
    _state.marks.set('<', buffer.surfaceId, sel.start);
    _state.marks.set('>', buffer.surfaceId, sel.end);
  }

  /// Leave any visual mode, saving the `'<`/`'>` marks.
  void _exitVisual(VimBuffer buffer) {
    if (!_isVisual()) return;
    _saveVisualMarks(buffer);
    _state.mode = VimMode.normal;
    _state.visualAnchor = null;
    buffer.selection = null;
    buffer.visualKind = VimMode.normal;
    buffer.onModeChanged(VimMode.normal);
  }

  /// Visual `p`/`P`: the selection is replaced by the register contents.
  /// The deleted text lands in the unnamed register (vim behavior).
  void _visualPaste(VimBuffer buffer, String reg) {
    final sel = buffer.selection;
    if (sel == null || !buffer.isEditable) {
      _exitVisual(buffer);
      return;
    }
    final entry = _state.registers.read(reg);
    if (entry.isEmpty) {
      _exitVisual(buffer);
      return;
    }
    _state.lastAction.clear();
    _saveVisualMarks(buffer);
    buffer.pushUndo();
    Operators.delete(buffer, sel, _state.registers);
    Operators.paste(buffer, entry, before: true);
    _state.mode = VimMode.normal;
    _state.visualAnchor = null;
    buffer.selection = null;
    buffer.visualKind = VimMode.normal;
    buffer.onModeChanged(VimMode.normal);
  }

  /// Visual `J`: join every line the selection spans.
  void _visualJoin(VimBuffer buffer) {
    final sel = buffer.selection?.normalized();
    if (sel == null || !buffer.isEditable) {
      _exitVisual(buffer);
      return;
    }
    _state.lastAction.clear();
    _saveVisualMarks(buffer);
    buffer.pushUndo();
    final joins = (sel.end.row - sel.start.row).clamp(1, 1 << 30);
    buffer.cursor = Pos(sel.start.row, 0);
    Operators.joinLines(buffer, joins);
    _state.mode = VimMode.normal;
    _state.visualAnchor = null;
    buffer.selection = null;
    buffer.visualKind = VimMode.normal;
    buffer.onModeChanged(VimMode.normal);
  }

  /// Visual `r{ch}`: overwrite every selected cell, preserving newlines.
  void _replaceSelection(VimBuffer buffer, Range sel, String ch) {
    final startRow = sel.start.row;
    final endRow = sel.end.row;
    for (var r = startRow; r <= endRow && r < buffer.lineCount; r++) {
      final len = buffer.rowLength(r);
      if (len == 0) continue;
      int c0;
      int c1;
      switch (sel.kind) {
        case RangeKind.linewise:
          c0 = 0;
          c1 = len - 1;
        case RangeKind.blockwise:
          c0 = sel.start.col;
          c1 = sel.end.col;
          if (c0 > c1) {
            final t = c0;
            c0 = c1;
            c1 = t;
          }
          if (c0 >= len) continue;
          c1 = c1.clamp(0, len - 1);
        case RangeKind.charwise:
          c0 = r == startRow ? sel.start.col : 0;
          c1 = (r == endRow ? sel.end.col : len - 1).clamp(0, len - 1);
      }
      buffer.replaceRange(
        Range(Pos(r, c0), Pos(r, c1), RangeKind.charwise),
        ch * (c1 - c0 + 1),
        RangeKind.charwise,
      );
    }
    buffer.cursor = sel.start;
  }

  /// Visual-block `I`/`A`: enter insert on the block's top row; the typed
  /// text replicates onto the remaining rows when the session ends (see
  /// [_enterNormal]).
  void _beginBlockInsert(VimBuffer buffer, {required bool append}) {
    final sel = buffer.selection?.normalized();
    if (sel == null || !buffer.isEditable) {
      _exitVisual(buffer);
      return;
    }
    var c0 = sel.start.col;
    var c1 = sel.end.col;
    if (c0 > c1) {
      final t = c0;
      c0 = c1;
      c1 = t;
    }
    final col = append ? c1 + 1 : c0;
    _saveVisualMarks(buffer);
    buffer.pushUndo();
    _state.pendingBlockInsert = (
      startRow: sel.start.row,
      endRow: sel.end.row,
      col: col,
      append: append,
    );
    _state.mode = VimMode.normal;
    _state.visualAnchor = null;
    buffer.selection = null;
    buffer.visualKind = VimMode.normal;
    final len = buffer.rowLength(sel.start.row);
    if (append && len < col) {
      buffer.insertAt(Pos(sel.start.row, len), ' ' * (col - len));
    }
    buffer.cursor = Pos(sel.start.row, col);
    _enterInsert(buffer, entry: 'i', pushUndo: false);
  }

  void _applyMotion(VimBuffer buffer, MotionResult motion) {
    if (_isVisual()) {
      buffer.cursor = motion.target;
      // Extend selection.
      final anchor = _state.visualAnchor ?? buffer.cursor;
      final kind = _state.mode == VimMode.visualLine
          ? RangeKind.linewise
          : _state.mode == VimMode.visualBlock
          ? RangeKind.blockwise
          : RangeKind.charwise;
      buffer.selection = Range(anchor, motion.target, kind).normalized();
      return;
    }
    buffer.cursor = motion.target;
  }

  void _toggleVisual(VimBuffer buffer, VimMode kind) {
    if (_state.mode == kind) {
      _exitVisual(buffer);
      return;
    }
    _enterVisual(buffer, kind);
  }

  bool _isVisual() =>
      _state.mode == VimMode.visualChar ||
      _state.mode == VimMode.visualLine ||
      _state.mode == VimMode.visualBlock;

  int _consumeCount() {
    final n = _state.pendingCount == 0 ? 1 : _state.pendingCount;
    _state.pendingCount = 0;
    return n;
  }

  void _handleGChord(String ch, VimBuffer buffer) {
    switch (ch) {
      // Motions — routed through _motionKey so a pending operator applies
      // (`dgg`, `yG`-via-gg, `dge`, …).
      case 'g':
        _motionKey(buffer, 'gg');
        return;
      case 'e':
        _motionKey(buffer, 'ge');
        return;
      case 'E':
        _motionKey(buffer, 'gE');
        return;
      case '_':
        _motionKey(buffer, 'g_');
        return;
      // Case operators — apply immediately on a visual selection, otherwise
      // latch like d/c/y (count moves aside for `2guw`-style products).
      case 'u':
      case 'U':
      case '~':
        final op = ch == '~' ? '~' : 'g$ch';
        if (_isVisual()) {
          _applyVisualOperator(buffer, op, '"');
        } else {
          _state.pendingOperator = op;
          _state.pendingOpCount = _state.pendingCount;
          _state.pendingCount = 0;
        }
        return;
      case 't':
        _onTabSwitch?.call(
          _state.pendingCount == 0 ? null : _state.pendingCount,
          forward: true,
        );
      case 'T':
        _onTabSwitch?.call(
          _state.pendingCount == 0 ? null : _state.pendingCount,
          forward: false,
        );
      case '*':
        _searchWord(buffer, forward: true, wholeWord: false);
        return;
      case '#':
        _searchWord(buffer, forward: false, wholeWord: false);
        return;
      case 'd':
      case 'D':
        // gd/gD: go to declaration — no semantic context; no-op.
        break;
      case 'J':
        Operators.joinLines(buffer, _consumeCount());
      default:
        break;
    }
    _state.pendingCount = 0;
  }

  // ── Macros ───────────────────────────────────────────────────────────────

  static bool _isMacroRegister(String ch) {
    if (ch.length != 1) return false;
    final u = ch.codeUnitAt(0);
    return (u >= 0x61 && u <= 0x7a) || (u >= 0x30 && u <= 0x39); // a-z 0-9
  }

  /// `{count}@{reg}` / `{count}@@` — hand the tape to the host player, which
  /// re-feeds the keys through its full key router (with reentrancy caps).
  void _playMacroRegister(String ch, VimBuffer buffer) {
    final count = _consumeCount();
    final reg = ch == '@' ? _state.macros.lastPlayed : ch;
    if (reg.isEmpty || !_isMacroRegister(reg)) return;
    final tape = _state.macros.tape(reg);
    if (tape == null || tape.isEmpty) return;
    _state.macros.lastPlayed = reg;
    final player = _onPlayMacro;
    if (player == null) return;
    player(<TeaKey>[for (var i = 0; i < count; i++) ...tape]);
  }

  void _repeatSearch(VimBuffer buffer, {required bool forward}) {
    final ls = _state.lastSearch;
    if (ls == null || ls.pattern.isEmpty) return;
    final dir = forward ? ls.forward : !ls.forward;
    _runSearch(ls.pattern, dir, buffer);
  }

  /// `*` / `#` (and `g*` / `g#`): search for the word under the cursor.
  void _searchWord(
    VimBuffer buffer, {
    required bool forward,
    required bool wholeWord,
  }) {
    final word = Motions.wordUnderCursor(buffer);
    if (word == null) return;
    final escaped = RegExp.escape(word);
    final pattern = wholeWord ? '\\b$escaped\\b' : escaped;
    _state.lastSearch = LastSearch(pattern, forward);
    _runSearch(pattern, forward, buffer);
  }

  /// Operator + `n`/`N`: apply the operator from the cursor to the next
  /// match of the last search (exclusive), e.g. `dn`.
  void _operateToSearch(VimBuffer buffer, {required bool forward}) {
    final op = _state.pendingOperator;
    if (!buffer.isEditable && op != 'y') {
      _state.clearPending();
      return;
    }
    final from = buffer.cursor;
    _repeatSearch(buffer, forward: forward);
    final to = buffer.cursor;
    if (to == from) {
      _state.clearPending();
      return;
    }
    buffer.cursor = from;
    _applyMotionOrOperate(
      buffer,
      MotionResult(to, exclusive: true),
      dotMotion: forward ? 'n' : 'N',
    );
  }

  // ── Dot-repeat ───────────────────────────────────────────────────────────

  void _captureSingleEdit(String key, int count, String reg) {
    _state.lastAction
      ..clear()
      ..kind = LastActionKind.singleEdit
      ..singleEdit = key
      ..count = count
      ..register = reg;
  }

  /// Replay [_state.lastAction]. Insertion sessions reinsert captured text
  /// programmatically rather than re-entering live insert mode.
  void _replayLastAction(VimBuffer buffer) {
    final a = _state.lastAction;
    if (a.kind == LastActionKind.none) return;
    if (!buffer.isEditable) return;
    switch (a.kind) {
      case LastActionKind.none:
        return;
      case LastActionKind.operatorMotion:
        if (a.motion == 'n' || a.motion == 'N') {
          _state.pendingOperator = a.operator;
          _state.pendingRegister = a.register == '"' ? '' : a.register;
          _operateToSearch(buffer, forward: a.motion == 'n');
          return;
        }
        final line = (a.motion == 'G' || a.motion == 'gg')
            ? (a.motionCount == 0 ? null : a.motionCount)
            : null;
        final count = a.motionCount == 0 ? 1 : a.motionCount;
        final m = _namedMotion(
          a.motion,
          buffer,
          count,
          findCh: a.findCh,
          line: line,
        );
        if (m == null) return;
        const findNames = {'f', 'F', 't', 'T', ';', ','};
        if (findNames.contains(a.motion) && m.target == buffer.cursor) return;
        _replayOperator(buffer, a, _rangeFromMotion(buffer, buffer.cursor, m));
      case LastActionKind.operatorDouble:
        final startRow = buffer.cursor.row;
        final endRow = (startRow + a.count - 1).clamp(0, buffer.lineCount - 1);
        _replayOperator(
          buffer,
          a,
          Range(
            Pos(startRow, 0),
            Pos(endRow, buffer.rowLength(endRow)),
            RangeKind.linewise,
          ),
        );
      case LastActionKind.operatorTextObject:
        final range = _resolveTextObject(
          buffer,
          a.textObject,
          inner: a.textObjectInner,
        );
        if (range != null) _replayOperator(buffer, a, range);
      case LastActionKind.singleEdit:
        _replaySingleEdit(buffer, a);
      case LastActionKind.replaceChar:
        final count = a.count;
        final c = buffer.cursor;
        if (c.col + count > buffer.rowLength(c.row)) return;
        buffer.pushUndo();
        buffer.replaceRange(
          Range(c, Pos(c.row, c.col + count - 1), RangeKind.charwise),
          a.replaceCharCh * count,
          RangeKind.charwise,
        );
        buffer.cursor = Pos(c.row, c.col + count - 1);
      case LastActionKind.insertSession:
        _replayInsertSession(buffer, a);
    }
  }

  /// Run a recorded operator over [range]. `c` is replayed as delete +
  /// reinsert of the captured text instead of re-entering live insert mode.
  void _replayOperator(VimBuffer buffer, LastAction a, Range range) {
    if (a.operator == 'c') {
      buffer.pushUndo();
      Operators.change(buffer, range, _state.registers, register: a.register);
      if (a.insertText.isNotEmpty) {
        buffer.insertAt(buffer.cursor, a.insertText);
        final c = buffer.cursor;
        if (c.col > 0) buffer.cursor = Pos(c.row, c.col - 1);
      }
      return;
    }
    _runOperator(a.operator, buffer, range, a.register);
  }

  void _replaySingleEdit(VimBuffer buffer, LastAction a) {
    final count = a.count;
    final reg = a.register;
    buffer.pushUndo();
    switch (a.singleEdit) {
      case 'x':
        for (var i = 0; i < count; i++) {
          final c = buffer.cursor;
          if (c.col < buffer.rowLength(c.row)) {
            Operators.delete(
              buffer,
              Range(c, c, RangeKind.charwise),
              _state.registers,
              register: reg,
            );
          }
        }
      case 'X':
        for (var i = 0; i < count; i++) {
          final c = buffer.cursor;
          if (c.col > 0) {
            Operators.delete(
              buffer,
              Range(
                Pos(c.row, c.col - 1),
                Pos(c.row, c.col - 1),
                RangeKind.charwise,
              ),
              _state.registers,
              register: reg,
            );
          }
        }
      case 'D':
        final c = buffer.cursor;
        final len = buffer.rowLength(c.row);
        if (len > 0) {
          Operators.delete(
            buffer,
            Range(c, Pos(c.row, len - 1), RangeKind.charwise),
            _state.registers,
            register: reg,
          );
        }
      case 'J':
        Operators.joinLines(buffer, count);
      case 'p':
        Operators.paste(
          buffer,
          _state.registers.read(reg),
          before: false,
          count: count,
        );
      case 'P':
        Operators.paste(
          buffer,
          _state.registers.read(reg),
          before: true,
          count: count,
        );
      case '~':
        final c = buffer.cursor;
        final len = buffer.rowLength(c.row);
        if (len == 0) break;
        final end = (c.col + count - 1).clamp(0, len - 1);
        Operators.toggleCase(
          buffer,
          Range(c, Pos(c.row, end), RangeKind.charwise),
        );
        buffer.cursor = Pos(c.row, (end + 1).clamp(0, len - 1));
    }
  }

  void _replayInsertSession(VimBuffer buffer, LastAction a) {
    buffer.pushUndo();
    // Reposition cursor matching the original entry key.
    switch (a.insertEntry) {
      case 'I':
        buffer.cursor = Pos(
          buffer.cursor.row,
          buffer.firstNonBlankCol(buffer.cursor.row),
        );
      case 'a':
        final c = buffer.cursor;
        final len = buffer.rowLength(c.row);
        if (len > 0 && c.col < len) buffer.cursor = Pos(c.row, c.col + 1);
      case 'A':
        buffer.cursor = Pos(
          buffer.cursor.row,
          buffer.rowLength(buffer.cursor.row),
        );
      case 'o':
        if (buffer.isMultiLine) {
          final r = buffer.cursor.row;
          buffer.insertAt(Pos(r + 1, 0), '\n');
          buffer.cursor = Pos(r + 1, 0);
        }
      case 'O':
        if (buffer.isMultiLine) {
          final r = buffer.cursor.row;
          buffer.insertAt(Pos(r, 0), '\n');
          buffer.cursor = Pos(r, 0);
        }
      case 's':
        final c = buffer.cursor;
        Operators.delete(
          buffer,
          Range(c, c, RangeKind.charwise),
          _state.registers,
          register: a.register,
        );
      case 'S':
        final r = buffer.cursor.row;
        Operators.delete(
          buffer,
          Range(Pos(r, 0), Pos(r, buffer.rowLength(r)), RangeKind.linewise),
          _state.registers,
          register: a.register,
        );
      case 'C':
        final c = buffer.cursor;
        final len = buffer.rowLength(c.row);
        if (len > 0) {
          Operators.delete(
            buffer,
            Range(c, Pos(c.row, len - 1), RangeKind.charwise),
            _state.registers,
            register: a.register,
          );
        }
      case 'R':
        for (var i = 0; i < a.count; i++) {
          for (final ch in a.insertText.split('')) {
            _overwriteChar(buffer, ch);
          }
        }
        final cr = buffer.cursor;
        if (cr.col > 0) buffer.cursor = Pos(cr.row, cr.col - 1);
        return;
      case 'i':
      case 'c':
        break;
    }
    if (a.insertText.isNotEmpty) {
      buffer.insertAt(buffer.cursor, a.insertText);
    }
    // Land cursor at the end of the inserted text minus one (vim semantics).
    final c = buffer.cursor;
    if (c.col > 0) buffer.cursor = Pos(c.row, c.col - 1);
  }
}
