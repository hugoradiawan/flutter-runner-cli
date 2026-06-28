import 'dart:io';

import 'package:path/path.dart' as p;

const Set<String> defaultExcludedDartSourceDirs = {
  '.dart_tool',
  'build',
  '.fvm',
  '.git',
};

Iterable<File> walkDartSourceFiles(
  Directory root, {
  Set<String> excludedDirs = defaultExcludedDartSourceDirs,
}) sync* {
  if (!root.existsSync()) return;

  final stack = <Directory>[root];
  while (stack.isNotEmpty) {
    final dir = stack.removeLast();
    final List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } catch (_) {
      continue;
    }

    for (final entity in entries) {
      if (entity is Directory) {
        if (!excludedDirs.contains(p.basename(entity.path))) {
          stack.add(entity);
        }
      } else if (entity is File && entity.path.endsWith('.dart')) {
        yield entity;
      }
    }
  }
}
