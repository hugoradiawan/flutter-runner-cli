import 'dart:async';
import 'dart:io';

import '../../presentation/app/run_tab.dart';

enum FrunNotifEvent {
  appLaunching,
  appStarted,
  hotReloading,
  hotReloaded,
  restarting,
  restarted,
  openingDevTools,
  devToolsReady,
  enteringInspect,
  inspectReady,
  launchingEmulator,
  emulatorReady;

  String get defaultBody {
    switch (this) {
      case appLaunching:
        return 'Launching app…';
      case appStarted:
        return 'App started';
      case hotReloading:
        return 'Hot reloading…';
      case hotReloaded:
        return 'Hot reload complete';
      case restarting:
        return 'Restarting…';
      case restarted:
        return 'Restart complete';
      case openingDevTools:
        return 'Opening DevTools…';
      case devToolsReady:
        return 'DevTools ready';
      case enteringInspect:
        return 'Inspector ON — tap widgets to jump to source';
      case inspectReady:
        return 'Inspector ready';
      case launchingEmulator:
        return 'Launching emulator…';
      case emulatorReady:
        return 'Emulator ready';
    }
  }
}

class FrunNotifier {
  const FrunNotifier();

  void notifyTab(RunTab tab, FrunNotifEvent event, {String? detail}) {
    final label = '${tab.entry.name} · ${tab.deviceId}';
    _sendAsync('frun · $label', detail ?? event.defaultBody);
  }

  void notify(FrunNotifEvent event, {String? label, String? detail}) {
    final title = label != null ? 'frun · $label' : 'frun';
    _sendAsync(title, detail ?? event.defaultBody);
  }

  void _sendAsync(String title, String body) {
    unawaited(_send(title, body));
  }

  Future<void> _send(String title, String body) async {
    final safeTitle = _escape(title);
    final safeBody = _escape(body);
    try {
      if (Platform.isMacOS) {
        await Process.run('osascript', [
          '-e',
          'display notification "$safeBody" with title "$safeTitle"',
        ]);
      } else if (Platform.isWindows) {
        await Process.run('powershell', ['-Command', _buildToast(safeTitle, safeBody)]);
      }
    } catch (_) {
      // Notifications are best-effort — never crash the main flow.
    }
  }

  static String _escape(String s) =>
      s.replaceAll('"', '\\"').replaceAll('\n', ' ').replaceAll('\r', '');

  static String _buildToast(String title, String body) => '''
[void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
\$t = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
\$nodes = \$t.GetElementsByTagName('text')
\$nodes.Item(0).AppendChild(\$t.CreateTextNode('$title')) > \$null
\$nodes.Item(1).AppendChild(\$t.CreateTextNode('$body')) > \$null
\$audio = \$t.CreateElement('audio')
\$audio.SetAttribute('silent', 'true')
\$t.DocumentElement.AppendChild(\$audio) > \$null
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('frun').Show([Windows.UI.Notifications.ToastNotification]::new(\$t))
''';
}
