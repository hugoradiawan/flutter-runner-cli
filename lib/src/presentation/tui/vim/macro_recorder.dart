import 'package:dart_tui/dart_tui.dart';

/// Keystroke macro store for `q{reg}` / `@{reg}`.
///
/// Tapes live here rather than in the RegisterBank because they are key
/// events, not text (a divergence from vim, where macros share registers).
/// Recording captures every key the engine sees; playback re-enters the
/// host's key router, so [replayDepth] suppresses appends — a macro that
/// invokes another records `@b`, not its expansion.
class MacroRecorder {
  final Map<String, List<TeaKey>> _tapes = <String, List<TeaKey>>{};
  List<TeaKey> _current = <TeaKey>[];

  /// Register being recorded into, or null when idle.
  String? recording;

  /// Register last executed by `@`; `@@` replays it.
  String lastPlayed = '';

  /// Incremented by the host around playback so replayed keys (and keys any
  /// nested playback produces) are never re-recorded.
  int replayDepth = 0;

  bool get isRecording => recording != null;

  List<TeaKey>? tape(String reg) => _tapes[reg];

  void start(String reg) {
    recording = reg;
    _current = <TeaKey>[];
  }

  void stop() {
    final reg = recording;
    if (reg == null) return;
    _tapes[reg] = _current;
    recording = null;
  }

  void append(TeaKey key) {
    if (recording == null || replayDepth > 0) return;
    _current.add(key);
  }

  /// Un-record the key just appended — used when a key turns out to be
  /// macro control (the `q` that stops recording) rather than content.
  void dropLast() {
    if (recording == null || replayDepth > 0) return;
    if (_current.isNotEmpty) _current.removeLast();
  }
}
