import '../entities/isolate_info.dart';

enum IsolateStepMode { over, into, out }

/// Live view of a running app's isolates plus lifecycle controls, backed by
/// the VM service.
abstract class IsolateControl {
  /// True while a VM-service connection is live.
  bool get isConnected;

  /// Monotonic version, bumped on every isolate list/status change. Lets the
  /// TUI's frame signature use one int instead of hashing every isolate per
  /// frame.
  int get revision;

  /// Current isolates, sorted by name.
  List<IsolateInfoEntity> get isolates;

  /// Notified whenever the isolate list or one of its statuses changes.
  Stream<List<IsolateInfoEntity>> get changes;

  /// Payloads of `Flutter.Error` extension events from the running app.
  Stream<Map<String, Object?>> get flutterErrors;

  Future<void> connect(String wsUri);
  Future<void> disconnect();
  Future<void> refresh();

  Future<void> pause(String id);
  Future<void> resume(String id, {IsolateStepMode? step});
  Future<void> kill(String id);

  /// The isolate's current stack (capped upstream), or null when no
  /// VM-service connection is live.
  Future<List<StackFrameEntity>?> stack(String id);
}
