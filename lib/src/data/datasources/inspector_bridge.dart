import 'dart:async';
import 'dart:convert';

import 'package:vm_service/vm_service.dart' as vm;

import '../../domain/ports/vm_uri_resolver.dart';
import '../../domain/value_objects/source_location.dart';
import '../services/package_config_uri_resolver.dart';

/// Calls a service extension on the currently-running app. Returns the
/// decoded response. The bridge asks for a fresh caller before every poll so
/// it always targets the active session (which may be swapped by restarts).
typedef ServiceExtensionCaller =
    Future<Object?> Function(String method, Map<String, Object?> params);

/// Bridges widget-inspector selection in the running app to a jump-to-source
/// action, emitted as [selectionJumps] for the presentation layer to route
/// into the user's IDE.
///
/// Two paths:
///   • In-app tap during `inspect` mode → Flutter posts `Flutter.Selection`
///     with a full `creationLocation` payload. Handled synchronously via
///     [_handleSelectionEvent].
///   • DevTools widget-tree click → no useful extension event is broadcast
///     (Flutter only fires `Flutter.Frame`/`Flutter.ServiceExtensionStateChanged`).
///     A poll on `ext.flutter.inspector.getSelectedSummaryWidget` picks up the
///     change. The poll adapts: 500 ms while the selection is actively
///     changing, backing off to 2 s once it has been quiet for a few seconds —
///     each poll is a VM-service RPC round-trip, so the fast cadence would
///     otherwise burn CPU/network for as long as the bridge stays attached.
class InspectorBridge {
  InspectorBridge({
    required Stream<vm.Event> extensionEvents,
    VmUriResolver resolver = const PackageConfigUriResolver(),
  }) : _extensionEvents = extensionEvents,
       _resolver = resolver;

  static const _objectGroup = 'frun-inspector';
  static const _pollInterval = Duration(milliseconds: 500);
  static const _idlePollInterval = Duration(seconds: 2);

  /// Consecutive no-change polls (~5 s at the fast cadence) before backing off.
  static const _idleThreshold = 10;

  final Stream<vm.Event> _extensionEvents;
  final VmUriResolver _resolver;

  final StreamController<SourceLocation> _jumps =
      StreamController<SourceLocation>.broadcast();

  /// Resolved source locations the user selected in the running app. The
  /// composition root routes these into the IDE opener.
  Stream<SourceLocation> get selectionJumps => _jumps.stream;

  ServiceExtensionCaller? Function()? _serviceExtension;
  String? _projectRoot;

  StreamSubscription<vm.Event>? _sub;
  Timer? _poll;
  bool _polling = false;
  bool _primed = false;
  String? _lastKey;
  int _quietPolls = 0;
  bool _pollIdle = false;

  /// Invalidates in-flight poll chains when attach/detach swaps state.
  int _pollGeneration = 0;

  bool get isAttached => _sub != null || _poll != null;

  /// Current poll cadence (test hook).
  Duration get debugPollInterval =>
      _pollIdle ? _idlePollInterval : _pollInterval;

  /// (Re)subscribe to selection events and start polling. Safe to call
  /// repeatedly; cancels any prior subscription/timer first so the bridge
  /// survives app restarts that swap the underlying VM-service stream.
  ///
  /// [serviceExtension] is re-invoked before every poll and must return the
  /// caller for the currently-active session, or null when none is running.
  void attach({
    required ServiceExtensionCaller? Function() serviceExtension,
    required String projectRoot,
  }) {
    _serviceExtension = serviceExtension;
    _projectRoot = projectRoot;
    _sub?.cancel();
    _poll?.cancel();
    _primed = false;
    _quietPolls = 0;
    _pollIdle = false;
    _pollGeneration++;
    _sub = _extensionEvents.listen((event) {
      if (event.extensionKind == 'Flutter.Selection') {
        _handleSelectionEvent(event);
      }
    });
    _schedulePoll();
  }

  Future<void> detach() async {
    _pollGeneration++;
    await _sub?.cancel();
    _poll?.cancel();
    _sub = null;
    _poll = null;
    _lastKey = null;
    _primed = false;
  }

  void _schedulePoll() {
    final generation = _pollGeneration;
    _poll = Timer(_pollIdle ? _idlePollInterval : _pollInterval, () async {
      if (generation != _pollGeneration) return;
      final before = _lastKey;
      await _pollSelection();
      if (generation != _pollGeneration) return;
      if (_lastKey != before) {
        _quietPolls = 0;
        _pollIdle = false;
      } else if (!_pollIdle && ++_quietPolls >= _idleThreshold) {
        _pollIdle = true;
      }
      _schedulePoll();
    });
  }

  Future<void> _handleSelectionEvent(vm.Event event) async {
    // The user is actively inspecting — restore the fast poll cadence.
    _quietPolls = 0;
    _pollIdle = false;
    final data = event.extensionData?.data ?? const <String, dynamic>{};
    final loc = _extractLocation(data);
    // User-driven tap — always open regardless of _primed state.
    if (loc != null) _open(loc, skipPrimingCheck: true);
  }

  Future<void> _pollSelection() async {
    if (_polling) return;
    _polling = true;
    try {
      final loc = await _fetchSelectedLocation();
      if (loc != null) _open(loc);
    } finally {
      _polling = false;
    }
  }

  void _open(_CreationLocation loc, {bool skipPrimingCheck = false}) {
    final src = _resolver.resolve(
      loc.uri,
      projectRoot: _projectRoot,
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
    _jumps.add(src);
  }

  /// Asks the running app for the currently-selected widget and pulls its
  /// `creationLocation`.
  Future<_CreationLocation?> _fetchSelectedLocation() async {
    final call = _serviceExtension?.call();
    if (call == null) return null;
    for (final method in const [
      'ext.flutter.inspector.getSelectedSummaryWidget',
      'ext.flutter.inspector.getSelectedWidget',
    ]) {
      try {
        final result = await call(method, <String, Object?>{
          'objectGroup': _objectGroup,
        });
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
    final loc =
        _coerceMap(data['creationLocation']) ??
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
  _CreationLocation({
    required this.uri,
    required this.line,
    required this.column,
  });
  final String uri;
  final int line;
  final int column;
}
