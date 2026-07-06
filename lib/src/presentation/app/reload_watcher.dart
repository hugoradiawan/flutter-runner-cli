import 'dart:async';

import '../../domain/ports/source_change_watcher.dart';
import 'app_state.dart';

/// Shared `.dart` file watcher. When any watched file is saved and at least one
/// session is running, [onReload] fires to hot-reload every running tab.
///
/// The watcher is created lazily on the first running session ([ensure]) and
/// torn down once the controller goes idle ([disposeIfIdle]).
class ReloadWatcher {
  ReloadWatcher(
    this._state, {
    required this.anyRunning,
    required this.onReload,
  });

  final AppState _state;

  /// True while at least one tab has a live session.
  final bool Function() anyRunning;

  /// Invoked (fire-and-forget) when a save should trigger a reload.
  final Future<void> Function() onReload;

  SourceChangeWatcher? _watcher;

  void ensure() {
    if (!_state.config.hotReloadOnSave) return;
    if (_watcher != null) return;
    // Watch the repo/workspace root so monorepo feature packages are included.
    final root = _state.project.watchRoot;
    _state.visibleTranscript.system('File watcher started on $root');
    final watcher = _state.deps.sourceWatcherFactory(
      root: root,
      onFileChanged: (path) {
        _state.visibleTranscript.system('[watcher] changed: $path');
      },
      onError: (e) {
        _state.visibleTranscript.warn('[watcher] error: $e');
      },
    );
    watcher.start();
    watcher.onChange.listen((_) {
      if (!anyRunning()) return;
      _state.visibleTranscript.system('File changed — hot reloading all tabs.');
      unawaited(onReload());
    });
    _watcher = watcher;
  }

  /// Tear the watcher down once there are no tabs left.
  Future<void> disposeIfIdle({required bool idle}) async {
    if (!idle) return;
    await _watcher?.dispose();
    _watcher = null;
  }
}
