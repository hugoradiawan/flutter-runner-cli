import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../domain/entities/diagnostic.dart';
import '../app_state.dart';
import 'command.dart';

typedef DartAnalyzeRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments,
      String workingDirectory,
      bool runInShell,
    );

/// Runs one-shot `dart analyze` and opens the diagnostics overlay.
class DiagnosticsCommand extends Command {
  DiagnosticsCommand({DartAnalyzeRunner? runAnalyze, String? dartExecutable})
    : _runAnalyze = runAnalyze ?? _runProcess,
      _dartExecutable = dartExecutable;

  final DartAnalyzeRunner _runAnalyze;
  final String? _dartExecutable;

  @override
  String get name => 'diagnostics';

  @override
  String get summary => 'Run dart analyze once and show diagnostics';

  @override
  String get usage => '/diagnostics [error|warning|info|todo|all]';

  @override
  List<String> get aliases => const ['problems', 'prob'];

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    final parsedFilter = _parseFilter(args, state);
    if (!parsedFilter.valid) return CommandResult.ok;

    state.diagnosticsFilter = parsedFilter.filter;
    state.diagnosticsSearch = '';
    state.transcript.system('Running dart analyze...');

    final dartExecutable = _dartExecutable ?? _defaultDartExecutable();
    final ProcessResult result;
    try {
      result = await _runAnalyze(
        dartExecutable,
        const <String>['analyze', '--format=json', '--no-fatal-warnings'],
        state.project.root,
        _shouldRunInShell(dartExecutable),
      );
    } on ProcessException catch (e) {
      state.showDiagnosticsPanel = false;
      state.transcript.warn('dart analyze failed: ${e.message}');
      return CommandResult.ok;
    }

    final parsed = parseDartAnalyzeJson(
      result.stdout.toString(),
      projectRoot: state.project.root,
    );
    if (parsed == null) {
      final detail = _firstUsefulLine(result.stderr, result.stdout);
      state.transcript.warn(
        detail == null
            ? 'dart analyze failed: could not parse analyzer output.'
            : 'dart analyze failed: $detail',
      );
      state.showDiagnosticsPanel = false;
      return CommandResult.ok;
    }

    final todos = scanDartTodoDiagnostics(root: state.project.watchRoot);
    state.diagnostics = mergeDiagnostics(parsed, todos);
    state.showDiagnosticsPanel = true;
    final (e, w, i, t) = DiagnosticEntity.counts(state.diagnostics);
    state.transcript.system(
      state.diagnostics.isEmpty
          ? 'Diagnostics: no analyzer issues or TODOs found.'
          : 'Diagnostics: $e errors, $w warnings, $i infos, $t todos.',
    );
    return CommandResult.ok;
  }

  static Future<ProcessResult> _runProcess(
    String executable,
    List<String> arguments,
    String workingDirectory,
    bool runInShell,
  ) {
    return Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: runInShell,
    );
  }

  ({bool valid, DiagnosticCategory? filter}) _parseFilter(
    List<String> args,
    AppState state,
  ) {
    if (args.isEmpty) return (valid: true, filter: null);
    final arg = args.first.toLowerCase();
    switch (arg) {
      case 'error':
      case 'errors':
      case 'e':
        return (valid: true, filter: DiagnosticCategory.error);
      case 'warning':
      case 'warn':
      case 'w':
        return (valid: true, filter: DiagnosticCategory.warning);
      case 'info':
      case 'infos':
      case 'i':
        return (valid: true, filter: DiagnosticCategory.info);
      case 'todo':
      case 'todos':
      case 't':
        return (valid: true, filter: DiagnosticCategory.todo);
      case 'all':
      case 'a':
        return (valid: true, filter: null);
      default:
        state.transcript.warn(
          'Unknown filter "$arg" - use error|warning|info|todo|all.',
        );
        return (valid: false, filter: null);
    }
  }

  static String _defaultDartExecutable() {
    final resolved = Platform.resolvedExecutable;
    if (p.basenameWithoutExtension(resolved).toLowerCase() == 'dart') {
      return resolved;
    }
    return Platform.isWindows ? 'dart.bat' : 'dart';
  }

  static bool _shouldRunInShell(String? executable) {
    if (!Platform.isWindows) return false;
    if (executable == null) return true;
    return p.extension(executable).toLowerCase() == '.bat';
  }

  static String? _firstUsefulLine(Object? stderr, Object? stdout) {
    for (final source in [stderr, stdout]) {
      final text = source?.toString().trim();
      if (text == null || text.isEmpty) continue;
      for (final line in const LineSplitter().convert(text)) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty) return trimmed;
      }
    }
    return null;
  }
}

List<DiagnosticEntity> mergeDiagnostics(
  List<DiagnosticEntity> analyzer,
  List<DiagnosticEntity> todos,
) {
  final out = <DiagnosticEntity>[];
  final seen = <String>{};
  for (final d in [...analyzer, ...todos]) {
    final key =
        '${p.normalize(d.filePath)}\x00${d.line}\x00${d.column}\x00${d.code ?? ''}';
    if (seen.add(key)) out.add(d);
  }
  return out;
}

List<DiagnosticEntity>? parseDartAnalyzeJson(
  String text, {
  required String projectRoot,
}) {
  final Object? decoded;
  try {
    decoded = json.decode(text);
  } catch (_) {
    return null;
  }
  if (decoded is! Map) return null;
  final diagnostics = decoded['diagnostics'];
  if (diagnostics is! List) return null;

  final out = <DiagnosticEntity>[];
  for (final item in diagnostics) {
    if (item is! Map) continue;
    final map = item.cast<String, Object?>();
    final location = (map['location'] as Map?)?.cast<String, Object?>();
    final range = (location?['range'] as Map?)?.cast<String, Object?>();
    final start = (range?['start'] as Map?)?.cast<String, Object?>();
    final file = location?['file'] as String?;
    if (file == null || file.isEmpty) continue;
    out.add(
      DiagnosticEntity(
        filePath: p.normalize(
          p.isAbsolute(file) ? file : p.join(projectRoot, file),
        ),
        line: (start?['line'] as num?)?.toInt() ?? 1,
        column: (start?['column'] as num?)?.toInt() ?? 1,
        severity: _severityFromAnalyze(map['severity']),
        message: _diagnosticMessage(map),
        code: _diagnosticCode(map['code']),
      ),
    );
  }
  return out;
}

DiagnosticSeverity _severityFromAnalyze(Object? severity) {
  switch (severity?.toString().toLowerCase()) {
    case 'error':
      return DiagnosticSeverity.error;
    case 'warning':
      return DiagnosticSeverity.warning;
    default:
      return DiagnosticSeverity.info;
  }
}

String _diagnosticMessage(Map<String, Object?> map) {
  final message = map['problemMessage'] ?? map['message'];
  return message?.toString().replaceAll('\n', ' ').trim() ?? '';
}

String? _diagnosticCode(Object? code) {
  if (code == null) return null;
  if (code is String) return code;
  if (code is Map) {
    final name = code['name'];
    if (name != null) return name.toString();
  }
  return code.toString();
}

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

Iterable<File> _dartFiles(Directory root) sync* {
  final List<FileSystemEntity> entries;
  try {
    entries = root.listSync(recursive: true, followLinks: false);
  } catch (_) {
    return;
  }
  for (final entity in entries) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('.dart')) continue;
    if (_isExcludedPath(root.path, entity.path)) continue;
    yield entity;
  }
}

bool _isExcludedPath(String root, String path) {
  final rel = p.isWithin(root, path) ? p.relative(path, from: root) : path;
  for (final segment in p.split(rel)) {
    if (segment == '.dart_tool' ||
        segment == 'build' ||
        segment == '.fvm' ||
        segment == '.git') {
      return true;
    }
  }
  return false;
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
