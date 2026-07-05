import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../../domain/entities/diagnostic.dart';
import 'dart_source_walker.dart';

const Set<String> _todoCodes = {'todo', 'fixme', 'hack', 'undone'};
const int _maxTodoDiagnostics = 2000;

final RegExp _todoMarkerPattern = RegExp(
  r'\b(TODO|FIXME|HACK|UNDONE)\b[:\s-]*(.*)',
  caseSensitive: false,
);

List<DiagnosticEntity> scanDartTodoDiagnostics({required String root}) {
  final dir = Directory(root);
  if (!dir.existsSync()) return const <DiagnosticEntity>[];
  final out = <DiagnosticEntity>[];
  for (final file in _dartFiles(dir)) {
    _scanTodoFile(file, out);
    if (out.length >= _maxTodoDiagnostics) break;
  }
  return out;
}

Future<List<DiagnosticEntity>> scanDartTodoDiagnosticsInIsolate({
  required String root,
}) => Isolate.run(() => scanDartTodoDiagnostics(root: root));

/// Live TODO/FIXME index over a source tree: seeded by a whole-tree scan,
/// then maintained incrementally per changed file by the diagnostics watcher.
class TodoDiagnosticsIndex {
  TodoDiagnosticsIndex({required String root}) : root = p.normalize(root);

  final String root;
  final Map<String, List<DiagnosticEntity>> _byPath =
      <String, List<DiagnosticEntity>>{};

  void refreshAll() {
    _byPath.clear();
    final dir = Directory(root);
    if (!dir.existsSync()) return;
    var count = 0;
    for (final file in _dartFiles(dir)) {
      count += updateFile(file.path);
      if (count >= _maxTodoDiagnostics) break;
    }
  }

  void replaceAll(Iterable<DiagnosticEntity> diagnostics) {
    _byPath.clear();
    var count = 0;
    for (final diagnostic in diagnostics) {
      if (count >= _maxTodoDiagnostics) break;
      final normalized = p.normalize(diagnostic.filePath);
      (_byPath[normalized] ??= <DiagnosticEntity>[]).add(diagnostic);
      count++;
    }
  }

  int updateFile(String path) {
    final normalized = p.normalize(path);
    final file = File(normalized);
    if (!file.existsSync()) {
      _byPath.remove(normalized);
      return 0;
    }
    final scanned = <DiagnosticEntity>[];
    _scanTodoFile(file, scanned);
    if (scanned.isEmpty) {
      _byPath.remove(normalized);
    } else {
      _byPath[normalized] = scanned;
    }
    return scanned.length;
  }

  void removeFile(String path) {
    _byPath.remove(p.normalize(path));
  }

  List<DiagnosticEntity> get diagnostics {
    if (_byPath.isEmpty) return const <DiagnosticEntity>[];
    final out = <DiagnosticEntity>[];
    for (final entry in _byPath.entries) {
      for (final diagnostic in entry.value) {
        if (out.length >= _maxTodoDiagnostics) return out;
        out.add(diagnostic);
      }
    }
    return out;
  }
}

Iterable<File> _dartFiles(Directory root) sync* {
  yield* walkDartSourceFiles(root);
}

void _scanTodoFile(File file, List<DiagnosticEntity> out) {
  List<String> lines;
  try {
    lines = file.readAsLinesSync();
  } catch (_) {
    return;
  }

  var inBlock = false;
  for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
    final line = lines[lineIndex];
    var cursor = 0;
    while (cursor < line.length) {
      if (inBlock) {
        final end = line.indexOf('*/', cursor);
        final segmentEnd = end < 0 ? line.length : end;
        _addTodoFromCommentSegment(
          out,
          file.path,
          lineIndex,
          cursor,
          line.substring(cursor, segmentEnd),
        );
        if (end < 0) break;
        inBlock = false;
        cursor = end + 2;
        continue;
      }

      final lineComment = line.indexOf('//', cursor);
      final blockComment = line.indexOf('/*', cursor);
      if (lineComment < 0 && blockComment < 0) break;
      if (lineComment >= 0 &&
          (blockComment < 0 || lineComment < blockComment)) {
        _addTodoFromCommentSegment(
          out,
          file.path,
          lineIndex,
          lineComment + 2,
          line.substring(lineComment + 2),
        );
        break;
      }

      final end = line.indexOf('*/', blockComment + 2);
      final segmentStart = blockComment + 2;
      final segmentEnd = end < 0 ? line.length : end;
      _addTodoFromCommentSegment(
        out,
        file.path,
        lineIndex,
        segmentStart,
        line.substring(segmentStart, segmentEnd),
      );
      if (end < 0) {
        inBlock = true;
        break;
      }
      cursor = end + 2;
    }
    if (out.length >= _maxTodoDiagnostics) return;
  }
}

void _addTodoFromCommentSegment(
  List<DiagnosticEntity> out,
  String filePath,
  int lineIndex,
  int segmentStartColumn,
  String segment,
) {
  if (out.length >= _maxTodoDiagnostics) return;
  final match = _todoMarkerPattern.firstMatch(segment);
  if (match == null) return;
  final code = match.group(1)!.toLowerCase();
  if (!_todoCodes.contains(code)) return;
  final message = segment.substring(match.start).trim();
  out.add(
    DiagnosticEntity(
      filePath: p.normalize(filePath),
      line: lineIndex + 1,
      column: segmentStartColumn + match.start + 1,
      severity: DiagnosticSeverity.info,
      message: message.isEmpty ? code.toUpperCase() : message,
      code: code,
    ),
  );
}
