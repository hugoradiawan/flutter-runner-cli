import '../../../data/datasources/frun_notifier.dart';
import '../../../domain/params/reload.params.dart';
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
    final useCase = state.hotRestartUseCase;
    if (useCase == null) {
      state.transcript.warn('No app running. Use /run first.');
      return CommandResult.ok;
    }
    state.notifier.notifyTab(tab, FrunNotifEvent.restarting);
    final result = await useCase.call(ReloadParams(tabId: tab.id));
    result.fold(
      (failure) =>
          tab.transcript.error('Hot restart failed: ${failure.message}'),
      (_) {
        state.notifier.notifyTab(tab, FrunNotifEvent.restarted);
        tab.transcript.success('Hot restart requested.');
      },
    );
    return CommandResult.ok;
  }
}
