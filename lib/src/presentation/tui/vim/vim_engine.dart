import 'package:dart_tui/dart_tui.dart';

import 'ex_parser.dart';
import 'motions.dart';
import 'operators.dart';
import 'text_objects.dart';
import 'vim_buffer.dart';
import 'vim_mode.dart';
import 'vim_state.dart';
part 'vim_engine.dispatch.dart';
part 'vim_engine.modes.dart';
part 'vim_engine.operate.dart';
part 'vim_engine.repeat.dart';

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
}
