import 'dart:convert';

import 'package:path/path.dart' as p;
import '../../domain/domain.dart';

/// Renders a `Flutter.Error` event payload into a compact, useful log.
///
/// Flutter serializes a deep `DiagnosticsNode` tree (the same one DevTools
/// shows) into the event. Naively flattening it produces hundreds of lines
/// dominated by framework stack frames. Instead this classifies nodes by
/// their `type`:
///   - `ErrorSummary` (the headline, e.g. "X was used after being disposed")
///   - `ErrorDescription` / `ErrorHint` (context)
///   - the "error-causing widget" block → a clickable `file:line`
///   - `DiagnosticsStackTrace` → frames, with framework noise collapsed
///
/// Stack frames and the summary live in each node's `properties` array (not
/// `children`), so both are walked. Set [verbose] to also dump the full raw
/// JSON payload; it is dumped automatically when nothing could be extracted.
String renderFlutterError(
  Map<dynamic, dynamic> data, {
  bool verbose = false,
  String? projectRoot,
}) {
  final errorsSince = (data['errorsSinceReload'] as num?)?.toInt() ?? 0;
  final library = data['library']?.toString() ?? 'Flutter framework';

  final buf = StringBuffer()
    ..writeln(
      '══ Exception caught by $library'
      '${errorsSince > 0 ? ' (error #${errorsSince + 1})' : ''} ══',
    );

  final parts = _ErrorParts();
  _collectNode(data['properties'], parts, projectRoot);
  _collectNode(data['children'], parts, projectRoot);
  _collectNode(data['stack'], parts, projectRoot);

  // Top-level summary fallbacks for Flutter versions that don't emit an
  // ErrorSummary node.
  final topDesc = data['description']?.toString() ?? '';
  if (parts.summary.isEmpty && topDesc.isNotEmpty) parts.summary.add(topDesc);
  final exc = _exceptionLine(data['exception']);
  if (parts.summary.isEmpty && exc.isNotEmpty) parts.summary.add(exc);

  for (final s in parts.summary) {
    buf.writeln(s);
  }
  for (final c in parts.context) {
    buf.writeln('  $c');
  }
  if (parts.widgetLoc != null) {
    buf.writeln('  widget: ${parts.widgetLoc}');
  } else if (parts.widgetRaw != null) {
    buf.writeln('  widget: ${parts.widgetRaw}');
  }
  for (final f in _trimFrames(parts.frames)) {
    buf.writeln(f);
  }

  final extractedAnything =
      parts.summary.isNotEmpty ||
      parts.context.isNotEmpty ||
      parts.frames.isNotEmpty ||
      parts.widgetLoc != null ||
      parts.widgetRaw != null;
  if (verbose || !extractedAnything) {
    buf.writeln(
      extractedAnything
          ? '--- raw Flutter.Error payload (verbose_errors) ---'
          : '--- raw Flutter.Error payload (nothing extracted) ---',
    );
    try {
      buf.writeln(const JsonEncoder.withIndent('  ').convert(data));
    } catch (_) {
      buf.writeln(data.toString());
    }
  }

  return buf.toString().trimRight();
}

/// Builds a `type: value` line from a top-level `exception` field, used as a
/// summary fallback. Mirrors the old flattening logic.
String _exceptionLine(Object? exception) {
  if (exception is String) return exception;
  if (exception is! Map) return '';
  final desc = exception['description']?.toString() ?? '';
  final type = exception['type']?.toString() ?? '';
  final value =
      exception['valueToString']?.toString() ??
      exception['message']?.toString() ??
      '';
  return [type, value, desc].where((s) => s.isNotEmpty).toSet().join(': ');
}

final RegExp _frameRe = RegExp(r'^#\d+\s');
final RegExp _locRe = RegExp(
  r'((?:file://|package:)\S+?\.dart):(\d+)(?::(\d+))?',
);

/// Recursively classifies a DiagnosticsNode (or list of them) into [parts],
/// walking both `properties` and `children`. [inWidget] is true once inside
/// the "error-causing widget" subtree so its source location is captured.
void _collectNode(
  Object? node,
  _ErrorParts parts,
  String? projectRoot, {
  int depth = 0,
  bool inWidget = false,
}) {
  if (depth > 12) return;
  if (node is List) {
    for (final child in node) {
      _collectNode(child, parts, projectRoot, depth: depth, inWidget: inWidget);
    }
    return;
  }
  if (node is! Map) return;

  final type = node['type']?.toString() ?? '';
  final name = node['name']?.toString() ?? '';
  final desc = (node['description']?.toString() ?? '').trim();
  final level = node['level']?.toString() ?? '';
  final isWidget =
      inWidget || name.toLowerCase().contains('error-causing widget');

  if (desc.isNotEmpty) {
    if (_frameRe.hasMatch(desc)) {
      parts.frames.add(desc);
    } else if (isWidget) {
      parts.widgetLoc ??= _extractLocation(desc, projectRoot);
      parts.widgetRaw ??= desc;
    } else if (type == 'ErrorSummary' || level == 'summary') {
      if (!parts.summary.contains(desc)) parts.summary.add(desc);
    } else if (type == 'ErrorDescription' || type == 'ErrorHint') {
      if (!parts.context.contains(desc)) parts.context.add(desc);
    }
    // Other node types (ErrorSpacer, bare DiagnosticsProperty, etc.) carry no
    // useful standalone text — skip to keep the log compact.
  }

  _collectNode(
    node['properties'],
    parts,
    projectRoot,
    depth: depth + 1,
    inWidget: isWidget,
  );
  _collectNode(
    node['children'],
    parts,
    projectRoot,
    depth: depth + 1,
    inWidget: isWidget,
  );
}

/// Pulls the first `file://…/x.dart:line:col` or `package:…` reference out of
/// [desc] and renders it as a clickable path: `package:` forms are kept
/// as-is, `file://` forms are resolved and made relative to [projectRoot]
/// (forward slashes) so the transcript link-extractor picks them up.
String? _extractLocation(String desc, String? projectRoot) {
  final m = _locRe.firstMatch(desc);
  if (m == null) return null;
  final uri = m.group(1)!;
  final line = int.tryParse(m.group(2)!) ?? 1;
  final col = m.group(3) != null ? int.tryParse(m.group(3)!) : null;
  final colSuffix = col != null ? ':$col' : '';
  if (uri.startsWith('package:')) return '$uri:$line$colSuffix';

  // Only `file://` URIs reach this point (`package:` returned above), so the
  // pure conversion suffices — no package-config resolution needed.
  final loc = SourceLocation.fromFileUri(uri, line: line, column: col ?? 1);
  if (loc == null) return null;
  var path = loc.file;
  if (projectRoot != null) {
    final rel = p.relative(loc.file, from: projectRoot);
    if (!rel.startsWith('..')) path = rel;
  }
  path = path.replaceAll(r'\', '/');
  return '$path:$line$colSuffix';
}

/// Drops pure framework frames (`package:flutter/…`, `dart:…`), collapsing
/// each consecutive run into a single `… N framework frames hidden` marker.
/// If filtering would hide everything, falls back to the top frames so the
/// stack is never empty.
List<String> _trimFrames(List<String> frames) {
  if (frames.isEmpty) return const <String>[];
  bool isNoise(String f) =>
      f.contains('package:flutter/') || f.contains('(dart:');

  final out = <String>[];
  var hidden = 0;
  void flush() {
    if (hidden > 0) {
      out.add('… $hidden framework frame${hidden == 1 ? '' : 's'} hidden');
      hidden = 0;
    }
  }

  for (final f in frames) {
    if (isNoise(f)) {
      hidden++;
    } else {
      flush();
      out.add(f);
    }
  }
  flush();

  final keptFrames = out.where((l) => l.startsWith('#')).length;
  if (keptFrames == 0) return frames.take(5).toList();
  return out;
}

/// Mutable accumulator for the classified pieces of a `Flutter.Error` payload,
/// filled by [_collectNode].
class _ErrorParts {
  final List<String> summary = <String>[];
  final List<String> context = <String>[];
  final List<String> frames = <String>[];
  String? widgetLoc;
  String? widgetRaw;
}
