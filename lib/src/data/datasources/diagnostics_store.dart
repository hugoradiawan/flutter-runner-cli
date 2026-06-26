import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/diagnostic.dart';

/// Per-project cache of the latest analyzer diagnostics, stored globally so the
/// project repo stays clean. One JSON file per project, keyed by a stable hash
/// of the project root — mirrors the `HistoryStore` location convention.
///
/// macOS / Linux: `~/.config/frun/diagnostics/<key>.json`
/// Windows: `%APPDATA%\frun\diagnostics\<key>.json`
///
/// The cache lets the counters show last-known totals instantly on launch,
/// before the analysis server finishes its first pass.
class DiagnosticsStore {
  DiagnosticsStore({required String projectRoot, String? overrideDir})
    : _projectRoot = p.normalize(projectRoot),
      _overrideDir = overrideDir;

  final String _projectRoot;
  final String? _overrideDir;

  String get dir => _overrideDir ?? _defaultDir();
  String get path => p.join(dir, '${_key(_projectRoot)}.json');

  static String _defaultDir() {
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return p.join(appData, 'frun', 'diagnostics');
      }
      final userProfile = Platform.environment['USERPROFILE'] ?? '.';
      return p.join(userProfile, 'AppData', 'Roaming', 'frun', 'diagnostics');
    }
    final xdg = Platform.environment['XDG_CONFIG_HOME'];
    final base = xdg != null && xdg.isNotEmpty
        ? xdg
        : p.join(_homeDir(), '.config');
    return p.join(base, 'frun', 'diagnostics');
  }

  static String _homeDir() {
    if (Platform.isWindows) {
      return Platform.environment['USERPROFILE'] ?? '.';
    }
    return Platform.environment['HOME'] ?? '.';
  }

  /// Stable FNV-1a 64-bit hash of the (case-normalized on Windows) project root,
  /// rendered as 16 hex chars. Keeps the filename short and filesystem-safe
  /// without pulling in the `crypto` package.
  static String _key(String root) {
    final normalized = Platform.isWindows ? root.toLowerCase() : root;
    const mask = 0xffffffffffffffff;
    var hash = 0xcbf29ce484222325;
    for (final unit in utf8.encode(normalized)) {
      hash = (hash ^ unit) & mask;
      hash = (hash * 0x100000001b3) & mask;
    }
    final hi = (hash >>> 32) & 0xffffffff;
    final lo = hash & 0xffffffff;
    return hi.toRadixString(16).padLeft(8, '0') +
        lo.toRadixString(16).padLeft(8, '0');
  }

  List<DiagnosticModel> load() {
    final file = File(path);
    if (!file.existsSync()) return const <DiagnosticModel>[];
    try {
      final decoded = json.decode(file.readAsStringSync());
      if (decoded is! Map) return const <DiagnosticModel>[];
      final list = decoded['diagnostics'];
      if (list is! List) return const <DiagnosticModel>[];
      final out = <DiagnosticModel>[];
      for (final item in list) {
        if (item is Map && item['file'] is String) {
          out.add(DiagnosticModel.fromJson(item.cast<String, Object?>()));
        }
      }
      return out;
    } catch (_) {
      return const <DiagnosticModel>[];
    }
  }

  void save(List<DiagnosticModel> diagnostics) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      json.encode(<String, Object?>{
        'root': _projectRoot,
        'diagnostics': diagnostics.map((d) => d.toJson()).toList(),
      }),
    );
  }
}
