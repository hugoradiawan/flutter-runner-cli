import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/ports/vm_uri_resolver.dart';
import '../../domain/value_objects/source_location.dart';

/// Resolves `package:` URIs through `.dart_tool/package_config.json` (and
/// `file://` URIs directly).
class PackageConfigUriResolver extends VmUriResolver {
  const PackageConfigUriResolver();

  @override
  SourceLocation? resolve(
    String uri, {
    String? projectRoot,
    int line = 1,
    int column = 1,
  }) {
    final parsed = Uri.tryParse(uri);
    if (parsed == null) return null;
    if (parsed.scheme == 'file') {
      return SourceLocation(
        file: parsed.toFilePath(),
        line: line,
        column: column,
      );
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
    final pkgConfigPath = p.join(
      projectRoot,
      '.dart_tool',
      'package_config.json',
    );
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
          : Uri.parse(
              p.normalize(p.join(p.dirname(pkgConfigPath), base.toFilePath())),
            ).resolve(packageUri);
      final abs = resolvedBase.resolve(rest);
      if (abs.scheme == 'file') return abs.toFilePath();
      // Relative URI — resolve manually against pkg config dir.
      return p.normalize(
        p.join(p.dirname(pkgConfigPath), base.path, packageUri, rest),
      );
    }
    return null;
  }
}
