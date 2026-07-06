import 'session_event.dart';

/// Handle to one live `flutter run` invocation, owned by the data layer's
/// session repository. Presentation holds this to read connection facts and
/// subscribe to [events]; every mutation (reload/restart/stop/detach) goes
/// through the session use cases instead.
abstract class RunSession {
  /// Caller-assigned identity — the run tab id.
  int get id;

  /// Set once Flutter reports `app.start`; required for reload/restart.
  String? get appId;

  /// WebSocket URI of the app's VM service, once reported.
  String? get vmServiceUri;

  /// True after `app.start` (an app id is in hand).
  bool get canHotReload;

  /// Diagnostic line describing the spawn (cwd + argv), for surfacing when a
  /// build fails in a path-dependent way.
  String? get spawnDiagnostic;

  /// Broadcast stream of session events. Ends with [SessionExited], then
  /// closes.
  Stream<SessionEvent> get events;

  /// Invoke a Flutter service extension on the running app.
  Future<Object?> callServiceExtension(
    String method, [
    Map<String, Object?> params = const <String, Object?>{},
  ]);
}
