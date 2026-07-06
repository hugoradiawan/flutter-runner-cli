import 'package:equatable/equatable.dart';

/// Heap counters for frun's own VM, as reported by its allocation profile.
/// All values are bytes.
class SelfHeapUsageEntity extends Equatable {
  const SelfHeapUsageEntity({
    required this.heapUsed,
    required this.heapCapacity,
    required this.externalUsage,
  });

  /// Live Dart objects.
  final int heapUsed;

  /// Memory the GC has reserved for the heap (>= [heapUsed]).
  final int heapCapacity;

  /// Native allocations tied to Dart objects (e.g. typed-data backing stores).
  final int externalUsage;

  @override
  List<Object?> get props => [heapUsed, heapCapacity, externalUsage];
}

/// One class's share of the live heap.
class HeapClassStatEntity extends Equatable {
  const HeapClassStatEntity({
    required this.className,
    this.libraryUri,
    required this.bytes,
    required this.instances,
  });

  final String className;
  final String? libraryUri;

  /// Bytes currently retained by live instances of this class.
  final int bytes;

  /// Live instance count.
  final int instances;

  /// Stable identity for diffing across snapshots — class names alone can
  /// collide between libraries.
  String get key => '${libraryUri ?? ''}|$className';

  @override
  List<Object?> get props => [className, libraryUri, bytes, instances];
}

/// Point-in-time picture of frun's own heap: totals plus the per-class
/// breakdown ("where the MBs come from").
class SelfMemoryReportEntity extends Equatable {
  const SelfMemoryReportEntity({
    required this.heap,
    required this.classes,
    required this.gcPerformed,
  });

  final SelfHeapUsageEntity heap;

  /// Sorted descending by [HeapClassStatEntity.bytes]; zero-byte rows dropped.
  final List<HeapClassStatEntity> classes;

  /// True when a full GC ran immediately before this measurement.
  final bool gcPerformed;

  @override
  List<Object?> get props => [heap, classes, gcPerformed];
}

/// Node in the VM's process-memory breakdown tree (Dart heap, code, profiler,
/// ...), sourced from the private `_getProcessMemoryUsage` RPC. Optional
/// detail: absent on SDKs that drop the RPC.
class ProcessMemoryNodeEntity extends Equatable {
  const ProcessMemoryNodeEntity({
    required this.name,
    this.description,
    required this.sizeBytes,
    required this.children,
  });

  final String name;
  final String? description;
  final int sizeBytes;
  final List<ProcessMemoryNodeEntity> children;

  @override
  List<Object?> get props => [name, description, sizeBytes, children];
}
