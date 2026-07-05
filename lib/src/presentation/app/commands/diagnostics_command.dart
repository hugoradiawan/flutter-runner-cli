import '../../../domain/entities/diagnostic.dart';
import '../app_state.dart';
import 'command.dart';

/// Runs one-shot `dart analyze` and opens the diagnostics overlay.
class DiagnosticsCommand extends Command {
  DiagnosticsCommand();

  @override
  String get name => 'diagnostics';

  @override
  String get summary => 'Run dart analyze once and show diagnostics';

  @override
  String get usage => '/diagnostics [error|warning|info|todo|all]';

  @override
  List<String> get aliases => const ['problems', 'prob'];

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    final parsedFilter = _parseFilter(args, state);
    if (!parsedFilter.valid) return CommandResult.ok;

    state.diagnosticsFilter = parsedFilter.filter;
    state.diagnosticsSearch = '';

    // Show the current view immediately (the live pipeline keeps it merged
    // with TODOs); the one-shot analyze below replaces it when it lands.
    final current = await state.deps.getDiagnosticsUseCase?.call();
    current?.fold((_) {}, (list) => state.diagnostics = list);
    state.showDiagnosticsPanel = true;
    state.transcript.system(
      'Showing current diagnostics; running dart analyze...',
    );

    final analyze = state.deps.analyzeProjectUseCase;
    if (analyze == null) {
      state.transcript.warn('dart analyze is not available in this session.');
      return CommandResult.ok;
    }
    final result = await analyze();
    result.fold((failure) => state.transcript.warn(failure.message), (
      diagnostics,
    ) {
      state.diagnostics = diagnostics;
      state.showDiagnosticsPanel = true;
      final (e, w, i, t) = DiagnosticEntity.counts(state.diagnostics);
      state.transcript.system(
        state.diagnostics.isEmpty
            ? 'Diagnostics: no analyzer issues or TODOs found.'
            : 'Diagnostics: $e errors, $w warnings, $i infos, $t todos.',
      );
    });
    return CommandResult.ok;
  }

  ({bool valid, DiagnosticCategory? filter}) _parseFilter(
    List<String> args,
    AppState state,
  ) {
    if (args.isEmpty) return (valid: true, filter: null);
    final arg = args.first.toLowerCase();
    switch (arg) {
      case 'error':
      case 'errors':
      case 'e':
        return (valid: true, filter: DiagnosticCategory.error);
      case 'warning':
      case 'warn':
      case 'w':
        return (valid: true, filter: DiagnosticCategory.warning);
      case 'info':
      case 'infos':
      case 'i':
        return (valid: true, filter: DiagnosticCategory.info);
      case 'todo':
      case 'todos':
      case 't':
        return (valid: true, filter: DiagnosticCategory.todo);
      case 'all':
      case 'a':
        return (valid: true, filter: null);
      default:
        state.transcript.warn(
          'Unknown filter "$arg" - use error|warning|info|todo|all.',
        );
        return (valid: false, filter: null);
    }
  }
}
