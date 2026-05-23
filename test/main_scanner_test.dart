import 'dart:io';

import 'package:frun/src/project/launch_config.dart';
import 'package:frun/src/project/main_scanner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('MainScanner', () {
    late Directory temp;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('frun_main_scan_');
    });

    tearDown(() => temp.deleteSync(recursive: true));

    test('finds files with top-level main and ignores those without', () {
      final libDir = Directory(p.join(temp.path, 'lib'))..createSync();
      File(p.join(libDir.path, 'main.dart'))
          .writeAsStringSync('void main() {}');
      File(p.join(libDir.path, 'main_dev.dart'))
          .writeAsStringSync('Future<void> main() async {}');
      File(p.join(libDir.path, 'widgets.dart'))
          .writeAsStringSync('class Widget {}');

      final entries = MainScanner.scan(libDir.path);
      final names = entries.map((e) => p.basename(e.program)).toList();
      expect(names, containsAll(<String>['main.dart', 'main_dev.dart']));
      expect(names, isNot(contains('widgets.dart')));
    });

    test('skips .dart_tool and build', () {
      final libDir = Directory(p.join(temp.path, 'lib'))..createSync();
      final buried = Directory(p.join(libDir.path, '.dart_tool', 'sub'))
        ..createSync(recursive: true);
      File(p.join(buried.path, 'main.dart')).writeAsStringSync('void main() {}');
      File(p.join(libDir.path, 'main.dart')).writeAsStringSync('void main() {}');
      final entries = MainScanner.scan(libDir.path);
      expect(entries, hasLength(1));
    });

    test('merge dedupes by program', () {
      const launchJson = <LaunchEntry>[
        LaunchEntry(name: 'dev', program: 'lib/main.dart'),
      ];
      const scanned = <LaunchEntry>[
        LaunchEntry(
          name: 'lib/main.dart',
          program: 'lib/main.dart',
          source: LaunchEntrySource.mainScanner,
        ),
        LaunchEntry(
          name: 'lib/main_dev.dart',
          program: 'lib/main_dev.dart',
          source: LaunchEntrySource.mainScanner,
        ),
      ];
      final merged = MainScanner.merge(launchJson, scanned);
      expect(merged, hasLength(2));
      expect(merged.first.source, LaunchEntrySource.launchJson);
    });
  });
}
