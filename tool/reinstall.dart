/// Force-rebuilds the global `frun` snapshot after a code change.
///
/// `dart pub global activate --source path` silently skips snapshot rebuilds
/// when the pubspec hasn't changed, so source-only edits aren't picked up.
/// This script deletes the cached snapshot first, then reactivates.
///
/// Run from anywhere:
///   dart run /path/to/flutter-runner-cli/tool/reinstall.dart
///
/// Or, from inside this repo:
///   dart run tool/reinstall.dart
library;

import 'dart:io';

import 'package:path/path.dart' as p;

void main() {
  final repoRoot = _repoRoot();
  final snapshotDir = Directory(
    p.join(repoRoot, '.dart_tool', 'pub', 'bin', 'frun'),
  );

  if (snapshotDir.existsSync()) {
    var deleted = 0;
    for (final entity in snapshotDir.listSync()) {
      if (entity is File && entity.path.contains('.snapshot')) {
        entity.deleteSync();
        deleted++;
      }
    }
    stdout.writeln(
      'Deleted $deleted stale snapshot(s) from ${snapshotDir.path}.',
    );
  } else {
    stdout.writeln('No snapshot dir yet — first activation will create it.');
  }

  stdout.writeln('Reactivating frun from $repoRoot…');
  final result = Process.runSync(
    Platform.isWindows ? 'dart.exe' : 'dart',
    ['pub', 'global', 'activate', '--source', 'path', repoRoot],
    runInShell: Platform.isWindows,
  );
  stdout.write(result.stdout);
  if ((result.stderr as String).isNotEmpty) stderr.write(result.stderr);
  if (result.exitCode != 0) {
    stderr.writeln('frun-reinstall failed (exit ${result.exitCode}).');
    exit(result.exitCode);
  }
  stdout.writeln(
    'Done. Run `frun` — first invocation will JIT-compile and cache a fresh snapshot.',
  );
}

String _repoRoot() {
  // tool/reinstall.dart lives at <repo>/tool/. Resolve via this script's URI.
  final scriptPath = Platform.script.toFilePath();
  return p.normalize(p.join(p.dirname(scriptPath), '..'));
}
