import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// A file location to open in the user's IDE.
class SourceLocation {
  const SourceLocation({
    required this.file,
    this.line = 1,
    this.column = 1,
  });

  /// Absolute path on disk.
  final String file;
  final int line;
  final int column;

  @override
  String toString() => '$file:$line:$column';

  /// Best-effort conversion from a VM service / dart:* script URI.
  ///
  /// - `file:///abs/path.dart` → that abs path.
  /// - `package:foo/bar.dart`  → resolved via `.dart_tool/package_config.json`
  ///                             relative to [projectRoot] if supplied.
  /// - Otherwise returns null.
  static SourceLocation? fromVmServiceUri(
    String uri, {
    String? projectRoot,
    int line = 1,
    int column = 1,
  }) {
    final parsed = Uri.tryParse(uri);
    if (parsed == null) return null;
    if (parsed.scheme == 'file') {
      return SourceLocation(file: parsed.toFilePath(), line: line, column: column);
    }
    if (parsed.scheme == 'package' && projectRoot != null) {
      final resolved = _resolvePackageUri(parsed, projectRoot);
      if (resolved != null) {
        return SourceLocation(file: resolved, line: line, column: column);
      }
    }
    return null;
  }

  static String? _resolvePackageUri(Uri uri, String projectRoot) {
    final pkgConfigPath = p.join(projectRoot, '.dart_tool', 'package_config.json');
    final file = File(pkgConfigPath);
    if (!file.existsSync()) return null;
    final Object? decoded;
    try {
      decoded = json.decode(file.readAsStringSync());
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final packages = decoded['packages'];
    if (packages is! List) return null;
    final pkgName = uri.pathSegments.first;
    for (final entry in packages) {
      if (entry is! Map) continue;
      if (entry['name'] != pkgName) continue;
      final rootUri = entry['rootUri']?.toString() ?? '';
      final packageUri = entry['packageUri']?.toString() ?? 'lib/';
      final rest = uri.pathSegments.skip(1).join('/');
      final base = Uri.parse(rootUri);
      final resolvedBase = base.hasScheme
          ? base.resolve(packageUri)
          : Uri.parse(p.normalize(p.join(p.dirname(pkgConfigPath), base.toFilePath()))).resolve(packageUri);
      final abs = resolvedBase.resolve(rest);
      if (abs.scheme == 'file') return abs.toFilePath();
      // Relative URI — resolve manually against pkg config dir.
      return p.normalize(p.join(p.dirname(pkgConfigPath), base.path, packageUri, rest));
    }
    return null;
  }
}
