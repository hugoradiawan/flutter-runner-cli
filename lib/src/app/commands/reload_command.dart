import '../../domain/params/reload.params.dart';
import '../../data/datasources/frun_notifier.dart';
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
    final useCase = state.hotReloadUseCase;
    if (useCase == null) {
      state.transcript.warn('No app running. Use /run first.');
      return CommandResult.ok;
    }
    state.notifier.notifyTab(tab, FrunNotifEvent.hotReloading);
    final result = await useCase.call(ReloadParams(tabId: tab.id));
    result.fold(
      (failure) => tab.transcript.error('Hot reload failed: ${failure.message}'),
      (_) {
        state.notifier.notifyTab(tab, FrunNotifEvent.hotReloaded);
        tab.transcript.success('Hot reload requested.');
      },
    );
    return CommandResult.ok;
  }
}

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
      (failure) => tab.transcript.error('Hot restart failed: ${failure.message}'),
      (_) {
        state.notifier.notifyTab(tab, FrunNotifEvent.restarted);
        tab.transcript.success('Hot restart requested.');
      },
    );
    return CommandResult.ok;
  }
}

class StopCommand extends Command {
  @override
  String get name => 'stop';

  @override
  String get summary => 'Stop the active tab (or `stop all` for every tab)';

  @override
  List<String> get aliases => const ['q'];

  @override
  String get usage => 'stop [all]';

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    if (args.isNotEmpty && args.first == 'all') {
      await state.runController.stopAll();
    } else {
      await state.runController.stopActive();
    }
    return CommandResult.ok;
  }
}

class DetachCommand extends Command {
  @override
  String get name => 'detach';

  @override
  String get summary => 'Detach from app (keeps app running, disconnects tool)';

  @override
  List<String> get aliases => const ['d'];

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    if (state.runController.activeTab?.session == null) {
      state.visibleTranscript.warn('No app running.');
      return CommandResult.ok;
    }
    await state.runController.detachActive();
    state.visibleTranscript.success('Detached — app continues running.');
    return CommandResult.ok;
  }
}

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
