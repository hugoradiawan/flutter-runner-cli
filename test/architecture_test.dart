/// Architecture ratchet: enforces the clean-architecture layer rules by
/// scanning import/export directives under `lib/`.
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
const knownPresentationToData = <String>{};

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
  final parts = <String, List<String>>{}; // owner -> resolved part targets
  final partOfFiles = <String>{}; // files that declare `part of`
  // `export` re-exposes types across a boundary just like `import` uses them,
  // so both directives feed the same layer-rule edges.
  final importPattern = RegExp(r'''^(?:import|export)\s+['"]([^'"]+)['"]''');
  final partPattern = RegExp(r'''^part\s+['"]([^'"]+)['"]''');
  final partOfPattern = RegExp(r'''^part\s+of\s''');
  // Conditional imports (`import 'a.dart' if (dart.library.io) 'b.dart';`)
  // hide the fallback URI from the line-based scan; catch it on raw content
  // since the directive usually wraps across lines.
  final conditionalPattern = RegExp(
    r'''if\s*\(dart\.library\.\w+(?:\s*==\s*[^)]+)?\)\s*['"]([^'"]+)['"]''',
  );

  for (final file in files) {
    final rel = p.posix.joinAll(p.split(p.relative(file.path, from: 'lib')));
    final targets = <String>[];
    final ownedParts = <String>[];
    for (final line in file.readAsLinesSync()) {
      final trimmed = line.trim();
      final m = importPattern.firstMatch(trimmed);
      if (m != null) {
        targets.add(_resolve(m.group(1)!, rel));
        continue;
      }
      if (partOfPattern.hasMatch(trimmed)) {
        partOfFiles.add(rel);
        continue;
      }
      final pm = partPattern.firstMatch(trimmed);
      if (pm != null) ownedParts.add(_resolve(pm.group(1)!, rel));
    }
    for (final m in conditionalPattern.allMatches(file.readAsStringSync())) {
      targets.add(_resolve(m.group(1)!, rel));
    }
    imports[rel] = targets;
    if (ownedParts.isNotEmpty) parts[rel] = ownedParts;
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

  test('part files stay in their owning library\'s directory and layer', () {
    // Parts bypass import analysis entirely (they can't have their own
    // directives), so a library `part`-ing a file from another layer would
    // smuggle code across the boundary invisibly. Pin parts to the owner's
    // directory, which implies the same layer.
    final actual = <String>{};
    final claimed = <String, int>{};
    parts.forEach((owner, targets) {
      for (final t in targets) {
        claimed[t] = (claimed[t] ?? 0) + 1;
        if (!File(p.join('lib', t)).existsSync()) {
          actual.add('$owner -> $t (missing on disk)');
        } else if (p.posix.dirname(t) != p.posix.dirname(owner)) {
          actual.add('$owner -> $t (outside owner directory)');
        }
      }
    });
    for (final f in partOfFiles) {
      final count = claimed[f] ?? 0;
      if (count != 1) {
        actual.add('$f (part of, claimed by $count part directives)');
      }
    }
    expect(
      actual,
      isEmpty,
      reason:
          'part/part-of placement violations:\n'
          '${(actual.toList()..sort()).join('\n')}',
    );
  });

  test('presentation (except di) reaches lower layers only via barrels', () {
    final actual = <String>{};
    imports.forEach((importer, targets) {
      if (!inLayer(importer, 'presentation')) return;
      if (importer == 'src/presentation/di/dependencies.dart') return;
      for (final t in targets) {
        final ok =
            t.startsWith('dart:') ||
            (t.startsWith('package:') && !t.startsWith('package:frun/')) ||
            t == 'src/domain/domain.dart' ||
            t == 'src/version.dart' ||
            inLayer(t, 'presentation');
        if (!ok) actual.add('$importer -> $t');
      }
    });
    expect(
      actual,
      isEmpty,
      reason:
          'Presentation must import lower layers through domain.dart '
          'only:\n${(actual.toList()..sort()).join('\n')}',
    );
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
