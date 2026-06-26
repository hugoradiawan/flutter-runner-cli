import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../models/frun_config.dart';

/// Persists [FrunConfig] as YAML in a global location.
///
/// macOS / Linux: `~/.config/frun/config.yaml`
/// Windows: `%APPDATA%\frun\config.yaml`
class ConfigStore {
  ConfigStore({String? overridePath}) : _overridePath = overridePath;

  final String? _overridePath;

  String get path => _overridePath ?? _defaultPath();

  static String _defaultPath() {
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return p.join(appData, 'frun', 'config.yaml');
      }
      final userProfile = Platform.environment['USERPROFILE'] ?? '.';
      return p.join(userProfile, 'AppData', 'Roaming', 'frun', 'config.yaml');
    }
    final xdg = Platform.environment['XDG_CONFIG_HOME'];
    final base = xdg != null && xdg.isNotEmpty
        ? xdg
        : p.join(_homeDir(), '.config');
    return p.join(base, 'frun', 'config.yaml');
  }

  static String _homeDir() {
    if (Platform.isWindows) {
      return Platform.environment['USERPROFILE'] ?? '.';
    }
    return Platform.environment['HOME'] ?? '.';
  }

  /// Load config, creating defaults if the file does not yet exist.
  FrunConfig load() {
    final file = File(path);
    if (!file.existsSync()) {
      const fresh = FrunConfig();
      save(fresh);
      return fresh;
    }
    final raw = file.readAsStringSync();
    if (raw.trim().isEmpty) return const FrunConfig();
    final doc = loadYaml(raw);
    if (doc is! Map) return const FrunConfig();
    return FrunConfig.fromMap(doc);
  }

  void save(FrunConfig config) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(_serialize(config.toJson()));
  }

  static String _serialize(Map<String, Object?> map) {
    final buffer = StringBuffer()
      ..writeln('# frun configuration')
      ..writeln('# Edit by hand or via `/config` inside the TUI.');
    for (final entry in map.entries) {
      buffer.writeln('${entry.key}: ${_yamlScalar(entry.value)}');
    }
    return buffer.toString();
  }

  static String _yamlScalar(Object? value) {
    if (value == null) return 'null';
    if (value is bool || value is num) return value.toString();
    final s = value.toString();
    // Quote strings that look like reserved YAML values or contain special chars.
    final needsQuoting =
        s.isEmpty ||
        s.contains(RegExp(r'[\s:#\[\]\{\},&*!|>%@`]')) ||
        const {
          'true',
          'false',
          'null',
          'yes',
          'no',
          'on',
          'off',
        }.contains(s.toLowerCase());
    if (!needsQuoting) return s;
    final escaped = s.replaceAll('"', r'\"');
    return '"$escaped"';
  }
}
