import 'dart:async';

import 'package:vm_service/vm_service.dart' as vm;

import 'app_state.dart';
import 'flutter_error_renderer.dart';
import 'run_tab.dart';

/// Owns the single shared VM-service / [IsolateManager] connection that follows
/// the active [RunTab].
///
/// Only one isolate connection exists per process; this re-points it at
/// whichever tab is active so the UX stays coherent. The active tab is read
/// lazily through [activeTab] so this collaborator never holds a stale
/// reference.
class IsolateConnection {
  IsolateConnection(this._state, this.activeTab);

  final AppState _state;

  /// Reads the controller's currently-active tab on demand.
  final RunTab? Function() activeTab;

  StreamSubscription<vm.Event>? _extensionSub;

  /// VM-service ws URI currently connected to. Guards against redundant
  /// reconnects when re-pointing to the active tab.
  String? _connectedVmUri;

  /// Re-point the connection at the active tab's VM service. Commands that act
  /// on the running app (`inspect`, `devtools`, `isolates`) call this first so
  /// they operate on the *selected* tab's device rather than whichever device
  /// connected last.
  ///
  /// Returns `true` when a live VM service is connected for the active tab.
  Future<bool> ensureForActiveTab() async {
    final ws = activeTab()?.session?.vmServiceUri;
    if (ws == null) {
      await disconnect();
      return false;
    }
    if (_connectedVmUri == ws && _state.isolateManager.service != null) {
      return true;
    }
    await connect(ws);
    return _state.isolateManager.service != null;
  }

  Future<void> connect(String wsUri) async {
    try {
      await _state.isolateManager.connect(wsUri);
      _connectedVmUri = wsUri;
      _state.transcript.system(
        'VM service connected (${_state.isolateManager.isolates.length} isolates).',
      );
      await _extensionSub?.cancel();
      _extensionSub = _state.isolateManager.extensionEvents.listen(
        _onExtensionEvent,
      );
    } catch (e) {
      _connectedVmUri = null;
      _state.transcript.warn('VM service connect failed: $e');
    }
  }

  Future<void> disconnect() async {
    await _extensionSub?.cancel();
    _extensionSub = null;
    _connectedVmUri = null;
    await _state.isolateManager.disconnect();
  }

  void _onExtensionEvent(vm.Event event) {
    if (event.extensionKind != 'Flutter.Error') return;
    final tab = activeTab();
    if (tab == null) return;
    final data = event.extensionData?.data ?? const <String, dynamic>{};
    tab.transcript.error(
      renderFlutterError(
        data,
        verbose: _state.config.verboseErrors,
        projectRoot: _state.project.root,
      ),
    );
  }
}
