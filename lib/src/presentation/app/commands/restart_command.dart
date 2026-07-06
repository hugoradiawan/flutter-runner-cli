import '../../../domain/domain.dart';
import '../app_state.dart';
import 'command.dart';

class RestartCommand extends Command {
  @override
  String get name => 'restart';

  @override
  String get summary => 'Hot restart the running app';

  @override
  List<String> get aliases => const ['R'];

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    final tab = state.runController.activeTab;
    if (tab == null || tab.session == null) {
      state.transcript.warn('No app running. Use /run first.');
      return CommandResult.ok;
    }
    state.deps.notifier.notify(
      FrunNotifEvent.restarting,
      label: tab.notificationLabel,
    );
    final result = await state.deps.hotRestartUseCase.call(
      ReloadParams(tabId: tab.id),
    );
    result.fold(
      (failure) =>
          tab.transcript.error('Hot restart failed: ${failure.message}'),
      (_) {
        state.deps.notifier.notify(
          FrunNotifEvent.restarted,
          label: tab.notificationLabel,
        );
        tab.transcript.success('Hot restart requested.');
      },
    );
    return CommandResult.ok;
  }
}
