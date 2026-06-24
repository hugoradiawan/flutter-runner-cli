/// Vim modes. `opPending` is only used internally while parsing
/// `[count][reg][operator][count][motion]`; it is never the resting state.
enum VimMode {
  insert,
  normal,
  visualChar,
  visualLine,
  visualBlock,
  replace,
  opPending,
  exCmd,
  search,
}

extension VimModeLabel on VimMode {
  String get label {
    switch (this) {
      case VimMode.insert:
        return '-- INSERT --';
      case VimMode.normal:
        return '-- NORMAL --';
      case VimMode.visualChar:
        return '-- VISUAL --';
      case VimMode.visualLine:
        return '-- V-LINE --';
      case VimMode.visualBlock:
        return '-- V-BLOCK --';
      case VimMode.replace:
        return '-- REPLACE --';
      case VimMode.opPending:
        return '-- O-PENDING --';
      case VimMode.exCmd:
        return '-- EX --';
      case VimMode.search:
        return '-- SEARCH --';
    }
  }
}
