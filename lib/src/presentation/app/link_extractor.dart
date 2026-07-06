/// One `file:line[:col]` reference found in a transcript line.
class TranscriptLink {
  const TranscriptLink({
    required this.uri,
    required this.line,
    this.column,
    required this.start,
    required this.end,
  });

  /// The textual form found in the log (e.g. `lib/main.dart` or `package:foo/x.dart`).
  final String uri;
  final int line;
  final int? column;

  /// Character offsets within the source line. Useful for highlighting.
  final int start;
  final int end;

  @override
  String toString() =>
      '$uri:$line${column == null ? "" : ":$column"} [$start..$end]';
}

/// Converts a transcript path — absolute or relative, either separator — to a
/// `file://` URI, resolving relative paths against [projectRoot].
///
/// Windows-ness is inferred from the shape of the path/root (drive-letter
/// prefix) rather than the host platform, so the conversion stays pure and
/// testable everywhere. Building the URI through [Uri.file] keeps drive
/// letters out of the URI authority; naive `'file://$root/$path'` string
/// concatenation turns `C:\Users\…` into a UNC host (`\\c\Users\…`) when
/// parsed back.
String pathToFileUri(String pathLike, String projectRoot) {
  final windowsAbs = RegExp(r'^[A-Za-z]:[\\/]');
  if (windowsAbs.hasMatch(pathLike)) {
    return Uri.file(pathLike, windows: true).toString();
  }
  if (pathLike.startsWith('/')) {
    return Uri.file(pathLike, windows: false).toString();
  }
  final rootIsWindows = windowsAbs.hasMatch(projectRoot);
  final sep = rootIsWindows ? r'\' : '/';
  final root = projectRoot.endsWith('/') || projectRoot.endsWith(r'\')
      ? projectRoot
      : '$projectRoot$sep';
  return Uri.file('$root$pathLike', windows: rootIsWindows).toString();
}

/// Extracts `file.dart:LINE[:COL]` and `package:foo/bar.dart:LINE:COL`
/// references from a single transcript line.
class LinkExtractor {
  // Match either:
  //   package:foo/bar/baz.dart:12:34
  //   C:/Users/me/app/lib/x.dart:12:34   (Windows absolute, drive letter)
  //   lib/src/whatever.dart:12
  //   lib\src\whatever.dart:12           (Windows relative, backslashes)
  //   ./some/relative/path.dart:5:7
  //   /abs/path.dart:42
  // We deliberately stay narrow: only ".dart" files. The Windows-drive
  // alternative comes before the generic one so the `C:` drive prefix is kept
  // rather than the match starting after the colon.
  static final RegExp _re = RegExp(
    r'(package:[a-zA-Z_][\w.]*\/[\w\-./]+\.dart|[A-Za-z]:[\w\-./\\]+\.dart|[\w\-./\\]+\.dart):(\d+)(?::(\d+))?',
  );

  static List<TranscriptLink> extract(String line) {
    final matches = _re.allMatches(line);
    final out = <TranscriptLink>[];
    for (final m in matches) {
      final uri = m.group(1)!;
      final ln = int.tryParse(m.group(2)!);
      if (ln == null) continue;
      final col = m.group(3) != null ? int.tryParse(m.group(3)!) : null;
      out.add(
        TranscriptLink(
          uri: uri,
          line: ln,
          column: col,
          start: m.start,
          end: m.end,
        ),
      );
    }
    return out;
  }
}
