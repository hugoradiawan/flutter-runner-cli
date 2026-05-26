import 'dart:io';

import 'package:path/path.dart' as p;

/// Persists command history as a plain text file (one entry per line).
///
/// macOS / Linux: `~/.config/frun/history`
/// Windows: `%APPDATA%\frun\history`
class HistoryStore {
  HistoryStore({String? overridePath}) : _overridePath = overridePath;

  final String? _overridePath;

  String get path => _overridePath ?? _defaultPath();

  static String _defaultPath() {
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return p.join(appData, 'frun', 'history');
      }
      final userProfile = Platform.environment['USERPROFILE'] ?? '.';
      return p.join(userProfile, 'AppData', 'Roaming', 'frun', 'history');
    }
    final xdg = Platform.environment['XDG_CONFIG_HOME'];
    final base =
        xdg != null && xdg.isNotEmpty ? xdg : p.join(_homeDir(), '.config');
    return p.join(base, 'frun', 'history');
  }

  static String _homeDir() {
    if (Platform.isWindows) {
      return Platform.environment['USERPROFILE'] ?? '.';
    }
    return Platform.environment['HOME'] ?? '.';
  }

  List<String> load() {
    final file = File(path);
    if (!file.existsSync()) return <String>[];
    return file
        .readAsLinesSync()
        .where((l) => l.isNotEmpty)
        .toList();
  }

  void save(List<String> history) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(history.join('\n'));
  }
}
