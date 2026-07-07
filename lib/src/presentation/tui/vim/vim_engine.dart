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
  }) : _state = state,
       _viewport = viewport,
       _runExCmd = runExCmd,
       _runSearch = runSearch,
       _onSubmit = onSubmit,
       _onTabSwitch = onTabSwitch;

  final VimState _state;
  final ViewportProvider _viewport;
  final ExCmdRunner _runExCmd;
  final SearchRunner _runSearch;
  final SubmitHandler? _onSubmit;
  final TabSwitcher? _onTabSwitch;

  VimState get state => _state;

  KeyResult handle(KeyMsg event, VimBuffer buffer) {
    final ke = event.keyEvent;

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

    // Replace mode: typed chars overwrite, Esc exits.
    if (_state.mode == VimMode.replace) {
      if (ke.code == KeyCode.escape) {
        _enterNormal(buffer);
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
      _state.lastAction
        ..clear()
        ..kind = LastActionKind.insertSession
        ..insertEntry = _state.insertEntry!
        ..insertText = captured
        ..count = 1;
    }
    _state.insertEntry = null;
    _state.insertCapture = null;
    buffer.exitInsertMode();
    final c = buffer.cursor;
    final len = buffer.rowLength(c.row);
    if (len > 0 && c.col >= len) {
      buffer.cursor = Pos(c.row, len - 1);
    } else if (c.col > 0 && _state.mode == VimMode.insert) {
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
      if (pattern.isNotEmpty) _runSearch(pattern, dir, buffer);
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
    Operators.replaceChar(buffer, ch);
    final c = buffer.cursor;
    final len = buffer.rowLength(c.row);
    if (c.col + 1 < len) buffer.cursor = Pos(c.row, c.col + 1);
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

    // f/F/t/T pending char.
    if (_state.pendingFind.isNotEmpty) {
      final pend = _state.pendingFind;
      final forward = pend == 'f' || pend == 't';
      final till = pend == 't' || pend == 'T';
      final count = _consumeCount();
      _state.pendingFind = '';
      _state.lastFind = LastFind(ch, forward, till);
      final motion = Motions.findChar(
        buffer,
        ch,
        count,
        forward: forward,
        till: till,
      );
      _applyMotion(buffer, motion);
      return;
    }

    // r{ch} replace.
    if (_state.pendingReplaceChar) {
      buffer.pushUndo();
      Operators.replaceChar(buffer, ch);
      _state.pendingReplaceChar = false;
      _state.lastAction
        ..clear()
        ..kind = LastActionKind.replaceChar
        ..replaceCharCh = ch
        ..count = 1;
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

    // Count digits (but not when an op-pending text-object would expect a count).
    if (_isDigit(ch) &&
        !(ch == '0' &&
            _state.pendingCount == 0 &&
            _state.pendingOperator.isEmpty)) {
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
      if (range != null) _applyRangeFromMotionOrTextObject(buffer, range);
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
      // zz/zt/zb are viewport hints; we no-op at engine level (FrunModel can
      // observe state and react). Reserved for future hook.
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
        _applyMotion(buffer, Motions.left(buffer, count));
      case KeyCode.right:
        _applyMotion(buffer, Motions.right(buffer, count));
      case KeyCode.up:
        _applyMotion(buffer, Motions.up(buffer, count));
      case KeyCode.down:
        _applyMotion(buffer, Motions.down(buffer, count));
      case KeyCode.home:
        _applyMotion(buffer, Motions.lineStart(buffer));
      case KeyCode.end:
        _applyMotion(buffer, Motions.lineEnd(buffer));
      case KeyCode.escape:
        if (_isVisual()) {
          _state.mode = VimMode.normal;
          buffer.selection = null;
          buffer.visualKind = VimMode.normal;
          buffer.onModeChanged(VimMode.normal);
        }
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
        // scroll one line down — no buffer mutation here; viewport-only.
        break;
      case 'y':
        break;
      case 'r':
        buffer.redo();
        break;
      case 'c':
        if (_isVisual()) {
          _state.mode = VimMode.normal;
          buffer.selection = null;
          buffer.visualKind = VimMode.normal;
          buffer.onModeChanged(VimMode.normal);
        }
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

    // Operator pending: a motion follows.
    if (_state.pendingOperator.isNotEmpty) {
      _resolveOperatorMotion(ch, buffer, count, reg);
      return;
    }

    switch (ch) {
      // Motions ────────────────────────────────────────────────────────────
      case 'h':
        _applyMotion(buffer, Motions.left(buffer, count));
      case 'l':
        _applyMotion(buffer, Motions.right(buffer, count));
      case 'j':
        _applyMotion(buffer, Motions.down(buffer, count));
      case 'k':
        _applyMotion(buffer, Motions.up(buffer, count));
      case 'w':
        _applyMotion(buffer, Motions.nextWordStart(buffer, count));
      case 'W':
        _applyMotion(
          buffer,
          Motions.nextWordStart(buffer, count, bigWord: true),
        );
      case 'e':
        _applyMotion(buffer, Motions.wordEnd(buffer, count));
      case 'E':
        _applyMotion(buffer, Motions.wordEnd(buffer, count, bigWord: true));
      case 'b':
        _applyMotion(buffer, Motions.prevWordStart(buffer, count));
      case 'B':
        _applyMotion(
          buffer,
          Motions.prevWordStart(buffer, count, bigWord: true),
        );
      case '0':
        _applyMotion(buffer, Motions.lineStart(buffer));
      case '^':
        _applyMotion(buffer, Motions.firstNonBlank(buffer));
      case r'$':
        _applyMotion(buffer, Motions.lineEnd(buffer));
      case '%':
        _state.jumps.push(buffer.surfaceId, buffer.cursor);
        _applyMotion(buffer, Motions.matchBracket(buffer));
      case '{':
        _state.jumps.push(buffer.surfaceId, buffer.cursor);
        _applyMotion(buffer, Motions.paragraph(buffer, count, forward: false));
      case '}':
        _state.jumps.push(buffer.surfaceId, buffer.cursor);
        _applyMotion(buffer, Motions.paragraph(buffer, count, forward: true));
      case 'G':
        _state.jumps.push(buffer.surfaceId, buffer.cursor);
        final n = _state.pendingCount == 0 ? null : _state.pendingCount;
        _applyMotion(buffer, Motions.goLine(buffer, n));
      case 'H':
        final vp = _viewport(buffer);
        _applyMotion(buffer, Motions.viewportTop(buffer, vp.top));
      case 'M':
        final vp = _viewport(buffer);
        _applyMotion(buffer, Motions.viewportMiddle(buffer, vp.top, vp.height));
      case 'L':
        final vp = _viewport(buffer);
        _applyMotion(buffer, Motions.viewportBottom(buffer, vp.top, vp.height));
      case 'f':
        _state.pendingFind = 'f';
      case 'F':
        _state.pendingFind = 'F';
      case 't':
        _state.pendingFind = 't';
      case 'T':
        _state.pendingFind = 'T';
      case ';':
        final lf = _state.lastFind;
        if (lf != null) {
          _applyMotion(
            buffer,
            Motions.findChar(
              buffer,
              lf.ch,
              count,
              forward: lf.forward,
              till: lf.till,
            ),
          );
        }
      case ',':
        final lf = _state.lastFind;
        if (lf != null) {
          _applyMotion(
            buffer,
            Motions.findChar(
              buffer,
              lf.ch,
              count,
              forward: !lf.forward,
              till: lf.till,
            ),
          );
        }
      case 'n':
        _repeatSearch(buffer, forward: true);
      case 'N':
        _repeatSearch(buffer, forward: false);

      // Edits / operators ──────────────────────────────────────────────────
      case 'i':
        _enterInsert(buffer, entry: 'i');
      case 'I':
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
        buffer.cursor = Pos(
          buffer.cursor.row,
          buffer.rowLength(buffer.cursor.row),
        );
        _enterInsert(buffer, entry: 'A');
      case 'o':
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
        buffer.pushUndo();
        Operators.paste(buffer, _state.registers.read(reg), before: false);
        _captureSingleEdit('p', count, reg);
      case 'P':
        buffer.pushUndo();
        Operators.paste(buffer, _state.registers.read(reg), before: true);
        _captureSingleEdit('P', count, reg);
      case 'r':
        _state.pendingReplaceChar = true;
      case 'R':
        buffer.pushUndo();
        _state.mode = VimMode.replace;
        buffer.onModeChanged(VimMode.replace);
      case 'J':
        if (buffer.isEditable) {
          buffer.pushUndo();
          Operators.joinLines(buffer, count);
          _captureSingleEdit('J', count, reg);
        }
      case '~':
        if (buffer.isEditable) {
          buffer.pushUndo();
          final c = buffer.cursor;
          final range = Range(c, c, RangeKind.charwise);
          Operators.toggleCase(buffer, range);
          if (c.col + 1 < buffer.rowLength(c.row)) {
            buffer.cursor = Pos(c.row, c.col + 1);
          }
          _captureSingleEdit('~', count, reg);
        }
      case 'u':
        if (buffer.undo()) {
          // OK
        }
      case '.':
        _replayLastAction(buffer);
      case 'v':
        _toggleVisual(buffer, VimMode.visualChar);
      case 'V':
        _toggleVisual(buffer, VimMode.visualLine);
      case 'd':
        if (_isVisual()) {
          _applyVisualOperator(buffer, 'd', reg);
        } else {
          _state.pendingOperator = 'd';
          return;
        }
      case 'c':
        if (_isVisual()) {
          _applyVisualOperator(buffer, 'c', reg);
        } else {
          _state.pendingOperator = 'c';
          return;
        }
      case 'y':
        if (_isVisual()) {
          _applyVisualOperator(buffer, 'y', reg);
        } else {
          _state.pendingOperator = 'y';
          return;
        }
      case '>':
        if (_isVisual()) {
          _applyVisualOperator(buffer, '>', reg);
        } else {
          _state.pendingOperator = '>';
          return;
        }
      case '<':
        if (_isVisual()) {
          _applyVisualOperator(buffer, '<', reg);
        } else {
          _state.pendingOperator = '<';
          return;
        }
      case '=':
        if (_isVisual()) {
          _applyVisualOperator(buffer, '=', reg);
        } else {
          _state.pendingOperator = '=';
          return;
        }
      case 'm':
        _state.pendingMarkOp = 'm';
      case "'":
        _state.pendingMarkOp = "'";
      case '`':
        _state.pendingMarkOp = '`';

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

  /// Resolve an operator + motion pair (`{count}{op}{motion}`).
  void _resolveOperatorMotion(
    String ch,
    VimBuffer buffer,
    int count,
    String reg,
  ) {
    // `dd` / `yy` / `cc` — operator doubled = whole line(s).
    if (ch == _state.pendingOperator) {
      final op = _state.pendingOperator;
      _applyLinewiseOperator(buffer, op, count, reg);
      if (op != 'y') {
        _state.lastAction
          ..clear()
          ..kind = LastActionKind.operatorDouble
          ..operator = op
          ..count = count
          ..register = reg;
      }
      _state.pendingOperator = '';
      _state.pendingCount = 0;
      _state.pendingRegister = '';
      return;
    }

    MotionResult? motion;
    switch (ch) {
      case 'h':
        motion = Motions.left(buffer, count);
      case 'l':
        motion = Motions.right(buffer, count);
      case 'j':
        motion = Motions.down(buffer, count);
      case 'k':
        motion = Motions.up(buffer, count);
      case 'w':
        motion = Motions.nextWordStart(buffer, count);
      case 'W':
        motion = Motions.nextWordStart(buffer, count, bigWord: true);
      case 'e':
        motion = Motions.wordEnd(buffer, count);
      case 'E':
        motion = Motions.wordEnd(buffer, count, bigWord: true);
      case 'b':
        motion = Motions.prevWordStart(buffer, count);
      case 'B':
        motion = Motions.prevWordStart(buffer, count, bigWord: true);
      case '0':
        motion = Motions.lineStart(buffer);
      case '^':
        motion = Motions.firstNonBlank(buffer);
      case r'$':
        motion = Motions.lineEnd(buffer);
      case '%':
        motion = Motions.matchBracket(buffer);
      case 'G':
        motion = Motions.goLine(
          buffer,
          _state.pendingCount == 0 ? null : _state.pendingCount,
        );
      case '{':
        motion = Motions.paragraph(buffer, count, forward: false);
      case '}':
        motion = Motions.paragraph(buffer, count, forward: true);
      default:
        // Not a motion (could be text-object prefix `i`/`a`, handled earlier).
        return;
    }

    final op = _state.pendingOperator;
    final motionCount = count;
    final range = _rangeFromMotion(buffer.cursor, motion);
    _runOperator(op, buffer, range, reg);
    if (op != 'y') {
      _state.lastAction
        ..clear()
        ..kind = LastActionKind.operatorMotion
        ..operator = op
        ..motion = ch
        ..count = 1
        ..motionCount = motionCount
        ..register = reg;
    }
    _state.pendingOperator = '';
    _state.pendingCount = 0;
    _state.pendingRegister = '';
  }

  Range _rangeFromMotion(Pos from, MotionResult motion) {
    if (motion.kind == RangeKind.linewise) {
      return Range(
        Pos(from.row, 0),
        Pos(motion.target.row, 0),
        RangeKind.linewise,
      );
    }
    if (motion.exclusive) {
      // Motion target is exclusive — back off by one before forming range.
      final t = motion.target;
      Pos endInclusive;
      if (t >= from) {
        endInclusive = Pos(t.row, (t.col - 1).clamp(0, 1 << 30));
      } else {
        endInclusive = t;
      }
      return Range(from, endInclusive, RangeKind.charwise);
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

  void _applyRangeFromMotionOrTextObject(VimBuffer buffer, Range range) {
    if (_isVisual()) {
      buffer.selection = range;
      buffer.cursor = range.end;
      return;
    }
    if (_state.pendingOperator.isEmpty) return;
    final reg = _state.pendingRegister.length == 1
        ? _state.pendingRegister
        : '"';
    final op = _state.pendingOperator;
    _runOperator(op, buffer, range, reg);
    _state.pendingOperator = '';
    _state.pendingCount = 0;
    _state.pendingRegister = '';
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
    _runOperator(op, buffer, sel, reg);
    _state.mode = VimMode.normal;
    buffer.selection = null;
    buffer.visualKind = VimMode.normal;
    buffer.onModeChanged(VimMode.normal);
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
      _state.mode = VimMode.normal;
      buffer.selection = null;
      buffer.visualKind = VimMode.normal;
      buffer.onModeChanged(VimMode.normal);
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
      case 'g':
        _state.jumps.push(buffer.surfaceId, buffer.cursor);
        _applyMotion(buffer, Motions.firstLine(buffer));
      case 'e':
        _applyMotion(buffer, Motions.prevWordEnd(buffer, _consumeCount()));
      case 'E':
        _applyMotion(
          buffer,
          Motions.prevWordEnd(buffer, _consumeCount(), bigWord: true),
        );
      case 'u':
        _state.pendingOperator = 'gu';
      case 'U':
        _state.pendingOperator = 'gU';
      case '~':
        _state.pendingOperator = '~';
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
      case '_':
        _applyMotion(buffer, Motions.lastNonBlank(buffer));
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

  void _repeatSearch(VimBuffer buffer, {required bool forward}) {
    final ls = _state.lastSearch;
    if (ls == null || ls.pattern.isEmpty) return;
    final dir = forward ? ls.forward : !ls.forward;
    _runSearch(ls.pattern, dir, buffer);
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
    if (!buffer.isEditable && a.kind != LastActionKind.none) return;
    switch (a.kind) {
      case LastActionKind.none:
        return;
      case LastActionKind.operatorMotion:
        _state.pendingOperator = a.operator;
        _state.pendingCount = a.motionCount;
        _state.pendingRegister = a.register == '"' ? '' : a.register;
        _resolveOperatorMotion(a.motion, buffer, a.motionCount, a.register);
      case LastActionKind.operatorDouble:
        _applyLinewiseOperator(buffer, a.operator, a.count, a.register);
      case LastActionKind.singleEdit:
        _replaySingleEdit(buffer, a);
      case LastActionKind.replaceChar:
        buffer.pushUndo();
        Operators.replaceChar(buffer, a.replaceCharCh);
      case LastActionKind.insertSession:
        _replayInsertSession(buffer, a);
    }
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
        Operators.paste(buffer, _state.registers.read(reg), before: false);
      case 'P':
        Operators.paste(buffer, _state.registers.read(reg), before: true);
      case '~':
        final c = buffer.cursor;
        Operators.toggleCase(buffer, Range(c, c, RangeKind.charwise));
        if (c.col + 1 < buffer.rowLength(c.row)) {
          buffer.cursor = Pos(c.row, c.col + 1);
        }
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
