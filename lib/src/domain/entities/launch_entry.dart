import '../../core/base/entity.dart';

/// One launch configuration discovered for `/run`. May come from
/// `.vscode/launch.json` or from a `main()` we found in `lib/`.
class LaunchEntryEntity extends Entity<LaunchEntryEntity> {
  const LaunchEntryEntity({
    required this.name,
    required this.program,
    this.cwd,
    this.deviceId,
    this.flutterMode,
    this.flavor,
    this.args = const <String>[],
    this.toolArgs = const <String>[],
    this.source = LaunchEntrySource.launchJson,
  });

  final String name;

  /// Dart entry-point. Relative to [cwd] if [cwd] is set, otherwise relative
  /// to the project root.
  final String program;

  /// Working directory for `flutter run`. When null, the Flutter project
  /// root is used. Lets monorepos point `cwd` at the actual sub-project from a
  /// workspace-level launch.json.
  final String? cwd;

  /// Optional device id from launch.json (`deviceId` field). If present,
  /// `/run` will use it instead of the user's currently-selected device.
  final String? deviceId;

  final String? flutterMode; // debug | profile | release
  final String? flavor;
  final List<String> args;
  final List<String> toolArgs;
  final LaunchEntrySource source;

  @override
  List<Object?> get props => [
    name,
    program,
    cwd,
    deviceId,
    flutterMode,
    flavor,
    args,
    toolArgs,
    source,
  ];

  @override
  String toString() => '$name ($program)';
}

enum LaunchEntrySource { launchJson, mainScanner }
