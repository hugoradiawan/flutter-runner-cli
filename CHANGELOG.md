## 0.1.0

Initial release. `frun` is a Flutter-developer-focused TUI built on
`utopia_tui` that:

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
