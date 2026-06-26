import 'dart:io';

import 'package:path/path.dart' as p;

/// Directory names never worth descending into when hunting for packages:
/// build output, platform shells (which carry ephemeral `pubspec.yaml`s under
/// `.symlinks`), dependency caches, and a package's own leaf content dirs.
const _pruned = <String>{
  'build',
  'ios',
  'android',
  'macos',
  'windows',
  'linux',
  'web',
  'node_modules',
  'lib',
  'test',
  'bin',
  'example',
};

/// Finds every Dart/Flutter package root (a directory containing a
/// `pubspec.yaml`) under [root].
///
/// `dart language-server`, when handed a single monorepo root, only analyzes
/// that root's own package and silently ignores sibling packages (melos / pub
/// workspaces). Passing each package as its own `workspaceFolder` makes the
/// server analyze them all — which is what project-wide diagnostics need.
///
/// The walk is depth-bounded and prunes heavy/ephemeral dirs (see [_pruned]) so
/// even large monorepos stay cheap. A directory's `pubspec.yaml` is recorded
/// before its children are pruned, so package roots are never missed. Always
/// returns at least `[root]`.
List<String> locatePackageRoots(String root, {int maxDepth = 5}) {
  final normalizedRoot = p.normalize(root);
  final rootDir = Directory(normalizedRoot);
  if (!rootDir.existsSync()) return <String>[normalizedRoot];

  final found = <String>[];

  void walk(Directory dir, int depth) {
    if (File(p.join(dir.path, 'pubspec.yaml')).existsSync()) {
      found.add(p.normalize(dir.path));
    }
    if (depth >= maxDepth) return;
    final List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } catch (_) {
      return; // unreadable dir — skip
    }
    for (final e in entries) {
      if (e is! Directory) continue;
      final name = p.basename(e.path);
      if (name.startsWith('.') || _pruned.contains(name)) continue;
      walk(e, depth + 1);
    }
  }

  walk(rootDir, 0);
  if (found.isEmpty) found.add(normalizedRoot);
  return found;
}
