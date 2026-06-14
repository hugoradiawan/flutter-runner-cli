import '../app_state.dart';
import '../run_controller.dart';
import 'command.dart';

class ReloadCommand extends Command {
  ReloadCommand(this.controller);
  final RunController controller;

  @override
  String get name => 'reload';

  @override
  String get summary => 'Hot reload the running app';

  @override
  List<String> get aliases => const ['r'];

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    await controller.hotReloadActive();
    return CommandResult.ok;
  }
}

class RestartCommand extends Command {
  RestartCommand(this.controller);
  final RunController controller;

  @override
  String get name => 'restart';

  @override
  String get summary => 'Hot restart the running app';

  @override
  List<String> get aliases => const ['R'];

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    await controller.hotRestartActive();
    return CommandResult.ok;
  }
}

class StopCommand extends Command {
  StopCommand(this.controller);
  final RunController controller;

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
      await controller.stopAll();
    } else {
      await controller.stopActive();
    }
    return CommandResult.ok;
  }
}

class DetachCommand extends Command {
  DetachCommand(this.controller);
  final RunController controller;

  @override
  String get name => 'detach';

  @override
  String get summary => 'Detach from app (keeps app running, disconnects tool)';

  @override
  List<String> get aliases => const ['d'];

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    if (controller.activeTab?.session == null) {
      state.visibleTranscript.warn('No app running.');
      return CommandResult.ok;
    }
    await controller.detachActive();
    state.visibleTranscript.success('Detached — app continues running.');
    return CommandResult.ok;
  }
}

class PerformanceOverlayCommand extends Command {
  PerformanceOverlayCommand(this.controller);
  final RunController controller;

  bool _enabled = false;

  @override
  String get name => 'perf';

  @override
  String get summary => 'Toggle performance overlay';

  @override
  List<String> get aliases => const ['P'];

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    final session = controller.activeTab?.session;
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
