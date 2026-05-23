import 'package:dart_tui/dart_tui.dart';

import '../config/config.dart';

enum VimMode { insert, normal }

/// What [InputController.handle] tells the caller to do next.
enum InputAction { none, submit }

/// A single-line input that supports a normal mode and an optional vim mode.
///
/// In "normal" editor mode, [VimMode] is always [VimMode.insert].
/// In "vim" editor mode, Escape leaves insert mode; typing in normal mode runs
/// motions/edits; `i`/`a`/`A`/`I`/`o` re-enter insert mode.
class InputController {
  InputController({required FrunEditorMode editorMode})
      : _editorMode = editorMode {
    _mode = VimMode.insert;
  }

  String _text = '';
  int _cursor = 0;
  late VimMode _mode;
  FrunEditorMode _editorMode;
  String _yank = '';
  String _pendingOperator = '';
  int _pendingCount = 0;

  String get text => _text;
  int get cursor => _cursor;
  VimMode get mode => _mode;
  FrunEditorMode get editorMode => _editorMode;

  set editorMode(FrunEditorMode mode) {
    _editorMode = mode;
    if (mode == FrunEditorMode.normal) _mode = VimMode.insert;
  }

  /// True if the input panel should treat printable chars as text entry.
  bool get isInserting =>
      _editorMode == FrunEditorMode.normal || _mode == VimMode.insert;

  void clear() {
    _text = '';
    _cursor = 0;
    _pendingOperator = '';
    _pendingCount = 0;
  }

  /// Replace the buffer's contents — used by `[+ Run]` button to inject
  /// "/run" and submit.
  void setText(String value) {
    _text = value;
    _cursor = value.length;
  }

  /// Removes the last [n] characters from the input. Kept for the modifier-
  /// arrow workaround in case dart_tui ever needs it.
  void removeLast(int n) {
    if (n <= 0 || _text.isEmpty) return;
    final r = n.clamp(0, _text.length);
    _text = _text.substring(0, _text.length - r);
    if (_cursor > _text.length) _cursor = _text.length;
  }

  InputAction handle(KeyMsg event) {
    if (_editorMode == FrunEditorMode.vim) {
      if (_mode == VimMode.normal) {
        return _handleVimNormal(event);
      }
      if (event.keyEvent.code == KeyCode.escape) {
        _mode = VimMode.normal;
        if (_cursor > 0) _cursor--;
        return InputAction.none;
      }
    }
    return _handleInsert(event);
  }

  InputAction _handleInsert(KeyMsg event) {
    final ke = event.keyEvent;
    final isCtrl = ke.modifiers.contains(KeyMod.ctrl);
    switch (ke.code) {
      case KeyCode.enter:
        return InputAction.submit;
      case KeyCode.backspace:
        if (_cursor > 0) {
          _text = _text.substring(0, _cursor - 1) + _text.substring(_cursor);
          _cursor--;
        }
      case KeyCode.delete:
        if (_cursor < _text.length) {
          _text = _text.substring(0, _cursor) + _text.substring(_cursor + 1);
        }
      case KeyCode.left:
        if (_cursor > 0) _cursor--;
      case KeyCode.right:
        if (_cursor < _text.length) _cursor++;
      case KeyCode.home:
        _cursor = 0;
      case KeyCode.end:
        _cursor = _text.length;
      case KeyCode.rune:
        if (isCtrl) {
          final t = ke.text;
          if (t == 'a' || t == 'A') {
            _cursor = 0;
          } else if (t == 'e' || t == 'E') {
            _cursor = _text.length;
          } else if (t == 'u' || t == 'U') {
            _text = _text.substring(_cursor);
            _cursor = 0;
          }
          break;
        }
        final ch = ke.text;
        if (ch.isNotEmpty && ch != '\n' && ch != '\r') {
          _text = _text.substring(0, _cursor) + ch + _text.substring(_cursor);
          _cursor += ch.length;
        }
      case KeyCode.space:
        _text = '${_text.substring(0, _cursor)} ${_text.substring(_cursor)}';
        _cursor += 1;
      default:
        break;
    }
    return InputAction.none;
  }

  InputAction _handleVimNormal(KeyMsg event) {
    final ke = event.keyEvent;
    if (ke.code == KeyCode.enter) return InputAction.submit;
    if (ke.code != KeyCode.rune) {
      switch (ke.code) {
        case KeyCode.left:
          if (_cursor > 0) _cursor--;
        case KeyCode.right:
          if (_cursor < _text.length) _cursor++;
        case KeyCode.escape:
          _pendingOperator = '';
          _pendingCount = 0;
        default:
          break;
      }
      return InputAction.none;
    }

    final ch = ke.text;
    final count = _pendingCount == 0 ? 1 : _pendingCount;

    if (RegExp(r'\d').hasMatch(ch) && !(ch == '0' && _pendingCount == 0)) {
      _pendingCount = _pendingCount * 10 + int.parse(ch);
      return InputAction.none;
    }

    if (_pendingOperator.isNotEmpty) {
      _applyOperator(_pendingOperator, ch, count);
      _pendingOperator = '';
      _pendingCount = 0;
      return InputAction.none;
    }

    switch (ch) {
      case 'h':
        _cursor = (_cursor - count).clamp(0, _text.length);
      case 'l':
        _cursor = (_cursor + count).clamp(0, _text.length);
      case 'w':
        for (var i = 0; i < count; i++) {
          _cursor = _nextWordStart(_cursor);
        }
      case 'b':
        for (var i = 0; i < count; i++) {
          _cursor = _prevWordStart(_cursor);
        }
      case '0':
        _cursor = 0;
      case r'$':
        _cursor = _text.length;
      case 'x':
        for (var i = 0; i < count; i++) {
          if (_cursor < _text.length) {
            _yank = _text[_cursor];
            _text =
                _text.substring(0, _cursor) + _text.substring(_cursor + 1);
          }
        }
      case 'i':
        _mode = VimMode.insert;
      case 'I':
        _cursor = 0;
        _mode = VimMode.insert;
      case 'a':
        if (_cursor < _text.length) _cursor++;
        _mode = VimMode.insert;
      case 'A':
        _cursor = _text.length;
        _mode = VimMode.insert;
      case 'd':
      case 'c':
      case 'y':
        _pendingOperator = ch;
      case 'p':
        if (_yank.isNotEmpty) {
          final insertAt = (_cursor + 1).clamp(0, _text.length);
          _text =
              _text.substring(0, insertAt) + _yank + _text.substring(insertAt);
          _cursor = insertAt + _yank.length - 1;
        }
      case 'P':
        if (_yank.isNotEmpty) {
          _text = _text.substring(0, _cursor) + _yank + _text.substring(_cursor);
          _cursor += _yank.length - 1;
        }
      case 'D':
        _yank = _text.substring(_cursor);
        _text = _text.substring(0, _cursor);
      case 'C':
        _yank = _text.substring(_cursor);
        _text = _text.substring(0, _cursor);
        _mode = VimMode.insert;
    }
    _pendingCount = 0;
    return InputAction.none;
  }

  void _applyOperator(String op, String motion, int count) {
    int start;
    int end;
    switch (motion) {
      case 'w':
        start = _cursor;
        end = _cursor;
        for (var i = 0; i < count; i++) {
          end = _nextWordStart(end);
        }
      case 'b':
        end = _cursor;
        start = _cursor;
        for (var i = 0; i < count; i++) {
          start = _prevWordStart(start);
        }
      case r'$':
        start = _cursor;
        end = _text.length;
      case '0':
        start = 0;
        end = _cursor;
      default:
        return;
    }
    if (start == end) return;
    final selected = _text.substring(start, end);
    if (op == 'y') {
      _yank = selected;
      return;
    }
    _yank = selected;
    _text = _text.substring(0, start) + _text.substring(end);
    _cursor = start;
    if (op == 'c') _mode = VimMode.insert;
  }

  int _nextWordStart(int from) {
    var i = from;
    while (i < _text.length && _isWordChar(_text[i])) {
      i++;
    }
    while (i < _text.length && !_isWordChar(_text[i])) {
      i++;
    }
    return i;
  }

  int _prevWordStart(int from) {
    var i = from;
    if (i > 0) i--;
    while (i > 0 && !_isWordChar(_text[i])) {
      i--;
    }
    while (i > 0 && _isWordChar(_text[i - 1])) {
      i--;
    }
    return i;
  }

  bool _isWordChar(String ch) => RegExp(r'[A-Za-z0-9_/.\-]').hasMatch(ch);
}
