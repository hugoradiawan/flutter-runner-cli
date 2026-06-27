import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

/// Watches a directory tree for `.dart` file changes and emits a debounced
/// [onChange] event suitable for triggering a hot reload.
///
/// Event-driven via `package:watcher` — native filesystem events
/// (inotify / ReadDirectoryChangesW / FSEvents) rather than polling, so idle
/// CPU stays at ~zero regardless of project size. Non-dart files and excluded
/// directories (.dart_tool, build, .fvm, .git) are filtered out so they never
/// trigger work.
class DartFileWatcher {
  DartFileWatcher({
    required this.root,
    this.debounce = const Duration(milliseconds: 250),
    this.onFileChanged,
    this.onWatcherError,
  });

  final String root;

  /// How long to coalesce a burst of file events before firing [onChange].
  final Duration debounce;

  /// Called with the path of a dart file that was added or modified.
  final void Function(String path)? onFileChanged;

  /// Called when the watcher backend reports an error.
  final void Function(Object error)? onWatcherError;

  static const Set<String> _excludedDirs = {
    '.dart_tool',
    'build',
    '.fvm',
    '.git',
  };

  StreamSubscription<WatchEvent>? _sub;
  Timer? _debounceTimer;

  final StreamController<void> _onChange = StreamController<void>.broadcast();
  Stream<void> get onChange => _onChange.stream;

  void start() {
    try {
      _sub = DirectoryWatcher(root).events.listen(
        _onEvent,
        onError: (Object e) => onWatcherError?.call(e),
      );
    } catch (e) {
      onWatcherError?.call(e);
    }
  }

  void _onEvent(WatchEvent event) {
    final path = event.path;
    if (!path.endsWith('.dart')) return;
    if (_isExcluded(path)) return;

    // A delete leaves the analyzer's last view in place and `openFile` would
    // just no-op on the missing path, so only push adds/modifies. Every change
    // (including removes) still nudges the debounced reload signal.
    if (event.type == ChangeType.ADD || event.type == ChangeType.MODIFY) {
      onFileChanged?.call(path);
    }
    _scheduleChange();
  }

  bool _isExcluded(String path) {
    final rel = p.isWithin(root, path) ? p.relative(path, from: root) : path;
    for (final segment in p.split(rel)) {
      if (_excludedDirs.contains(segment)) return true;
    }
    return false;
  }

  void _scheduleChange() {
    if (_onChange.isClosed) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () {
      if (!_onChange.isClosed) _onChange.add(null);
    });
  }

  Future<void> dispose() async {
    _debounceTimer?.cancel();
    await _sub?.cancel();
    _sub = null;
    await _onChange.close();
  }
}
