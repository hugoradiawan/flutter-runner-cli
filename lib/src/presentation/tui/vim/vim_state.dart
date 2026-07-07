import 'jumplist.dart';
import 'macro_recorder.dart';
import 'marks.dart';
import 'registers.dart';
import 'vim_buffer.dart';
import 'vim_mode.dart';

class LastSearch {
  const LastSearch(this.pattern, this.forward);
  final String pattern;
  final bool forward;
}

/// What kind of change `.` should replay.
enum LastActionKind {
  none,
  operatorMotion, // [count][op]{motion} (motion may be 2-char: gg ge gE g_)
  operatorDouble, // dd / yy / cc / guu …
  operatorTextObject, // d/c/y + iw/a(/… text object
  singleEdit, // x X D C J p P s S Y ~ (no operand)
  replaceChar, // r{ch}
  insertSession, // i/I/a/A/o/O/s/S + typed text
}

/// Captured payload of the last mutating action. Replayed by `.`.
class LastAction {
  LastActionKind kind = LastActionKind.none;
  int count = 1;
  String register = '"';
  String operator = '';
  int motionCount = 1;
  String motion = '';

  /// Target char of an f/F/t/T motion (`dfx` stores 'x').
  String findCh = '';

  /// Text-object key + inner/around flag (`diw` stores 'w', inner=true).
  String textObject = '';
  bool textObjectInner = false;
  String singleEdit = '';
  String replaceCharCh = '';
  String insertEntry = '';
  String insertText = '';

  void clear() {
    kind = LastActionKind.none;
    count = 1;
    register = '"';
    operator = '';
    motionCount = 1;
    motion = '';
    findCh = '';
    textObject = '';
    textObjectInner = false;
    singleEdit = '';
    replaceCharCh = '';
    insertEntry = '';
    insertText = '';
  }
}

/// Mutable per-engine state. One instance backs the entire TUI.
class VimState {
  VimState({RegisterBank? registers}) : registers = registers ?? RegisterBank();

  VimMode mode = VimMode.insert;

  /// Pending count (e.g. "3" in `3dw`). 0 means "no count typed".
  int pendingCount = 0;

  /// Count typed *before* an operator (`2` in `2d3w`). Moved out of
  /// [pendingCount] when the operator registers so the motion's own count
  /// accumulates separately; effective count is the product.
  int pendingOpCount = 0;

  /// Pending register selector (e.g. `"a` → 'a'). Empty when none.
  String pendingRegister = '';

  /// Pending operator (`d c y > < = ~ gu gU g~ r`). Empty when none.
  String pendingOperator = '';

  /// True when last char typed was `g` (for `gg ge gu gU g~ gd gE`).
  bool pendingG = false;

  /// True when last char was `z` (`zz zt zb`).
  bool pendingZ = false;

  /// Replace-mode prefix (used by `r{ch}` — single char then back to normal).
  bool pendingReplaceChar = false;

  /// f/t/F/T pending — collects the next char.
  String pendingFind = ''; // 'f' | 'F' | 't' | 'T'

  /// Pending mark/jump prefix: 'm' (set), '`' (jump exact), "'" (jump line).
  String pendingMarkOp = '';

  /// Visual anchor (set when entering visual mode).
  Pos? visualAnchor;

  /// Vim's curswant: the column j/k keep aiming for while passing through
  /// shorter lines. Null when the last motion wasn't vertical.
  int? desiredCol;

  /// Search prompt draft (during VimMode.search).
  String searchDraft = '';

  /// Ex-mode draft (during VimMode.exCmd).
  String exDraft = '';

  /// Last `f`/`t` (char + dir + till).
  LastFind? lastFind;

  /// Last `/`/`?`.
  LastSearch? lastSearch;

  /// Persistent storage.
  final RegisterBank registers;
  final MarkBank marks = MarkBank();
  final JumpList jumps = JumpList();
  final MacroRecorder macros = MacroRecorder();

  /// Used by `:s/old/new/` substitute history.
  String lastSubstitutePattern = '';
  String lastSubstituteReplacement = '';

  /// The most recent mutating action (for `.` repeat).
  final LastAction lastAction = LastAction();

  /// Active during an insert session opened by i/a/I/A/o/O/s/S/cc/C.
  /// The entry key is remembered so `.` can re-open the same session, and
  /// every rune typed in passInsert is appended to [insertCapture] until Esc.
  String? insertEntry;
  StringBuffer? insertCapture;

  /// Active visual-block I/A insert: the block to replicate the captured
  /// text over when the session ends. Null outside block-insert sessions.
  ({int startRow, int endRow, int col, bool append})? pendingBlockInsert;

  /// Replace-mode (`R`) session state: overwritten chars for backspace
  /// restore (null entry = char was appended past EOL), the typed capture
  /// for count replay + dot-repeat, and the `{count}R` multiplier.
  final List<(Pos, String?)> replaceStack = [];
  StringBuffer? replaceCapture;
  int replaceSessionCount = 1;

  /// Tab width / shift width for `>` `<`.
  int shiftWidth = 2;

  void clearPending() {
    pendingCount = 0;
    pendingOpCount = 0;
    pendingRegister = '';
    pendingOperator = '';
    pendingG = false;
    pendingZ = false;
    pendingReplaceChar = false;
    pendingFind = '';
    pendingMarkOp = '';
  }
}

class LastFind {
  const LastFind(this.ch, this.forward, this.till);
  final String ch;
  final bool forward;
  final bool till;
}
