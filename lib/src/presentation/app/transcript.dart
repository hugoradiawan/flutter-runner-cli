import 'dart:collection';

enum TranscriptLevel { info, success, warn, error, debug, system }

class TranscriptLine {
  TranscriptLine({
    required this.text,
    required this.level,
    this.onClick,
  });

  final String text;
  final TranscriptLevel level;

  /// Optional click action. When set, the TUI registers a hit region for this
  /// line so the user can click it to fire [onClick]. Used by command output
  /// that lists pickable items (e.g. `/run` entries).
  final void Function()? onClick;
}

/// Append-only log of lines rendered in the transcript panel.
class Transcript {
  Transcript();

  /// Ring-buffer cap. Long-running sessions (hours of hot reload + daemon
  /// events) would otherwise grow [_lines] without bound. Once full, the oldest
  /// lines are evicted so retained memory stays flat regardless of uptime.
  static const int _maxLines = 10000;

  final Queue<TranscriptLine> _lines = Queue<TranscriptLine>();
  int _revision = 0;

  /// Monotonic version, useful for telling the renderer something changed.
  int get revision => _revision;

  List<TranscriptLine> get lines => List.unmodifiable(_lines);

  void info(String text) => _add(text, TranscriptLevel.info);
  void success(String text) => _add(text, TranscriptLevel.success);
  void warn(String text) => _add(text, TranscriptLevel.warn);
  void error(String text) => _add(text, TranscriptLevel.error);
  void debug(String text) => _add(text, TranscriptLevel.debug);
  void system(String text) => _add(text, TranscriptLevel.system);

  /// Append a clickable line. [onClick] fires when the user clicks the row
  /// in the TUI. The line is also navigable via the normal scroll/search
  /// flow — the click is purely an extra affordance.
  void action(
    String text, {
    required void Function() onClick,
    TranscriptLevel level = TranscriptLevel.info,
  }) => _add(text, level, onClick: onClick);

  void _add(String text, TranscriptLevel level, {void Function()? onClick}) {
    for (final raw in text.split('\n')) {
      _lines.add(
        TranscriptLine(text: raw, level: level, onClick: onClick),
      );
    }
    while (_lines.length > _maxLines) {
      _lines.removeFirst();
    }
    _revision++;
  }

  void clear() {
    _lines.clear();
    _revision++;
  }
}
