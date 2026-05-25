import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Polls a directory tree for `.dart` file mtime changes and emits a debounced
/// [onChange] event suitable for triggering a hot reload.
///
/// Uses fully-async [dart:io] so the Dart event loop is never blocked.
/// Within each directory, all dart file stats are fetched in parallel via
/// [Future.wait] for speed. Excluded directories (.dart_tool, build, .fvm)
/// are skipped at the directory level so they are never traversed.
class DartFileWatcher {
  DartFileWatcher({
    required this.root,
    this.pollInterval = const Duration(milliseconds: 500),
    this.debounce = const Duration(milliseconds: 250),
    this.onFileChanged,
    this.onWatcherError,
  });

  final String root;
  final Duration pollInterval;
  final Duration debounce;

  /// Called with the path of a dart file whose mtime changed.
  final void Function(String path)? onFileChanged;

  /// Called when the poll itself throws an unexpected error.
  final void Function(Object error)? onWatcherError;

  final Map<String, int> _mtimes = {}; // path → mtime ms
  Timer? _pollTimer;
  Timer? _debounceTimer;
  bool _initialized = false;
  bool _polling = false;

  final StreamController<void> _onChange = StreamController<void>.broadcast();
  Stream<void> get onChange => _onChange.stream;

  void start() {
    _pollTimer = Timer.periodic(pollInterval, (_) => _poll());
  }

  Future<void> _poll() async {
    if (_polling || _onChange.isClosed) return;
    _polling = true;
    try {
      bool changed = false;
      final queue = <Directory>[Directory(root)];

      while (queue.isNotEmpty) {
        final dir = queue.removeLast();

        // Collect sub-dirs and dart files via async stream — never blocks.
        final subDirs = <Directory>[];
        final dartFiles = <File>[];
        try {
          await for (final entity in dir.list(followLinks: false)) {
            final name = p.basename(entity.path);
            if (entity is Directory) {
              if (name != '.dart_tool' &&
                  name != 'build' &&
                  name != '.fvm' &&
                  name != '.git') {
                subDirs.add(entity);
              }
            } else if (entity is File && name.endsWith('.dart')) {
              dartFiles.add(entity);
            }
          }
        } catch (_) {}

        queue.addAll(subDirs);

        // Stat all dart files in this directory in parallel.
        if (dartFiles.isNotEmpty) {
          final results = await Future.wait(
            dartFiles.map((f) async {
              try {
                final stat = await f.stat();
                return (f.path, stat.modified.millisecondsSinceEpoch);
              } catch (_) {
                return (f.path, -1);
              }
            }),
          );
          for (final (path, mtime) in results) {
            if (mtime < 0) continue;
            final prev = _mtimes[path];
            _mtimes[path] = mtime;
            if (_initialized && prev != null && mtime != prev) {
              changed = true;
              onFileChanged?.call(path);
            }
          }
        }
      }

      _initialized = true;
      if (changed && !_onChange.isClosed) {
        _debounceTimer?.cancel();
        _debounceTimer = Timer(debounce, () {
          if (!_onChange.isClosed) _onChange.add(null);
        });
      }
    } catch (e) {
      onWatcherError?.call(e);
    } finally {
      _polling = false;
    }
  }

  Future<void> dispose() async {
    _pollTimer?.cancel();
    _debounceTimer?.cancel();
    await _onChange.close();
  }
}
