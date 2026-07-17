import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../../domain/entities/melos_command.dart';

/// A resolved melos workspace: the directory holding the melos config plus the
/// custom scripts declared in it.
class MelosWorkspace {
  const MelosWorkspace({required this.root, required this.scripts});

  /// Directory to run `melos` in (holds `melos.yaml` and/or a `pubspec.yaml`
  /// with a `melos:` key).
  final String root;

  /// Custom scripts declared in the config.
  final List<MelosCommandEntity> scripts;
}

/// Reads melos configuration for a project. Walks up from the project root to
/// find the workspace directory, then parses custom scripts from the root
/// `pubspec.yaml` (`melos:` key) and/or a sibling `melos.yaml`.
class MelosConfigReader {
  const MelosConfigReader();

  /// Resolve the melos workspace for [startDir], or null when [startDir] is
  /// not inside a melos workspace.
  MelosWorkspace? read(String startDir) {
    final root = _findMelosRoot(startDir);
    if (root == null) return null;

    final scripts = <String, MelosCommandEntity>{};

    // pubspec.yaml `melos:` -> `scripts:`
    final pubspec = _loadMap(File(p.join(root, 'pubspec.yaml')));
    final melosSection = pubspec?['melos'];
    if (melosSection is Map) {
      _collectScripts(melosSection['scripts'], scripts);
    }

    // melos.yaml top-level `scripts:`
    final melosYaml = _loadMap(File(p.join(root, 'melos.yaml')));
    if (melosYaml != null) {
      _collectScripts(melosYaml['scripts'], scripts);
    }

    final sorted = scripts.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return MelosWorkspace(root: root, scripts: sorted);
  }

  /// Walk up from [startDir] to the first ancestor that is a melos workspace:
  /// it has a `melos.yaml`, or a `pubspec.yaml` with a top-level `melos:` key.
  static String? _findMelosRoot(String startDir) {
    Directory current = Directory(startDir).absolute;
    while (true) {
      final path = current.path;
      if (File(p.join(path, 'melos.yaml')).existsSync()) return path;
      final pubspec = _loadMap(File(p.join(path, 'pubspec.yaml')));
      if (pubspec != null && pubspec['melos'] is Map) return path;

      final parent = current.parent;
      if (parent.path == current.path) return null;
      current = parent;
    }
  }

  /// Adds entries from a melos `scripts:` map. Each value is either a String
  /// (the shell command) or a Map with `run`/`description`. We run scripts via
  /// `melos run <name>`, so only the name and description matter here.
  static void _collectScripts(
    Object? raw,
    Map<String, MelosCommandEntity> out,
  ) {
    if (raw is! Map) return;
    for (final entry in raw.entries) {
      final name = entry.key?.toString();
      if (name == null || name.isEmpty) continue;
      final value = entry.value;
      final String raw;
      if (value is Map) {
        raw = value['description']?.toString() ??
            value['run']?.toString() ??
            '';
      } else {
        raw = value?.toString() ?? '';
      }
      // Collapse newlines/indentation from multiline YAML scalars to a single
      // line so the picker chip stays one row tall.
      final description = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
      out[name] = MelosCommandEntity(
        name: name,
        description: description,
        kind: MelosCommandKind.script,
        melosArgs: <String>['run', name],
      );
    }
  }

  static Map<dynamic, dynamic>? _loadMap(File file) {
    try {
      if (!file.existsSync()) return null;
      final doc = loadYaml(file.readAsStringSync());
      return doc is Map ? doc : null;
    } catch (_) {
      return null;
    }
  }
}
