import 'dart:collection';

enum TranscriptLevel { info, success, warn, error, debug, system }

class TranscriptLine {
  TranscriptLine({required this.text, required this.level, this.onClick});

  final String text;
  final TranscriptLevel level;

  /// Optional click action. When set, the TUI registers a hit region for this
  /// line so the user can click it to fire [onClick]. Used by command output
  /// that lists pickable items (e.g. `/run` entries).
  final void Function()? onClick;
}

/// Append-only log of lines rendered in the transcript panel.
class Transcript {
  Transcript({int? maxLines}) : _maxLines = maxLines ?? defaultMaxLines;

  /// Default ring-buffer cap for newly created transcripts. Mutable so the
  /// scrollback depth can be tuned at runtime (the `scrollback` command sets it
  /// for the system transcript, every open tab, and any future tab). Long
  /// sessions (hours of hot reload + daemon events) would otherwise grow
  /// [_buffer] without bound; once full the oldest lines are evicted so
  /// retained memory stays flat regardless of uptime.
  static int defaultMaxLines = 1000;

  /// Backing store plus a head pointer. Eviction advances [_head] instead of
  /// shifting elements, so appends at a full buffer stay amortized O(1); the
  /// dead prefix is compacted away only once it outgrows the live region.
  final List<TranscriptLine> _buffer = <TranscriptLine>[];
  int _head = 0;
  int _revision = 0;
  int _baseIndex = 0;
  _TranscriptView? _view;
  int _debugCompactions = 0;

  int _maxLines;

  /// This transcript's current retained-line cap.
  int get maxLines => _maxLines;

  /// Raise or lower the cap at runtime. Lowering trims the oldest lines
  /// immediately and advances [revision] so the renderer refreshes.
  set maxLines(int value) {
    _maxLines = value < 1 ? 1 : value;
    if (_trim()) _revision++;
  }

  /// Monotonic version, useful for telling the renderer something changed.
  int get revision => _revision;

  /// Absolute index of the first retained line. Increments as the ring buffer
  /// trims, letting render caches drop only evicted rows.
  int get baseIndex => _baseIndex;

  /// Number of retained lines.
  int get length => _buffer.length - _head;

  /// Live read-only view of retained lines. The view tracks the transcript as
  /// it mutates: index 0 is always the line at [baseIndex]. Callers that need
  /// point-in-time stability must key off [revision] (all render caches do)
  /// or copy — do not hold this across an await expecting frozen contents.
  List<TranscriptLine> get snapshot => _view ??= _TranscriptView(this);

  List<TranscriptLine> get lines => snapshot;

  /// Times the dead prefix was compacted out of [_buffer] (test hook).
  int get debugCompactions => _debugCompactions;

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
      _buffer.add(TranscriptLine(text: raw, level: level, onClick: onClick));
    }
    _trim();
    _revision++;
  }

  /// Evict the oldest lines until within [_maxLines]. Returns whether any line
  /// was removed. Eviction just advances [_head]; the buffer is compacted only
  /// when the dead prefix exceeds the live region, keeping eviction amortized
  /// O(1) per appended line.
  bool _trim() {
    var removed = false;
    while (_buffer.length - _head > _maxLines) {
      _head++;
      _baseIndex++;
      removed = true;
    }
    if (_head > _buffer.length - _head) {
      _buffer.removeRange(0, _head);
      _head = 0;
      _debugCompactions++;
    }
    return removed;
  }

  void clear() {
    _buffer.clear();
    _head = 0;
    _baseIndex = 0;
    _revision++;
  }
}

/// Unmodifiable live window over a [Transcript]'s retained lines.
class _TranscriptView extends ListBase<TranscriptLine> {
  _TranscriptView(this._owner);

  final Transcript _owner;

  @override
  int get length => _owner.length;

  @override
  set length(int newLength) =>
      throw UnsupportedError('Cannot resize a transcript snapshot');

  @override
  TranscriptLine operator [](int index) {
    final head = _owner._head;
    if (index < 0 || head + index >= _owner._buffer.length) {
      throw RangeError.index(index, this, 'index', null, _owner.length);
    }
    return _owner._buffer[head + index];
  }

  @override
  void operator []=(int index, TranscriptLine value) =>
      throw UnsupportedError('Cannot modify a transcript snapshot');
}
