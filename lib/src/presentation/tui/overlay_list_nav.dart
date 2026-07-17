import 'package:dart_tui/dart_tui.dart';

/// What a navigation key resolved to. [OverlayNavConsumed] means the key was
/// part of a pending sequence (count digit, first `g`) and must not fall
/// through to overlay-specific handling.
sealed class OverlayNavAction {
  const OverlayNavAction();
}

final class OverlayNavMove extends OverlayNavAction {
  const OverlayNavMove(this.delta);
  final int delta;
}

final class OverlayNavEdge extends OverlayNavAction {
  const OverlayNavEdge({required this.first});
  final bool first;
}

final class OverlayNavHalfPage extends OverlayNavAction {
  const OverlayNavHalfPage({required this.down});
  final bool down;
}

final class OverlayNavClose extends OverlayNavAction {
  const OverlayNavClose();
}

final class OverlayNavStartSearch extends OverlayNavAction {
  const OverlayNavStartSearch();
}

final class OverlayNavConsumed extends OverlayNavAction {
  const OverlayNavConsumed();
}

/// Mutable selection state for one modal overlay list: the selected row and
/// the scroll offset that keeps it visible.
class OverlaySelection {
  int index = 0;
  int scroll = 0;

  void reset() {
    index = 0;
    scroll = 0;
  }
}

/// Shared vim-style list navigation for the modal overlays (diagnostics,
/// isolates, config editor): count-aware `j`/`k`, `gg`/`G`, `Ctrl-d`/`Ctrl-u`,
/// `q` to close, `/` to search. Arrows work regardless of editor mode.
///
/// Returns null for keys it doesn't own so overlay-specific handling (action
/// keys, filter chips, live text filters) stays with the caller.
class OverlayListNav {
  int _count = 0;
  bool _pendingG = false;

  void reset() {
    _count = 0;
    _pendingG = false;
  }

  OverlayNavAction? interpret(TeaKey ke, {required bool vim}) {
    if (ke.code == KeyCode.up) {
      final n = _takeCount();
      return OverlayNavMove(-n);
    }
    if (ke.code == KeyCode.down) {
      final n = _takeCount();
      return OverlayNavMove(n);
    }
    if (!vim) return null;

    if (ke.code == KeyCode.rune && ke.modifiers.contains(KeyMod.ctrl)) {
      final t = ke.text.toLowerCase();
      if (t == 'd') {
        reset();
        return const OverlayNavHalfPage(down: true);
      }
      if (t == 'u') {
        reset();
        return const OverlayNavHalfPage(down: false);
      }
      return null;
    }

    final plain =
        ke.code == KeyCode.rune && ke.modifiers.isEmpty && ke.text.length == 1;
    if (!plain) return null;
    final ch = ke.text;

    final digit = ch.codeUnitAt(0) >= 0x30 && ch.codeUnitAt(0) <= 0x39;
    if (digit && (ch != '0' || _count > 0)) {
      _count = _count * 10 + int.parse(ch);
      _pendingG = false;
      return const OverlayNavConsumed();
    }

    switch (ch) {
      case 'j':
        return OverlayNavMove(_takeCount());
      case 'k':
        return OverlayNavMove(-_takeCount());
      case 'g':
        if (_pendingG) {
          reset();
          return const OverlayNavEdge(first: true);
        }
        _pendingG = true;
        return const OverlayNavConsumed();
      case 'G':
        reset();
        return const OverlayNavEdge(first: false);
      case 'q':
        reset();
        return const OverlayNavClose();
      case '/':
        reset();
        return const OverlayNavStartSearch();
      default:
        _pendingG = false;
        return null;
    }
  }

  int _takeCount() {
    final n = _count == 0 ? 1 : _count;
    reset();
    return n;
  }
}
