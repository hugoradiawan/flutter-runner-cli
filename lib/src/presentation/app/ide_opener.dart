import '../../domain/value_objects/source_location.dart';
import 'app_state.dart';

/// Open [loc] in the user's configured IDE, reporting progress and failures
/// on the system transcript. The single presentation-side jump-to-source path
/// (transcript links, diagnostics rows, isolate stacks, inspector taps).
Future<void> openInIde(SourceLocation loc, AppState state) async {
  final ide = state.config.ide;
  state.transcript.system('Opening ${loc.file}:${loc.line} in ${ide.id}…');
  final result = await state.deps.ideLauncher.open(
    loc,
    ide: ide,
    nvimServer: state.config.nvimServer,
  );
  result.fold((failure) => state.transcript.error(failure.message), (_) {});
}
