import '../../../domain/domain.dart';
import '../app_state.dart';
import '../ide_opener.dart';
import 'command.dart';

/// `isolates` — inspect and control Dart isolates.
///
/// Usage:
///   isolates                       → list
///   isolates pause `<id>`          → pause an isolate
///   isolates resume `<id>`         → resume an isolate
///   isolates step `<id>` [over|in|out]
///   isolates kill `<id>`           → kill an isolate
///   isolates stack `<id>`          → print the current stack (opens top frame in IDE)
class IsolatesCommand extends Command {
  IsolatesCommand(this.manager);

  final IsolateControl manager;

  @override
  String get name => 'isolates';

  @override
  String get summary => 'Inspect and manage Dart isolates';

  @override
  String get usage =>
      'isolates [list|panel|refresh|start|pause|resume|step|kill|stack `<id>`]';

  @override
  List<String> get aliases => const ['iso'];

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    if (args.isEmpty) {
      // Re-point if possible, but still show the panel so its empty/no-service
      // state can explain what to do next.
      if (state.runController.hasTabs) {
        await state.runController.ensureIsolatesForActiveTab();
      }
      _showPanel(state);
      return CommandResult.ok;
    }

    final sub = args.first;
    final id = args.length >= 2 ? args[1] : null;
    switch (sub) {
      case 'panel':
      case 'ui':
        if (state.runController.hasTabs) {
          await state.runController.ensureIsolatesForActiveTab();
        }
        _showPanel(state);
      case 'list':
      case 'ls':
        if (state.runController.hasTabs) {
          await state.runController.ensureIsolatesForActiveTab();
        }
        _print(state);
      case 'refresh':
        if (await _ensureServiceForCommand(state)) {
          await _wrap(state, manager.refresh);
        }
      case 'start':
      case 'rerun':
        await state.runController.rerunActive();
      case 'pause':
        if (await _ensureServiceForCommand(state)) {
          await _wrap(state, () async => manager.pause(_need(id)));
        }
      case 'resume':
        if (await _ensureServiceForCommand(state)) {
          await _wrap(state, () async => manager.resume(_need(id)));
        }
      case 'step':
        if (await _ensureServiceForCommand(state)) {
          final mode = args.length >= 3 ? args[2] : 'over';
          final step = _stepFromMode(mode);
          await _wrap(state, () async => manager.resume(_need(id), step: step));
        }
      case 'kill':
        if (await _ensureServiceForCommand(state)) {
          await _wrap(state, () async => manager.kill(_need(id)));
        }
      case 'stack':
        if (await _ensureServiceForCommand(state)) {
          await _printStack(state, _need(id));
        }
      default:
        state.visibleTranscript.warn('Usage: $usage');
    }
    return CommandResult.ok;
  }

  void _showPanel(AppState state) {
    state.clearPickers();
    state.showDiagnosticsPanel = false;
    state.showIsolatesPanel = true;
  }

  Future<bool> _ensureServiceForCommand(AppState state) async {
    if (manager.isConnected) return true;
    if (state.runController.hasTabs) {
      await state.runController.ensureIsolatesForActiveTab();
    }
    if (manager.isConnected) return true;
    state.visibleTranscript.warn(
      'No VM service yet. Start the app with /run, then try /isolates.',
    );
    return false;
  }

  void _print(AppState state) {
    final list = manager.isolates;
    if (list.isEmpty) {
      state.visibleTranscript.info('No isolates connected.');
      return;
    }
    state.visibleTranscript.system('Isolates:');
    for (final iso in list) {
      final extra = iso.pauseReason == null ? '' : ' (${iso.pauseReason})';
      state.visibleTranscript.info(
        '  ${iso.id.padRight(22)} ${iso.name.padRight(24)} ${iso.status.name}$extra',
      );
    }
  }

  Future<void> _printStack(AppState state, String id) async {
    try {
      final frames = await manager.stack(id);
      if (frames == null) {
        state.visibleTranscript.warn('No stack available.');
        return;
      }
      if (frames.isEmpty) {
        state.visibleTranscript.info('Stack empty for $id.');
        return;
      }
      state.visibleTranscript.system('Stack for $id:');
      for (var i = 0; i < frames.length && i < 30; i++) {
        final f = frames[i];
        final script = f.scriptUri ?? '';
        state.visibleTranscript.info('  #$i  ${f.functionName}  $script');
      }
      // Auto-open the top frame in the user's IDE if it has a script.
      final scriptUri = frames.first.scriptUri;
      if (scriptUri != null) {
        final loc = state.deps.vmUriResolver.resolve(scriptUri);
        if (loc != null) await openInIde(loc, state);
      }
    } catch (e) {
      state.visibleTranscript.error('Stack lookup failed: $e');
    }
  }

  Future<void> _wrap(AppState state, Future<void> Function() body) async {
    try {
      await body();
    } catch (e) {
      state.visibleTranscript.error('VM service call failed: $e');
    }
  }

  String _need(String? id) {
    if (id == null) throw StateError('isolate id required');
    return id;
  }

  IsolateStepMode _stepFromMode(String mode) {
    switch (mode) {
      case 'in':
        return IsolateStepMode.into;
      case 'out':
        return IsolateStepMode.out;
      case 'over':
      default:
        return IsolateStepMode.over;
    }
  }
}
