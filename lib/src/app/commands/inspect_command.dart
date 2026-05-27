import '../../ide/frun_notifier.dart';
import '../app_state.dart';
import 'command.dart';

/// `/inspect` — toggle Flutter's widget-inspector "select widget mode".
///
/// While select mode is on, tapping a widget in the running app emits an
/// `ext.flutter.inspector.selection` event over the VM service. The shared
/// [InspectorBridge] resolves its `creationLocation` and opens the matching
/// source file in the user's IDE.
class InspectCommand extends Command {
  InspectCommand();

  bool _enabled = false;

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
    if (_enabled) {
      state.notifier.notify(FrunNotifEvent.enteringInspect);
    }
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
      state.inspectorBridge.attach(state);
      state.notifier.notify(FrunNotifEvent.inspectReady);
      state.visibleTranscript.success(
        'Inspector ON — tap widgets in the app to jump to source.',
      );
    } else {
      await state.inspectorBridge.detach();
      state.notifier.notify(FrunNotifEvent.inspectReady, detail: 'Inspector OFF');
      state.visibleTranscript.success('Inspector OFF.');
    }
    return CommandResult.ok;
  }
}
