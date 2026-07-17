import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/entities/launch_entry.dart';
import '../models/daemon_messages.dart';

/// A single `flutter run --machine` invocation.
///
/// `flutter run --machine` uses the same JSON-RPC framing as `flutter daemon`,
/// but is scoped to one app: it emits `app.start`, `app.debugPort`,
/// `app.started`, `app.devTools`, `app.log`, `app.progress`, `app.stop` events
/// and accepts `app.restart`, `app.callServiceExtension`, `app.stop`,
/// `app.detach` requests.
class AppRunSession {
  AppRunSession._(this._process);

  /// Test seam: wrap an already-started (fake) [process] instead of spawning
  /// `flutter run --machine`. Production code must use [start].
  AppRunSession.forTesting(Process process) : _process = process {
    _listen();
  }

  final Process _process;
  int _nextId = 1;
  final Map<int, Completer<Object?>> _pending = <int, Completer<Object?>>{};
  final StreamController<DaemonEvent> _events =
      StreamController<DaemonEvent>.broadcast();
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  bool _disposed = false;

  // Populated as events arrive.
  String? appId;
  String? vmServiceUri;
  String? devToolsUri;
  String? deviceId;
  String? launchMode;

  /// True once Flutter reports `app.started` — the app is actually running.
  /// `app.start` only means an app id exists; it fires before the build and
  /// install finish, so it must not be used to gate auto-reload.
  bool started = false;

  Stream<DaemonEvent> get events => _events.stream;

  Future<int> get exitCode => _process.exitCode;

  /// Diagnostic line describing this session's spawn (cwd + args). Populated
  /// by [start] so callers can surface it to the user when a build fails in a
  /// way that depends on path resolution (Gradle output discovery, pub
  /// workspaces, etc.). Per-instance so concurrent launches can't clobber
  /// each other's diagnostic.
  String? spawnDiagnostic;

  static Future<AppRunSession> start({
    required String projectRoot,
    required LaunchEntryEntity entry,
    required String deviceId,
    String? flutterExecutable,
    Map<String, String>? environment,
  }) async {
    final exe =
        flutterExecutable ?? (Platform.isWindows ? 'flutter.bat' : 'flutter');

    // Flutter requires the working directory to be the package root (where
    // pubspec.yaml lives). Launching from a workspace ancestor breaks Gradle
    // output discovery on Android ("Gradle build failed to produce an .apk
    // file. It's likely that this file was generated under .../app/build,
    // but the tool couldn't find it."). We resolve target to an absolute
    // path using launch.json `cwd` (when set) or projectRoot, then always
    // spawn from projectRoot.
    final workingDir = projectRoot;
    final launchBase = entry.cwd != null && entry.cwd!.isNotEmpty
        ? entry.cwd!
        : projectRoot;
    final target = p.isAbsolute(entry.program)
        ? entry.program
        : p.normalize(p.join(launchBase, entry.program));

    final args = <String>[
      'run',
      '--machine',
      '-d',
      deviceId,
      '-t',
      target,
      if (entry.flutterMode != null) '--${entry.flutterMode}',
      if (entry.flavor != null) ...['--flavor', entry.flavor!],
      ...entry.toolArgs,
      if (entry.args.isNotEmpty) ...['--', ...entry.args],
    ];

    final process = await Process.start(
      exe,
      args,
      workingDirectory: workingDir,
      environment: environment,
      runInShell: Platform.isWindows,
    );
    final session = AppRunSession._(process)
      ..deviceId = deviceId
      ..spawnDiagnostic =
          'spawn: cwd=$workingDir exe=$exe args=${args.join(' ')}';
    session._listen();
    return session;
  }

  void _listen() {
    _stdoutSub = _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleStdout);
    _stderrSub = _process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (_disposed || _events.isClosed) return;
          if (line.isEmpty) return;
          _events.add(
            DaemonEvent(
              name: 'app.log',
              params: <String, Object?>{'log': line, 'error': true},
            ),
          );
        });
    unawaited(_process.exitCode.whenComplete(_close));
    // A write to the stdin of a dead process surfaces its broken-pipe error on
    // `stdin.done`; without a listener that error is uncaught and fatal.
    unawaited(_process.stdin.done.catchError((_) {}));
  }

  void _handleStdout(String line) {
    if (_disposed || _events.isClosed) return;
    if (!line.startsWith('[')) {
      // Non-RPC chatter — surface as a log line.
      if (line.isNotEmpty) {
        _events.add(
          DaemonEvent(name: 'app.log', params: <String, Object?>{'log': line}),
        );
      }
      return;
    }
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
      return;
    }

    if (map.containsKey('event')) {
      final name = map['event'] as String? ?? '';
      final params =
          (map['params'] as Map?)?.cast<String, Object?>() ??
          <String, Object?>{};
      _absorb(name, params);
      if (!_events.isClosed) {
        _events.add(DaemonEvent(name: name, params: params));
      }
    }
  }

  void _absorb(String event, Map<String, Object?> params) {
    switch (event) {
      case 'app.start':
        appId = params['appId'] as String? ?? appId;
        deviceId = params['deviceId'] as String? ?? deviceId;
        launchMode = params['launchMode'] as String? ?? launchMode;
      case 'app.started':
        started = true;
      case 'app.debugPort':
        vmServiceUri = params['wsUri'] as String? ?? vmServiceUri;
      case 'app.devTools':
        devToolsUri =
            params['wsUri'] as String? ??
            params['uri'] as String? ??
            devToolsUri;
    }
  }

  Future<Object?> _request(
    String method, [
    Map<String, Object?> params = const <String, Object?>{},
  ]) {
    if (_disposed) {
      return Future.error(StateError('AppRunSession is disposed'));
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
    try {
      _process.stdin.writeln(payload);
    } catch (e) {
      _pending.remove(id);
      return Future.error(StateError('flutter run stdin write failed: $e'));
    }
    return completer.future;
  }

  Future<void> hotReload({String reason = 'manual'}) async {
    final id = appId;
    if (id == null) throw StateError('App has not started yet.');
    await _request('app.restart', <String, Object?>{
      'appId': id,
      'fullRestart': false,
      'reason': reason,
      'pause': false,
    });
  }

  Future<void> hotRestart({String reason = 'manual'}) async {
    final id = appId;
    if (id == null) throw StateError('App has not started yet.');
    await _request('app.restart', <String, Object?>{
      'appId': id,
      'fullRestart': true,
      'reason': reason,
      'pause': false,
    });
  }

  Future<Object?> callServiceExtension(
    String method, [
    Map<String, Object?> params = const <String, Object?>{},
  ]) async {
    final id = appId;
    if (id == null) throw StateError('App has not started yet.');
    return _request('app.callServiceExtension', <String, Object?>{
      'appId': id,
      'methodName': method,
      if (params.isNotEmpty) 'params': params,
    });
  }

  Future<void> stop() async {
    if (_disposed) return;
    final id = appId;
    if (id != null) {
      try {
        await _request('app.stop', <String, Object?>{'appId': id});
      } catch (_) {
        /* may already be stopped */
      }
    }
    _close();
  }

  Future<void> detach() async {
    if (_disposed) return;
    final id = appId;
    if (id != null) {
      try {
        await _request('app.detach', <String, Object?>{'appId': id});
      } catch (_) {
        /* app may already be gone; detach is best-effort */
      }
    }
    _closeWithoutKill();
  }

  void _closeWithoutKill() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_stdoutSub?.cancel());
    unawaited(_stderrSub?.cancel());
    _stdoutSub = null;
    _stderrSub = null;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('flutter run detached'));
      }
    }
    _pending.clear();
    _events.close();
  }

  void _close() {
    if (_disposed) return;
    _disposed = true;
    // Stop pulling from the child's pipes BEFORE closing the events
    // controller — otherwise late stdout/stderr lines would try to publish
    // to an already-closed StreamController and crash the host.
    unawaited(_stdoutSub?.cancel());
    unawaited(_stderrSub?.cancel());
    _stdoutSub = null;
    _stderrSub = null;
    try {
      _process.kill();
    } catch (_) {
      /* already dead */
    }
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('flutter run exited'));
      }
    }
    _pending.clear();
    _events.close();
  }
}
