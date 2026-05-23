# 📊 Graph Analysis Report

**Root:** `lib`

## Summary

| Metric | Value |
|--------|-------|
| Nodes | 249 |
| Edges | 208 |
| Communities | 41 |
| Hyperedges | 0 |

### Confidence Breakdown

| Level | Count | Percentage |
|-------|-------|------------|
| EXTRACTED | 208 | 100.0% |
| INFERRED | 0 | 0.0% |
| AMBIGUOUS | 0 | 0.0% |

## 🌟 God Nodes (Most Connected)

| Node | Degree | Community |
|------|--------|-----------|
| frun | 25 | 0 |
| frun_app | 18 | 1 |
| run_controller | 12 | 2 |
| input_controller | 9 | 3 |
| app_state | 9 | 4 |
| app_session | 8 | 7 |
| isolate_manager | 8 | 5 |
| flutter_daemon | 7 | 8 |
| run_command | 7 | 9 |
| isolates_command | 6 | 10 |

## 🔮 Surprising Connections

_No surprising connections found._

## 🏘️ Communities

### Community 0 — runFrun() (26 nodes, cohesion: 0.08)

- frun
- _bootDaemon()
- dart:async
- dart:io
- package:dart_tui/dart_tui.dart
- src/app/app_state.dart
- src/app/commands/clear_command.dart
- src/app/commands/command_registry.dart
- src/app/commands/config_command.dart
- src/app/commands/devices_command.dart
- src/app/commands/devtools_command.dart
- src/app/commands/emulators_command.dart
- src/app/commands/help_command.dart
- src/app/commands/inspect_command.dart
- src/app/commands/isolates_command.dart
- src/app/commands/quit_command.dart
- src/app/commands/reload_command.dart
- src/app/commands/run_command.dart
- src/app/commands/status_command.dart
- src/config/config_store.dart
- _…and 6 more_

### Community 1 — _ModSetExt (19 nodes, cohesion: 0.11)

- frun_app
- ../app/app_state.dart
- ../app/commands/command.dart
- ../app/commands/command_registry.dart
- ../app/link_extractor.dart
- ../app/run_tab.dart
- ../app/transcript.dart
- clipboard.dart
- ../config/config.dart
- dart:async
- dart:math'
- hit_regions.dart
- ../ide/source_location.dart
- input_controller.dart
- package:dart_tui/dart_tui.dart
- theme.dart
- transcript_cursor.dart
- ../version.dart
- _ModSetExt

### Community 2 — tabs() (13 nodes, cohesion: 0.15)

- run_controller
- _activeIndex()
- activeTab()
- hotReloadTab()
- hotRestartTab()
- app_state.dart
- ../daemon/app_session.dart
- ../daemon/daemon_messages.dart
- dart:async
- ../project/launch_config.dart
- run_tab.dart
- ../watcher/dart_file_watcher.dart
- tabs()

### Community 3 — _text() (10 nodes, cohesion: 0.20)

- input_controller
- _cursor()
- _editorMode()
- ../config/config.dart
- package:dart_tui/dart_tui.dart
- InputAction
- _mode()
- RegExp()
- _text()
- VimMode

### Community 4 — _config() (10 nodes, cohesion: 0.20)

- app_state
- _config()
- ../config/config.dart
- ../daemon/flutter_daemon.dart
- ../devices/device_manager.dart
- ../ide/ide_launcher.dart
- ../project/project_detector.dart
- run_controller.dart
- transcript.dart
- ../vm/isolate_manager.dart

### Community 5 — _service() (9 nodes, cohesion: 0.22)

- isolate_manager
- _changes()
- _extensionStream()
- dart:async
- package:vm_service/vm_service.dart'
- package:vm_service/vm_service_io.dart
- _isolates()
- IsolateStatus
- _service()

### Community 6 — .name() (9 nodes, cohesion: 0.22)

- config
- FrunDevToolsAutoOpen
- .name()
- FrunEditorMode
- .name()
- FrunIde
- .name()
- FrunThemeMode
- .name()

### Community 7 — _process() (9 nodes, cohesion: 0.22)

- app_session
- _events()
- daemon_messages.dart
- dart:async
- dart:convert
- dart:io
- package:path/path.dart'
- ../project/launch_config.dart
- _process()

### Community 8 — _stderrLines() (8 nodes, cohesion: 0.25)

- flutter_daemon
- _events()
- _executable()
- daemon_messages.dart
- dart:async
- dart:convert
- dart:io
- _stderrLines()

### Community 9 — ../run_controller.dart (8 nodes, cohesion: 0.25)

- run_command
- ../app_state.dart
- command.dart
- dart:io
- package:path/path.dart'
- ../../project/launch_config.dart
- ../../project/main_scanner.dart
- ../run_controller.dart

### Community 10 — ../../vm/isolate_manager.dart (7 nodes, cohesion: 0.29)

- isolates_command
- ../app_state.dart
- command.dart
- ../../ide/ide_launcher.dart
- ../../ide/source_location.dart
- package:vm_service/vm_service.dart'
- ../../vm/isolate_manager.dart

### Community 11 — transcript.dart (7 nodes, cohesion: 0.29)

- run_tab
- ../daemon/app_session.dart
- ../daemon/daemon_messages.dart
- dart:async
- package:path/path.dart'
- ../project/launch_config.dart
- transcript.dart

### Community 12 — _commandFor() (6 nodes, cohesion: 0.33)

- ide_launcher
- _commandFor()
- ../app/app_state.dart
- ../config/config.dart
- dart:io
- source_location.dart

### Community 13 — package:vm_service/vm_service.dart' (6 nodes, cohesion: 0.33)

- inspect_command
- ../app_state.dart
- command.dart
- dart:async
- ../../ide/source_location.dart
- package:vm_service/vm_service.dart'

### Community 14 — _revision() (6 nodes, cohesion: 0.33)

- transcript
- _add()
- dart:collection
- List()
- _revision()
- TranscriptLevel

### Community 15 — p() (5 nodes, cohesion: 0.40)

- project_detector
- dart:io
- package:path/path.dart'
- package:yaml/yaml.dart
- p()

### Community 16 — dart:io (5 nodes, cohesion: 0.40)

- devtools_command
- ../app_state.dart
- command.dart
- ../../config/config.dart
- dart:io

### Community 17 — _onChange() (5 nodes, cohesion: 0.40)

- dart_file_watcher
- dart:async
- package:path/path.dart'
- package:watcher/watcher.dart
- _onChange()

### Community 18 — FrunTheme() (5 nodes, cohesion: 0.40)

- theme
- FrunTheme()
- ../app/transcript.dart
- ../config/config.dart
- package:dart_tui/dart_tui.dart

### Community 19 — ../../config/config_store.dart (19) (5 nodes, cohesion: 0.40)

- config_command
- ../app_state.dart
- command.dart
- ../../config/config.dart
- ../../config/config_store.dart

### Community 20 — package:yaml/yaml.dart (5 nodes, cohesion: 0.40)

- config_store
- config.dart
- dart:io
- package:path/path.dart'
- package:yaml/yaml.dart

### Community 21 — ../../devices/emulator_manager.dart (5 nodes, cohesion: 0.40)

- emulators_command
- ../app_state.dart
- command.dart
- ../../config/config_store.dart
- ../../devices/emulator_manager.dart

### Community 22 — _changes() (5 nodes, cohesion: 0.40)

- device_manager
- _changes()
- ../daemon/daemon_messages.dart
- ../daemon/flutter_daemon.dart
- dart:async

### Community 23 — _daemon() (5 nodes, cohesion: 0.40)

- emulator_manager
- _daemon()
- ../daemon/daemon_messages.dart
- ../daemon/flutter_daemon.dart
- dart:async

### Community 24 — command_registry.dart (4 nodes, cohesion: 0.50)

- help_command
- ../app_state.dart
- command.dart
- command_registry.dart

### Community 25 — LaunchEntrySource (4 nodes, cohesion: 0.50)

- launch_config
- dart:convert
- dart:io
- LaunchEntrySource

### Community 26 — package:path/path.dart' (4 nodes, cohesion: 0.50)

- main_scanner
- dart:io
- launch_config.dart
- package:path/path.dart'

### Community 27 — package:path/path.dart' (27) (4 nodes, cohesion: 0.50)

- source_location
- dart:convert
- dart:io
- package:path/path.dart'

### Community 28 — ../../config/config_store.dart (4 nodes, cohesion: 0.50)

- devices_command
- ../app_state.dart
- command.dart
- ../../config/config_store.dart

### Community 29 — ../run_controller.dart (29) (4 nodes, cohesion: 0.50)

- reload_command
- ../app_state.dart
- command.dart
- ../run_controller.dart

### Community 30 — run() (3 nodes, cohesion: 0.67)

- command
- ../app_state.dart
- run()

### Community 31 — copyToClipboard() (3 nodes, cohesion: 0.67)

- clipboard
- copyToClipboard()
- dart:io

### Community 32 — command.dart (3 nodes, cohesion: 0.67)

- status_command
- ../app_state.dart
- command.dart

### Community 33 — FlutterEmulator() (3 nodes, cohesion: 0.67)

- daemon_messages
- FlutterDevice()
- FlutterEmulator()

### Community 34 — _byName() (3 nodes, cohesion: 0.67)

- command_registry
- _byName()
- command.dart

### Community 35 — _regions() (3 nodes, cohesion: 0.67)

- hit_regions
- package:dart_tui/dart_tui.dart
- _regions()

### Community 36 — command.dart (36) (3 nodes, cohesion: 0.67)

- quit_command
- ../app_state.dart
- command.dart

### Community 37 — command.dart (37) (3 nodes, cohesion: 0.67)

- clear_command
- ../app_state.dart
- command.dart

### Community 38 — transcript_cursor (1 nodes, cohesion: 1.00)

- transcript_cursor

### Community 39 — link_extractor (1 nodes, cohesion: 1.00)

- link_extractor

### Community 40 — version (1 nodes, cohesion: 1.00)

- version

## 🕳️ Knowledge Gaps

**Isolated nodes** (3):
- link_extractor
- transcript_cursor
- version

**Thin communities** (< 3 nodes): 3 communities

## 💰 Token Cost

| File | Tokens |
|------|--------|
| output | 0 |
| input | 0 |
| **Total** | **0** |

## ❓ Suggested Questions

1. What role does 'transcript_cursor' play? It has no connections in the graph.
1. What role does 'link_extractor' play? It has no connections in the graph.
1. What role does 'version' play? It has no connections in the graph.
1. Why is '_service()' (9 nodes) loosely connected (cohesion 0.22)? Should it be split?
1. Why is 'transcript.dart' (7 nodes) loosely connected (cohesion 0.29)? Should it be split?
1. Why is 'tabs()' (13 nodes) loosely connected (cohesion 0.15)? Should it be split?
1. Why is '_process()' (9 nodes) loosely connected (cohesion 0.22)? Should it be split?

---
_Generated by graphify-rs_
