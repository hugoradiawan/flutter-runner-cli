import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/launch_config.dart';

/// Walks `lib/` looking for top-level `main()`s. Each one becomes a
/// [LaunchEntry] tagged as [LaunchEntrySource.mainScanner].
class MainScanner {
  /// Recursively scan [libDir] for `*.dart` files whose source declares a
  /// top-level `main` function. Files in `.dart_tool/` and `build/` are
  /// excluded.
  static List<LaunchEntry> scan(String libDir) {
    final dir = Directory(libDir);
    if (!dir.existsSync()) return const <LaunchEntry>[];
    final entries = <LaunchEntry>[];
    final mainPattern = RegExp(r'^\s*(?:void|Future<\s*void\s*>|Future)?\s*main\s*\(', multiLine: true);
    final iterable = dir.listSync(recursive: true, followLinks: false);
    for (final entity in iterable) {
      if (entity is! File) continue;
      final path = entity.path;
      if (!path.endsWith('.dart')) continue;
      final relParts = p.split(p.relative(path, from: libDir));
      if (relParts.any((s) => s == '.dart_tool' || s == 'build')) continue;
      try {
        final source = entity.readAsStringSync();
        if (!mainPattern.hasMatch(source)) continue;
      } on FileSystemException {
        continue;
      }
      final rel = p.relative(path, from: p.dirname(libDir));
      entries.add(LaunchEntry(
        name: rel,
        program: rel,
        source: LaunchEntrySource.mainScanner,
      ));
    }
    entries.sort((a, b) => a.program.compareTo(b.program));
    return entries;
  }

  /// Merge launch.json entries with main-scanner entries, deduping by program
  /// path. launch.json entries win (they carry richer config).
  static List<LaunchEntry> merge(
    List<LaunchEntry> launchJson,
    List<LaunchEntry> scanned,
  ) {
    final seenPrograms = launchJson.map((e) => e.program).toSet();
    final out = <LaunchEntry>[...launchJson];
    for (final s in scanned) {
      if (seenPrograms.add(s.program)) out.add(s);
    }
    return out;
  }
}
