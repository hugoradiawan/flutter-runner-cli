/// Watches a source tree and emits a debounced [onChange] tick per burst of
/// file events — the trigger for hot-reload-on-save.
abstract class SourceChangeWatcher {
  Stream<void> get onChange;

  void start();

  Future<void> dispose();
}
