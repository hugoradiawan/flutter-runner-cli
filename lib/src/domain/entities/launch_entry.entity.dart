import '../../ca/entity.dart';

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
  });

  final String name;
  final String program;
  final String? cwd;
  final String? deviceId;
  final String? flutterMode;
  final String? flavor;
  final List<String> args;
  final List<String> toolArgs;

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
  ];
}
