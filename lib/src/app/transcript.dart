import 'dart:collection';

enum TranscriptLevel { info, success, warn, error, debug, system }

class TranscriptLine {
  TranscriptLine({
    required this.text,
    required this.level,
    required this.timestamp,
  });

  final String text;
  final TranscriptLevel level;
  final DateTime timestamp;
}

/// Append-only ring buffer of lines rendered in the transcript panel.
class Transcript {
  Transcript({this.maxLines = 2000});

  final int maxLines;
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

  void _add(String text, TranscriptLevel level) {
    for (final raw in text.split('\n')) {
      _lines.add(
        TranscriptLine(
          text: raw,
          level: level,
          timestamp: DateTime.now(),
        ),
      );
      if (_lines.length > maxLines) _lines.removeFirst();
    }
    _revision++;
  }

  void clear() {
    _lines.clear();
    _revision++;
  }
}
