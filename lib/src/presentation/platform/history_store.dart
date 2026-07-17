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
    final base = xdg != null && xdg.isNotEmpty
        ? xdg
        : p.join(_homeDir(), '.config');
    return p.join(base, 'frun', 'history');
  }

  static String _homeDir() {
    if (Platform.isWindows) {
      return Platform.environment['USERPROFILE'] ?? '.';
    }
    return Platform.environment['HOME'] ?? '.';
  }

  static const int _maxHistory = 500;

  /// Best-effort: history is a convenience, so IO failures (locked file,
  /// permissions, full disk) must never crash startup or command submission.
  List<String> load() {
    try {
      final file = File(path);
      if (!file.existsSync()) return <String>[];
      final all = file.readAsLinesSync().where((l) => l.isNotEmpty).toList();
      if (all.length > _maxHistory) {
        return all.sublist(all.length - _maxHistory);
      }
      return all;
    } catch (_) {
      return <String>[];
    }
  }

  /// Best-effort — see [load].
  void save(List<String> history) {
    try {
      final file = File(path);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(history.join('\n'));
    } catch (_) {
      /* ignore — in-memory history still works this session */
    }
  }
}
