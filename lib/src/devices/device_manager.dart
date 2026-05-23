import 'dart:async';

import '../daemon/daemon_messages.dart';
import '../daemon/flutter_daemon.dart';

/// Maintains an up-to-date view of connected devices by subscribing to the
/// daemon's `device.added` / `device.removed` events.
class DeviceManager {
  DeviceManager(this._daemon);

  final FlutterDaemon _daemon;
  final Map<String, FlutterDevice> _devices = <String, FlutterDevice>{};
  final StreamController<List<FlutterDevice>> _changes =
      StreamController<List<FlutterDevice>>.broadcast();
  StreamSubscription<DaemonEvent>? _sub;

  /// Snapshot of the current device list, sorted by name.
  List<FlutterDevice> get devices {
    final list = _devices.values.toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  Stream<List<FlutterDevice>> get changes => _changes.stream;

  FlutterDevice? byId(String? id) => id == null ? null : _devices[id];

  /// Pull the initial list and start listening for changes.
  Future<void> start() async {
    _sub = _daemon.events.listen(_onEvent);
    await _daemon.enableDevicePolling();
    final initial = await _daemon.getDevices();
    for (final d in initial) {
      _devices[d.id] = d;
    }
    _emit();
  }

  void _onEvent(DaemonEvent event) {
    switch (event.name) {
      case 'device.added':
        final device = FlutterDevice.fromJson(event.params);
        _devices[device.id] = device;
        _emit();
      case 'device.removed':
        final id = event.params['id'] as String?;
        if (id != null) {
          _devices.remove(id);
          _emit();
        }
      default:
        break;
    }
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(devices);
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _changes.close();
  }
}
