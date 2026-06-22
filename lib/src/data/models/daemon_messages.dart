/// Typed DTOs for records the Flutter daemon emits over its JSON-RPC stream.
///
/// The daemon is intentionally loosely-typed (it adds fields between releases),
/// so these classes only surface what `frun` actually consumes.
library;

class FlutterDevice {
  const FlutterDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.category,
    required this.platformType,
    required this.ephemeral,
    required this.emulator,
    this.emulatorId,
    this.raw,
  });

  final String id;
  final String name;
  final String platform;
  final String? category;
  final String? platformType;
  final bool ephemeral;
  final bool emulator;
  final String? emulatorId;
  final Map<String, Object?>? raw;

  factory FlutterDevice.fromJson(Map<String, Object?> json) => FlutterDevice(
    id: json['id'] as String? ?? '<unknown>',
    name: json['name'] as String? ?? '<unknown>',
    platform: json['platform'] as String? ?? 'unknown',
    category: json['category'] as String?,
    platformType: json['platformType'] as String?,
    ephemeral: (json['ephemeral'] as bool?) ?? true,
    emulator: (json['emulator'] as bool?) ?? false,
    emulatorId: json['emulatorId'] as String?,
    raw: json,
  );
}

class FlutterEmulator {
  const FlutterEmulator({
    required this.id,
    required this.name,
    this.category,
    this.platformType,
  });

  final String id;
  final String name;
  final String? category;
  final String? platformType;

  factory FlutterEmulator.fromJson(Map<String, Object?> json) =>
      FlutterEmulator(
        id: json['id'] as String? ?? '<unknown>',
        name: json['name'] as String? ?? json['id'] as String? ?? '<unknown>',
        category: json['category'] as String?,
        platformType: json['platformType'] as String?,
      );
}

/// Generic event published by the daemon (`device.added`, `app.log`, etc.).
class DaemonEvent {
  const DaemonEvent({required this.name, required this.params});

  final String name;
  final Map<String, Object?> params;
}

/// Thrown when the daemon returns an error for a request.
class DaemonRequestException implements Exception {
  DaemonRequestException(this.method, this.payload);

  final String method;
  final Object? payload;

  @override
  String toString() => 'DaemonRequestException($method): $payload';
}
