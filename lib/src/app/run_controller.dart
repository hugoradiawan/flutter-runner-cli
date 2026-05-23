import 'dart:async';

import '../daemon/app_session.dart';
import '../daemon/daemon_messages.dart';
import '../project/launch_config.dart';
import '../watcher/dart_file_watcher.dart';
import 'app_state.dart';

/// Owns the single active [AppRunSession] for a project, plus the file watcher
/// that drives hot reload on save.
class RunController {
  RunController(this.state);

  final AppState state;
  AppRunSession? _session;
  LaunchEntry? _lastEntry;
  String? _lastDeviceId;
  DartFileWatcher? _watcher;
  StreamSubscription<DaemonEvent>? _eventsSub;

  AppRunSession? get session => _session;
  LaunchEntry? get lastEntry => _lastEntry;
  bool get isRunning => _session != null;

  /// Start an app. Tears down any existing session first.
  Future<void> start(LaunchEntry entry, {required String deviceId}) async {
    await stop();
    state.transcript.system(
      'Launching ${entry.name} on $deviceId (${entry.program})…',
    );
    try {
      final session = await AppRunSession.start(
        projectRoot: state.project.root,
        entry: entry,
        deviceId: deviceId,
      );
      _session = session;
      _lastEntry = entry;
      _lastDeviceId = deviceId;
      _eventsSub = session.events.listen(_onEvent);
      // Capture the session in the callback so a late exit from an older
      // process can't clobber a newer session (happens when switching apps
      // without /stop — the killed process resolves exitCode after the new
      // one is already running).
      unawaited(
        session.exitCode.then((code) => _onProcessExit(session, code)),
      );
      _startWatcher();
    } catch (e) {
      state.transcript.error('Failed to launch: $e');
    }
  }

  void _startWatcher() {
    if (!state.config.hotReloadOnSave) return;
    final watcher = DartFileWatcher(root: state.project.libDir);
    watcher.start();
    watcher.onChange.listen((_) {
      if (_session == null) return;
      state.transcript.system('File changed — hot reload.');
      hotReload();
    });
    _watcher = watcher;
  }

  Future<void> hotReload() async {
    final s = _session;
    if (s == null) {
      state.transcript.warn('No app running. Use /run first.');
      return;
    }
    try {
      await s.hotReload();
      state.transcript.success('Hot reload requested.');
    } catch (e) {
      state.transcript.error('Hot reload failed: $e');
    }
  }

  Future<void> hotRestart() async {
    final s = _session;
    if (s == null) {
      state.transcript.warn('No app running. Use /run first.');
      return;
    }
    try {
      await s.hotRestart();
      state.transcript.success('Hot restart requested.');
    } catch (e) {
      state.transcript.error('Hot restart failed: $e');
    }
  }

  /// Re-launch the last entry on the same device.
  Future<void> rerun() async {
    final entry = _lastEntry;
    final deviceId = _lastDeviceId ?? state.selectedDeviceId;
    if (entry == null || deviceId == null) {
      state.transcript.warn('Nothing to rerun. Use /run first.');
      return;
    }
    await start(entry, deviceId: deviceId);
  }

  Future<void> stop() async {
    final s = _session;
    if (s == null) return;
    state.transcript.system('Stopping running app…');
    try {
      await s.stop();
    } catch (e) {
      state.transcript.warn('Stop reported error: $e');
    }
    await _eventsSub?.cancel();
    _eventsSub = null;
    await _watcher?.dispose();
    _watcher = null;
    _session = null;
  }

  void _onEvent(DaemonEvent event) {
    switch (event.name) {
      case 'app.start':
        state.transcript.success('App started (appId=${event.params['appId']}).');
      case 'app.debugPort':
        final ws = event.params['wsUri']?.toString();
        if (ws != null) {
          state.transcript.info('VM service: $ws');
          _connectIsolates(ws);
        }
      case 'app.devTools':
        final uri = event.params['wsUri'] ?? event.params['uri'];
        if (uri != null) state.transcript.info('DevTools: $uri');
      case 'app.log':
        final raw = event.params['log']?.toString() ?? '';
        if (raw.isEmpty) return;
        if (event.params['error'] == true) {
          state.transcript.error(raw);
        } else {
          state.transcript.info(raw);
        }
      case 'app.progress':
        final msg = event.params['message']?.toString() ?? '';
        if (msg.isNotEmpty) state.transcript.system(msg);
      case 'app.stop':
        state.transcript.system('App stopped.');
        unawaited(state.isolateManager.disconnect());
    }
  }

  Future<void> _connectIsolates(String wsUri) async {
    try {
      await state.isolateManager.connect(wsUri);
      state.transcript.system(
        'VM service connected (${state.isolateManager.isolates.length} isolates).',
      );
    } catch (e) {
      state.transcript.warn('VM service connect failed: $e');
    }
  }

  void _onProcessExit(AppRunSession exitedSession, int code) {
    if (_session != exitedSession) {
      // A newer session has already taken over — this exit notification
      // belongs to a previous run. Don't touch the active state.
      return;
    }
    state.transcript.system('flutter run exited (code $code).');
    _session = null;
    _watcher?.dispose();
    _watcher = null;
    unawaited(state.isolateManager.disconnect());
  }
}
