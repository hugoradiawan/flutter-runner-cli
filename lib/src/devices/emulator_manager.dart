import 'dart:async';

import '../data/models/daemon_messages.dart';
import '../data/datasources/flutter_daemon.dart';

class EmulatorManager {
  EmulatorManager(this._daemon);

  final FlutterDaemon _daemon;

  Future<List<FlutterEmulator>> list() => _daemon.getEmulators();

  Future<void> launch(String id, {bool coldBoot = false}) =>
      _daemon.launchEmulator(id, coldBoot: coldBoot);

  Future<void> create({String? name}) => _daemon.createEmulator(name: name);

  /// Launches [id] and resolves with the freshly-added [FlutterDevice] once
  /// the daemon reports it. Times out after [timeout].
  Future<FlutterDevice?> launchAndAwaitDevice(
    String id, {
    bool coldBoot = false,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final completer = Completer<FlutterDevice?>();
    final sub = _daemon.events.listen((event) {
      if (event.name != 'device.added') return;
      final device = FlutterDevice.fromJson(event.params);
      if (device.emulatorId == id && !completer.isCompleted) {
        completer.complete(device);
      }
    });
    try {
      await _daemon.launchEmulator(id, coldBoot: coldBoot);
    } catch (e) {
      if (!completer.isCompleted) completer.completeError(e);
    }
    return completer.future.timeout(
      timeout,
      onTimeout: () => null,
    ).whenComplete(sub.cancel);
  }
}


