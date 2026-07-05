import 'dart:io';

import '../../domain/value_objects/config_values.dart';
import '../../domain/value_objects/source_location.dart';
import '../../presentation/app/app_state.dart';

/// Opens a [SourceLocation] in the user's configured IDE by shelling out to
/// its CLI.
class IdeLauncher {
  IdeLauncher();

  Future<void> open(SourceLocation loc, AppState state) async {
    final ide = state.config.ide;
    String? nvimServer;
    if (ide == FrunIde.neovim) {
      nvimServer = _neovimServer(state);
      if (nvimServer == null) {
        state.transcript.error(
          'Neovim server not found. Run frun inside a Neovim/Neovide :terminal '
          '(sets \$NVIM), or set "/config set nvim_server <addr>" to your nvim '
          '--listen address.',
        );
        return;
      }
    }
    final spec = _commandFor(ide, loc, nvimServer: nvimServer);
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

  /// Resolve the Neovim/Neovide RPC server address: explicit config first, then
  /// `$NVIM` (set inside an nvim/Neovide `:terminal`), then the legacy
  /// `$NVIM_LISTEN_ADDRESS`. Null when none is available.
  static String? _neovimServer(AppState state) {
    final cfg = state.config.nvimServer;
    if (cfg != null && cfg.trim().isNotEmpty) return cfg.trim();
    return Platform.environment['NVIM'] ??
        Platform.environment['NVIM_LISTEN_ADDRESS'];
  }

  /// Build the executable + argv for [ide] given [loc]. Visible for testing.
  static IdeCommandSpec commandFor(
    FrunIde ide,
    SourceLocation loc, {
    String? nvimServer,
  }) => _commandFor(ide, loc, nvimServer: nvimServer);

  static IdeCommandSpec _commandFor(
    FrunIde ide,
    SourceLocation loc, {
    String? nvimServer,
  }) {
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
      case FrunIde.neovim:
        // Send an "open file at line:col" keystroke to the running nvim/Neovide
        // over its RPC server. nvim ex commands want forward slashes (also valid
        // on Windows); spaces in the :edit arg must be backslash-escaped.
        final path = loc.file.replaceAll('\\', '/');
        final escaped = path.replaceAll(' ', r'\ ');
        final keys =
            '<C-\\><C-N>:wincmd p<CR>:edit $escaped<CR>'
            ':call cursor(${loc.line},${loc.column})<CR>';
        return IdeCommandSpec(
          executable: 'nvim',
          args: ['--server', nvimServer!, '--remote-send', keys],
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
