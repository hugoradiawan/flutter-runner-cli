import 'dart:async';

import 'package:vm_service/vm_service.dart' as vm;

import '../../ide/source_location.dart';
import '../app_state.dart';
import 'command.dart';

/// `/inspect` — toggle Flutter's widget-inspector "select widget mode".
///
/// While select mode is on, tapping a widget in the running app emits an
/// `ext.flutter.inspector.selection` event over the VM service. We resolve its
/// `creationLocation` and open the matching source file in the user's IDE.
class InspectCommand extends SlashCommand {
  InspectCommand();

  bool _enabled = false;
  StreamSubscription<vm.Event>? _sub;

  @override
  String get name => 'inspect';

  @override
  String get summary =>
      'Toggle widget inspector "select" mode (tap widgets → opens in IDE)';

  @override
  List<String> get aliases => const ['i'];

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    final session = state.runController.session;
    if (session == null) {
      state.visibleTranscript.warn('No running app. Start one with /run first.');
      return CommandResult.ok;
    }
    _enabled = !_enabled;
    try {
      await session.callServiceExtension(
        'ext.flutter.inspector.show',
        <String, Object?>{'enabled': _enabled},
      );
    } catch (e) {
      state.visibleTranscript.error('Could not toggle inspector: $e');
      _enabled = !_enabled;
      return CommandResult.ok;
    }
    if (_enabled) {
      _attach(state);
      state.visibleTranscript.success(
        'Inspector ON — tap widgets in the app to jump to source.',
      );
    } else {
      await _sub?.cancel();
      _sub = null;
      state.visibleTranscript.success('Inspector OFF.');
    }
    return CommandResult.ok;
  }

  void _attach(AppState state) {
    _sub?.cancel();
    _sub = state.isolateManager.extensionEvents.listen((event) {
      if (event.extensionKind != 'Flutter.Selection') return;
      _handleSelection(event, state);
    });
  }

  Future<void> _handleSelection(vm.Event event, AppState state) async {
    final data = event.extensionData?.data ?? const <String, dynamic>{};
    final loc = _extractLocation(data);
    if (loc == null) {
      state.visibleTranscript.warn('Inspector selection had no creationLocation.');
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
  }

  _CreationLocation? _extractLocation(Map<dynamic, dynamic> data) {
    Map<dynamic, dynamic>? loc;
    final raw = data['creationLocation'];
    if (raw is Map) {
      loc = raw;
    } else {
      // Selection events sometimes nest the widget object under "value".
      final value = data['value'];
      if (value is Map) {
        final inner = value['creationLocation'];
        if (inner is Map) loc = inner;
      }
    }
    if (loc == null) return null;
    final file = (loc['file'] ?? loc['uri'])?.toString();
    if (file == null) return null;
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
