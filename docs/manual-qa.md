# Manual QA checklist

For releases — run through this in a real Flutter project on macOS and Windows.

## Setup
- `dart pub get` succeeds.
- `dart analyze` clean.
- `dart test` green.
- `dart run tool/install.dart` installs `frun` (native exe on PATH).

## Outside a Flutter project
- `frun` prints "No pubspec.yaml found…" and exits with code 64.

## Inside a Flutter project
- `frun` launches the TUI. Info bar (right side) shows project name,
  selected device, and IDE id; tab count appears once tabs exist.
- `frun apps/sub` (or any absolute path) starts in that sub-project.
- `frun --version` prints the version and exits without touching the TUI.
- `/help` lists every registered command, with aliases.
- `/config show` prints config; `/config path` prints the file path.
- `/config set ide zed` persists and is shown on next `/config show`.
- `/status` toggles a 5-row status block under the transcript.

## Devices & emulators
- `/devices` lists connected devices after the daemon banner appears.
- `/devices select <id>` flips the status panel and is persisted.
- `/emulators` lists known emulators.
- `/emulators launch <id>` boots an emulator and auto-selects it once `device.added` fires.

## Run lifecycle
- `/run` (no arg) opens the clickable launch picker above the prompt;
  `Esc` closes it. The `[+ Run]` button on the tab strip re-opens it.
- `/run <idx>` or `/run <name>` boots the app on the selected device.
- App logs appear in the active tab's transcript.
- `app.devTools` arrives → `/devtools` URL printed; status panel (when
  visible) shows the URI.
- Editing a `.dart` file under `lib/` triggers a hot reload on every
  running tab within ~250 ms.
- `/reload`, `/restart`, `/stop` operate on the active tab.
- `/stop all` stops every tab and clears the strip.

## Multi-device tabs
- `/run` on a second device adds a new tab; `/run` on the same launch +
  device focuses the existing one (no duplicate).
- Clicking a tab label switches the active tab and its transcript.
- `Ctrl-T` cycles tabs forward; `gt` / `gT` / `Ngt` work in vim mode.
- Per-tab buttons on the active tab: `r` reload, `R` restart, `S` stop.
  Each is clickable.

## Isolates
- After app start, `/isolates` lists one or more isolates with status `running`.
- `/isolates pause <id>` flips to `paused`.
- `/isolates resume <id>` flips back.
- `/isolates stack <id>` prints frames and opens the top frame in the configured IDE.

## Widget inspector
- `/inspect` toggles select mode; tapping a widget in the running app
  opens the source file in the IDE at the right line.
- After `/devtools`, clicking a widget node in the DevTools inspector also
  opens the source in the IDE (inspector bridge polling).

## Transcript links
- An error like `Exception at lib/foo.dart:42:7` shows the link.
- `Tab` cycles focus through visible links.
- `Enter` (with prompt empty) opens the focused link in the IDE.
- Clicking a link with the mouse opens it directly.

## Mouse
- Wheel up/down scrolls the transcript.
- Left-click + drag selects; releasing copies the selection to the system
  clipboard and prints `Copied N chars.`
- Clicking tab labels, per-tab `r` / `R` / `S`, `[+ Run]`, and launch
  picker chips all dispatch as expected.

## Vim mode
- `/config set editor_mode vim` switches prompt; mode label reflects in footer.
- `Esc` returns to normal mode; `i`/`a`/`I`/`A` re-enter insert.
- `dw` deletes a word; `0`/`$` jump to ends.
- `:run`, `:reload`, `:devtools`, `:q`, `:wq`, `:noh`, `:reg`,
  `:s/foo/bar/g` all work; arbitrary `/cmd` is reachable as `:cmd`.
- `/foo` then `n` / `N` searches the input buffer; over the transcript
  the same works in cursor mode.
- `"+y` and `"*y` yank to the system clipboard; `p` pastes.
- `gt` / `gT` / `Ngt` cycle / jump to tabs.
- With the prompt empty, `Esc` enters transcript cursor mode (`hjkl`,
  `v`/`V`/`Ctrl-V`, `y`, `/`, `n`/`N`); `Esc` exits back to insert.

## Exit
- `/quit` cleanly restores the cursor and exits.
- `Ctrl-C` also exits cleanly.
