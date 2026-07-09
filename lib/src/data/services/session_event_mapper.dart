import '../../domain/entities/session_event.dart';
import '../models/daemon_messages.dart';

/// Maps a raw `flutter run --machine` [DaemonEvent] onto the domain
/// [SessionEvent] hierarchy. Pure — no IO, no state.
SessionEvent mapDaemonEvent(DaemonEvent event) {
  final params = event.params;
  switch (event.name) {
    case 'app.start':
      return SessionStarted(
        appId: params['appId']?.toString(),
        deviceId: params['deviceId']?.toString(),
        launchMode: params['launchMode']?.toString(),
      );
    case 'app.debugPort':
      return SessionDebugPort(vmServiceUri: params['wsUri']?.toString());
    case 'app.devTools':
      return SessionDevTools(
        uri: (params['wsUri'] ?? params['uri'])?.toString(),
      );
    case 'app.log':
      return SessionLogLine(
        message: normalizeAppLog(params['log']?.toString() ?? ''),
        stackTrace: params['stackTrace']?.toString() ?? '',
        isError: params['error'] == true,
      );
    case 'app.progress':
      return SessionProgress(params['message']?.toString() ?? '');
    case 'app.stop':
      return SessionStopped(
        error: params['error']?.toString() ?? '',
        trace: params['trace']?.toString() ?? '',
      );
    case 'daemon.logMessage':
      return SessionDaemonLog(
        message: params['message']?.toString() ?? '',
        level: switch (params['level']?.toString()) {
          'error' => SessionLogLevel.error,
          'warning' => SessionLogLevel.warning,
          'status' => SessionLogLevel.status,
          _ => SessionLogLevel.info,
        },
      );
    default:
      return SessionUnknown(name: event.name, params: params);
  }
}

/// iOS/macOS `print()` output is delivered as `flutter: <text>` with the ESC
/// control byte rendered in caret notation by Apple's unified logging, so ANSI
/// color codes arrive as the literal characters `\^[[38;5;208m` (an escaping
/// backslash, the caret-notation ESC `^[`, then the `[` CSI intro) instead of a
/// real `\x1b[…m`. Undo both — rebuild the CSI introducer so the transcript's
/// ANSI pipeline colors it, and drop the `flutter: ` prefix — so iOS/macOS logs
/// render like Android's (which already carry real ESC bytes).
///
/// De-caret is scoped to the `^[[` CSI introducer (plus its optional escaping
/// backslash) so it only touches escape sequences, and the leading-`flutter: `
/// strip is per line. Android lines (real ESC, logcat-tagged) match neither
/// guard, so this is a no-op on the already-working path.
String normalizeAppLog(String log) {
  var out = stripLogcatPrefix(log);
  if (out.contains('^[[')) out = out.replaceAll(_caretCsi, '\x1b[');
  if (out.startsWith('flutter: ') || out.contains('\nflutter: ')) {
    out = out.replaceAll(_flutterPrefix, '');
  }
  return out;
}

/// Caret-notation CSI introducer as delivered by Apple's unified logging: an
/// optional escaping backslash, `^[` (caret-notation ESC), then the `[` CSI
/// intro — e.g. `\^[[38;5;208m` or `^[[0m`. Rewritten to a real `\x1b[`.
final _caretCsi = RegExp(r'\\?\^\[\[');

/// Leading `flutter: ` prefix on any line (iOS/macOS/desktop `print` output).
final _flutterPrefix = RegExp(r'^flutter: ', multiLine: true);

/// Android logcat tags each line with e.g. `I/flutter ( 7225): `. Strip it
/// so the transcript shows only the app's own log text.
final _logcatPrefix = RegExp(r'^[VDIWEF]/[^(]*\(\s*\d+\):\s?', multiLine: true);

/// Cheap reject before the regex: this runs for every `app.log` event, and
/// most payloads are single untagged lines. Only reach [_logcatPrefix] when
/// the first line looks tagged (`X/` with X in VDIWEF) or the payload is
/// multi-line (later lines may be tagged).
String stripLogcatPrefix(String log) {
  if (log.length < 4) return log;
  final tagged =
      log.codeUnitAt(1) == 0x2F /* '/' */ &&
      switch (log.codeUnitAt(0)) {
        0x56 || 0x44 || 0x49 || 0x57 || 0x45 || 0x46 => true, // VDIWEF
        _ => false,
      };
  if (!tagged && !log.contains('\n')) return log;
  return log.replaceAll(_logcatPrefix, '');
}
