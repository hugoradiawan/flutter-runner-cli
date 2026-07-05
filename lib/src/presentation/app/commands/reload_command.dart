import '../../../domain/params/reload_params.dart';
import '../../../domain/value_objects/notification_event.dart';
import '../app_state.dart';
import 'command.dart';

class ReloadCommand extends Command {
  @override
  String get name => 'reload';

  @override
  String get summary => 'Hot reload the running app';

  @override
  List<String> get aliases => const ['r'];

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    final tab = state.runController.activeTab;
    if (tab == null || tab.session == null) {
      state.transcript.warn('No app running. Use /run first.');
      return CommandResult.ok;
    }
    final useCase = state.deps.hotReloadUseCase;
    if (useCase == null) {
      state.transcript.warn('No app running. Use /run first.');
      return CommandResult.ok;
    }
    state.deps.notifier.notify(
      FrunNotifEvent.hotReloading,
      label: tab.notificationLabel,
    );
    final result = await useCase.call(ReloadParams(tabId: tab.id));
    result.fold(
      (failure) =>
          tab.transcript.error('Hot reload failed: ${failure.message}'),
      (_) {
        state.deps.notifier.notify(
          FrunNotifEvent.hotReloaded,
          label: tab.notificationLabel,
        );
        tab.transcript.success('Hot reload requested.');
      },
    );
    return CommandResult.ok;
  }
}
