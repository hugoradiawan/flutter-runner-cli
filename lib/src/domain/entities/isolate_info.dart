/// Frun's view of a single Dart isolate. Mutable: the VM-service listener
/// updates [name]/[status] in place as events arrive.
class IsolateInfoEntity {
  IsolateInfoEntity({
    required this.id,
    required this.name,
    required this.status,
    this.pauseReason,
  });

  final String id;
  String name;
  IsolateStatus status;
  String? pauseReason;
}

enum IsolateStatus { running, paused, exited, unknown }

/// One frame of an isolate's stack, as shown in the isolates panel.
class StackFrameEntity {
  const StackFrameEntity({
    required this.index,
    required this.functionName,
    this.scriptUri,
  });

  final int index;
  final String functionName;
  final String? scriptUri;
}
