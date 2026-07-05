import 'package:path/path.dart' as p;

import '../../core/base/entity.dart';

/// Information about the Flutter project that `frun` is launched inside.
///
/// In a monorepo, [root] is where the runnable Flutter project's `pubspec.yaml`
/// lives (e.g. `apps/client`) while [workspaceRoot] is the highest ancestor
/// that contains a `.vscode/` directory (e.g. the monorepo root). They are
/// equal when the project is its own workspace.
///
/// [watchRoot] is the highest ancestor with any repo/workspace marker
/// (`.git`, `.vscode`, `.zed`, `melos.yaml`) — used by the file watcher so
/// edits in monorepo packages outside [root] still trigger hot reload.
class FlutterProjectEntity extends Entity<FlutterProjectEntity> {
  const FlutterProjectEntity({
    required this.root,
    required this.name,
    required this.workspaceRoot,
    required this.watchRoot,
    required this.hasVsCodeFolder,
    required this.hasZedFolder,
  });

  final String root;
  final String name;
  final String workspaceRoot;
  final String watchRoot;
  final bool hasVsCodeFolder;
  final bool hasZedFolder;

  String get pubspecPath => p.join(root, 'pubspec.yaml');
  String get launchJsonPath => p.join(workspaceRoot, '.vscode', 'launch.json');
  String get libDir => p.join(root, 'lib');

  @override
  List<Object?> get props => [
    root,
    name,
    workspaceRoot,
    watchRoot,
    hasVsCodeFolder,
    hasZedFolder,
  ];
}
