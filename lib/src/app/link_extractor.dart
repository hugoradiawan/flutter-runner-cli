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

/// Extracts `file.dart:LINE[:COL]` and `package:foo/bar.dart:LINE:COL`
/// references from a single transcript line.
class LinkExtractor {
  // Match either:
  //   package:foo/bar/baz.dart:12:34
  //   lib/src/whatever.dart:12
  //   ./some/relative/path.dart:5:7
  //   /abs/path.dart:42
  // We deliberately stay narrow: only ".dart" files.
  static final RegExp _re = RegExp(
    r'(package:[a-zA-Z_][\w.]*\/[\w\-./]+\.dart|[\w./\-]+\.dart):(\d+)(?::(\d+))?',
  );

  static List<TranscriptLink> extract(String line) {
    final matches = _re.allMatches(line);
    final out = <TranscriptLink>[];
    for (final m in matches) {
      final uri = m.group(1)!;
      final ln = int.tryParse(m.group(2)!);
      if (ln == null) continue;
      final col = m.group(3) != null ? int.tryParse(m.group(3)!) : null;
      out.add(TranscriptLink(
        uri: uri,
        line: ln,
        column: col,
        start: m.start,
        end: m.end,
      ));
    }
    return out;
  }
}
