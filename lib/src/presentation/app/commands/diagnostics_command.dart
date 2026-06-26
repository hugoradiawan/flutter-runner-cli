import '../../../domain/entities/diagnostic.dart';
import '../app_state.dart';
import 'command.dart';

/// Toggles the diagnostics ("problems") overlay — a VS Code-style list of all
/// analyzer errors/warnings/infos in the project, grouped by file. An optional
/// argument pre-applies a severity filter and forces the panel open.
class DiagnosticsCommand extends Command {
  @override
  String get name => 'diagnostics';

  @override
  String get summary =>
      'Toggle the diagnostics panel (analyzer errors/warnings/infos)';

  @override
  String get usage => '/diagnostics [error|warning|info|todo|all]';

  @override
  List<String> get aliases => const ['problems', 'prob'];

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    if (args.isNotEmpty) {
      final arg = args.first.toLowerCase();
      switch (arg) {
        case 'error':
        case 'errors':
        case 'e':
          state.diagnosticsFilter = DiagnosticCategory.error;
        case 'warning':
        case 'warn':
        case 'w':
          state.diagnosticsFilter = DiagnosticCategory.warning;
        case 'info':
        case 'infos':
        case 'i':
          state.diagnosticsFilter = DiagnosticCategory.info;
        case 'todo':
        case 'todos':
        case 't':
          state.diagnosticsFilter = DiagnosticCategory.todo;
        case 'all':
        case 'a':
          state.diagnosticsFilter = null;
        default:
          state.transcript.warn(
            'Unknown filter "$arg" — use error|warning|info|todo|all.',
          );
          return CommandResult.ok;
      }
      state.showDiagnosticsPanel = true; // explicit filter implies "show".
    } else {
      state.showDiagnosticsPanel = !state.showDiagnosticsPanel;
    }

    if (state.showDiagnosticsPanel) {
      final (e, w, i, t) = DiagnosticEntity.counts(state.diagnostics);
      state.transcript.system(
        'Diagnostics: $e errors, $w warnings, $i infos, $t todos.',
      );
    } else {
      state.transcript.system('Diagnostics panel hidden.');
    }
    return CommandResult.ok;
  }
}
