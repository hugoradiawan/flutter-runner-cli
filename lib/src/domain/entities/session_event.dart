/// Events a running app session emits, mapped 1:1 from what the presentation
/// layer actually consumes of the `flutter run --machine` protocol.
sealed class SessionEvent {
  const SessionEvent();
}

/// Flutter reported `app.start` — the app has an id and can be controlled.
final class SessionStarted extends SessionEvent {
  const SessionStarted({this.appId, this.deviceId, this.launchMode});

  final String? appId;
  final String? deviceId;
  final String? launchMode;
}

/// The VM service for the app is listening.
final class SessionDebugPort extends SessionEvent {
  const SessionDebugPort({this.vmServiceUri});

  final String? vmServiceUri;
}

/// Flutter served DevTools for this app.
final class SessionDevTools extends SessionEvent {
  const SessionDevTools({this.uri});

  final String? uri;
}

/// One application log line (logcat prefixes already stripped).
final class SessionLogLine extends SessionEvent {
  const SessionLogLine({
    required this.message,
    this.stackTrace = '',
    this.isError = false,
  });

  final String message;
  final String stackTrace;
  final bool isError;
}

/// Tooling progress ("Running Gradle task…").
final class SessionProgress extends SessionEvent {
  const SessionProgress(this.message);

  final String message;
}

/// Flutter reported `app.stop` — the app is gone (the tool process may
/// linger briefly; see [SessionExited]).
final class SessionStopped extends SessionEvent {
  const SessionStopped({this.error = '', this.trace = ''});

  final String error;
  final String trace;
}

enum SessionLogLevel { info, warning, error, status }

/// A log message from the flutter tool itself (`daemon.logMessage`).
final class SessionDaemonLog extends SessionEvent {
  const SessionDaemonLog({required this.message, required this.level});

  final String message;
  final SessionLogLevel level;
}

/// The `flutter run` process exited. Always the final event; the session's
/// event stream closes right after it.
final class SessionExited extends SessionEvent {
  const SessionExited(this.exitCode);

  final int exitCode;
}

/// An event this tool does not model; surfaced for debug visibility.
final class SessionUnknown extends SessionEvent {
  const SessionUnknown({required this.name, required this.params});

  final String name;
  final Map<String, Object?> params;
}
