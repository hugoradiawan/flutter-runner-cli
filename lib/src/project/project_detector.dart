import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Information about the Flutter project that `frun` is launched inside.
///
/// In a monorepo, [root] is where the runnable Flutter project's `pubspec.yaml`
/// lives (e.g. `apps/client`) while [workspaceRoot] is the highest ancestor
/// that contains a `.vscode/` directory (e.g. the monorepo root). They are
/// equal when the project is its own workspace.
class FlutterProject {
  FlutterProject({
    required this.root,
    required this.name,
    required this.workspaceRoot,
    required this.hasVsCodeFolder,
    required this.hasZedFolder,
  });

  final String root;
  final String name;
  final String workspaceRoot;
  final bool hasVsCodeFolder;
  final bool hasZedFolder;

  String get pubspecPath => p.join(root, 'pubspec.yaml');
  String get launchJsonPath => p.join(workspaceRoot, '.vscode', 'launch.json');
  String get libDir => p.join(root, 'lib');
}

class ProjectDetectionResult {
  ProjectDetectionResult.success(this.project) : error = null;
  ProjectDetectionResult.failure(this.error) : project = null;

  final FlutterProject? project;
  final String? error;

  bool get isOk => project != null;
}

class _Candidate {
  _Candidate({
    required this.dir,
    required this.name,
    required this.dependsOnFlutter,
    required this.hasMainEntry,
  });

  final String dir;
  final String name;
  final bool dependsOnFlutter;
  final bool hasMainEntry;

  bool get isApp => dependsOnFlutter && hasMainEntry;
}

class ProjectDetector {
  /// Walk up from [startDir] until a `pubspec.yaml` is found.
  ///
  /// - If that pubspec depends on Flutter → use it.
  /// - If it's a Dart workspace pubspec (`workspace: [...]`), look at the
  ///   listed sub-packages and pick the single Flutter **app** (one with a
  ///   `main()`). If there are zero or multiple, return a helpful error.
  /// - Otherwise → fail.
  static ProjectDetectionResult detect({required String startDir}) {
    Directory current = Directory(startDir).absolute;
    while (true) {
      final pubspec = File(p.join(current.path, 'pubspec.yaml'));
      if (pubspec.existsSync()) {
        return _interpretPubspec(current.path, pubspec);
      }
      final parent = current.parent;
      if (parent.path == current.path) {
        return ProjectDetectionResult.failure(
          'No pubspec.yaml found in $startDir or any parent directory.',
        );
      }
      current = parent;
    }
  }

  static ProjectDetectionResult _interpretPubspec(
    String dir,
    File pubspecFile,
  ) {
    final doc = _readPubspec(pubspecFile);
    if (doc == null) {
      return ProjectDetectionResult.failure(
        'pubspec.yaml at ${pubspecFile.path} is not a valid YAML map.',
      );
    }
    final name = (doc['name'] as Object?)?.toString() ?? '<unnamed>';

    if (_dependsOnFlutter(doc)) {
      return _build(dir: dir, name: name);
    }

    final workspaceEntries = _workspaceEntries(doc);
    if (workspaceEntries.isNotEmpty) {
      return _resolveFromWorkspace(
        workspaceRoot: dir,
        entries: workspaceEntries,
      );
    }

    return ProjectDetectionResult.failure(
      'Found pubspec.yaml at ${pubspecFile.path}, but it does not depend on Flutter '
      'and is not a workspace pubspec.\n'
      'Either run `frun` from inside a Flutter project, or pass a path: `frun <path-to-flutter-project>`.',
    );
  }

  static ProjectDetectionResult _resolveFromWorkspace({
    required String workspaceRoot,
    required List<String> entries,
  }) {
    final candidates = <_Candidate>[];
    for (final entry in entries) {
      final subDir = p.normalize(p.join(workspaceRoot, entry));
      final subPubspec = File(p.join(subDir, 'pubspec.yaml'));
      if (!subPubspec.existsSync()) continue;
      final doc = _readPubspec(subPubspec);
      if (doc == null) continue;
      final name = (doc['name'] as Object?)?.toString() ?? entry;
      candidates.add(_Candidate(
        dir: subDir,
        name: name,
        dependsOnFlutter: _dependsOnFlutter(doc),
        hasMainEntry: _hasMain(subDir),
      ));
    }

    final apps = candidates.where((c) => c.isApp).toList();
    if (apps.length == 1) {
      return _build(dir: apps.single.dir, name: apps.single.name);
    }
    if (apps.isEmpty) {
      return ProjectDetectionResult.failure(
        'Workspace pubspec at $workspaceRoot lists ${entries.length} package(s), '
        'but none look like a runnable Flutter app.\n'
        'Pass a path to disambiguate: `frun <path-to-flutter-project>`.',
      );
    }
    final listing = apps.map((c) {
      final rel = p.relative(c.dir, from: workspaceRoot);
      return '  - $rel  (${c.name})';
    }).join('\n');
    return ProjectDetectionResult.failure(
      'Workspace at $workspaceRoot has more than one Flutter app:\n'
      '$listing\n'
      'Pick one: `frun <path>` (e.g. `frun ${p.relative(apps.first.dir, from: workspaceRoot)}`).',
    );
  }

  static ProjectDetectionResult _build({required String dir, required String name}) {
    final workspaceRoot = _findWorkspaceRoot(dir);
    return ProjectDetectionResult.success(
      FlutterProject(
        root: dir,
        name: name,
        workspaceRoot: workspaceRoot,
        hasVsCodeFolder:
            Directory(p.join(workspaceRoot, '.vscode')).existsSync(),
        hasZedFolder: Directory(p.join(workspaceRoot, '.zed')).existsSync() ||
            Directory(p.join(dir, '.zed')).existsSync(),
      ),
    );
  }

  static Map<dynamic, dynamic>? _readPubspec(File file) {
    try {
      final raw = file.readAsStringSync();
      final doc = loadYaml(raw);
      return doc is Map ? doc : null;
    } catch (_) {
      return null;
    }
  }

  /// Pulls a list of relative paths out of a `workspace:` top-level key.
  /// Returns an empty list if not a workspace pubspec.
  static List<String> _workspaceEntries(Map<dynamic, dynamic> pubspec) {
    final raw = pubspec['workspace'];
    if (raw is! List) return const <String>[];
    final out = <String>[];
    for (final entry in raw) {
      final s = entry?.toString();
      if (s != null && s.isNotEmpty) out.add(s);
    }
    return out;
  }

  /// Walks upward from [projectRoot] looking for the nearest ancestor that
  /// contains a `.vscode/` directory.
  static String _findWorkspaceRoot(String projectRoot) {
    Directory current = Directory(projectRoot).absolute;
    while (true) {
      if (Directory(p.join(current.path, '.vscode')).existsSync()) {
        return current.path;
      }
      final parent = current.parent;
      if (parent.path == current.path) return projectRoot;
      current = parent;
    }
  }

  /// Cheap probe for "is this a runnable Flutter app?" — looks for any
  /// `lib/main*.dart` containing a `main(` call. Avoids reading every file
  /// fully — stops after the first match.
  static bool _hasMain(String packageDir) {
    final libDir = Directory(p.join(packageDir, 'lib'));
    if (!libDir.existsSync()) return false;
    final mainPattern = RegExp(
      r'^\s*(?:void|Future<\s*void\s*>|Future)?\s*main\s*\(',
      multiLine: true,
    );
    for (final entity in libDir.listSync()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!name.startsWith('main') || !name.endsWith('.dart')) continue;
      try {
        if (mainPattern.hasMatch(entity.readAsStringSync())) return true;
      } catch (_) {/* ignore */}
    }
    return false;
  }

  static bool _dependsOnFlutter(Map<dynamic, dynamic> pubspec) {
    bool sectionHasFlutter(Object? section) {
      if (section is! Map) return false;
      return section.containsKey('flutter');
    }

    if (sectionHasFlutter(pubspec['dependencies'])) return true;
    if (sectionHasFlutter(pubspec['dev_dependencies'])) return true;
    if (pubspec['flutter'] is Map) return true;
    // SDK constraint `flutter: ">= ..."` in environment also marks Flutter
    // packages even when they don't list `flutter` as a dep directly.
    final env = pubspec['environment'];
    if (env is Map && env.containsKey('flutter')) return true;
    return false;
  }
}
