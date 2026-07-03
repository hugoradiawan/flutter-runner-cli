import 'package:frun/src/data/services/isolate_manager.dart';
import 'package:test/test.dart';

void main() {
  group('IsolateManager isolate list cache', () {
    test('repeated reads return the same sorted list instance', () {
      final manager = IsolateManager(
        isolates: [
          IsolateInfo(id: 'b', name: 'worker', status: IsolateStatus.running),
          IsolateInfo(id: 'a', name: 'main', status: IsolateStatus.running),
        ],
      );

      final first = manager.isolates;
      expect(first.map((i) => i.name), ['main', 'worker']);
      expect(
        identical(first, manager.isolates),
        isTrue,
        reason: 'no re-sort/re-allocate until the list changes',
      );
      expect(manager.revision, manager.revision);
    });

    test('changes invalidate the cache and bump the revision', () async {
      final manager = IsolateManager(
        isolates: [
          IsolateInfo(id: 'a', name: 'main', status: IsolateStatus.running),
        ],
      );

      final before = manager.isolates;
      final revBefore = manager.revision;

      // disconnect() clears the map and emits — the one mutation reachable
      // without a live VM connection.
      await manager.disconnect();

      expect(manager.revision, greaterThan(revBefore));
      final after = manager.isolates;
      expect(identical(before, after), isFalse);
      expect(after, isEmpty);
    });
  });
}
