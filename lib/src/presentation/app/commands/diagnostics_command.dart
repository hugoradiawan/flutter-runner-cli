import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../../../data/services/dart_source_walker.dart';
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
  DiagnosticsCommand({
    DartAnalyzeRunner? runAnalyze,
    String? dartExecutable,
    Duration analyzeTimeout = const Duration(seconds: 20),
  }) : _runAnalyze = runAnalyze,
       _dartExecutable = dartExecutable,
       _analyzeTimeout = analyzeTimeout;

  final DartAnalyzeRunner? _runAnalyze;
  final String? _dartExecutable;
  final Duration _analyzeTimeout;

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
    final todos = scanDartTodoDiagnostics(root: state.project.root);
    final currentAnalyzerDiagnostics = state.diagnostics
        .where((d) => d.category != DiagnosticCategory.todo)
        .toList(growable: false);
    state.diagnostics = mergeDiagnostics(currentAnalyzerDiagnostics, todos);
    state.showDiagnosticsPanel = true;
    state.transcript.system(
      'Showing current diagnostics; running dart analyze...',
    );

    final dartExecutable = _dartExecutable ?? _defaultDartExecutable();
    final ProcessResult result;
    try {
      final runner = _runAnalyze;
      if (runner == null) {
        result = await _runProcess(
          dartExecutable,
          const <String>['analyze', '--format=json', '--no-fatal-warnings'],
          state.project.root,
          _shouldRunInShell(dartExecutable),
          timeout: _analyzeTimeout,
        );
      } else {
        result = await runner(
          dartExecutable,
          const <String>['analyze', '--format=json', '--no-fatal-warnings'],
          state.project.root,
          _shouldRunInShell(dartExecutable),
        ).timeout(_analyzeTimeout);
      }
    } on ProcessException catch (e) {
      state.transcript.warn('dart analyze failed: ${e.message}');
      return CommandResult.ok;
    } on TimeoutException {
      state.transcript.warn(
        'dart analyze timed out after ${_analyzeTimeout.inSeconds}s; showing current diagnostics.',
      );
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
      return CommandResult.ok;
    }

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
    bool runInShell, {
    required Duration timeout,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: runInShell,
    );
    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();
    final exitCode = await process.exitCode.timeout(
      timeout,
      onTimeout: () {
        process.kill();
        throw TimeoutException('dart analyze timed out', timeout);
      },
    );
    return ProcessResult(
      process.pid,
      exitCode,
      await stdoutFuture,
      await stderrFuture,
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

Future<List<DiagnosticEntity>> scanDartTodoDiagnosticsInIsolate({
  required String root,
}) => Isolate.run(() => scanDartTodoDiagnostics(root: root));

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
