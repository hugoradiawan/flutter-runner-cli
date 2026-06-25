import '../app_state.dart';
import 'command.dart';

class PerformanceOverlayCommand extends Command {
  bool _enabled = false;

  @override
  String get name => 'perf';

  @override
  String get summary => 'Toggle performance overlay';

  @override
  List<String> get aliases => const ['P'];

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    final session = state.runController.activeTab?.session;
    if (session == null) {
      state.visibleTranscript.warn('No app running.');
      return CommandResult.ok;
    }
    _enabled = !_enabled;
    try {
      await session.callServiceExtension(
        'ext.flutter.showPerformanceOverlay',
        <String, Object?>{'enabled': _enabled},
      );
      state.visibleTranscript.success(
        'Performance overlay ${_enabled ? 'ON' : 'OFF'}.',
      );
    } catch (e) {
      _enabled = !_enabled;
      state.visibleTranscript.error('Toggle failed: $e');
    }
    return CommandResult.ok;
  }
}
