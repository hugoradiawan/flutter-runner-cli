import 'dart:async';

import 'package:path/path.dart' as p;

import '../../domain/entities/diagnostic.dart';
import 'dart_file_watcher.dart';
import 'todo_diagnostics.dart';

/// Owns the live-diagnostics pipeline: the TODO/FIXME index (seeded by an
/// isolate scan, maintained per-file by a source watcher), the analyzer-burst
/// merge, and the debounced publish. Emits the merged analyzer + TODO view on
/// [merged] and human-readable problems on [warnings]; it never touches the
/// transcript or any presentation state.
class LiveDiagnosticsCoordinator {
  LiveDiagnosticsCoordinator({
    required String projectRoot,
    required String watchRoot,
    required Stream<List<DiagnosticEntity>> analyzerDiagnostics,
    required List<DiagnosticEntity> Function() analyzerSnapshot,
    void Function(String path)? onFileChanged,
    Future<List<DiagnosticEntity>> Function(String root)? scanTodos,
    bool watchFiles = true,
    Duration publishDebounce = const Duration(milliseconds: 250),
  }) : _projectRoot = projectRoot,
       _watchRoot = watchRoot,
       _analyzerDiagnostics = analyzerDiagnostics,
       _analyzerSnapshot = analyzerSnapshot,
       _onFileChanged = onFileChanged,
       _scanTodos =
           scanTodos ??
           ((root) => scanDartTodoDiagnosticsInIsolate(root: root)),
       _watchFiles = watchFiles,
       _publishDebounce = publishDebounce,
       _todoIndex = TodoDiagnosticsIndex(root: projectRoot);

  final String _projectRoot;
  final String _watchRoot;
  final Stream<List<DiagnosticEntity>> _analyzerDiagnostics;
  final List<DiagnosticEntity> Function() _analyzerSnapshot;
  final void Function(String path)? _onFileChanged;
  final Future<List<DiagnosticEntity>> Function(String root) _scanTodos;
  final bool _watchFiles;
  final Duration _publishDebounce;

  final TodoDiagnosticsIndex _todoIndex;
  List<DiagnosticEntity> _todos = const <DiagnosticEntity>[];
  bool _todoReady = false;

  /// Dart-file changes seen before the initial isolate scan lands. Replayed
  /// against the index once it is seeded so edits made during the scan window
  /// are not lost.
  final List<(String, DartFileChangeType)> _pendingTodoChanges =
      <(String, DartFileChangeType)>[];

  StreamSubscription<List<DiagnosticEntity>>? _analyzerSub;
  DartFileWatcher? _watcher;
  StreamSubscription<void>? _watcherChangeSub;
  Timer? _publishTimer;

  final StreamController<List<DiagnosticEntity>> _merged =
      StreamController<List<DiagnosticEntity>>.broadcast();
  final StreamController<String> _warnings =
      StreamController<String>.broadcast();

  /// Merged analyzer + TODO diagnostics, one emission per analyzer settle /
  /// coalesced file-change burst.
  Stream<List<DiagnosticEntity>> get merged => _merged.stream;

  /// Human-readable warnings ("Diagnostics watcher error: …") for the caller
  /// to surface.
  Stream<String> get warnings => _warnings.stream;

  /// True once the initial whole-tree TODO scan has seeded the index.
  bool get todoReady => _todoReady;

  /// Current review-marker diagnostics (empty until [todoReady]).
  List<DiagnosticEntity> get todos => _todos;

  void start() {
    _analyzerSub = _analyzerDiagnostics.listen(
      _publish,
      onError: (Object e) => _warnings.add('Live diagnostics error: $e'),
    );

    if (_watchFiles) {
      final watcher = DartFileWatcher(
        root: _watchRoot,
        onFileChanged: _onFileChanged,
        onDartFileChanged: handleDartFileChanged,
        onWatcherError: (Object e) =>
            _warnings.add('Diagnostics watcher error: $e'),
      );
      watcher.start();
      // FS events arrive in bursts (branch switches, format-on-save sweeps);
      // coalesce them so the merge/publish pass runs once per burst, matching
      // the analysis server's own emit debounce.
      _watcherChangeSub = watcher.onChange.listen((_) => _schedulePublish());
      _watcher = watcher;
    }

    unawaited(
      _scanTodos(_projectRoot)
          .then((initialTodos) {
            _todoIndex.replaceAll(initialTodos);
            _todoReady = true;
            for (final (path, type) in _pendingTodoChanges) {
              _applyTodoChange(path, type);
            }
            _pendingTodoChanges.clear();
            _todos = _todoIndex.diagnostics;
            _publish(_analyzerSnapshot());
          })
          .catchError((Object e) {
            _warnings.add('TODO diagnostics scan failed: $e');
          }),
    );
  }

  /// Visible for testing (the watcher path needs real FS events otherwise).
  void handleDartFileChanged(String path, DartFileChangeType type) {
    if (!_isWithinRoot(_projectRoot, path)) return;
    if (!_todoReady) {
      _pendingTodoChanges.add((path, type));
    } else {
      _applyTodoChange(path, type);
    }
  }

  void _applyTodoChange(String path, DartFileChangeType type) {
    switch (type) {
      case DartFileChangeType.add:
      case DartFileChangeType.modify:
      case DartFileChangeType.other:
        _todoIndex.updateFile(path);
      case DartFileChangeType.remove:
        _todoIndex.removeFile(path);
    }
    _todos = _todoIndex.diagnostics;
  }

  void _schedulePublish() {
    _publishTimer?.cancel();
    _publishTimer = Timer(_publishDebounce, () {
      _publish(_analyzerSnapshot());
    });
  }

  void _publish(List<DiagnosticEntity> analyzerDiagnostics) {
    _merged.add(DiagnosticEntity.merge(analyzerDiagnostics, _todos));
  }

  static bool _isWithinRoot(String root, String path) {
    final normalizedRoot = p.normalize(p.absolute(root));
    final normalizedPath = p.normalize(p.absolute(path));
    return normalizedPath == normalizedRoot ||
        p.isWithin(normalizedRoot, normalizedPath);
  }

  Future<void> dispose() async {
    _publishTimer?.cancel();
    await _analyzerSub?.cancel();
    await _watcherChangeSub?.cancel();
    await _watcher?.dispose();
    await _merged.close();
    await _warnings.close();
  }
}
