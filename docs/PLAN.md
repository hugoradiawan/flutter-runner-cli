# Flutter Runner CLI (`frun`) — Implementation Plan

## Context

Greenfield repo (`flutter-runner-cli`) currently has only `.gitattributes`. The goal is to build an open-source Dart package that publishes a `frun` executable: a TUI app that gives Flutter developers the same workflow a VS Code Flutter extension provides — device picking, launching, hot reload/restart, DevTools, isolate inspection, jump-to-source — but inside a terminal, with no AI features. Look-and-feel inspiration: Claude Code's TUI (persistent input line, scrollable transcript, slash commands, status footer).

Confirmed design decisions (this session):
- **TUI library:** `dart_tui` (Tea-style Model/Msg/Cmd, Canvas painter,
  mouse + alt-screen, easy for OSS contributors to extend).
- **Config:** global only at `~/.config/frun/config.yaml` (Windows: `%APPDATA%\frun\config.yaml`).
- **`/run` discovery:** parse `.vscode/launch.json` (`type: dart`) AND auto-detect `lib/**main*.dart` files with a `main()`.
- **Open-in-IDE:** shell out to the configured IDE CLI (`code -g file:line:col`, `zed file:line:col`). DTD integration deferred.

> Status: milestones 1–11 in the list below are implemented in `lib/src/`.
> The TUI now also supports concurrent `flutter run` sessions as a tab
> strip (see `app/run_controller.dart`, `app/run_tab.dart`) — every `/run`
> opens or focuses a tab, and file saves hot-reload every running tab.

## Goals

- One command (`frun`) to launch a TUI from any Flutter project root.
- Manage devices and emulators (list, select, launch, create).
- Run a Flutter app via the daemon; surface logs, hot reload on save, hot restart on demand.
- Launch DevTools and surface its URL when the app is running.
- Inspect Dart isolates (a "call-stack-like" pane): list, status, pause, resume, step, kill.
- Jump-to-source from widget-inspector picks and from stack frames in error output via the user's IDE.
- Slash-command palette (`/run`, `/devices`, `/emulators`, `/devtools`, `/restart`, `/quit`, `/help`, `/config`, …).
- Vim or normal editor mode for the input line.
- Runs on macOS and Windows (Linux as a free byproduct).

## Non-Goals

- No AI features.
- No source editing inside the TUI (we shell out to the user's IDE).
- No remote debugging UI beyond what the Dart VM service already exposes.
- No bundled DevTools UI — we point the browser at the served URL.

## Architecture

Layered, with the TUI as a thin renderer over a service layer:

```
┌──────────────────────────────────────────────────────────┐
│ TUI shell (dart_tui)                                      │
│   panels: Transcript · Status · Devices · Isolates · Cmd  │
└──────────────────────────────────────────────────────────┘
                       │ events / view-model
┌──────────────────────────────────────────────────────────┐
│ App state (ChangeNotifier-style streams)                  │
└──────────────────────────────────────────────────────────┘
   │            │              │              │
┌──────┐  ┌──────────┐  ┌────────────┐  ┌──────────────┐
│Config│  │ Flutter  │  │ VM Service │  │ FS watcher / │
│ I/O  │  │ Daemon   │  │ (vm_service)│ │ IDE launcher │
└──────┘  └──────────┘  └────────────┘  └──────────────┘
```

Each external integration is wrapped behind a Dart interface so tests can swap in fakes.

## Tech Stack

| Concern | Package |
|---|---|
| TUI | `dart_tui` |
| CLI parsing | `args` |
| Flutter daemon JSON-RPC | spawn `flutter daemon` + `flutter run --machine`, custom JSON-RPC client over stdio (the daemon framing is line-delimited `[{...}]`) |
| VM service | `vm_service` (official) |
| File watching | `watcher` |
| YAML config | `yaml` + `yaml_writer` |
| Path / platform | `path`, `io` |
| Process | `dart:io` `Process.start` |
| Logging | `logging` |
| Testing | `test`, `mocktail` |

Pin `meta`, `collection` at whatever `dart_tui` requires.

## Project Structure

```
flutter-runner-cli/
  bin/
    frun.dart                    # CLI entry — args parsing, calls runFrun()
  lib/
    frun.dart                    # public library entry — runFrun()
    src/
      version.dart               # frunVersion constant
      app/
        app_state.dart           # global observable state
        transcript.dart          # transcript buffer + line models
        link_extractor.dart      # path:line[:col] regex extractor
        run_controller.dart      # owns RunTab list (multi-device tabs)
        run_tab.dart             # one concurrent flutter run session
        commands/                # slash-command handlers
          command.dart           # SlashCommand + CommandResult
          command_registry.dart
          run_command.dart
          reload_command.dart    # /reload, /restart, /stop
          devices_command.dart
          emulators_command.dart
          devtools_command.dart
          isolates_command.dart
          inspect_command.dart
          status_command.dart    # toggles status panel
          config_command.dart
          clear_command.dart
          quit_command.dart
          help_command.dart
      config/
        config.dart              # model + enums
        config_store.dart        # load/save YAML at ~/.config/frun/
      project/
        project_detector.dart    # find pubspec, .vscode, lib/main*.dart
        launch_config.dart       # parse .vscode/launch.json
        main_scanner.dart        # scan lib/ for files with main()
      daemon/
        flutter_daemon.dart      # spawn + JSON-RPC over stdio
        daemon_messages.dart     # typed request/response/event models
        app_session.dart         # one running app (appId, vmServiceUri…)
      devices/
        device_manager.dart
        emulator_manager.dart
      vm/
        isolate_manager.dart     # vm_service wrapper, pause/resume/step
      watcher/
        dart_file_watcher.dart   # debounce, ignores .dart_tool/build/
      ide/
        ide_launcher.dart        # code/zed CLI dispatch
        source_location.dart
        inspector_bridge.dart    # VM-service inspector selection → IDE
      tui/
        frun_app.dart            # top-level TeaModel (layout, paint, input)
        theme.dart
        input_controller.dart    # normal-mode prompt buffer
        transcript_cursor.dart   # vim cursor over the rendered transcript
        hit_regions.dart         # mouse hit-test table
        clipboard.dart           # OSC52 + system clipboard helpers
        vim/                     # engine, motions, operators, text objects,
                                 # marks, jumplist, registers, ex parser, …
  test/
    ...                          # commands, config, daemon, launch_config,
                                 # link_extractor, ide_launcher, vim/, …
  tool/
    reinstall.dart               # nukes + reactivates the pub-global snapshot
  pubspec.yaml                   # declares `executables: { frun: frun }`
  README.md
  CHANGELOG.md
  LICENSE                        # MIT (OSS-friendly)
```

## TUI Layout

```
┌─ frun · my_app ──────────────────────────────────────────────────────────┐
│ Transcript (full-width, borderless; logs, command output, daemon events) │
│                                                                          │
│ ─ Status (optional, toggled by /status) ──────────────────────────────── │
│ Device:    iPhone 15 sim                                                 │
│ Launch:    dev                                                           │
│ VM service: ws://127.0.0.1:54331/…                                       │
│ DevTools:  http://127.0.0.1:9100/?uri=…                                  │
│                                                                          │
│ ─ Launch picker (only while open) ──────────────────────────────────── x │
│ ┌─────────────────────────────────────────────────────────────────────┐  │
│ │  [ 0] dev   debug · emulator-5554                                   │  │
│ │  [ 1] prod  release                                                 │  │
│ └─────────────────────────────────────────────────────────────────────┘  │
│ [ 1: dev · emulator-5554 ][ r ][ R ][ S ]  [+ Run]    my_app  dev:emul…  │
│ > /run_                                                                  │
│ ↑↓ scroll · ^↑↓ half · esc cursor · click tabs · ^t next tab · ^c quit   │
└──────────────────────────────────────────────────────────────────────────┘
```

- **Transcript panel** full-width, scrollable, color-coded
  (info/warn/error), wrap-aware. `Tab` cycles `file.dart:line[:col]` links,
  `Enter` opens the focused one. Mouse clicks on links and clickable lines
  are handled too. With vim mode, `Esc` over an empty prompt enters a
  transcript cursor mode with `hjkl`, visual selection, yank, and search.
- **Status panel** optional; `/status` toggles a 5-row block under the
  transcript with device, launch, VM-service and DevTools URIs.
- **Launch picker** opens above the prompt when `/run` runs with no
  argument; chips are clickable, `x` (or `Esc`) closes it.
- **Tab strip** above the prompt — one tab per concurrent `flutter run`.
  Click labels to switch; per-tab `r` / `R` / `S` buttons on the active
  tab. Far right shows `{project}  dev:{id}  ide:{id}  tabs:N`.
- **Input prompt** persistent; multi-line in vim mode; slash/`:` command
  completion shown in the footer hint.
- **Footer / status bar** reflects current mode + relevant hints
  (suggestions, link nav, picker, ex/search drafts, cursor mode).

## Feature Modules — implementation notes

### 1. Bootstrap & project detection
- `bin/frun.dart` resolves CWD, walks up to nearest `pubspec.yaml`, refuses to start if it's not a Flutter project (no `flutter` in dependencies). Print a friendly error.
- Detect IDE on first run: presence of `.vscode/` → suggest `vscode`; presence of `.zed/` or no marker → ask via the first-run wizard (one-screen TUI prompt).

### 2. Config system (`lib/src/config/`)
- Single global YAML. Schema:
  ```yaml
  ide: vscode              # vscode | zed
  editor_mode: normal      # normal | vim
  theme: dark              # dark | light — frun FrunTheme
  hot_reload_on_save: true
  default_device_id: null  # remembered across sessions
  open_devtools_on_launch: ask  # always | never | ask
  ```
- `ConfigStore.load()` creates the file with defaults if absent. `/config show`, `/config path`, and `/config set <key> <value>` read/write the YAML in place via `yaml_edit` (no full rewrite).

### 3. Flutter daemon client (`lib/src/daemon/`)
- Spawn `flutter daemon` once per session for device/emulator discovery.
- Spawn `flutter run --machine <launch args>` per app launch (separate Process) — this gives `app.start`, `app.debugPort`, `app.started`, `app.devTools`, `app.log`, `app.progress`, `app.stop` events.
- Implement a small JSON-RPC framer: daemon writes lines starting with `[{` containing a single JSON object; ignore other lines. Methods we use:
  - `device.getDevices`, `device.enable`
  - `emulator.getEmulators`, `emulator.launch`, `emulator.create`
  - `app.restart` (with `fullRestart: false` → hot reload, `true` → hot restart)
  - `app.callServiceExtension` (used for `ext.flutter.inspector.*`)
  - `app.stop`, `app.detach`
  - `devtools.serve`
- Wrap each as a typed async method returning a `Future<Result>` with a per-call `id`.

### 4. Device manager
- Subscribes to `device.added` / `device.removed` events from the persistent daemon.
- Maintains an observable list; `/devices` opens a picker panel; selection persists to config.
- Status panel always shows current selection.

### 5. Emulator manager
- `/emulators` lists results from `emulator.getEmulators`.
- If list is empty, offer to run `emulator.create` (Android only — note this in the picker).
- `emulator.launch` then waits for the corresponding `device.added` and auto-selects it.

### 6. Launch configs (`/run`)
- **`launch_config.dart`** parses `.vscode/launch.json` (strip JSONC comments) and yields entries where `type == 'dart'`. Captures `name`, `program`, `args`, `flutterMode`, `toolArgs`.
- **`main_scanner.dart`** walks `lib/` (skip `.dart_tool/`, `build/`) and yields files containing a top-level `void main(` (cheap regex; good enough).
- `/run` merges both into one picker. Selection drives `flutter run --machine` arguments.
- Subsequent `/run` re-prompts; `/restart` reuses the last selection.

### 7. Run lifecycle
- On `app.start`, create an `AppSession` holding `appId`, `vmServiceUri`, `deviceId`.
- On `app.debugPort`, the VM service URI becomes available — connect `vm_service` (see §9).
- On `app.devTools`, populate status panel; if config says `always` open the URL via `url_launcher_cli` (or platform-specific `open` / `start` / `xdg-open`).
- On `app.log`, route through Transcript with stream tag (`stdout`/`stderr`).
- On `app.progress` (e.g., building), render a spinner in the status panel.
- On `app.stop`, tear down VM service client and clear session.

### 8. File watcher (hot reload trigger)
- `watcher` over `lib/` and `test/` (configurable). Debounce 250 ms. Only fires `app.restart {fullRestart:false}` for `.dart` changes when a session is active and `hot_reload_on_save` is true.
- Keyboard: `r` → hot reload, `R` → hot restart, regardless of toggle.

### 9. Isolate manager (VM service)
- Use the `vm_service` package over the WebSocket from `app.debugPort.wsUri`.
- On connect: `getVM()` → list isolates; subscribe to `Isolate` and `Debug` streams.
- For each isolate maintain `{id, name, status (running/paused/exited), pauseReason}`.
- Render in the Isolates panel; arrow keys move selection; actions:
  - `space` → pause/resume toggle (`pause` / `resume` RPCs)
  - `s` → step over, `i` → step in, `o` → step out (resume with `step` param)
  - `k` → kill (`kill` RPC)
  - `Enter` → expand into a frame list (`getStack`) shown in a side modal; selecting a frame with a `script` + `line` opens it in the IDE via §11.

### 10. DevTools (`/devtools`)
- If session active and no DevTools URI yet: send `devtools.serve` to the persistent daemon, then construct `http://host:port/?uri=<vmServiceUri>`. Print the URL in the transcript and, if config allows, open in browser.
- If no session active: print a hint to `/run` first.

### 11. IDE launcher (`lib/src/ide/ide_launcher.dart`)
- Input: `SourceLocation(file, line, column)`.
- Dispatch by configured IDE:
  - `vscode` → `code -g <abs>:<line>:<col>`
  - `zed`    → `zed <abs>:<line>:<col>`
- On Windows, resolve `code.cmd` from PATH; fall back to `%LOCALAPPDATA%\Programs\Microsoft VS Code\bin\code.cmd`. For Zed on Windows, accept the user-supplied path in config.
- Used by: widget-inspector tap handler (§12), isolate stack-frame Enter (§9), and Transcript link activation for error stacks.

### 12. Widget inspector → IDE
- When session is active, expose `/inspect` to toggle "select widget mode" by calling `ext.flutter.inspector.show` via `app.callServiceExtension`.
- Listen on the VM service for `ext.flutter.inspector.selection` extension events (alternative: poll `ext.flutter.inspector.getSelectedSummaryWidget`).
- Extract `creationLocation` (file/line/column) from the selected widget JSON and pipe through `IdeLauncher.open(...)`.

### 13. Error-link parsing
- A small regex pass over Transcript lines spots `path/to/file.dart:LINE[:COL]` and `package:foo/bar.dart:LINE:COL` patterns; uses `PackageConfig` to resolve `package:` URIs.
- Tab/Shift-Tab in the Transcript focuses links; Enter opens the focused one in IDE.

### 14. Slash-command system
- Central `CommandRegistry` keyed by name; each command declares `name`, `summary`, `usage`, `aliases`, `run(args, ctx)`.
- Input panel shows fuzzy-matched completions while typing `/`.
- Built-in set: `/run`, `/restart`, `/reload`, `/stop`, `/devices`, `/emulators`, `/devtools`, `/inspect`, `/isolates`, `/status`, `/config`, `/clear`, `/help`, `/quit`. Vim ex mode (`:cmd`) routes through the same registry.

### 15. Vim mode (input panel)
- `editor.dart` exposes an `InputController` with `mode: insert | normal | visual`.
- Implement movement (`h j k l w b 0 $`), edits (`x d{motion} c{motion} y{motion} p`), and registers for the single-line input. Multi-line not required (it's a prompt).
- Mode shows in the keybindings footer.

### 16. Cross-platform notes
- Use `Platform.isWindows` to switch line endings, ANSI handling, and path style.
- On Windows, ANSI is required: `runFrun()` refuses to start if `stdout.supportsAnsiEscapes` is false (use Windows Terminal / PowerShell 7+).
- Use `path.context` consistently — never string-concatenate paths.
- Process spawning uses `runInShell: false` everywhere except for `code.cmd`/batch files on Windows.

### 17. Nice-to-have extras (gated behind config flags)
- `/log filter <regex>` — transient filter on Transcript.
- `/screenshot` — calls `ext.flutter.takeScreenshot` and writes a PNG to CWD.
- `/perf overlay` — toggles `ext.flutter.showPerformanceOverlay`.
- `/locale <code>` — `ext.flutter.platformOverride` / locale override.
- `/theme dark|light` — switches the TUI theme live.

## Milestones (suggested PR slicing)

1. **Skeleton** — `pubspec.yaml` declaring `frun` executable, `bin/frun.dart` prints "hello", CI (analyze + test), MIT LICENSE, README. ✅
2. **Config + project detection + TUI shell** — empty panels render; `/help`, `/quit`, `/config` work. ✅
3. **Daemon client + devices** — persistent daemon, `/devices`, status panel updates. ✅
4. **Emulators** — `/emulators`, launch + auto-select; create-flow for Android. ✅
5. **Launch + run lifecycle + transcript logs + file watcher + hot reload** — `/run` flow end-to-end with reload-on-save. ✅
6. **DevTools integration** — `/devtools`, URL in status, optional auto-open, inspector bridge attached. ✅
7. **VM service / isolate panel** — list, status, pause/resume/step/kill; stack-frame open in IDE. ✅
8. **Widget inspector → IDE** — `/inspect` mode and selection navigation; DevTools-side selection covered via polling. ✅
9. **Error-link Tab navigation in Transcript**. ✅ (plus mouse clicks)
10. **Vim mode** — insert / normal / visual{char,line,block} / op-pending / replace / search / ex; transcript cursor mode; tab navigation (`gt` / `gT` / `Ngt`). ✅
11. **Multi-device tabs** — `/run` opens a tab per launch+device; shared file watcher; per-tab buttons (`r` / `R` / `S`); clickable launch picker. ✅ (added after the original list)
12. **Windows polish** — ANSI, `code.cmd`, path tests on a Windows runner in CI.
13. **Docs + GIFs + pub.dev publish**.

Each milestone is independently releasable; the package is usable from milestone 5 onward.

## Verification

- Unit tests cover: `launch.json` parser (with JSONC), `main_scanner`, daemon JSON-RPC framer, config round-trip, IDE launcher command construction (table-driven across OS × IDE), regex link extractor, vim-mode keymap.
- Integration tests using a tiny throwaway Flutter project under `test_fixtures/`: spin up the daemon against a real `flutter` SDK on CI, run the counter app on the desktop embedder (no emulator needed), assert events arrive.
- Manual smoke checklist in `docs/manual-qa.md` covering each slash command on macOS and Windows.

## Open Questions / Future Work

- **DTD support** for IDE navigation: deferred; revisit once DTD has a stable public navigate API beyond the current IDE plugins.
- **Theming hooks** for community-contributed color schemes.
- **Web/desktop run target nuances**: hot reload semantics differ on web; document caveats.
- **Plugin system** so contributors can register extra slash commands without forking.
- **Persisting transcript per-session** to `.frun/logs/` for postmortem debugging.
