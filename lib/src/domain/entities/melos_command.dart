import '../../core/base/entity.dart';

/// One runnable melos command surfaced in the `/melos` picker. Either a
/// built-in ([MelosCommandKind.builtin], e.g. `bootstrap`, `clean`) or a
/// custom script ([MelosCommandKind.script]) declared in the monorepo config.
class MelosCommandEntity extends Entity<MelosCommandEntity> {
  const MelosCommandEntity({
    required this.name,
    required this.description,
    required this.kind,
    required this.melosArgs,
  });

  /// Display name and resolve token (e.g. `bootstrap`, `analyze`).
  final String name;

  /// One-line description shown next to the name in the picker.
  final String description;

  final MelosCommandKind kind;

  /// Arguments passed to the `melos` executable, e.g. `['bootstrap']`,
  /// `['clean']`, or `['run', '<script>']`.
  final List<String> melosArgs;

  /// The full command line for logs/notifications, e.g. `melos bootstrap`.
  String get commandLine => 'melos ${melosArgs.join(' ')}';

  @override
  List<Object?> get props => [name, description, kind, melosArgs];

  @override
  String toString() => commandLine;
}

enum MelosCommandKind { builtin, script }
