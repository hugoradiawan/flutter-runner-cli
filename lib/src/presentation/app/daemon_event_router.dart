import 'dart:async';

import '../../data/datasources/app_session.dart';
import '../../data/datasources/frun_notifier.dart';
import '../../data/models/daemon_messages.dart';
import 'app_state.dart';
import 'isolate_connection.dart';
import 'run_tab.dart';

/// Routes `flutter run` daemon events for a tab into its transcript, notifies
/// the [FrunNotifier], and drives the shared [IsolateConnection] for the active
/// tab.
class DaemonEventRouter {
  DaemonEventRouter(this._state, this._isolates, this.activeTab);

  final AppState _state;
  final IsolateConnection _isolates;

  /// Reads the controller's currently-active tab on demand.
  final RunTab? Function() activeTab;

  void onEvent(RunTab tab, DaemonEvent event) {
    switch (event.name) {
      case 'app.start':
        tab.transcript.success('App started (appId=${event.params['appId']}).');
        _state.notifier.notifyTab(tab, FrunNotifEvent.appStarted);
      case 'app.debugPort':
        final ws = event.params['wsUri']?.toString();
        if (ws != null) {
          tab.transcript.info('VM service: $ws');
          // Isolate connection is shared across the process — only the active
          // tab drives it to keep the UX coherent.
          if (tab == activeTab()) _isolates.connect(ws);
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
        if (tab == activeTab()) {
          unawaited(_isolates.disconnect());
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

  void onProcessExit(RunTab tab, AppRunSession exitedSession, int code) {
    if (tab.session != exitedSession) {
      // A newer session has taken over this tab — ignore the older exit.
      return;
    }
    tab.transcript.system('flutter run exited (code $code).');
    tab.session = null;
    if (tab == activeTab()) {
      unawaited(_isolates.disconnect());
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
}
