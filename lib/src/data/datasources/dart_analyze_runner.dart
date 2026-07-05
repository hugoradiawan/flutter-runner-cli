import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/entities/diagnostic.dart';

typedef AnalyzeProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments,
      String workingDirectory,
      bool runInShell,
    );

/// Thrown by [DartAnalyzeRunner.analyze]; [message] is the exact user-facing
/// text the diagnostics command reports.
class DartAnalyzeException implements Exception {
  const DartAnalyzeException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Runs one-shot `dart analyze --format=json` for a project and parses the
/// output into diagnostics.
class DartAnalyzeRunner {
  DartAnalyzeRunner({
    AnalyzeProcessRunner? runProcess,
    String? dartExecutable,
    Duration timeout = const Duration(seconds: 20),
  }) : _runProcessOverride = runProcess,
       _dartExecutable = dartExecutable,
       _timeout = timeout;

  final AnalyzeProcessRunner? _runProcessOverride;
  final String? _dartExecutable;
  final Duration _timeout;

  /// Analyzes [projectRoot]; throws [DartAnalyzeException] when the process
  /// cannot run, times out, or produces unparseable output.
  Future<List<DiagnosticEntity>> analyze({required String projectRoot}) async {
    final dartExecutable = _dartExecutable ?? _defaultDartExecutable();
    final ProcessResult result;
    try {
      final runner = _runProcessOverride;
      if (runner == null) {
        result = await _runProcess(
          dartExecutable,
          const <String>['analyze', '--format=json', '--no-fatal-warnings'],
          projectRoot,
          _shouldRunInShell(dartExecutable),
          timeout: _timeout,
        );
      } else {
        result = await runner(
          dartExecutable,
          const <String>['analyze', '--format=json', '--no-fatal-warnings'],
          projectRoot,
          _shouldRunInShell(dartExecutable),
        ).timeout(_timeout);
      }
    } on ProcessException catch (e) {
      throw DartAnalyzeException('dart analyze failed: ${e.message}');
    } on TimeoutException {
      throw DartAnalyzeException(
        'dart analyze timed out after ${_timeout.inSeconds}s; '
        'showing current diagnostics.',
      );
    }

    final parsed = parseDartAnalyzeJson(
      result.stdout.toString(),
      projectRoot: projectRoot,
    );
    if (parsed == null) {
      final detail = _firstUsefulLine(result.stderr, result.stdout);
      throw DartAnalyzeException(
        detail == null
            ? 'dart analyze failed: could not parse analyzer output.'
            : 'dart analyze failed: $detail',
      );
    }
    return parsed;
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
