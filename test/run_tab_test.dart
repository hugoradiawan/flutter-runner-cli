import 'package:frun/src/domain/entities/launch_entry.dart';
import 'package:frun/src/domain/entities/run_session.dart';
import 'package:frun/src/presentation/app/run_tab.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockRunSession extends Mock implements RunSession {}

void main() {
  LaunchEntryEntity entry() =>
      const LaunchEntryEntity(name: 'app', program: 'lib/main.dart');

  group('RunTab', () {
    test('cannot hot reload before a session is attached', () {
      final tab = RunTab(id: 1, entry: entry(), deviceId: 'device');

      expect(tab.canHotReload, isFalse);
    });

    test('cannot hot reload before Flutter reports app.start', () {
      final session = MockRunSession();
      when(() => session.canHotReload).thenReturn(false);

      final tab = RunTab(id: 1, entry: entry(), deviceId: 'device')
        ..session = session;

      expect(tab.canHotReload, isFalse);
    });

    test('can hot reload after Flutter reports app.start', () {
      final session = MockRunSession();
      when(() => session.canHotReload).thenReturn(true);

      final tab = RunTab(id: 1, entry: entry(), deviceId: 'device')
        ..session = session;

      expect(tab.canHotReload, isTrue);
    });
  });
}
