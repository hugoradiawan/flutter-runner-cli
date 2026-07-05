import '../value_objects/source_location.dart';

/// Resolves VM-service script URIs to on-disk source locations.
abstract class VmUriResolver {
  const VmUriResolver();

  /// Best-effort conversion from a VM service / dart:* script URI.
  ///
  /// - `file:///abs/path.dart` → that abs path.
  /// - `package:foo/bar.dart`  → resolved via the project's package config
  ///                             relative to [projectRoot] if supplied.
  /// - Otherwise returns null.
  SourceLocation? resolve(
    String uri, {
    String? projectRoot,
    int line = 1,
    int column = 1,
  });
}
