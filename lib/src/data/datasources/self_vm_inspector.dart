import 'dart:developer' as developer;
import 'dart:isolate';

import 'package:vm_service/vm_service.dart' as vm;
import 'package:vm_service/vm_service_io.dart';

import '../../domain/entities/self_memory.dart';
import '../../domain/ports/self_memory_inspector.dart';

/// Connects to frun's *own* VM service (a separate connection from the child
/// app's [IsolateManager]) and implements the domain [SelfMemoryInspector]
/// port. Only works when the process was launched with the VM service
/// enabled; otherwise every method reports unavailable.
class SelfVmInspector implements SelfMemoryInspector {
  SelfVmInspector({vm.VmService? service}) : _service = service;

  vm.VmService? _service;
  String? _lastError;

  @override
  String? get lastError => _lastError;

  @override
  Future<bool> isAvailable() async => await _connect() != null;

  /// Lazily connect to this process's own service protocol. A null server URI
  /// (VM service not enabled) is not cached — the check is cheap and keeps
  /// the answer honest if the environment changes.
  Future<vm.VmService?> _connect() async {
    if (_service != null) return _service;
    try {
      final info = await developer.Service.getInfo();
      final wsUri = info.serverWebSocketUri;
      if (wsUri == null) return null;
      return _service = await vmServiceConnectUri(wsUri.toString());
    } catch (e) {
      _lastError = '$e';
      return null;
    }
  }

  @override
  Future<SelfMemoryReportEntity?> report({bool forceGc = false}) async {
    final profile = await _withService(
      (service, isolateId) =>
          service.getAllocationProfile(isolateId, gc: forceGc ? true : null),
    );
    if (profile == null) return null;
    final usage = profile.memoryUsage;
    return SelfMemoryReportEntity(
      heap: SelfHeapUsageEntity(
        heapUsed: usage?.heapUsage ?? 0,
        heapCapacity: usage?.heapCapacity ?? 0,
        externalUsage: usage?.externalUsage ?? 0,
      ),
      classes: mapClassStats(profile.members),
      gcPerformed: forceGc,
    );
  }

  @override
  Future<ProcessMemoryNodeEntity?> processMemoryTree() async {
    final response = await _withService(
      (service, _) => service.callMethod('_getProcessMemoryUsage'),
    );
    final json = response?.json;
    return mapProcessMemoryJson(json?['root'] as Map<String, Object?>?);
  }

  /// Run one RPC against the main isolate, retrying once on a stale
  /// connection (the service socket dies silently if DDS restarts).
  Future<T?> _withService<T>(
    Future<T> Function(vm.VmService service, String isolateId) body,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final service = await _connect();
      if (service == null) return null;
      final isolateId = developer.Service.getIsolateId(Isolate.current);
      if (isolateId == null) return null;
      try {
        return await body(service, isolateId);
      } on vm.RPCError catch (e) {
        // The service answered — the method is unsupported or the request was
        // bad. The connection is healthy; retrying won't change the answer.
        _lastError = '$e';
        return null;
      } catch (e) {
        _lastError = '$e';
        await dispose();
      }
    }
    return null;
  }

  /// [vm.ClassHeapStats] → entities: drop empty rows, sort descending by
  /// retained bytes. Static so tests can exercise it without a connection.
  static List<HeapClassStatEntity> mapClassStats(
    List<vm.ClassHeapStats>? members,
  ) {
    final stats = <HeapClassStatEntity>[
      for (final member in members ?? const <vm.ClassHeapStats>[])
        if ((member.bytesCurrent ?? 0) > 0)
          HeapClassStatEntity(
            className: member.classRef?.name ?? '<unknown>',
            libraryUri: member.classRef?.library?.uri,
            bytes: member.bytesCurrent ?? 0,
            instances: member.instancesCurrent ?? 0,
          ),
    ]..sort((a, b) => b.bytes.compareTo(a.bytes));
    return stats;
  }

  /// Recursive `_getProcessMemoryUsage` JSON → entity tree. Static for
  /// connection-free unit tests; null in → null out.
  static ProcessMemoryNodeEntity? mapProcessMemoryJson(
    Map<String, Object?>? json,
  ) {
    if (json == null) return null;
    return ProcessMemoryNodeEntity(
      name: json['name'] as String? ?? '<unnamed>',
      description: json['description'] as String?,
      sizeBytes: (json['size'] as num?)?.toInt() ?? 0,
      children: [
        for (final child in json['children'] as List<Object?>? ?? const [])
          if (child is Map<String, Object?>) ?mapProcessMemoryJson(child),
      ],
    );
  }

  @override
  Future<void> dispose() async {
    await _service?.dispose();
    _service = null;
  }
}
