import 'dart:io';

import '../../../domain/domain.dart';
import '../app_state.dart';
import 'command.dart';

/// `devtools` — serve DevTools (via the persistent daemon) and print the URL
/// pointing at the running app's VM service.
class DevToolsCommand extends Command {
  @override
  String get name => 'devtools';

  @override
  String get summary => 'Serve DevTools and print its URL';

  @override
  List<String> get aliases => const ['dt', 'v'];

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    final daemon = state.deps.daemon;
    if (daemon == null) {
      state.visibleTranscript.warn(
        'Flutter daemon not ready yet. Try again shortly.',
      );
      return CommandResult.ok;
    }
    state.deps.notifier.notify(FrunNotifEvent.openingDevTools);
    Map<String, Object?> served;
    try {
      served = await daemon.serveDevTools();
    } catch (e) {
      state.visibleTranscript.error('devtools.serve failed: $e');
      return CommandResult.ok;
    }
    final host = served['host'] as String? ?? '127.0.0.1';
    final port = (served['port'] as num?)?.toInt();
    if (port == null) {
      state.visibleTranscript.error(
        'DevTools server did not report a port. Response: $served',
      );
      return CommandResult.ok;
    }
    final vmUri = state.runController.session?.vmServiceUri;
    final base = 'http://$host:$port/';
    final full = vmUri == null
        ? base
        : '$base?uri=${Uri.encodeComponent(vmUri)}&page=inspector';
    state.runController.activeTab?.devToolsUri = full;
    state.visibleTranscript.success('DevTools: $full');

    // Re-point the shared VM connection at this tab's device so DevTools widget
    // clicks open source from the selected app.
    await state.runController.ensureIsolatesForActiveTab();
    state.deps.inspectorBridge.attach(
      serviceExtension: () => state.runController.serviceExtensionCaller,
      projectRoot: state.project.root,
    );
    state.visibleTranscript.system(
      'Inspector bridge ON — leaf clicks in DevTools open in ${state.config.ide.id}.',
    );

    state.deps.notifier.notify(FrunNotifEvent.devToolsReady, detail: full);
    _open(full, state);
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
    Process.start(exe, args, runInShell: Platform.isWindows)
        .then((p) {
          state.visibleTranscript.system('Opened DevTools in browser.');
        })
        .catchError((Object e) {
          state.visibleTranscript.warn('Could not auto-open browser: $e');
        });
  }
}
