import '../entities/self_memory.dart';

/// Introspects frun's *own* Dart VM (not the child app's) so `/mem` can show
/// where the process's memory goes. Only usable when frun was launched with
/// its VM service enabled (`dart run --enable-vm-service` or
/// `DART_VM_OPTIONS=--enable-vm-service` for a compiled exe); every method
/// degrades to false/null otherwise.
abstract class SelfMemoryInspector {
  /// True when frun's own VM exposes a service protocol to connect to.
  Future<bool> isAvailable();

  /// Heap totals + per-class allocation profile for frun's main isolate.
  /// [forceGc] runs a full GC first (the basis of `/mem gc`). Null when no
  /// self VM service is available.
  Future<SelfMemoryReportEntity?> report({bool forceGc = false});

  /// VM-internal RSS breakdown tree. Null when unavailable or when the SDK
  /// doesn't support the underlying (private) RPC.
  Future<ProcessMemoryNodeEntity?> processMemoryTree();

  /// Last connection/RPC failure, for surfacing in command output.
  String? get lastError;

  Future<void> dispose();
}
