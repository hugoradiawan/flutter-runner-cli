import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

/// Watches a directory tree for `.dart` file changes and emits a debounced
/// notification suitable for triggering a hot reload.
class DartFileWatcher {
  DartFileWatcher({
    required this.root,
    this.debounce = const Duration(milliseconds: 250),
  });

  final String root;
  final Duration debounce;

  DirectoryWatcher? _watcher;
  StreamSubscription<WatchEvent>? _sub;
  Timer? _timer;
  final StreamController<void> _onChange = StreamController<void>.broadcast();

  Stream<void> get onChange => _onChange.stream;

  void start() {
    _watcher = DirectoryWatcher(root);
    _sub = _watcher!.events.listen(_handle);
  }

  void _handle(WatchEvent event) {
    if (!event.path.endsWith('.dart')) return;
    if (_excluded(event.path)) return;
    _timer?.cancel();
    _timer = Timer(debounce, () => _onChange.add(null));
  }

  bool _excluded(String path) {
    final rel = p.relative(path, from: root);
    final parts = p.split(rel);
    return parts.any((s) => s == '.dart_tool' || s == 'build' || s == '.fvm');
  }

  Future<void> dispose() async {
    _timer?.cancel();
    await _sub?.cancel();
    await _onChange.close();
  }
}
