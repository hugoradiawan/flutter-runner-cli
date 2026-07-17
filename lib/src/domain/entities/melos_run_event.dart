/// An event emitted while a melos command runs. Either a line of output
/// ([MelosRunLine]) or the process exit ([MelosRunExit]).
sealed class MelosRunEvent {
  const MelosRunEvent();
}

/// One line of stdout/stderr from the running melos process.
final class MelosRunLine extends MelosRunEvent {
  const MelosRunLine(this.text, {this.isError = false});

  final String text;

  /// True when the line came from stderr.
  final bool isError;
}

/// Terminal event: the process exited with [code] (null if it could not be
/// determined). [code] == 0 means success.
final class MelosRunExit extends MelosRunEvent {
  const MelosRunExit(this.code);

  final int? code;

  bool get ok => code == 0;
}
