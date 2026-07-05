/// Architecture ratchet: enforces the clean-architecture layer rules by
/// scanning import directives under `lib/`.
///
/// Layer rules:
///   - domain   -> core only (no dart:io, no dart_tui, no data/presentation)
///   - data     -> core + domain (never presentation)
///   - presentation -> core + domain (+ data ONLY from di/dependencies.dart)
///
/// `lib/frun.dart` is the composition root and exempt.
///
/// Known violations are allowlisted below. Each refactor phase deletes its
/// entries; the test fails both when a NEW violation appears and when an
/// allowlisted entry no longer exists (so the lists stay honest).
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// data -> presentation (the import-direction cycle). Format:
/// 'importer -> imported', both lib-relative posix paths.
const knownDataToPresentation = <String>{};

/// presentation -> data outside the sanctioned seam (di/dependencies.dart).
const knownPresentationToData = <String>{
  'src/presentation/app/commands/emulators_command.dart -> src/data/datasources/emulator_manager.dart',
  'src/presentation/app/commands/isolates_command.dart -> src/data/services/isolate_manager.dart',
  'src/presentation/app/commands/run_command.dart -> src/data/models/launch_config.dart',
  'src/presentation/app/commands/run_command.dart -> src/data/services/main_scanner.dart',
  'src/presentation/app/daemon_event_router.dart -> src/data/datasources/app_session.dart',
  'src/presentation/app/daemon_event_router.dart -> src/data/models/daemon_messages.dart',
  'src/presentation/app/reload_watcher.dart -> src/data/services/dart_file_watcher.dart',
  'src/presentation/app/run_controller.dart -> src/data/datasources/app_session.dart',
  'src/presentation/app/run_tab.dart -> src/data/datasources/app_session.dart',
  'src/presentation/app/run_tab.dart -> src/data/models/daemon_messages.dart',
  'src/presentation/tui/clipboard.dart -> src/data/services/windows_clipboard.dart',
  'src/presentation/tui/frun_app.dart -> src/data/services/history_store.dart',
  'src/presentation/tui/frun_app.dart -> src/data/services/isolate_manager.dart',
};

/// domain purity violations (should stay empty).
const knownDomainViolations = <String>{};

void main() {
  final libDir = Directory('lib');
  final files = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  final imports = <String, List<String>>{}; // lib-relative -> targets
  final importPattern = RegExp(r'''^import\s+['"]([^'"]+)['"]''');

  for (final file in files) {
    final rel = p.posix.joinAll(p.split(p.relative(file.path, from: 'lib')));
    final targets = <String>[];
    for (final line in file.readAsLinesSync()) {
      final m = importPattern.firstMatch(line.trim());
      if (m == null) continue;
      targets.add(_resolve(m.group(1)!, rel));
    }
    imports[rel] = targets;
  }

  bool inLayer(String path, String layer) => path.startsWith('src/$layer/');

  Set<String> edges(
    bool Function(String importer) fromWhere,
    bool Function(String imported) toWhere,
  ) {
    final found = <String>{};
    imports.forEach((importer, targets) {
      if (!fromWhere(importer)) return;
      for (final t in targets) {
        if (toWhere(t)) found.add('$importer -> $t');
      }
    });
    return found;
  }

  test('data never imports presentation (beyond allowlist)', () {
    final actual = edges(
      (f) => inLayer(f, 'data'),
      (t) => inLayer(t, 'presentation'),
    );
    _expectRatchet(actual, knownDataToPresentation);
  });

  test('domain imports only core (and pure packages)', () {
    const allowedPackages = {'equatable', 'path', 'meta', 'collection'};
    final actual = <String>{};
    imports.forEach((importer, targets) {
      if (!inLayer(importer, 'domain')) return;
      for (final t in targets) {
        final ok =
            inLayer(t, 'core') ||
            inLayer(t, 'domain') ||
            (t.startsWith('dart:') && t != 'dart:io') ||
            (t.startsWith('package:') &&
                allowedPackages.contains(t.split(':')[1].split('/')[0]));
        if (!ok) actual.add('$importer -> $t');
      }
    });
    _expectRatchet(actual, knownDomainViolations);
  });

  test('presentation imports data only from di/dependencies.dart', () {
    final actual = edges(
      (f) =>
          inLayer(f, 'presentation') &&
          f != 'src/presentation/di/dependencies.dart',
      (t) => inLayer(t, 'data'),
    );
    _expectRatchet(actual, knownPresentationToData);
  });

  test('core imports nothing from other layers', () {
    final actual = edges(
      (f) => inLayer(f, 'core'),
      (t) =>
          inLayer(t, 'domain') ||
          inLayer(t, 'data') ||
          inLayer(t, 'presentation'),
    );
    expect(actual, isEmpty);
  });
}

/// Resolves an import URI to a lib-relative posix path when it points inside
/// this package; returns the URI unchanged otherwise (dart:/package: externals).
String _resolve(String uri, String importerRel) {
  if (uri.startsWith('package:frun/')) {
    return uri.substring('package:frun/'.length);
  }
  if (uri.startsWith('dart:') || uri.startsWith('package:')) return uri;
  final dir = p.posix.dirname(importerRel);
  return p.posix.normalize(p.posix.join(dir, uri));
}

void _expectRatchet(Set<String> actual, Set<String> allowlist) {
  final newViolations = actual.difference(allowlist);
  final stale = allowlist.difference(actual);
  expect(
    newViolations,
    isEmpty,
    reason:
        'NEW layer violations (fix them or discuss):\n'
        '${(newViolations.toList()..sort()).join('\n')}',
  );
  expect(
    stale,
    isEmpty,
    reason:
        'Allowlist entries no longer violated — delete them:\n'
        '${(stale.toList()..sort()).join('\n')}',
  );
}
