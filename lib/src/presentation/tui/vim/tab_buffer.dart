/// Thin contract the engine's tab-switching callback drives. The TUI passes a
/// concrete implementation wrapping `RunController.cycleActive` /
/// `RunController.setActiveIndex`.
abstract class TabSwitchSink {
  int get tabCount;
  int get activeIndex;
  void next();
  void previous();
  void goTo(int oneBasedIndex);
}

/// Default implementation used by `FrunModel`. Delegates to the supplied
/// callbacks so we don't take a hard dependency on `RunController` here.
class CallbackTabSwitchSink implements TabSwitchSink {
  CallbackTabSwitchSink({
    required int Function() tabCount,
    required int Function() activeIndex,
    required void Function(int index) setActiveIndex,
    required void Function({required bool forward}) cycle,
  })  : _tabCount = tabCount,
        _activeIndex = activeIndex,
        _setActiveIndex = setActiveIndex,
        _cycle = cycle;

  final int Function() _tabCount;
  final int Function() _activeIndex;
  final void Function(int index) _setActiveIndex;
  final void Function({required bool forward}) _cycle;

  @override
  int get tabCount => _tabCount();

  @override
  int get activeIndex => _activeIndex();

  @override
  void next() => _cycle(forward: true);

  @override
  void previous() => _cycle(forward: false);

  @override
  void goTo(int oneBasedIndex) {
    if (oneBasedIndex < 1) return;
    _setActiveIndex(oneBasedIndex - 1);
  }
}
