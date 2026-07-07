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
