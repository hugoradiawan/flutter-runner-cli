import 'dart:async';

import '../clipboard.dart';
import 'vim_buffer.dart';

class RegisterEntry {
  const RegisterEntry(this.text, this.kind);
  final String text;
  final RangeKind kind;
  static const empty = RegisterEntry('', RangeKind.charwise);
  bool get isEmpty => text.isEmpty;
}

/// Vim-style register bank.
///
///   - `"`  unnamed   — every yank/delete overwrites
///   - `0`  yank      — only set by `y`
///   - `1`..`9`       — rotated on every delete (1=newest)
///   - `a`..`z`       — named; uppercase A..Z appends to lowercase
///   - `-`            — small-delete (single-line, non-linewise)
///   - `+`, `*`       — system clipboard; lazy read/write via clipboard.dart
///   - `_`            — black hole; never stores, always empty on read
typedef ClipboardWriter = Future<bool> Function(String text);
typedef ClipboardReader = Future<String?> Function();

class RegisterBank {
  RegisterBank({ClipboardWriter? writer, ClipboardReader? reader})
    : _writer = writer ?? copyToClipboard,
      _reader = reader ?? pasteFromClipboard;

  final ClipboardWriter _writer;
  final ClipboardReader _reader;

  final Map<String, RegisterEntry> _byName = <String, RegisterEntry>{};

  /// Cached last clipboard read so synchronous `p`/`P` after a `"+y` works
  /// without awaiting (we still write through synchronously on yank).
  RegisterEntry _clipboardCache = RegisterEntry.empty;

  RegisterEntry read(String name) {
    if (name == '_') return RegisterEntry.empty;
    if (name == '+' || name == '*') return _clipboardCache;
    return _byName[name] ?? RegisterEntry.empty;
  }

  /// Record a yank into [name] (defaults to unnamed). Mirrors to the OS
  /// clipboard unconditionally, matching `set clipboard=unnamedplus`.
  void yank(String text, RangeKind kind, {String name = '"'}) {
    final entry = RegisterEntry(text, kind);
    _setNamed(name, entry, append: _isUppercase(name));
    _byName['"'] = entry;
    _byName['0'] = entry;
    _clipboardCache = entry;
    unawaited(_writer(text));
  }

  /// Record a delete into [name] (defaults to unnamed). Rotates 1..9 and
  /// also sets `-` when the delete is small (single-line, charwise).
  void delete(String text, RangeKind kind, {String name = '"'}) {
    if (name == '_') return; // black hole
    final entry = RegisterEntry(text, kind);
    _setNamed(name, entry, append: _isUppercase(name));
    _byName['"'] = entry;
    // Rotate numbered registers 9←8←…←1, then 1=entry.
    for (var i = 9; i > 1; i--) {
      final prev = _byName['${i - 1}'];
      if (prev != null) _byName['$i'] = prev;
    }
    _byName['1'] = entry;
    if (kind == RangeKind.charwise && !text.contains('\n')) {
      _byName['-'] = entry;
    }
    if (name == '+' || name == '*') {
      _clipboardCache = entry;
      unawaited(_writer(text));
    }
  }

  void _setNamed(String name, RegisterEntry entry, {required bool append}) {
    if (name == '_' || name == '"' || name == '+' || name == '*') return;
    final key = name.toLowerCase();
    if (append) {
      final prev = _byName[key];
      if (prev == null || prev.isEmpty) {
        _byName[key] = entry;
      } else {
        _byName[key] = RegisterEntry(prev.text + entry.text, entry.kind);
      }
    } else {
      _byName[key] = entry;
    }
  }

  bool _isUppercase(String s) =>
      s.length == 1 && s.codeUnitAt(0) >= 0x41 && s.codeUnitAt(0) <= 0x5A;

  /// Pull the system clipboard into the `+`/`*` cache; awaited at app boot
  /// so the first `"+p` after launch sees the OS clipboard. Subsequent reads
  /// happen on demand via [refreshClipboard].
  Future<void> refreshClipboard() async {
    final text = await _reader();
    if (text == null) return;
    _clipboardCache = RegisterEntry(text, RangeKind.charwise);
  }

  /// All non-empty register names, for `:reg`.
  List<MapEntry<String, RegisterEntry>> all() {
    final out = <MapEntry<String, RegisterEntry>>[];
    final keys = _byName.keys.toList()..sort();
    for (final k in keys) {
      final v = _byName[k]!;
      if (!v.isEmpty) out.add(MapEntry(k, v));
    }
    if (!_clipboardCache.isEmpty) {
      out.add(MapEntry('+', _clipboardCache));
    }
    return out;
  }
}
