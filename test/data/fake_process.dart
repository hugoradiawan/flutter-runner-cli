/// Shared in-memory [Process] fake for datasource tests.
///
/// Drives the JSON-RPC-over-stdio protocol (`flutter daemon`,
/// `flutter run --machine`) and plain line-streaming (`melos`) without
/// spawning anything: tests push stdout/stderr bytes through controllers,
/// complete the exit code on demand, and read back what the code under test
/// wrote to stdin.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class FakeProcess implements Process {
  final StreamController<List<int>> stdoutCtrl = StreamController<List<int>>();
  final StreamController<List<int>> stderrCtrl = StreamController<List<int>>();
  final Completer<int> exitCodeCompleter = Completer<int>();
  final FakeStdin stdinSink = FakeStdin();
  bool killed = false;

  @override
  Stream<List<int>> get stdout => stdoutCtrl.stream;

  @override
  Stream<List<int>> get stderr => stderrCtrl.stream;

  @override
  IOSink get stdin => stdinSink;

  @override
  Future<int> get exitCode => exitCodeCompleter.future;

  @override
  int get pid => 4242;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    if (!exitCodeCompleter.isCompleted) exitCodeCompleter.complete(-1);
    return true;
  }

  /// Emit one stdout line (adds the trailing newline).
  void emitStdout(String line) => stdoutCtrl.add(utf8.encode('$line\n'));

  /// Emit one stderr line (adds the trailing newline).
  void emitStderr(String line) => stderrCtrl.add(utf8.encode('$line\n'));

  /// Emit a protocol message in daemon framing: `[{...}]` on one line.
  void writeRpc(Map<String, Object?> message) =>
      emitStdout(json.encode([message]));

  /// The `id` of the [index]-th JSON-RPC request written to stdin.
  int requestId(int index) {
    final decoded = json.decode(stdinSink.lines[index]) as List;
    final map = (decoded.first as Map).cast<String, Object?>();
    return (map['id'] as num).toInt();
  }

  /// The `method` of the [index]-th JSON-RPC request written to stdin.
  String requestMethod(int index) {
    final decoded = json.decode(stdinSink.lines[index]) as List;
    final map = (decoded.first as Map).cast<String, Object?>();
    return map['method'] as String? ?? '';
  }

  /// Complete the exit code and close both pipes, like a real process ending.
  Future<void> exit(int code) async {
    if (!exitCodeCompleter.isCompleted) exitCodeCompleter.complete(code);
    if (!stdoutCtrl.isClosed) await stdoutCtrl.close();
    if (!stderrCtrl.isClosed) await stderrCtrl.close();
  }
}

/// Captures everything written to the process's stdin; can simulate a broken
/// pipe via [throwOnWrite].
class FakeStdin implements IOSink {
  final List<String> lines = <String>[];
  bool throwOnWrite = false;
  final Completer<void> _done = Completer<void>();

  @override
  void writeln([Object? object = '']) {
    if (throwOnWrite) {
      throw const SocketException('broken pipe');
    }
    lines.add('$object');
  }

  @override
  void write(Object? object) => writeln(object);

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> close() async {
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> flush() async {}

  @override
  Encoding encoding = utf8;

  @override
  void add(List<int> data) => writeln(utf8.decode(data));

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {}

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      writeln(objects.join(separator));

  @override
  void writeCharCode(int charCode) => writeln(String.fromCharCode(charCode));
}
