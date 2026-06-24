import 'jumplist.dart';
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
  operatorMotion,   // [count][op]{motion}
  operatorDouble,   // dd / yy / cc
  singleEdit,       // x X D C J p P s S Y ~ (no operand)
  replaceChar,      // r{ch}
  insertSession,    // i/I/a/A/o/O/s/S/cc/C + typed text
}

/// Captured payload of the last mutating action. Replayed by `.`.
class LastAction {
  LastActionKind kind = LastActionKind.none;
  int count = 1;
  String register = '"';
  String operator = '';
  int motionCount = 1;
  String motion = '';
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
    singleEdit = '';
    replaceCharCh = '';
    insertEntry = '';
    insertText = '';
  }
}

/// Mutable per-engine state. One instance backs the entire TUI.
class VimState {
  VimState({RegisterBank? registers})
      : registers = registers ?? RegisterBank();

  VimMode mode = VimMode.insert;

  /// Pending count (e.g. "3" in `3dw`). 0 means "no count typed".
  int pendingCount = 0;

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

  /// Tab width / shift width for `>` `<`.
  int shiftWidth = 2;

  void clearPending() {
    pendingCount = 0;
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
