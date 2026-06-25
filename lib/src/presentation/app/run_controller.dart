import 'dart:async';

import 'package:vm_service/vm_service.dart' as vm;

import '../../data/datasources/app_session.dart';
import '../../data/datasources/dart_file_watcher.dart';
import '../../data/datasources/emulator_manager.dart';
import '../../data/datasources/frun_notifier.dart';
import '../../data/models/daemon_messages.dart';
import '../../data/models/launch_config.dart';
import '../../domain/value_objects/config_values.dart';
import 'app_state.dart';
import 'flutter_error_renderer.dart';
import 'run_tab.dart';

/// Owns all concurrent `flutter run` sessions as a list of [RunTab]s. Tabs are
/// added on `run`, removed on `stop`, and one is "active" â€” that's the tab
/// the TUI renders and the one `reload`, `restart`, `stop` operate on.
///
/// The file watcher is shared: when any `.dart` file is saved, every running
/// session is hot-reloaded.
class RunController {
  RunController(this.state);

  final AppState state;

  final List<RunTab> tabs = <RunTab>[];
  int _activeIndex = -1;
  int _nextTabId = 1;

  DartFileWatcher? _watcher;
  StreamSubscription<vm.Event>? _extensionSub;

  /// VM-service ws URI the shared [IsolateManager] is currently connected to.
  /// Guards against redundant reconnects when re-pointing to the active tab.
  String? _connectedVmUri;

  RunTab? get activeTab => (_activeIndex >= 0 && _activeIndex < tabs.length)
      ? tabs[_activeIndex]
      : null;
  int get activeIndex => _activeIndex;
  bool get isRunning => activeTab?.isRunning ?? false;
  bool get hasTabs => tabs.isNotEmpty;

  /// Legacy single-session getter, kept for the status panel.
  AppRunSession? get session => activeTab?.session;

  /// Legacy "last entry" getter, kept for the status panel.
  LaunchEntry? get lastEntry => activeTab?.entry;

  /// Stash [entry] as the pending run and open the run-target picker. The
  /// picker lists connected devices (physical, running emulators, desktop and
  /// web platforms) plus offline emulators that can be booted on demand. The
  /// TUI renders it; picking a target calls [launchOnTarget].
  Future<void> openRunTargetPicker(LaunchEntry entry) async {
    state.pendingRunEntry = entry;

    final devices = state.deviceManager?.devices ?? const [];
    final connectedAvdIds = devices
        .where((d) => d.emulatorId != null)
        .map((d) => d.emulatorId!)
        .toSet();

    var emulators = const <FlutterEmulator>[];
    final daemon = state.daemon;
    if (daemon != null) {
      try {
        emulators = await EmulatorManager(
          daemon,
        ).list().timeout(const Duration(seconds: 10));
      } catch (_) {}
    }

    final targets = <RunTarget>[
      for (final d in devices) RunTarget.device(d),
      for (final e in emulators)
        if (!connectedAvdIds.contains(e.id)) RunTarget.emulator(e),
    ];

    if (targets.isEmpty) {
      state.pendingRunEntry = null;
      state.visibleTranscript.warn(
        'No devices or emulators available. Connect a device or run /emulators create.',
      );
      return;
    }
    state.setRunTargetPicker(targets);
  }

  /// Launch the pending run entry on [target]. Offline emulators are booted
  /// first; once a device id is in hand, defers to [startOrFocus].
  Future<RunTab?> launchOnTarget(RunTarget target) async {
    final entry = state.pendingRunEntry;
    state.pendingRunEntry = null;
    state.clearPickers();
    if (entry == null) return null;

    String deviceId;
    if (target.needsBoot) {
      final daemon = state.daemon;
      if (daemon == null) {
        state.visibleTranscript.warn(
          'Flutter daemon is still starting. Try /run again shortly.',
        );
        return null;
      }
      final coldBoot = state.config.emulatorBoot == FrunEmulatorBoot.cold;
      state.visibleTranscript.system('Launching emulator ${target.id}â€¦');
      try {
        final device = await EmulatorManager(
          daemon,
        ).launchAndAwaitDevice(target.id, coldBoot: coldBoot);
        if (device == null) {
          state.visibleTranscript.warn(
            'Emulator ${target.id} launched but no device appeared within the timeout.',
          );
          return null;
        }
        deviceId = device.id;
      } catch (e) {
        state.visibleTranscript.error(
          'Failed to launch emulator ${target.id}: $e',
        );
        return null;
      }
    } else {
      deviceId = target.id;
    }
    return startOrFocus(entry, deviceId: deviceId);
  }

  /// Start an app, or focus an existing tab that matches this entry + device.
  Future<RunTab?> startOrFocus(
    LaunchEntry entry, {
    required String deviceId,
  }) async {
    final dedupeKey = '${entry.name}|${entry.program}|$deviceId';
    for (var i = 0; i < tabs.length; i++) {
      if (tabs[i].dedupeKey == dedupeKey && tabs[i].isRunning) {
        _activeIndex = i;
        state.transcript.system(
          'Already running â€” focused tab ${i + 1} (${tabs[i].label}).',
        );
        return tabs[i];
      }
    }

    final tab = RunTab(id: _nextTabId++, entry: entry, deviceId: deviceId);
    tabs.add(tab);
    _activeIndex = tabs.length - 1;
    tab.transcript.system(
      'Launching ${entry.name} on $deviceId (${entry.program})â€¦',
    );
    state.notifier.notifyTab(tab, FrunNotifEvent.appLaunching);
    try {
      final session = await AppRunSession.start(
        projectRoot: state.project.root,
        entry: entry,
        deviceId: deviceId,
      );
      final diag = AppRunSession.lastSpawnDiagnostic;
      if (diag != null) tab.transcript.system(diag);
      tab.session = session;
      tab.eventsSub = session.events.listen((e) => _onEvent(tab, e));
      // Capture the session in the callback so a late exit from an older
      // process can't clobber a newer session (happens when an app dies
      // after we already wired a new one up).
      unawaited(
        session.exitCode.then((code) => _onProcessExit(tab, session, code)),
      );
      _ensureWatcher();
      return tab;
    } catch (e) {
      tab.transcript.error('Failed to launch: $e');
      tabs.remove(tab);
      if (_activeIndex >= tabs.length) _activeIndex = tabs.length - 1;
      return null;
    }
  }

  void _ensureWatcher() {
    if (!state.config.hotReloadOnSave) return;
    if (_watcher != null) return;
    // Watch the repo/workspace root so monorepo feature packages are included.
    final root = state.project.watchRoot;
    state.visibleTranscript.system('File watcher started on $root');
    final watcher = DartFileWatcher(
      root: root,
      onFileChanged: (path) {
        state.visibleTranscript.system('[watcher] changed: $path');
      },
      onWatcherError: (e) {
        state.visibleTranscript.warn('[watcher] error: $e');
      },
    );
    watcher.start();
    watcher.onChange.listen((_) {
      if (tabs.every((t) => !t.isRunning)) return;
      state.visibleTranscript.system(
        'File changed â€” hot reloading all tabs.',
      );
      unawaited(hotReloadAll());
    });
    _watcher = watcher;
  }

  Future<void> _disposeWatcherIfIdle() async {
    if (tabs.isNotEmpty) return;
    await _watcher?.dispose();
    _watcher = null;
  }

  Future<void> hotReloadAll() async {
    for (final tab in tabs) {
      final s = tab.session;
      if (s == null) continue;
      state.notifier.notifyTab(tab, FrunNotifEvent.hotReloading);
      try {
        await s.hotReload();
        state.notifier.notifyTab(tab, FrunNotifEvent.hotReloaded);
        tab.transcript.success('Hot reload requested.');
      } catch (e) {
        tab.transcript.error('Hot reload failed: $e');
      }
    }
  }

  Future<void> hotReloadActive() => hotReloadTab(activeTab);
  Future<void> hotRestartActive() => hotRestartTab(activeTab);

  Future<void> hotReloadTab(RunTab? tab) async {
    if (tab == null || tab.session == null) {
      state.transcript.warn('No app running. Use /run first.');
      return;
    }
    state.notifier.notifyTab(tab, FrunNotifEvent.hotReloading);
    try {
      await tab.session!.hotReload();
      state.notifier.notifyTab(tab, FrunNotifEvent.hotReloaded);
      tab.transcript.success('Hot reload requested.');
    } catch (e) {
      tab.transcript.error('Hot reload failed: $e');
    }
  }

  Future<void> hotRestartTab(RunTab? tab) async {
    if (tab == null || tab.session == null) {
      state.transcript.warn('No app running. Use /run first.');
      return;
    }
    state.notifier.notifyTab(tab, FrunNotifEvent.restarting);
    try {
      await tab.session!.hotRestart();
      state.notifier.notifyTab(tab, FrunNotifEvent.restarted);
      tab.transcript.success('Hot restart requested.');
    } catch (e) {
      tab.transcript.error('Hot restart failed: $e');
    }
  }

  /// Stop and remove an arbitrary tab (not necessarily the active one).
  /// Used by the clickable per-tab stop / close glyph.
  Future<void> stopTabByIndex(int index) async {
    if (index < 0 || index >= tabs.length) return;
    final tab = tabs[index];
    await _stopTab(tab);
    final actualIndex = tabs.indexOf(tab);
    if (actualIndex >= 0) tabs.removeAt(actualIndex);
    if (tabs.isEmpty) {
      _activeIndex = -1;
    } else if (_activeIndex >= tabs.length) {
      _activeIndex = tabs.length - 1;
    } else if (actualIndex >= 0 && _activeIndex > actualIndex) {
      _activeIndex--;
    }
    await _disposeWatcherIfIdle();
  }

  /// Re-launch a specific tab on the same device.
  Future<void> rerunTabByIndex(int index) async {
    if (index < 0 || index >= tabs.length) return;
    final tab = tabs[index];
    final entry = tab.entry;
    final deviceId = tab.deviceId;
    await stopTabByIndex(index);
    await startOrFocus(entry, deviceId: deviceId);
  }

  /// Re-launch the active tab's entry on the same device.
  Future<void> rerunActive() async {
    final tab = activeTab;
    if (tab == null) {
      state.transcript.warn('Nothing to rerun. Use /run first.');
      return;
    }
    final entry = tab.entry;
    final deviceId = tab.deviceId;
    await stopActive();
    await startOrFocus(entry, deviceId: deviceId);
  }

  Future<void> stopActive() async {
    final tab = activeTab;
    if (tab == null) return;
    await _stopTab(tab);
    final removedIndex = tabs.indexOf(tab);
    if (removedIndex >= 0) tabs.removeAt(removedIndex);
    if (tabs.isEmpty) {
      _activeIndex = -1;
    } else if (_activeIndex >= tabs.length) {
      _activeIndex = tabs.length - 1;
    }
    await _disposeWatcherIfIdle();
  }

  Future<void> detachActive() async {
    final tab = activeTab;
    if (tab == null) return;
    await _detachTab(tab);
    final removedIndex = tabs.indexOf(tab);
    if (removedIndex >= 0) tabs.removeAt(removedIndex);
    if (tabs.isEmpty) {
      _activeIndex = -1;
    } else if (_activeIndex >= tabs.length) {
      _activeIndex = tabs.length - 1;
    }
    await _disposeWatcherIfIdle();
  }

  Future<void> _detachTab(RunTab tab) async {
    final s = tab.session;
    if (s != null) {
      tab.transcript.system('Detaching from appâ€¦');
      try {
        await s.detach();
      } catch (e) {
        tab.transcript.warn('Detach reported error: $e');
      }
    }
    await tab.eventsSub?.cancel();
    tab.eventsSub = null;
    tab.session = null;
  }

  Future<void> stopAll() async {
    if (tabs.isEmpty) return;
    final snapshot = List<RunTab>.from(tabs);
    for (final tab in snapshot) {
      await _stopTab(tab);
    }
    tabs.clear();
    _activeIndex = -1;
    await _disposeWatcherIfIdle();
  }

  Future<void> _stopTab(RunTab tab) async {
    final s = tab.session;
    if (s != null) {
      tab.transcript.system('Stopping appâ€¦');
      try {
        await s.stop();
      } catch (e) {
        tab.transcript.warn('Stop reported error: $e');
      }
    }
    await tab.eventsSub?.cancel();
    tab.eventsSub = null;
    tab.session = null;
  }

  /// Cycle the active tab. No-op if there are fewer than two tabs.
  void cycleActive({bool forward = true}) {
    if (tabs.length < 2) return;
    final delta = forward ? 1 : -1;
    _activeIndex = (_activeIndex + delta) % tabs.length;
    if (_activeIndex < 0) _activeIndex += tabs.length;
  }

  void setActiveIndex(int index) {
    if (index < 0 || index >= tabs.length) return;
    _activeIndex = index;
  }

  /// Re-point the shared [IsolateManager] connection at the active tab's VM
  /// service. Commands that act on the running app (`inspect`, `devtools`,
  /// `isolates`) call this first so they operate on the *selected* tab's
  /// device rather than whichever device connected last.
  ///
  /// Returns `true` when a live VM service is connected for the active tab.
  Future<bool> ensureIsolatesForActiveTab() async {
    final ws = activeTab?.session?.vmServiceUri;
    if (ws == null) {
      await _disconnectIsolates();
      return false;
    }
    if (_connectedVmUri == ws && state.isolateManager.service != null) {
      return true;
    }
    await _connectIsolates(ws);
    return state.isolateManager.service != null;
  }

  void _onEvent(RunTab tab, DaemonEvent event) {
    switch (event.name) {
      case 'app.start':
        tab.transcript.success('App started (appId=${event.params['appId']}).');
        state.notifier.notifyTab(tab, FrunNotifEvent.appStarted);
      case 'app.debugPort':
        final ws = event.params['wsUri']?.toString();
        if (ws != null) {
          tab.transcript.info('VM service: $ws');
          // Isolate connection is shared across the process â€” only the active
          // tab drives it to keep the UX coherent.
          if (tab == activeTab) _connectIsolates(ws);
        }
      case 'app.devTools':
        final uri = event.params['wsUri'] ?? event.params['uri'];
        if (uri != null) tab.transcript.info('DevTools: $uri');
      case 'app.log':
        final raw = _stripLogcatPrefix(event.params['log']?.toString() ?? '');
        final stack = event.params['stackTrace']?.toString() ?? '';
        if (raw.isEmpty && stack.isEmpty) return;
        final isError = event.params['error'] == true;
        if (raw.isNotEmpty) {
          if (isError) {
            tab.transcript.error(raw);
          } else {
            tab.transcript.info(raw);
          }
        }
        if (stack.isNotEmpty) {
          if (isError) {
            tab.transcript.error(stack);
          } else {
            tab.transcript.info(stack);
          }
        }
      case 'app.progress':
        final msg = event.params['message']?.toString() ?? '';
        if (msg.isNotEmpty) tab.transcript.system(msg);
      case 'app.stop':
        final err = event.params['error']?.toString() ?? '';
        final trace = event.params['trace']?.toString() ?? '';
        if (err.isNotEmpty) tab.transcript.error(err);
        if (trace.isNotEmpty) tab.transcript.error(trace);
        tab.transcript.system('App stopped.');
        if (tab == activeTab) {
          unawaited(_disconnectIsolates());
        }
      case 'daemon.logMessage':
        final msg = event.params['message']?.toString() ?? '';
        if (msg.isEmpty) return;
        final level = event.params['level']?.toString() ?? 'info';
        switch (level) {
          case 'error':
            tab.transcript.error(msg);
          case 'warning':
            tab.transcript.warn(msg);
          case 'status':
            tab.transcript.system(msg);
          default:
            tab.transcript.info(msg);
        }
      default:
        tab.transcript.debug('${event.name}: ${event.params}');
    }
  }

  /// Android logcat tags each line with e.g. `I/flutter ( 7225): `. Strip it
  /// so the transcript shows only the app's own log text.
  static final _logcatPrefix = RegExp(
    r'^[VDIWEF]/[^(]*\(\s*\d+\):\s?',
    multiLine: true,
  );

  static String _stripLogcatPrefix(String log) =>
      log.replaceAll(_logcatPrefix, '');

  Future<void> _connectIsolates(String wsUri) async {
    try {
      await state.isolateManager.connect(wsUri);
      _connectedVmUri = wsUri;
      state.transcript.system(
        'VM service connected (${state.isolateManager.isolates.length} isolates).',
      );
      await _extensionSub?.cancel();
      _extensionSub = state.isolateManager.extensionEvents.listen(
        _onExtensionEvent,
      );
    } catch (e) {
      _connectedVmUri = null;
      state.transcript.warn('VM service connect failed: $e');
    }
  }

  Future<void> _disconnectIsolates() async {
    await _extensionSub?.cancel();
    _extensionSub = null;
    _connectedVmUri = null;
    await state.isolateManager.disconnect();
  }

  void _onExtensionEvent(vm.Event event) {
    if (event.extensionKind != 'Flutter.Error') return;
    final tab = activeTab;
    if (tab == null) return;
    final data = event.extensionData?.data ?? const <String, dynamic>{};
    tab.transcript.error(
      renderFlutterError(
        data,
        verbose: state.config.verboseErrors,
        projectRoot: state.project.root,
      ),
    );
  }

  void _onProcessExit(RunTab tab, AppRunSession exitedSession, int code) {
    if (tab.session != exitedSession) {
      // A newer session has taken over this tab â€” ignore the older exit.
      return;
    }
    tab.transcript.system('flutter run exited (code $code).');
    tab.session = null;
    if (tab == activeTab) {
      unawaited(_disconnectIsolates());
    }
  }
}
