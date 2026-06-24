import 'dart:async';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:vm_service/vm_service.dart' as vm;

import '../data/datasources/app_session.dart';
import '../data/datasources/dart_file_watcher.dart';
import '../data/models/daemon_messages.dart';
import '../data/datasources/emulator_manager.dart';
import '../domain/value_objects/config_values.dart';
import '../data/datasources/frun_notifier.dart';
import '../data/models/source_location.dart';
import '../data/models/launch_config.dart';
import 'app_state.dart';
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

  /// Renders a `Flutter.Error` event payload into a compact, useful log.
  ///
  /// Flutter serializes a deep `DiagnosticsNode` tree (the same one DevTools
  /// shows) into the event. Naively flattening it produces hundreds of lines
  /// dominated by framework stack frames. Instead this classifies nodes by
  /// their `type`:
  ///   - `ErrorSummary` (the headline, e.g. "X was used after being disposed")
  ///   - `ErrorDescription` / `ErrorHint` (context)
  ///   - the "error-causing widget" block â†’ a clickable `file:line`
  ///   - `DiagnosticsStackTrace` â†’ frames, with framework noise collapsed
  ///
  /// Stack frames and the summary live in each node's `properties` array (not
  /// `children`), so both are walked. Set [verbose] to also dump the full raw
  /// JSON payload; it is dumped automatically when nothing could be extracted.
  static String renderFlutterError(
    Map<dynamic, dynamic> data, {
    bool verbose = false,
    String? projectRoot,
  }) {
    final errorsSince = (data['errorsSinceReload'] as num?)?.toInt() ?? 0;
    final library = data['library']?.toString() ?? 'Flutter framework';

    final buf = StringBuffer()
      ..writeln(
        'â•â• Exception caught by $library'
        '${errorsSince > 0 ? ' (error #${errorsSince + 1})' : ''} â•â•',
      );

    final parts = _ErrorParts();
    _collectNode(data['properties'], parts, projectRoot);
    _collectNode(data['children'], parts, projectRoot);
    _collectNode(data['stack'], parts, projectRoot);

    // Top-level summary fallbacks for Flutter versions that don't emit an
    // ErrorSummary node.
    final topDesc = data['description']?.toString() ?? '';
    if (parts.summary.isEmpty && topDesc.isNotEmpty) parts.summary.add(topDesc);
    final exc = _exceptionLine(data['exception']);
    if (parts.summary.isEmpty && exc.isNotEmpty) parts.summary.add(exc);

    for (final s in parts.summary) {
      buf.writeln(s);
    }
    for (final c in parts.context) {
      buf.writeln('  $c');
    }
    if (parts.widgetLoc != null) {
      buf.writeln('  widget: ${parts.widgetLoc}');
    } else if (parts.widgetRaw != null) {
      buf.writeln('  widget: ${parts.widgetRaw}');
    }
    for (final f in _trimFrames(parts.frames)) {
      buf.writeln(f);
    }

    final extractedAnything =
        parts.summary.isNotEmpty ||
        parts.context.isNotEmpty ||
        parts.frames.isNotEmpty ||
        parts.widgetLoc != null ||
        parts.widgetRaw != null;
    if (verbose || !extractedAnything) {
      buf.writeln(
        extractedAnything
            ? '--- raw Flutter.Error payload (verbose_errors) ---'
            : '--- raw Flutter.Error payload (nothing extracted) ---',
      );
      try {
        buf.writeln(const JsonEncoder.withIndent('  ').convert(data));
      } catch (_) {
        buf.writeln(data.toString());
      }
    }

    return buf.toString().trimRight();
  }

  /// Builds a `type: value` line from a top-level `exception` field, used as a
  /// summary fallback. Mirrors the old flattening logic.
  static String _exceptionLine(Object? exception) {
    if (exception is String) return exception;
    if (exception is! Map) return '';
    final desc = exception['description']?.toString() ?? '';
    final type = exception['type']?.toString() ?? '';
    final value =
        exception['valueToString']?.toString() ??
        exception['message']?.toString() ??
        '';
    return [type, value, desc].where((s) => s.isNotEmpty).toSet().join(': ');
  }

  static final RegExp _frameRe = RegExp(r'^#\d+\s');
  static final RegExp _locRe = RegExp(
    r'((?:file://|package:)\S+?\.dart):(\d+)(?::(\d+))?',
  );

  /// Recursively classifies a DiagnosticsNode (or list of them) into [parts],
  /// walking both `properties` and `children`. [inWidget] is true once inside
  /// the "error-causing widget" subtree so its source location is captured.
  static void _collectNode(
    Object? node,
    _ErrorParts parts,
    String? projectRoot, {
    int depth = 0,
    bool inWidget = false,
  }) {
    if (depth > 12) return;
    if (node is List) {
      for (final child in node) {
        _collectNode(
          child,
          parts,
          projectRoot,
          depth: depth,
          inWidget: inWidget,
        );
      }
      return;
    }
    if (node is! Map) return;

    final type = node['type']?.toString() ?? '';
    final name = node['name']?.toString() ?? '';
    final desc = (node['description']?.toString() ?? '').trim();
    final level = node['level']?.toString() ?? '';
    final isWidget =
        inWidget || name.toLowerCase().contains('error-causing widget');

    if (desc.isNotEmpty) {
      if (_frameRe.hasMatch(desc)) {
        parts.frames.add(desc);
      } else if (isWidget) {
        parts.widgetLoc ??= _extractLocation(desc, projectRoot);
        parts.widgetRaw ??= desc;
      } else if (type == 'ErrorSummary' || level == 'summary') {
        if (!parts.summary.contains(desc)) parts.summary.add(desc);
      } else if (type == 'ErrorDescription' || type == 'ErrorHint') {
        if (!parts.context.contains(desc)) parts.context.add(desc);
      }
      // Other node types (ErrorSpacer, bare DiagnosticsProperty, etc.) carry no
      // useful standalone text â€” skip to keep the log compact.
    }

    _collectNode(
      node['properties'],
      parts,
      projectRoot,
      depth: depth + 1,
      inWidget: isWidget,
    );
    _collectNode(
      node['children'],
      parts,
      projectRoot,
      depth: depth + 1,
      inWidget: isWidget,
    );
  }

  /// Pulls the first `file://â€¦/x.dart:line:col` or `package:â€¦` reference out of
  /// [desc] and renders it as a clickable path: `package:` forms are kept
  /// as-is, `file://` forms are resolved and made relative to [projectRoot]
  /// (forward slashes) so the transcript link-extractor picks them up.
  static String? _extractLocation(String desc, String? projectRoot) {
    final m = _locRe.firstMatch(desc);
    if (m == null) return null;
    final uri = m.group(1)!;
    final line = int.tryParse(m.group(2)!) ?? 1;
    final col = m.group(3) != null ? int.tryParse(m.group(3)!) : null;
    final colSuffix = col != null ? ':$col' : '';
    if (uri.startsWith('package:')) return '$uri:$line$colSuffix';

    final loc = SourceLocation.fromVmServiceUri(
      uri,
      projectRoot: projectRoot,
      line: line,
      column: col ?? 1,
    );
    if (loc == null) return null;
    var path = loc.file;
    if (projectRoot != null) {
      final rel = p.relative(loc.file, from: projectRoot);
      if (!rel.startsWith('..')) path = rel;
    }
    path = path.replaceAll(r'\', '/');
    return '$path:$line$colSuffix';
  }

  /// Drops pure framework frames (`package:flutter/â€¦`, `dart:â€¦`), collapsing
  /// each consecutive run into a single `â€¦ N framework frames hidden` marker.
  /// If filtering would hide everything, falls back to the top frames so the
  /// stack is never empty.
  static List<String> _trimFrames(List<String> frames) {
    if (frames.isEmpty) return const <String>[];
    bool isNoise(String f) =>
        f.contains('package:flutter/') || f.contains('(dart:');

    final out = <String>[];
    var hidden = 0;
    void flush() {
      if (hidden > 0) {
        out.add('â€¦ $hidden framework frame${hidden == 1 ? '' : 's'} hidden');
        hidden = 0;
      }
    }

    for (final f in frames) {
      if (isNoise(f)) {
        hidden++;
      } else {
        flush();
        out.add(f);
      }
    }
    flush();

    final keptFrames = out.where((l) => l.startsWith('#')).length;
    if (keptFrames == 0) return frames.take(5).toList();
    return out;
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

/// Mutable accumulator for the classified pieces of a `Flutter.Error` payload,
/// filled by [RunController._collectNode].
class _ErrorParts {
  final List<String> summary = <String>[];
  final List<String> context = <String>[];
  final List<String> frames = <String>[];
  String? widgetLoc;
  String? widgetRaw;
}
