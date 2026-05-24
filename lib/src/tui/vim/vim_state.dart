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
