import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// An [IOSink] wrapper that coalesces every write issued within one
/// event-loop turn into a single downstream write, bracketed by DEC 2026
/// synchronized-update sequences.
///
/// dart_tui's `AnsiRenderer` repaints a frame as many small `write()` calls
/// (cursor move + line + erase, per changed row) and never flushes, so a
/// scrolling transcript reaches the terminal as dozens of tiny writes that
/// paint visibly top to bottom. Its synchronized-update support stays off
/// because the upstream capability probe sends the DECRPM *response* syntax
/// (`\x1b[?2026$y`) instead of the DECRQM query (`\x1b[?2026$p`), which no
/// terminal answers.
///
/// The renderer runs synchronously within one event-loop turn, so a microtask
/// boundary delimits exactly one frame burst. Buffering until that boundary
/// and emitting one write per frame means the terminal host (ConPTY on
/// Windows) receives the whole repaint in a single pipe read and presents it
/// in one pass, which removes the visible top-to-bottom line sweep.
///
/// [syncUpdates] additionally wraps each batch in DEC 2026 synchronized-update
/// sequences. Off by default: under ConPTY (Windows Terminal, Zed, VS Code)
/// the re-rendering middleman has been observed to drop rows that are never
/// rewritten afterwards (the renderer's line diff skips unchanged rows, so a
/// once-lost static row — e.g. the tab strip — never heals). The single
/// write per frame already provides effective atomicity without it.
final class SynchronizedFrameSink implements IOSink {
  SynchronizedFrameSink(this._inner, {bool syncUpdates = false})
    : _syncUpdates = syncUpdates;

  final IOSink _inner;
  final bool _syncUpdates;
  final StringBuffer _pending = StringBuffer();
  bool _drainScheduled = false;
  bool _closed = false;

  static const String _beginSync = '\x1b[?2026h';
  static const String _endSync = '\x1b[?2026l';

  void _append(String text) {
    if (_closed || text.isEmpty) return;
    _pending.write(text);
    if (!_drainScheduled) {
      _drainScheduled = true;
      scheduleMicrotask(_drain);
    }
  }

  /// Push the buffered batch downstream as one bracketed write. Safe to call
  /// with an empty buffer (the microtask left over after an explicit [flush]
  /// lands here and no-ops).
  void _drain() {
    _drainScheduled = false;
    if (_pending.isEmpty) return;
    final batch = _pending.toString();
    _pending.clear();
    _inner.write(_syncUpdates ? '$_beginSync$batch$_endSync' : batch);
  }

  @override
  void write(Object? object) => _append(object?.toString() ?? '');

  @override
  void writeln([Object? object = '']) => _append('${object ?? ''}\n');

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) =>
      _append(objects.map((o) => '$o').join(separator));

  @override
  void writeCharCode(int charCode) => _append(String.fromCharCode(charCode));

  // Byte-level APIs bypass the text buffer; drain first so earlier buffered
  // text is not reordered behind the bytes.
  @override
  void add(List<int> data) {
    _drain();
    _inner.add(data);
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) {
    _drain();
    return _inner.addStream(stream);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _inner.addError(error, stackTrace);

  @override
  Future<void> flush() {
    _drain();
    return _inner.flush();
  }

  /// Drains and flushes but never closes the wrapped sink — this wraps the
  /// process's real stdout, which must stay usable after the TUI exits.
  @override
  Future<void> close() {
    _drain();
    _closed = true;
    return _inner.flush();
  }

  @override
  Future<dynamic> get done => _inner.done;

  @override
  Encoding get encoding => _inner.encoding;

  @override
  set encoding(Encoding value) => _inner.encoding = value;
}
