import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/entities/launch_entry.dart';
import 'dart_source_walker.dart';

/// Walks `lib/` looking for top-level `main()`s. Each one becomes a
/// [LaunchEntryEntity] tagged as [LaunchEntrySource.mainScanner].
class MainScanner {
  /// Recursively scan [libDir] for `*.dart` files whose source declares a
  /// top-level `main` function. Files in `.dart_tool/` and `build/` are
  /// excluded.
  static List<LaunchEntryEntity> scan(String libDir) {
    final dir = Directory(libDir);
    if (!dir.existsSync()) return const <LaunchEntryEntity>[];
    final entries = <LaunchEntryEntity>[];
    final mainPattern = RegExp(
      r'^\s*(?:void|Future<\s*void\s*>|Future)?\s*main\s*\(',
      multiLine: true,
    );
    for (final entity in walkDartSourceFiles(dir)) {
      final path = entity.path;
      try {
        final source = entity.readAsStringSync();
        if (!mainPattern.hasMatch(source)) continue;
      } on FileSystemException {
        continue;
      }
      final rel = p.relative(path, from: p.dirname(libDir));
      entries.add(
        LaunchEntryEntity(
          name: rel,
          program: rel,
          source: LaunchEntrySource.mainScanner,
        ),
      );
    }
    entries.sort((a, b) => a.program.compareTo(b.program));
    return entries;
  }

  /// Merge launch.json entries with main-scanner entries, deduping by program
  /// path. launch.json entries win (they carry richer config).
  static List<LaunchEntryEntity> merge(
    List<LaunchEntryEntity> launchJson,
    List<LaunchEntryEntity> scanned,
  ) {
    final seenPrograms = launchJson.map((e) => e.program).toSet();
    final out = <LaunchEntryEntity>[...launchJson];
    for (final s in scanned) {
      if (seenPrograms.add(s.program)) out.add(s);
    }
    return out;
  }
}
