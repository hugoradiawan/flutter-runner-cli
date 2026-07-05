/// A file location to open in the user's IDE.
class SourceLocation {
  const SourceLocation({required this.file, this.line = 1, this.column = 1});

  /// Absolute path on disk.
  final String file;
  final int line;
  final int column;

  @override
  String toString() => '$file:$line:$column';

  /// Pure conversion of a `file://` URI to an on-disk location. Returns null
  /// for any other scheme — use a `VmUriResolver` when `package:` URIs must
  /// be resolved too (that requires reading `.dart_tool/package_config.json`).
  static SourceLocation? fromFileUri(
    String uri, {
    int line = 1,
    int column = 1,
  }) {
    final parsed = Uri.tryParse(uri);
    if (parsed == null || parsed.scheme != 'file') return null;
    return SourceLocation(
      file: parsed.toFilePath(),
      line: line,
      column: column,
    );
  }
}
