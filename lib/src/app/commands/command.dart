import '../app_state.dart';

/// Result of executing a slash command. The runner uses this to decide whether
/// to exit, refresh, or stay put.
class CommandResult {
  const CommandResult({this.shouldQuit = false});

  final bool shouldQuit;

  static const ok = CommandResult();
  static const quit = CommandResult(shouldQuit: true);
}

abstract class SlashCommand {
  String get name;
  String get summary;
  String get usage => '/$name';
  List<String> get aliases => const <String>[];

  Future<CommandResult> run(List<String> args, AppState state);
}
