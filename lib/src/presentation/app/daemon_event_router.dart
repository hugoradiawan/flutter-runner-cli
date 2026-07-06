import 'dart:async';

import '../../domain/entities/session_event.dart';
import '../../domain/value_objects/notification_event.dart';
import 'app_state.dart';
import 'isolate_connection.dart';
import 'run_tab.dart';

/// Routes a tab's [SessionEvent]s into its transcript, notifies the desktop
/// notifier, and drives the shared [IsolateConnection] for the active tab.
class DaemonEventRouter {
  DaemonEventRouter(this._state, this._isolates, this.activeTab);

  final AppState _state;
  final IsolateConnection _isolates;

  /// Reads the controller's currently-active tab on demand.
  final RunTab? Function() activeTab;

  void onEvent(RunTab tab, SessionEvent event) {
    switch (event) {
      case SessionStarted(:final appId):
        tab.transcript.success('App started (appId=$appId).');
        _state.deps.notifier.notify(
          FrunNotifEvent.appStarted,
          label: tab.notificationLabel,
        );
      case SessionDebugPort(:final vmServiceUri):
        if (vmServiceUri != null) {
          tab.transcript.info('VM service: $vmServiceUri');
          // Isolate connection is shared across the process — only the active
          // tab drives it to keep the UX coherent.
          if (tab == activeTab()) _isolates.connect(vmServiceUri);
        }
      case SessionDevTools(:final uri):
        if (uri != null) {
          tab.transcript.info('DevTools: $uri');
          tab.devToolsUri = uri;
        }
      case SessionLogLine(:final message, :final stackTrace, :final isError):
        if (message.isEmpty && stackTrace.isEmpty) return;
        if (message.isNotEmpty) {
          if (isError) {
            tab.transcript.error(message);
          } else {
            tab.transcript.info(message);
          }
        }
        if (stackTrace.isNotEmpty) {
          if (isError) {
            tab.transcript.error(stackTrace);
          } else {
            tab.transcript.info(stackTrace);
          }
        }
      case SessionProgress(:final message):
        if (message.isNotEmpty) tab.transcript.system(message);
      case SessionStopped(:final error, :final trace):
        if (error.isNotEmpty) tab.transcript.error(error);
        if (trace.isNotEmpty) tab.transcript.error(trace);
        tab.transcript.system('App stopped.');
        if (tab == activeTab()) {
          unawaited(_isolates.disconnect());
        }
      case SessionDaemonLog(:final message, :final level):
        if (message.isEmpty) return;
        switch (level) {
          case SessionLogLevel.error:
            tab.transcript.error(message);
          case SessionLogLevel.warning:
            tab.transcript.warn(message);
          case SessionLogLevel.status:
            tab.transcript.system(message);
          case SessionLogLevel.info:
            tab.transcript.info(message);
        }
      case SessionExited(:final exitCode):
        // Deliberate stops cancel the tab's event subscription before the
        // exit event lands, so this only fires for natural process deaths.
        tab.transcript.system('flutter run exited (code $exitCode).');
        tab.session = null;
        if (tab == activeTab()) {
          unawaited(_isolates.disconnect());
        }
      case SessionUnknown(:final name, :final params):
        tab.transcript.debug('$name: $params');
    }
  }
}
