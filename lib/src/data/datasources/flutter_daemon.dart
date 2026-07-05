import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/daemon_messages.dart';

/// Thin client for `flutter daemon`.
///
/// The Flutter tool's "daemon" mode reads JSON-RPC commands on stdin and emits
/// responses + events on stdout. Each protocol message is a JSON list with one
/// object inside, on its own line:
///
///     [{"id":1,"method":"device.getDevices"}]
///     [{"id":1,"result":[...]}]
///     [{"event":"device.added","params":{...}}]
///
/// Non-protocol lines (banners, log spam) are ignored.
///
/// This class owns the [Process] and an internal stream of [DaemonEvent]s.
class FlutterDaemon {
  FlutterDaemon._({required Process process, required String executable})
    : _process = process,
      _executable = executable;

  final Process _process;
  // The resolved `flutter` (or `flutter.bat`) path we launched. Useful for
  // diagnostics; kept on the instance so callers can read it via [executable].
  final String _executable;
  int _nextId = 1;
  final Map<int, Completer<Object?>> _pending = <int, Completer<Object?>>{};
  final StreamController<DaemonEvent> _events =
      StreamController<DaemonEvent>.broadcast();
  final StreamController<String> _stderrLines =
      StreamController<String>.broadcast();
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  bool _disposed = false;

  /// Path of the `flutter` binary used to launch the daemon.
  String get executable => _executable;

  /// Broadcast stream of every event the daemon emits.
  Stream<DaemonEvent> get events => _events.stream;

  /// Diagnostic stream of every stderr line written by the daemon.
  Stream<String> get stderrLines => _stderrLines.stream;

  /// Spawn `flutter daemon` and return a ready-to-use client.
  ///
  /// Throws [ProcessException] when `flutter` is not on the PATH.
  static Future<FlutterDaemon> start({
    String? flutterExecutable,
    Map<String, String>? environment,
  }) async {
    final exe = flutterExecutable ?? _defaultFlutterExecutable();
    final process = await Process.start(
      exe,
      const ['daemon'],
      environment: environment,
      runInShell: Platform.isWindows,
    );
    final daemon = FlutterDaemon._(process: process, executable: exe);
    daemon._listen();
    return daemon;
  }

  static String _defaultFlutterExecutable() =>
      Platform.isWindows ? 'flutter.bat' : 'flutter';

  void _listen() {
    _stdoutSub = _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleStdoutLine, onError: _onStdioError);
    _stderrSub = _process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (_disposed || _stderrLines.isClosed) return;
          if (line.isNotEmpty) _stderrLines.add(line);
        });
    unawaited(_process.exitCode.whenComplete(_failPending));
  }

  void _handleStdoutLine(String line) {
    if (_disposed) return;
    if (!line.startsWith('[')) return;
    final Object? decoded;
    try {
      decoded = json.decode(line);
    } catch (_) {
      return;
    }
    if (decoded is! List || decoded.isEmpty) return;
    final entry = decoded.first;
    if (entry is! Map) return;
    final map = entry.cast<String, Object?>();
    if (map.containsKey('id')) {
      final id = (map['id'] as num).toInt();
      final completer = _pending.remove(id);
      if (completer == null) return;
      if (map.containsKey('error')) {
        completer.completeError(DaemonRequestException('id=$id', map['error']));
      } else {
        completer.complete(map['result']);
      }
    } else if (map.containsKey('event')) {
      final name = map['event'] as String? ?? '';
      final params =
          (map['params'] as Map?)?.cast<String, Object?>() ??
          <String, Object?>{};
      if (!_events.isClosed) {
        _events.add(DaemonEvent(name: name, params: params));
      }
    }
  }

  void _onStdioError(Object error, StackTrace stack) {
    if (_disposed || _stderrLines.isClosed) return;
    _stderrLines.add('daemon stdout error: $error');
  }

  void _failPending() {
    final ex = StateError('Flutter daemon exited (code ${_process.exitCode})');
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(ex);
    }
    _pending.clear();
  }

  /// Send a JSON-RPC request and await its result.
  Future<Object?> request(
    String method, [
    Map<String, Object?> params = const <String, Object?>{},
  ]) {
    if (_disposed) {
      return Future.error(StateError('FlutterDaemon is disposed'));
    }
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    final payload = json.encode([
      <String, Object?>{
        'id': id,
        'method': method,
        if (params.isNotEmpty) 'params': params,
      },
    ]);
    _process.stdin.writeln(payload);
    return completer.future;
  }

  Future<List<FlutterDevice>> getDevices() async {
    final raw = await request('device.getDevices');
    if (raw is! List) return const <FlutterDevice>[];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map((m) => FlutterDevice.fromJson(m.cast<String, Object?>()))
        .toList(growable: false);
  }

  Future<void> enableDevicePolling() async {
    await request('device.enable');
  }

  Future<List<FlutterEmulator>> getEmulators() async {
    final raw = await request('emulator.getEmulators');
    if (raw is! List) return const <FlutterEmulator>[];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map((m) => FlutterEmulator.fromJson(m.cast<String, Object?>()))
        .toList(growable: false);
  }

  Future<void> launchEmulator(String id, {bool coldBoot = false}) async {
    await request('emulator.launch', <String, Object?>{
      'emulatorId': id,
      if (coldBoot) 'coldBoot': true,
    });
  }

  Future<void> createEmulator({String? name}) async {
    await request('emulator.create', <String, Object?>{'name': ?name});
  }

  /// Ask the daemon to serve DevTools. Returns the served `host:port`.
  Future<Map<String, Object?>> serveDevTools() async {
    final raw = await request('devtools.serve');
    if (raw is Map) return raw.cast<String, Object?>();
    return <String, Object?>{};
  }

  Future<void> shutdown() async {
    if (_disposed) return;
    try {
      await request('daemon.shutdown');
    } catch (_) {
      /* daemon may already be gone */
    }
    _disposed = true;
    // Cancel pipes BEFORE closing the controllers so late lines don't crash.
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    try {
      _process.kill();
    } catch (_) {
      /* already dead */
    }
    await _events.close();
    await _stderrLines.close();
  }
}
