import 'package:vm_service/vm_service.dart' as vm;

import '../../ide/ide_launcher.dart';
import '../../ide/source_location.dart';
import '../../vm/isolate_manager.dart';
import '../app_state.dart';
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
  IsolatesCommand(this.manager, this.ide);

  final IsolateManager manager;
  final IdeLauncher ide;

  @override
  String get name => 'isolates';

  @override
  String get summary => 'Inspect, pause/resume, step, kill Dart isolates';

  @override
  String get usage =>
      'isolates [pause|resume|step|kill|stack `<id>`]';

  @override
  List<String> get aliases => const ['iso'];

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    // Re-point the shared VM connection at the selected tab's device so the
    // listed / controlled isolates belong to the active tab.
    await state.runController.ensureIsolatesForActiveTab();
    if (manager.service == null) {
      state.visibleTranscript.warn(
        'No VM service yet. Start the app with /run, then try /isolates.',
      );
      return CommandResult.ok;
    }

    if (args.isEmpty) {
      _print(state);
      return CommandResult.ok;
    }

    final sub = args.first;
    final id = args.length >= 2 ? args[1] : null;
    switch (sub) {
      case 'list':
      case 'ls':
        _print(state);
      case 'pause':
        await _wrap(state, () async => manager.pause(_need(id)));
      case 'resume':
        await _wrap(state, () async => manager.resume(_need(id)));
      case 'step':
        final mode = args.length >= 3 ? args[2] : 'over';
        final step = _stepFromMode(mode);
        await _wrap(state, () async => manager.resume(_need(id), step: step));
      case 'kill':
        await _wrap(state, () async => manager.kill(_need(id)));
      case 'stack':
        await _printStack(state, _need(id));
      default:
        state.visibleTranscript.warn('Usage: $usage');
    }
    return CommandResult.ok;
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
      final stack = await manager.getStack(id);
      if (stack == null) {
        state.visibleTranscript.warn('No stack available.');
        return;
      }
      final frames = stack.frames ?? const <vm.Frame>[];
      if (frames.isEmpty) {
        state.visibleTranscript.info('Stack empty for $id.');
        return;
      }
      state.visibleTranscript.system('Stack for $id:');
      for (var i = 0; i < frames.length && i < 30; i++) {
        final f = frames[i];
        final fn = f.function?.name ?? '<anon>';
        final loc = f.location;
        final script = loc?.script?.uri ?? '';
        state.visibleTranscript.info('  #$i  $fn  $script');
      }
      // Auto-open the top frame in the user's IDE if it has a script.
      final top = frames.first;
      final scriptUri = top.location?.script?.uri;
      if (scriptUri != null) {
        final loc = SourceLocation.fromVmServiceUri(scriptUri);
        if (loc != null) await ide.open(loc, state);
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

  String _stepFromMode(String mode) {
    switch (mode) {
      case 'in':
        return vm.StepOption.kInto;
      case 'out':
        return vm.StepOption.kOut;
      case 'over':
      default:
        return vm.StepOption.kOver;
    }
  }
}
