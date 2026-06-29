import 'dart:async';

import 'package:path/path.dart' as p;

import '../../data/datasources/app_session.dart';
import '../../data/models/daemon_messages.dart';
import '../../data/models/launch_config.dart';
import 'transcript.dart';

/// One concurrent `flutter run` session and the UI state that belongs to it
/// (per-tab transcript, event subscription). Tabs are owned by [RunController]
/// and rendered by the TUI in a strip just above the input field.
class RunTab {
  RunTab({required this.id, required this.entry, required this.deviceId})
    : transcript = Transcript();

  /// Stable identity assigned by [RunController] (monotonic counter).
  final int id;

  final LaunchEntry entry;
  final String deviceId;

  /// Per-tab transcript so logs from different devices don't interleave.
  final Transcript transcript;

  AppRunSession? session;
  StreamSubscription<DaemonEvent>? eventsSub;

  /// Per-tab widget-inspector "select" mode state. Each device remembers its
  /// own on/off so switching tabs doesn't desync the toggle.
  bool inspectEnabled = false;

  bool get isRunning => session != null;

  /// True after Flutter has emitted `app.start` for this session. Auto-reload
  /// must wait for this because startup/build file events can arrive before the
  /// daemon has an app id to reload.
  bool get canHotReload => session?.appId != null;

  /// Short label rendered in the tab strip. Falls back to the dart entry's
  /// basename when the launch entry has a generic name.
  String get label {
    final name = entry.name.isNotEmpty ? entry.name : p.basename(entry.program);
    return '$name · $deviceId';
  }

  /// Identity for deduping `/run` invocations — same launch on same device
  /// resolves to the same tab.
  String get dedupeKey => '${entry.name}|${entry.program}|$deviceId';
}
