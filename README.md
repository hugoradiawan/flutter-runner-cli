# frun — Flutter Runner CLI

A terminal UI for Flutter development. Run `frun` in any Flutter project to
get device pickers, hot reload on save, DevTools links, isolate inspection,
and widget-inspector jump-to-source — without leaving your shell.

Think "the Flutter VS Code extension, but a TUI." No AI features.

```
┌─ frun · my_app ──────────────────────────  device: iPhone 15 · IDE: vscode ──┐
│ Transcript                                          │ Status                  │
│ frun 0.1.0 — type /help for commands.               │ Device:   iPhone 15 sim │
│ Project: my_app (/Users/me/dev/my_app)              │ IDE:      vscode        │
│ Detected .vscode/ → launch configs available.       │ Hot reload (save): on   │
│ > /run                                              │ Launch:   dev           │
│ Launch entries:                                     │ VM:       ws://…        │
│   [ 0] dev   main_dev.dart  launch.json  debug      │ DevTools: http://…/?uri=│
│ Pick one with `/run <index>` or `/run <name>`.      │ Isolates: 3             │
│ > /run 0                                            │                         │
│ Launching dev on emulator-5554 (lib/main_dev.dart)… │                         │
│ App started.                                        │                         │
│ VM service: ws://127.0.0.1:54331/…                  │                         │
├─────────────────────────────────────────────────────┴─────────────────────────┤
│ > /reload                                                                     │
│ enter: submit · ctrl-c: quit · pgup/pgdn: scroll              normal mode     │
└───────────────────────────────────────────────────────────────────────────────┘
```

## Status

Early development. The roadmap is in `docs/PLAN.md`. Core features (device
picking, run, hot reload, DevTools, isolate control, widget inspector,
jump-to-source) are wired; UI polish and pickers are still evolving.

## Install (from source)

```sh
git clone https://github.com/hugoradiawan/flutter-runner-cli
cd flutter-runner-cli
dart pub get
dart pub global activate --source path .
```

Make sure `~/.pub-cache/bin` is on your `PATH`. Then in any Flutter project:

```sh
frun
```

### After pulling new code

`dart pub global activate --source path` silently skips snapshot rebuilds
when `pubspec.yaml` hasn't changed, so source-only edits aren't picked up.
After a `git pull`, run:

```sh
dart run tool/reinstall.dart
```

That deletes the cached snapshot and reactivates frun in one shot.

## Slash commands

| Command | Aliases | Purpose |
|---|---|---|
| `/help`        | `/h`, `/?` | Show all commands |
| `/run [idx]`   |            | Pick a launch entry and start the app |
| `/reload`      | `/r`       | Hot reload |
| `/restart`     | `/R`       | Hot restart |
| `/stop`        |            | Stop the running app |
| `/devices`     | `/dev`     | List devices or select with `select <id>` |
| `/emulators`   | `/emu`     | List, launch, or create emulators |
| `/devtools`    | `/dt`      | Serve DevTools and print URL |
| `/isolates`    | `/iso`     | Inspect / pause / resume / step / kill Dart isolates |
| `/inspect`     | `/i`       | Toggle widget inspector (taps → IDE) |
| `/config`      |            | View or set config (`show`, `path`, `set <k> <v>`) |
| `/clear`       | `/cls`     | Clear transcript |
| `/quit`        | `/q`, `/exit` | Exit |

While the transcript is in view, `Tab` cycles through `file.dart:line[:col]`
links; pressing `Enter` (with the prompt empty) opens the focused link in
your configured IDE.

## Configuration

Global YAML at `~/.config/frun/config.yaml` (or `%APPDATA%\frun\config.yaml`
on Windows). Defaults:

```yaml
ide: vscode                    # vscode | zed
editor_mode: normal            # normal | vim
theme: dark                    # dark | light
hot_reload_on_save: true
default_device_id: null
open_devtools_on_launch: ask   # always | never | ask
```

Edit live with `/config set <key> <value>`.

### IDE jump-to-source

| IDE   | Command frun runs |
|-------|-------------------|
| vscode | `code -g file:line:col` (Windows: `code.cmd`) |
| zed    | `zed file:line:col` |

The CLI must be on your `PATH`. For VS Code: open the Command Palette and run
"Shell Command: Install 'code' command in PATH" once.

## Vim mode

`/config set editor_mode vim` switches the prompt to a small vim-style editor
(insert/normal modes). Supported in normal mode: `h j l 0 $ w b x i I a A d{w,b,$,0} c{w,b,$,0} y{w,b,$,0} p P D C`, plus a numeric count prefix.

## How it works

- A persistent `flutter daemon` process supplies devices and emulators.
- `/run` spawns `flutter run --machine` per launch and parses its JSON-RPC stream.
- File saves under `lib/` trigger debounced hot-reload requests.
- The VM service is consumed via the official `vm_service` package for
  isolate control and widget-inspector selection events.
- Devtools is served on-demand via the daemon's `devtools.serve` command.

## License

MIT — see [LICENSE](LICENSE).
