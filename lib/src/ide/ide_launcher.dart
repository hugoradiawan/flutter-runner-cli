import 'dart:io';

import '../app/app_state.dart';
import '../config/config.dart';
import 'source_location.dart';

/// Opens a [SourceLocation] in the user's configured IDE by shelling out to
/// its CLI.
class IdeLauncher {
  IdeLauncher();

  Future<void> open(SourceLocation loc, AppState state) async {
    final ide = state.config.ide;
    final spec = _commandFor(ide, loc);
    state.transcript.system('Opening ${loc.file}:${loc.line} in ${ide.id}…');
    try {
      final result = await Process.run(
        spec.executable,
        spec.args,
        runInShell: Platform.isWindows && spec.runInShell,
      );
      if (result.exitCode != 0) {
        state.transcript.error(
          '${ide.id} exited ${result.exitCode}: ${result.stderr}',
        );
      }
    } on ProcessException catch (e) {
      state.transcript.error(
        'Could not run "${spec.executable}". Is ${ide.id} on your PATH? ($e)',
      );
    }
  }

  /// Build the executable + argv for [ide] given [loc]. Visible for testing.
  static IdeCommandSpec commandFor(FrunIde ide, SourceLocation loc) =>
      _commandFor(ide, loc);

  static IdeCommandSpec _commandFor(FrunIde ide, SourceLocation loc) {
    final positional = '${loc.file}:${loc.line}:${loc.column}';
    switch (ide) {
      case FrunIde.vscode:
        // `code -g` accepts file:line[:column]
        final exe = Platform.isWindows ? 'code.cmd' : 'code';
        return IdeCommandSpec(
          executable: exe,
          args: ['-g', positional],
          runInShell: Platform.isWindows,
        );
      case FrunIde.zed:
        return IdeCommandSpec(
          executable: 'zed',
          args: [positional],
          runInShell: false,
        );
    }
  }
}

class IdeCommandSpec {
  IdeCommandSpec({
    required this.executable,
    required this.args,
    required this.runInShell,
  });

  final String executable;
  final List<String> args;
  final bool runInShell;
}
