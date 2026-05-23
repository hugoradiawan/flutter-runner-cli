import 'dart:io';

import '../../config/config.dart';
import '../app_state.dart';
import 'command.dart';

/// `/devtools` — serve DevTools (via the persistent daemon) and print the URL
/// pointing at the running app's VM service.
class DevToolsCommand extends SlashCommand {
  @override
  String get name => 'devtools';

  @override
  String get summary => 'Serve DevTools and print its URL';

  @override
  List<String> get aliases => const ['dt'];

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    final daemon = state.daemon;
    if (daemon == null) {
      state.transcript.warn('Flutter daemon not ready yet. Try again shortly.');
      return CommandResult.ok;
    }
    Map<String, Object?> served;
    try {
      served = await daemon.serveDevTools();
    } catch (e) {
      state.transcript.error('devtools.serve failed: $e');
      return CommandResult.ok;
    }
    final host = served['host'] as String? ?? '127.0.0.1';
    final port = (served['port'] as num?)?.toInt();
    if (port == null) {
      state.transcript.error(
        'DevTools server did not report a port. Response: $served',
      );
      return CommandResult.ok;
    }
    final vmUri = state.runController.session?.vmServiceUri;
    final base = 'http://$host:$port/';
    final full = vmUri == null
        ? base
        : '$base?uri=${Uri.encodeComponent(vmUri)}';
    state.runController.session?.devToolsUri = full;
    state.transcript.success('DevTools: $full');

    final autoOpen = state.config.openDevtoolsOnLaunch;
    if (autoOpen == FrunDevToolsAutoOpen.always) {
      _open(full, state);
    }
    return CommandResult.ok;
  }

  void _open(String url, AppState state) {
    String exe;
    List<String> args;
    if (Platform.isMacOS) {
      exe = 'open';
      args = [url];
    } else if (Platform.isWindows) {
      exe = 'cmd';
      args = ['/c', 'start', '', url];
    } else {
      exe = 'xdg-open';
      args = [url];
    }
    Process.start(exe, args, runInShell: Platform.isWindows).then((p) {
      state.transcript.system('Opened DevTools in browser.');
    }).catchError((Object e) {
      state.transcript.warn('Could not auto-open browser: $e');
    });
  }
}
