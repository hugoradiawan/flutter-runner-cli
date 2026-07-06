import 'dart:async';

import '../../domain/entities/device.dart';
import '../../domain/entities/emulator.dart';
import '../../domain/entities/launch_entry.dart';
import '../../domain/entities/run_session.dart';
import '../../domain/params/emulator_launch_params.dart';
import '../../domain/params/reload_params.dart';
import '../../domain/params/session_params.dart';
import '../../domain/value_objects/config_values.dart';
import '../../domain/value_objects/notification_event.dart';
import 'app_state.dart';
import 'daemon_event_router.dart';
import 'isolate_connection.dart';
import 'reload_watcher.dart';
import 'run_tab.dart';

/// Owns all concurrent `flutter run` sessions as a list of [RunTab]s. Tabs are
/// added on `run`, removed on `stop`, and one is "active" — that's the tab
/// the TUI renders and the one `reload`, `restart`, `stop` operate on.
///
/// Live sessions are owned by the data layer's session repository; each tab
/// holds only the domain [RunSession] handle for event/log wiring. Every
/// start / reload / restart / stop / detach goes through the domain use cases
/// on [AppState.deps], so the domain is the single control surface shared with
/// the slash-command handlers. Device and emulator discovery for the run
/// picker likewise go through use cases.
///
/// Three collaborators handle the cross-cutting concerns: [IsolateConnection]
/// (the shared VM service that follows the active tab), [DaemonEventRouter]
/// (per-tab `flutter run` event handling), and [ReloadWatcher] (the shared
/// file watcher that hot-reloads every running session on save).
class RunController {
  RunController(this.state) {
    _isolates = IsolateConnection(state, () => activeTab);
    _events = DaemonEventRouter(state, _isolates, () => activeTab);
    _watcher = ReloadWatcher(
      state,
      anyRunning: () => tabs.any((t) => t.canHotReload),
      onReload: hotReloadAll,
    );
  }

  final AppState state;

  final List<RunTab> tabs = <RunTab>[];
  int _activeIndex = -1;
  int _nextTabId = 1;

  late final IsolateConnection _isolates;
  late final DaemonEventRouter _events;
  late final ReloadWatcher _watcher;

  RunTab? get activeTab => (_activeIndex >= 0 && _activeIndex < tabs.length)
      ? tabs[_activeIndex]
      : null;
  int get activeIndex => _activeIndex;
  bool get isRunning => activeTab?.isRunning ?? false;
  bool get hasTabs => tabs.isNotEmpty;

  /// Legacy single-session getter, kept for the status panel.
  RunSession? get session => activeTab?.session;

  /// Legacy "last entry" getter, kept for the status panel.
  LaunchEntryEntity? get lastEntry => activeTab?.entry;

  /// Service-extension caller targeting the active session, or null when no
  /// app is running. Handed to the inspector bridge so it always polls the
  /// currently-selected tab.
  Future<Object?> Function(String method, Map<String, Object?> params)?
  get serviceExtensionCaller {
    final s = session;
    if (s == null) return null;
    return (method, params) => s.callServiceExtension(method, params);
  }

  /// Stash [entry] as the pending run and open the run-target picker. The
  /// picker lists connected devices (physical, running emulators, desktop and
  /// web platforms) plus offline emulators that can be booted on demand. The
  /// TUI renders it; picking a target calls [launchOnTarget].
  Future<void> openRunTargetPicker(LaunchEntryEntity entry) async {
    state.pendingRunEntry = entry;

    final devicesResult = await state.deps.listDevicesUseCase?.call();
    final devices =
        devicesResult?.fold((_) => const <DeviceEntity>[], (d) => d) ??
        const <DeviceEntity>[];
    final connectedAvdIds = devices
        .where((d) => d.emulatorId != null)
        .map((d) => d.emulatorId!)
        .toSet();

    final emulatorsResult = await state.deps.listEmulatorsUseCase?.call();
    final emulators =
        emulatorsResult?.fold((_) => const <EmulatorEntity>[], (e) => e) ??
        const <EmulatorEntity>[];

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
      final launchUseCase = state.deps.launchEmulatorUseCase;
      if (launchUseCase == null) {
        state.visibleTranscript.warn(
          'Flutter daemon is still starting. Try /run again shortly.',
        );
        return null;
      }
      final coldBoot = state.config.emulatorBoot == FrunEmulatorBoot.cold;
      state.visibleTranscript.system('Launching emulator ${target.id}…');
      final result = await launchUseCase.call(
        EmulatorLaunchParams(
          emulator: EmulatorEntity(
            id: target.id,
            name: target.name,
            platformType: target.platform,
          ),
          coldBoot: coldBoot,
        ),
      );
      final device = result.fold((_) => null, (d) => d);
      if (device == null) {
        state.visibleTranscript.error(
          'Failed to launch emulator ${target.id}: '
          '${result.fold((f) => f.message, (_) => '')}',
        );
        return null;
      }
      deviceId = device.id;
    } else {
      deviceId = target.id;
    }
    return startOrFocus(entry, deviceId: deviceId);
  }

  /// Start an app, or focus an existing tab that matches this entry + device.
  Future<RunTab?> startOrFocus(
    LaunchEntryEntity entry, {
    required String deviceId,
  }) async {
    final dedupeKey = '${entry.name}|${entry.program}|$deviceId';
    for (var i = 0; i < tabs.length; i++) {
      if (tabs[i].dedupeKey == dedupeKey && tabs[i].isRunning) {
        _activeIndex = i;
        state.transcript.system(
          'Already running — focused tab ${i + 1} (${tabs[i].label}).',
        );
        return tabs[i];
      }
    }

    final tab = RunTab(id: _nextTabId++, entry: entry, deviceId: deviceId);
    tabs.add(tab);
    _activeIndex = tabs.length - 1;
    tab.transcript.system(
      'Launching ${entry.name} on $deviceId (${entry.program})…',
    );
    state.deps.notifier.notify(
      FrunNotifEvent.appLaunching,
      label: tab.notificationLabel,
    );
    final result = await state.deps.startSessionUseCase.call(
      SessionStartParams(
        sessionId: tab.id,
        projectRoot: state.project.root,
        entry: entry,
        deviceId: deviceId,
      ),
    );
    return result.fold(
      (failure) {
        tab.transcript.error('Failed to launch: ${failure.message}');
        tabs.remove(tab);
        if (_activeIndex >= tabs.length) _activeIndex = tabs.length - 1;
        return null;
      },
      (session) {
        final diag = session.spawnDiagnostic;
        if (diag != null) tab.transcript.system(diag);
        tab.session = session;
        tab.eventsSub = session.events.listen((e) => _events.onEvent(tab, e));
        _watcher.ensure();
        return tab;
      },
    );
  }

  Future<void> _disposeWatcherIfIdle() =>
      _watcher.disposeIfIdle(idle: tabs.isEmpty);

  Future<void> _disposeIsolatesIfIdle() async {
    if (tabs.isEmpty) await _isolates.disconnect();
  }

  Future<void> hotReloadAll() async {
    for (final tab in tabs) {
      if (tab.canHotReload) await _reload(tab);
    }
  }

  Future<void> hotReloadActive() => hotReloadTab(activeTab);
  Future<void> hotRestartActive() => hotRestartTab(activeTab);

  Future<void> hotReloadTab(RunTab? tab) async {
    if (tab == null || tab.session == null) {
      state.transcript.warn('No app running. Use /run first.');
      return;
    }
    await _reload(tab);
  }

  /// Drive a hot reload for [tab] through the domain use case. Assumes the tab
  /// has a live session (callers guard).
  Future<void> _reload(RunTab tab) async {
    state.deps.notifier.notify(
      FrunNotifEvent.hotReloading,
      label: tab.notificationLabel,
    );
    final result = await state.deps.hotReloadUseCase.call(
      ReloadParams(tabId: tab.id),
    );
    result.fold(
      (f) => tab.transcript.error('Hot reload failed: ${f.message}'),
      (_) {
        state.deps.notifier.notify(
          FrunNotifEvent.hotReloaded,
          label: tab.notificationLabel,
        );
        tab.transcript.success('Hot reload requested.');
      },
    );
  }

  Future<void> hotRestartTab(RunTab? tab) async {
    if (tab == null || tab.session == null) {
      state.transcript.warn('No app running. Use /run first.');
      return;
    }
    state.deps.notifier.notify(
      FrunNotifEvent.restarting,
      label: tab.notificationLabel,
    );
    final result = await state.deps.hotRestartUseCase.call(
      ReloadParams(tabId: tab.id),
    );
    result.fold(
      (f) => tab.transcript.error('Hot restart failed: ${f.message}'),
      (_) {
        state.deps.notifier.notify(
          FrunNotifEvent.restarted,
          label: tab.notificationLabel,
        );
        tab.transcript.success('Hot restart requested.');
      },
    );
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
    await _disposeIsolatesIfIdle();
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
    await _disposeIsolatesIfIdle();
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
    if (tab.session != null) {
      tab.transcript.system('Detaching from app…');
      final result = await state.deps.detachSessionUseCase.call(
        ReloadParams(tabId: tab.id),
      );
      result.fold(
        (f) => tab.transcript.warn('Detach reported error: ${f.message}'),
        (_) {},
      );
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
    await _isolates.disconnect();
  }

  Future<void> _stopTab(RunTab tab) async {
    if (tab.session != null) {
      tab.transcript.system('Stopping app…');
      final result = await state.deps.stopSessionUseCase.call(
        ReloadParams(tabId: tab.id),
      );
      result.fold(
        (f) => tab.transcript.warn('Stop reported error: ${f.message}'),
        (_) {},
      );
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

  /// Re-point the shared isolate connection at the active tab's VM service.
  /// Returns `true` when a live VM service is connected for the active tab.
  Future<bool> ensureIsolatesForActiveTab() => _isolates.ensureForActiveTab();
}
