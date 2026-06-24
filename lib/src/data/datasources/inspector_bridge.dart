import 'dart:async';
import 'dart:convert';

import 'package:vm_service/vm_service.dart' as vm;

import '../../app/app_state.dart';
import '../models/source_location.dart';

/// Bridges widget-inspector selection in the running app to a jump-to-source
/// action in the user's IDE.
///
/// Two paths:
///   • In-app tap during `/inspect` mode → Flutter posts `Flutter.Selection`
///     with a full `creationLocation` payload. Handled synchronously via
///     [_handleSelectionEvent].
///   • DevTools widget-tree click → no useful extension event is broadcast
///     (Flutter only fires `Flutter.Frame`/`Flutter.ServiceExtensionStateChanged`).
///     A 500 ms poll on `ext.flutter.inspector.getSelectedSummaryWidget`
///     picks up the change.
class InspectorBridge {
  static const _objectGroup = 'frun-inspector';
  static const _pollInterval = Duration(milliseconds: 500);

  StreamSubscription<vm.Event>? _sub;
  Timer? _poll;
  bool _polling = false;
  bool _primed = false;
  String? _lastKey;

  bool get isAttached => _sub != null || _poll != null;

  /// (Re)subscribe to selection events and start polling. Safe to call
  /// repeatedly; cancels any prior subscription/timer first so the bridge
  /// survives app restarts that swap the underlying VM-service stream.
  void attach(AppState state) {
    _sub?.cancel();
    _poll?.cancel();
    _primed = false;
    _sub = state.isolateManager.extensionEvents.listen((event) {
      if (event.extensionKind == 'Flutter.Selection') {
        _handleSelectionEvent(event, state);
      }
    });
    _poll = Timer.periodic(_pollInterval, (_) => _pollSelection(state));
  }

  Future<void> detach() async {
    await _sub?.cancel();
    _poll?.cancel();
    _sub = null;
    _poll = null;
    _lastKey = null;
    _primed = false;
  }

  Future<void> _handleSelectionEvent(vm.Event event, AppState state) async {
    final data = event.extensionData?.data ?? const <String, dynamic>{};
    final loc = _extractLocation(data);
    // User-driven tap — always open regardless of _primed state.
    if (loc != null) await _open(loc, state, skipPrimingCheck: true);
  }

  Future<void> _pollSelection(AppState state) async {
    if (_polling) return;
    _polling = true;
    try {
      final loc = await _fetchSelectedLocation(state);
      if (loc != null) await _open(loc, state);
    } finally {
      _polling = false;
    }
  }

  Future<void> _open(
    _CreationLocation loc,
    AppState state, {
    bool skipPrimingCheck = false,
  }) async {
    final src = SourceLocation.fromVmServiceUri(
      loc.uri,
      projectRoot: state.project.root,
      line: loc.line,
      column: loc.column,
    );
    if (src == null) return;
    final key = '${src.file}:${src.line}:${src.column}';
    // Only open when selection actually changes. Without this, the 500 ms
    // poller would re-launch the IDE on every tick and yank focus away
    // continuously.
    if (key == _lastKey) return;
    final wasPrimed = _primed;
    _primed = true;
    _lastKey = key;
    // First poll observation after attach is the pre-existing selection —
    // skip it. User-driven Flutter.Selection events bypass this guard.
    if (!wasPrimed && !skipPrimingCheck) return;
    await state.ideLauncher.open(src, state);
  }

  /// Asks the running app for the currently-selected widget and pulls its
  /// `creationLocation`.
  Future<_CreationLocation?> _fetchSelectedLocation(AppState state) async {
    final session = state.runController.session;
    if (session == null) return null;
    for (final method in const [
      'ext.flutter.inspector.getSelectedSummaryWidget',
      'ext.flutter.inspector.getSelectedWidget',
    ]) {
      try {
        final result = await session.callServiceExtension(
          method,
          <String, Object?>{'objectGroup': _objectGroup},
        );
        final loc = _extractFromResponse(result);
        if (loc != null) return loc;
      } catch (_) {
        // Try next method.
      }
    }
    return null;
  }

  _CreationLocation? _extractFromResponse(Object? response) {
    final node = _coerceMap(response);
    if (node == null) return null;
    // Service-extension responses are often wrapped as {type, method, result}.
    // The `result` may itself be a Map or a JSON-encoded string.
    final inner = _coerceMap(node['result']);
    return _extractLocation(inner ?? node);
  }

  Map<dynamic, dynamic>? _coerceMap(Object? value) {
    if (value is Map) return value;
    if (value is String && value.isNotEmpty) {
      try {
        final decoded = json.decode(value);
        if (decoded is Map) return decoded;
      } catch (_) {}
    }
    return null;
  }

  _CreationLocation? _extractLocation(Map<dynamic, dynamic> data) {
    final loc = _coerceMap(data['creationLocation']) ??
        _coerceMap(_coerceMap(data['value'])?['creationLocation']);
    if (loc == null) return null;
    final file = (loc['file'] ?? loc['uri'])?.toString();
    if (file == null || file.isEmpty) return null;
    final line = (loc['line'] as num?)?.toInt() ?? 1;
    final column = (loc['column'] as num?)?.toInt() ?? 1;
    return _CreationLocation(uri: file, line: line, column: column);
  }
}

class _CreationLocation {
  _CreationLocation({required this.uri, required this.line, required this.column});
  final String uri;
  final int line;
  final int column;
}
