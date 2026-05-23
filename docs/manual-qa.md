# Manual QA checklist

For releases — run through this in a real Flutter project on macOS and Windows.

## Setup
- `dart pub get` succeeds.
- `dart analyze` clean.
- `dart test` green.
- `dart pub global activate --source path .` installs `frun`.

## Outside a Flutter project
- `frun` prints "No pubspec.yaml found…" and exits with code 64.

## Inside a Flutter project
- `frun` launches the TUI. Header shows project name + selected device (or `(none)`).
- `/help` lists every registered command.
- `/config show` prints config; `/config path` prints the file path.
- `/config set ide zed` persists and is shown on next `/config show`.

## Devices & emulators
- `/devices` lists connected devices after the daemon banner appears.
- `/devices select <id>` flips the status panel and is persisted.
- `/emulators` lists known emulators.
- `/emulators launch <id>` boots an emulator and auto-selects it once `device.added` fires.

## Run lifecycle
- `/run` lists entries from `.vscode/launch.json` (if any) AND `lib/**main*.dart`.
- `/run <idx>` boots the app on the selected device.
- App logs appear in the transcript.
- `app.devTools` arrives → `/devtools` URL appears in the status panel.
- Editing a `.dart` file under `lib/` triggers a hot reload within ~250 ms.
- `/reload`, `/restart`, `/stop` all behave as advertised.

## Isolates
- After app start, `/isolates` lists one or more isolates with status `running`.
- `/isolates pause <id>` flips to `paused`.
- `/isolates resume <id>` flips back.
- `/isolates stack <id>` prints frames and opens the top frame in the configured IDE.

## Widget inspector
- `/inspect` toggles select mode; tapping a widget in the running app opens the source file in the IDE at the right line.

## Transcript links
- An error like `Exception at lib/foo.dart:42:7` shows the link.
- `Tab` cycles focus through visible links.
- `Enter` (with prompt empty) opens the focused link in the IDE.

## Vim mode
- `/config set editor_mode vim` switches prompt; mode label reflects in footer.
- `Esc` returns to normal mode; `i`/`a`/`I`/`A` re-enter insert.
- `dw` deletes a word; `0`/`$` jump to ends.

## Exit
- `/quit` cleanly restores the cursor and exits.
- `Ctrl-C` also exits cleanly.
