/// Builds and installs `frun` for fast startup.
///
/// The previous flow (`dart pub global activate --source path .`) made every
/// `frun` invocation re-resolve dependencies and rebuild a snapshot — roughly
/// five seconds of overhead per launch. This script instead produces a
/// standalone AOT executable that launches natively with zero pub work.
///
/// It builds two artifacts:
///   1. `<pub-cache>/bin/frun.exe` — AOT native exe, the everyday `frun` on PATH.
///      (`.EXE` precedes `.BAT` in PATHEXT, so this wins over any stale shim.)
///   2. `bin/frun.dart-<sdk>.snapshot` — kernel snapshot the pub-generated
///      `frun.bat` looks for, so the fallback path is also fast (no re-resolve).
///
/// Run from inside the repo:
///   dart run tool/install.dart
library;

import 'dart:io';

import 'package:path/path.dart' as p;

void main() {
  final dart = Platform.resolvedExecutable;
  final repoRoot = _repoRoot();
  final sdkVersion = Platform.version.split(' ').first;

  // 1. Ensure dependencies are present (also writes pubspec.lock).
  _run(dart, ['pub', 'get'], repoRoot, 'Resolving dependencies');

  // 2. AOT native exe into the pub-cache bin dir (already on PATH).
  final destDir = _pubCacheBinDir();
  Directory(destDir).createSync(recursive: true);
  final exePath = p.join(destDir, _exeName('frun'));
  _run(
    dart,
    ['compile', 'exe', p.join('bin', 'frun.dart'), '-o', exePath],
    repoRoot,
    'Compiling native executable',
  );

  // 3. Kernel snapshot where frun.bat expects it, for the fallback path.
  final snapshotPath = p.join(
    repoRoot,
    'bin',
    'frun.dart-$sdkVersion.snapshot',
  );
  _run(
    dart,
    ['compile', 'kernel', p.join('bin', 'frun.dart'), '-o', snapshotPath],
    repoRoot,
    'Building fallback snapshot',
  );

  stdout
    ..writeln('')
    ..writeln('Installed frun (native): $exePath')
    ..writeln('Fallback snapshot:       $snapshotPath')
    ..writeln('Startup is now native. no pub re-resolve per launch.');

  if (!_onPath(destDir)) {
    stdout
      ..writeln('')
      ..writeln('WARNING: $destDir is not on your PATH.')
      ..writeln('Add it so the `frun` command resolves to the new exe.');
  }
}

void _run(String exe, List<String> args, String cwd, String label) {
  stdout.writeln('$label…');
  final result = Process.runSync(exe, args, workingDirectory: cwd);
  stdout.write(result.stdout);
  if ((result.stderr as String).isNotEmpty) stderr.write(result.stderr);
  if (result.exitCode != 0) {
    stderr.writeln(
      'frun-install failed during "$label" (exit ${result.exitCode}).',
    );
    exit(result.exitCode);
  }
}

/// The directory pub puts globally-activated executables in, which the Dart
/// installer adds to PATH. Honours PUB_CACHE if set.
String _pubCacheBinDir() {
  final env = Platform.environment;
  final pubCache = env['PUB_CACHE'];
  if (pubCache != null && pubCache.isNotEmpty) {
    return p.join(pubCache, 'bin');
  }
  if (Platform.isWindows) {
    final localAppData = env['LOCALAPPDATA'];
    if (localAppData != null && localAppData.isNotEmpty) {
      return p.join(localAppData, 'Pub', 'Cache', 'bin');
    }
  }
  final home = env['HOME'] ?? env['USERPROFILE'] ?? '';
  return p.join(home, '.pub-cache', 'bin');
}

String _exeName(String base) => Platform.isWindows ? '$base.exe' : base;

bool _onPath(String dir) {
  final pathVar = Platform.environment['PATH'] ?? '';
  final sep = Platform.isWindows ? ';' : ':';
  final target = p.canonicalize(dir);
  return pathVar.split(sep).any((entry) {
    if (entry.isEmpty) return false;
    try {
      return p.canonicalize(entry) == target;
    } catch (_) {
      return false;
    }
  });
}

String _repoRoot() {
  final scriptPath = Platform.script.toFilePath();
  return p.normalize(p.join(p.dirname(scriptPath), '..'));
}
