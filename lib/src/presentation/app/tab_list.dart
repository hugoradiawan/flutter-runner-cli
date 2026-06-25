import 'run_tab.dart';

/// Owns the ordered list of [RunTab]s and the "active" index — the tab the TUI
/// renders and that most commands (`reload`, `restart`, `stop`) operate on.
///
/// Pure bookkeeping: no sessions, IO, or app state. [RunController] composes
/// this and layers session lifecycle on top. The active index is kept valid
/// through every mutation:
///   - adding a tab makes it active;
///   - removing a tab keeps the *same* tab active where possible: the index is
///     shifted down when an earlier tab is removed, clamped to the last tab
///     when the active tab was at the end, and reset to -1 when empty.
class TabList {
  final List<RunTab> _tabs = <RunTab>[];
  int _activeIndex = -1;
  int _nextId = 1;

  /// Read-only view of the tabs in order.
  List<RunTab> get tabs => List<RunTab>.unmodifiable(_tabs);

  int get length => _tabs.length;
  bool get isEmpty => _tabs.isEmpty;
  bool get isNotEmpty => _tabs.isNotEmpty;
  bool get hasTabs => _tabs.isNotEmpty;

  int get activeIndex => _activeIndex;

  RunTab? get active => (_activeIndex >= 0 && _activeIndex < _tabs.length)
      ? _tabs[_activeIndex]
      : null;

  /// Next monotonic tab id. Mirrors the old `_nextTabId++`.
  int nextId() => _nextId++;

  /// Append [tab] and make it active.
  void add(RunTab tab) {
    _tabs.add(tab);
    _activeIndex = _tabs.length - 1;
  }

  /// Remove [tab] by identity, keeping the active index valid. No-op when
  /// [tab] is not present.
  void remove(RunTab tab) {
    final index = _tabs.indexOf(tab);
    if (index < 0) return;
    _tabs.removeAt(index);
    if (_tabs.isEmpty) {
      _activeIndex = -1;
    } else if (_activeIndex >= _tabs.length) {
      _activeIndex = _tabs.length - 1;
    } else if (_activeIndex > index) {
      _activeIndex--;
    }
  }

  /// Drop all tabs. Does not reset the id counter.
  void clear() {
    _tabs.clear();
    _activeIndex = -1;
  }

  /// Cycle the active tab. No-op with fewer than two tabs.
  void cycle({bool forward = true}) {
    if (_tabs.length < 2) return;
    final delta = forward ? 1 : -1;
    _activeIndex = (_activeIndex + delta) % _tabs.length;
    if (_activeIndex < 0) _activeIndex += _tabs.length;
  }

  /// Set the active tab by index. No-op when [index] is out of range.
  void setActiveIndex(int index) {
    if (index < 0 || index >= _tabs.length) return;
    _activeIndex = index;
  }
}
