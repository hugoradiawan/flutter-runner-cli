import 'dart:async';

import 'package:vm_service/vm_service.dart' as vm;

import '../app/app_state.dart';
import 'source_location.dart';

/// Listens to widget-inspector selection events from the running app's VM
/// service and opens the corresponding source file in the configured IDE.
///
/// Triggers:
///   • `/inspect` in-app tap → Flutter posts `Flutter.Selection` with a
///     `creationLocation` payload.
///   • DevTools widget-tree click → Flutter posts `Flutter.SelectionChanged`
///     (no payload). We then pull the selected widget's details via
///     `ext.flutter.inspector.getSelectedSummaryWidget`.
class InspectorBridge {
  static const _selectionKinds = <String>{
    'Flutter.Selection',
    'Flutter.SelectionChanged',
  };
  static const _objectGroup = 'frun-inspector';

  StreamSubscription<vm.Event>? _sub;
  bool _busy = false;

  bool get isAttached => _sub != null;

  /// (Re)subscribe against the current `state.isolateManager.extensionEvents`
  /// stream. Safe to call repeatedly; cancels any prior subscription first so
  /// the bridge survives app restarts that swap the underlying stream.
  void attach(AppState state) {
    _sub?.cancel();
    _sub = state.isolateManager.extensionEvents.listen((event) {
      final kind = event.extensionKind ?? '(none)';
      state.visibleTranscript.system('[inspector-bridge] ext event: $kind');
      if (!_selectionKinds.contains(kind)) {
        // Any Flutter.* event during select-mode usage might carry selection
        // info — pull on every Flutter.* just in case the kind name differs
        // across versions.
        if (kind.startsWith('Flutter.')) {
          _handleSelection(event, state);
        }
        return;
      }
      _handleSelection(event, state);
    });
  }

  Future<void> detach() async {
    await _sub?.cancel();
    _sub = null;
  }

  Future<void> _handleSelection(vm.Event event, AppState state) async {
    if (_busy) return;
    _busy = true;
    try {
      final data = event.extensionData?.data ?? const <String, dynamic>{};
      var loc = _extractLocation(data);
      loc ??= await _fetchSelectedLocation(state);
      if (loc == null) {
        state.visibleTranscript.warn(
          'Inspector selection had no resolvable creationLocation.',
        );
        return;
      }
      final src = SourceLocation.fromVmServiceUri(
        loc.uri,
        projectRoot: state.project.root,
        line: loc.line,
        column: loc.column,
      );
      if (src == null) {
        state.visibleTranscript.warn('Could not resolve ${loc.uri} to a file.');
        return;
      }
      await state.ideLauncher.open(src, state);
    } finally {
      _busy = false;
    }
  }

  /// Asks the running app for the currently-selected widget and pulls its
  /// `creationLocation`. Used when the selection event itself omitted the
  /// payload (e.g., DevTools-driven tree clicks).
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
    Map<dynamic, dynamic>? node;
    if (response is Map) {
      final result = response['result'];
      if (result is Map) {
        node = result;
      } else {
        node = response;
      }
    }
    if (node == null) return null;
    return _extractLocation(node);
  }

  _CreationLocation? _extractLocation(Map<dynamic, dynamic> data) {
    Map<dynamic, dynamic>? loc;
    final raw = data['creationLocation'];
    if (raw is Map) {
      loc = raw;
    } else {
      final value = data['value'];
      if (value is Map) {
        final inner = value['creationLocation'];
        if (inner is Map) loc = inner;
      }
    }
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
