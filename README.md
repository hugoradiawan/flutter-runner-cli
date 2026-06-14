# frun — Flutter Runner CLI

A terminal UI for Flutter development. Run `frun` in any Flutter project to
get device pickers, hot reload on save, DevTools links, isolate inspection,
multi-device tabs, and widget-inspector jump-to-source — without leaving
your shell.

Think "the Flutter VS Code extension, but a TUI." No AI features.

```
Starting flutter daemon…
frun 0.1.0 — type help for commands.
Project: my_app  (~/dev/my_app)
Detected .vscode/ → launch configs available via run.
Vim mode active — press i to type commands.
Flutter daemon ready (3 devices).
> run
Launch entries:
  [0] dev   lib/main_dev.dart   launch.json   debug
Pick one with `run <index|name>` (or click in the picker).
> run 0
Launching dev on emulator-5554 (lib/main_dev.dart)…
App started. VM service: ws://127.0.0.1:54331/…

[ 1: dev · emulator-5554 ][ r ][ R ][ S ]
┌────────────────────────────────────────────────────────────────────────┐
│ >                                           my_app  vscode  tabs:1  ►  │
└────────────────────────────────────────────────────────────────────────┘
```

## Status

Early development. The roadmap is in `docs/PLAN.md`. Core features (device
picking, run, hot reload, DevTools, isolate control, widget inspector,
multi-device tabs, jump-to-source) are wired; UI polish keeps evolving.

## Install (from source)

```sh
git clone https://github.com/hugoradiawan/flutter-runner-cli
cd flutter-runner-cli
dart run tool/install.dart
```

`install.dart` compiles a standalone native executable to your pub-cache bin
directory (`%LOCALAPPDATA%\Pub\Cache\bin` on Windows, `~/.pub-cache/bin`
elsewhere) — so `frun` launches natively with no per-run dependency resolution.
Make sure that directory is on your `PATH` (the script warns if it isn't). Then
in any Flutter project:

```sh
frun                # use the current directory
frun apps/client    # explicit path — useful in monorepos
frun --help         # show CLI flags
frun --version
```

### After pulling new code

The native exe is a build artifact — it won't reflect source edits until you
rebuild. After a `git pull` (or any local change), run:

```sh
dart run tool/install.dart
```

For a tight inner loop while hacking on frun itself, skip the build and run
from source directly:

```sh
dart run bin/frun.dart
```

## Commands

Type a command name at the prompt — no prefix.

| Command | Aliases | Purpose |
|---|---|---|
| `help`        | `h`, `?`      | Show all commands |
| `run [idx]`   |               | Pick a launch entry and start the app (opens a clickable picker if no arg) |
| `reload`      | `r`           | Hot reload the active tab |
| `restart`     | `R`           | Hot restart the active tab |
| `stop`        | `q`           | Stop the active tab (`stop all` stops every tab) |
| `detach`      | `d`           | Detach from the app — leaves it running, disconnects frun |
| `perf`        | `P`           | Toggle the performance overlay on the active tab |
| `devices`     | `dev`         | List devices or select with `select <id>` |
| `emulators`   | `emu`         | List, launch, or create emulators |
| `devtools`    | `dt`, `v`     | Serve DevTools, print URL, attach inspector bridge |
| `isolates`    | `iso`         | Inspect / pause / resume / step / kill Dart isolates |
| `inspect`     | `i`           | Toggle widget inspector (taps → IDE) |
| `status`      | `s`           | Toggle the status panel under the transcript |
| `config`      |               | View or set config (`show`, `path`, `set <k> <v>`) |
| `clear`       | `cls`, `c`    | Clear transcript |
| `quit`        | `exit`        | Exit |

In vim mode the same commands are also reachable via `:` (e.g. `:run 0`,
`:reload`, `:q`). Note: in vim mode `:q` quits, but at the prompt `q` is the
alias for `stop` — type `quit` or `exit` to leave frun.

While the transcript is in view, `Tab` cycles through `file.dart:line[:col]`
links; pressing `Enter` (with the prompt empty) opens the focused link in
your configured IDE.

## Multi-device tabs

Every `run` opens (or focuses) a tab in the strip just above the prompt.
You can run the same project on several devices at once — each tab keeps
its own transcript and session.

- Click a tab label to make it active.
- Per-tab buttons on the active tab: `r` reload, `R` restart, `S` stop.
- `Ctrl-T` cycles to the next tab. In vim mode `gt` / `gT` / `Ngt` also work.
- A file save triggers a hot reload on **every** running tab simultaneously
  (when `hot_reload_on_save` is on).
- `stop` stops the active tab; `stop all` stops every tab.
- The `[+ Run]` button at the right edge of the tab strip re-opens the
  launch picker.

## Mouse

The TUI runs with full mouse support:

- Click tab labels, per-tab buttons, the `[+ Run]` button, and launch-picker
  entries.
- Click any source link in the transcript to open it in the IDE.
- Wheel-scroll the transcript; click-drag to select text (released selection
  is copied to the system clipboard).

## Configuration

Global YAML at `~/.config/frun/config.yaml` (or `%APPDATA%\frun\config.yaml`
on Windows). Defaults:

```yaml
ide: vscode                    # vscode | zed | neovim
editor_mode: normal            # normal | vim
theme: dark                    # dark | light
hot_reload_on_save: true
open_devtools_on_launch: ask   # always | never | ask
emulator_boot: quick           # quick | cold
verbose_errors: false          # true → dump full Flutter.Error payloads instead of the compact summary
nvim_server: null              # nvim/Neovide RPC addr (for ide: neovim); null → $NVIM
```

Edit live with `config set <key> <value>`. `config path` prints the file
location; `config show` dumps the current values.

### IDE jump-to-source

| IDE   | Command frun runs |
|-------|-------------------|
| vscode | `code -g file:line:col` (Windows: `code.cmd`) |
| zed    | `zed file:line:col` |
| neovim | `nvim --server <addr> --remote-send …` into the running nvim/Neovide |

For vscode/zed the CLI must be on your `PATH`. For VS Code: open the Command
Palette and run "Shell Command: Install 'code' command in PATH" once.

### Neovim / Neovide

`ide: neovim` sends the jump to an **already-running** Neovim (or Neovide)
instead of spawning a new editor. frun finds the instance's RPC server address
this way, in order:

1. The `nvim_server` config key, if set.
2. The `$NVIM` env var — automatically set when frun runs inside an nvim or
   Neovide `:terminal`. **This is the zero-config path: just run frun from a
   `:terminal` and set `ide: neovim`.**
3. The legacy `$NVIM_LISTEN_ADDRESS`.

For a **standalone Neovide window** (frun in a separate OS terminal), start
Neovide listening and point frun at it:

```sh
neovide -- --listen 127.0.0.1:6789
# then, in frun:
# config set nvim_server 127.0.0.1:6789
# config set ide neovim
```

`nvim` must be on your `PATH`. If no server can be found, frun prints a hint
instead of opening anything.

## Vim mode

`config set editor_mode vim` switches the prompt to a small vim-style
editor with insert / normal / visual{char,line,block} / op-pending /
replace / search / ex sub-modes.

Supported in normal mode: `h j k l 0 ^ $ w b e W B E g_ gg G {} () f F t T ; ,
x X i I a A o O r R s S D C Y` plus a numeric count prefix; operators
`d c y > <` over motions and text objects (`iw aw i" a" i( a(` etc.);
registers (`"a … "z`, `"+` / `"*` for the system clipboard);
`p P` to paste; `u Ctrl-R` for undo/redo on the input buffer;
`v V Ctrl-V` for visual modes; `/` and `?` for search with `n N`;
`:` for ex commands — anything resolvable to a command works (e.g.
`:run`, `:reload`, `:devtools`, `:q`, `:wq`, `:noh`, `:reg`, `:s/foo/bar/g`).
Tab navigation: `gt` next, `gT` previous, `Ngt` jump to tab N.

With the prompt empty in vim mode, `Esc` enters **transcript cursor mode**:
`hjkl` to move, `v V Ctrl-V` to select, `y` to yank to clipboard, `/` to
search the visible transcript, `n` / `N` to step matches.

## How it works

- A persistent `flutter daemon` process supplies devices and emulators.
- `run` spawns `flutter run --machine` per launch and parses its JSON-RPC
  stream — multiple concurrent runs are kept as separate `RunTab`s.
- File saves under `lib/` trigger debounced hot-reload requests across
  every running tab.
- The VM service is consumed via the official `vm_service` package for
  isolate control and widget-inspector selection events.
- DevTools is served on-demand via the daemon's `devtools.serve` command;
  the inspector bridge attaches automatically so DevTools widget clicks
  also jump to the IDE.
- The TUI is rendered with [`dart_tui`](https://pub.dev/packages/dart_tui).

## License

MIT — see [LICENSE](LICENSE).
