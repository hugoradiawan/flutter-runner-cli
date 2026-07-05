import 'package:frun/src/data/datasources/app_session.dart';
import 'package:frun/src/domain/entities/launch_entry.dart';
import 'package:frun/src/presentation/app/run_tab.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAppRunSession extends Mock implements AppRunSession {}

void main() {
  LaunchEntryEntity entry() =>
      const LaunchEntryEntity(name: 'app', program: 'lib/main.dart');

  group('RunTab', () {
    test('cannot hot reload before a session is attached', () {
      final tab = RunTab(id: 1, entry: entry(), deviceId: 'device');

      expect(tab.canHotReload, isFalse);
    });

    test('cannot hot reload before Flutter reports app.start', () {
      final session = MockAppRunSession();
      when(() => session.appId).thenReturn(null);

      final tab = RunTab(id: 1, entry: entry(), deviceId: 'device')
        ..session = session;

      expect(tab.canHotReload, isFalse);
    });

    test('can hot reload after Flutter reports app.start', () {
      final session = MockAppRunSession();
      when(() => session.appId).thenReturn('app-1');

      final tab = RunTab(id: 1, entry: entry(), deviceId: 'device')
        ..session = session;

      expect(tab.canHotReload, isTrue);
    });
  });
}
