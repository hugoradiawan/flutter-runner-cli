## Unreleased

- Multi-device tabs: `/run` opens a new tab per launch+device combination,
  or focuses an existing one. Per-tab transcripts and sessions; file saves
  hot-reload every running tab. `/stop` stops the active tab, `/stop all`
  stops every tab. `Ctrl-T` cycles tabs; click tab labels and the per-tab
  `r` / `R` / `S` buttons in the active tab.
- Clickable launch picker rendered above the prompt when `/run` is invoked
  with no argument; `[+ Run]` button in the tab strip re-opens it.
- `/status` (`/s`) command toggles a 5-row status panel under the
  transcript with device / launch / VM service / DevTools URIs.
- `/devtools` now also attaches the inspector bridge so widget clicks
  inside DevTools jump to the configured IDE, not just `/inspect` taps in
  the running app.
- Vim mode expanded: visual (char/line/block), op-pending, replace, search
  (`/` `?` `n` `N`), ex commands (`:` — every `/cmd` works as `:cmd`, plus
  `:q` `:wq` `:noh` `:reg` `:s/foo/bar/g`), register set incl. system
  clipboard (`"+` / `"*`), undo / redo, tab navigation (`gt` / `gT` /
  `Ngt`). With the prompt empty, `Esc` enters a transcript cursor mode
  with `hjkl` motion, visual selection, yank, and search.
- Mouse: wheel-scroll transcript, click-drag to select (copy on release),
  click source links to open in IDE.
- CLI: optional positional path argument so `frun apps/client` works in
  monorepos; `--help` and `--version` flags.

## 0.1.0

Initial release. `frun` is a Flutter-developer-focused TUI built on
`dart_tui` that:

- Detects the surrounding Flutter project and reads optional `.vscode/launch.json`.
- Speaks the `flutter daemon` JSON-RPC protocol for devices, emulators, and DevTools.
- Spawns `flutter run --machine` per app launch with full streaming logs.
- Hot-reloads on save (debounced) and exposes `/reload` / `/restart` / `/stop`.
- Connects to the VM service via `vm_service` for an isolate panel with
  pause / resume / step / kill and stack inspection.
- Toggles the widget inspector and opens tapped widget creationLocations
  in the configured IDE (VS Code or Zed) via `code -g` or `zed`.
- Extracts `file.dart:line[:col]` references from the transcript so `Tab`
  cycles focus and `Enter` opens them in the IDE.
- Ships a small vim-mode for the input prompt.
- Persists configuration globally under `~/.config/frun/` (or `%APPDATA%\frun\` on Windows).

Built and tested on macOS and Linux (Dart 3.10). Windows path is supported
in code (separate `code.cmd` handling, AppData config) and ships in CI.
