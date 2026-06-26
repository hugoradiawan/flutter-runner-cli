/// Backwards-compatible alias for `tool/install.dart`.
///
/// frun now installs as a standalone AOT executable (see install.dart). This
/// shim keeps `dart run tool/reinstall.dart` working for existing muscle memory.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

void main() {
  final installScript = p.join(
    p.dirname(Platform.script.toFilePath()),
    'install.dart',
  );
  final result = Process.runSync(Platform.resolvedExecutable, [
    'run',
    installScript,
  ]);
  stdout.write(result.stdout);
  if ((result.stderr as String).isNotEmpty) stderr.write(result.stderr);
  exit(result.exitCode);
}
