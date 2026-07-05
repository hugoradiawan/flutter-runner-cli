import '../../../domain/value_objects/notification_event.dart';
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

  @override
  String get name => 'inspect';

  @override
  String get summary =>
      'Toggle widget inspector "select" mode (tap widgets → opens in IDE)';

  @override
  List<String> get aliases => const ['i'];

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    final tab = state.runController.activeTab;
    final session = tab?.session;
    if (tab == null || session == null) {
      state.visibleTranscript.warn(
        'No running app. Start one with /run first.',
      );
      return CommandResult.ok;
    }
    // Re-point the shared VM connection at this tab's device so the inspector
    // bridge listens to the selected app's selection events.
    await state.runController.ensureIsolatesForActiveTab();
    tab.inspectEnabled = !tab.inspectEnabled;
    if (tab.inspectEnabled) {
      state.deps.notifier.notify(FrunNotifEvent.enteringInspect);
    }
    try {
      await session.callServiceExtension(
        'ext.flutter.inspector.show',
        <String, Object?>{'enabled': tab.inspectEnabled},
      );
    } catch (e) {
      state.visibleTranscript.error('Could not toggle inspector: $e');
      tab.inspectEnabled = !tab.inspectEnabled;
      return CommandResult.ok;
    }
    if (tab.inspectEnabled) {
      state.deps.inspectorBridge.attach(
        serviceExtension: () => state.runController.serviceExtensionCaller,
        projectRoot: state.project.root,
      );
      state.deps.notifier.notify(FrunNotifEvent.inspectReady);
      state.visibleTranscript.success(
        'Inspector ON — tap widgets in the app to jump to source.',
      );
    } else {
      await state.deps.inspectorBridge.detach();
      state.deps.notifier.notify(
        FrunNotifEvent.inspectReady,
        detail: 'Inspector OFF',
      );
      state.visibleTranscript.success('Inspector OFF.');
    }
    return CommandResult.ok;
  }
}
