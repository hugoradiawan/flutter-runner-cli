import 'dart:io';

import '../../../domain/domain.dart';
import '../app_state.dart';
import '../transcript.dart';
import 'command.dart';

/// Breaks down where frun's own memory goes: process RSS vs Dart heap, the
/// classes holding the bytes, and transcript/scrollback buffer estimates.
/// Heap detail needs frun's own VM service (see the hint printed when it is
/// missing); RSS and buffer estimates always work.
///
/// `mem gc` forces a full GC and shows before/after; `mem diff` compares
/// against the previous `mem diff` call to expose growth.
class MemCommand extends Command {
  MemCommand(
    this.inspector, {
    int Function()? currentRss,
    int Function()? peakRss,
    String Function()? scriptUri,
  }) : _currentRss = currentRss ?? (() => ProcessInfo.currentRss),
       _peakRss = peakRss ?? (() => ProcessInfo.maxRss),
       _scriptUri = scriptUri ?? (() => Platform.script.toString());

  final SelfMemoryInspector inspector;
  final int Function() _currentRss;
  final int Function() _peakRss;
  final String Function() _scriptUri;

  /// Rolling baseline for `mem diff`. Lives on the command instance — the
  /// registry keeps one instance for the app lifetime.
  _MemSnapshot? _snapshot;

  @override
  String get name => 'mem';

  @override
  String get summary => 'Show frun memory breakdown (heap, classes, buffers)';

  @override
  String get usage => '/mem [gc|diff]';

  @override
  Future<CommandResult> run(List<String> args, AppState state) async {
    try {
      if (args.isEmpty) return await _overview(state);
      switch (args.first) {
        case 'gc':
          return await _gc(state);
        case 'diff':
          return await _diff(state);
        default:
          state.transcript.warn('Usage: $usage');
          return CommandResult.ok;
      }
    } finally {
      // Don't keep the self VM-service websocket (plus its stream buffers)
      // alive between rare /mem invocations — reconnecting is cheap.
      await inspector.dispose();
    }
  }

  Future<CommandResult> _overview(AppState state) async {
    // Read RSS before the allocation profile: the profile itself allocates.
    final rss = _currentRss();
    final peak = _peakRss();
    final report = await inspector.report();

    final out = StringBuffer('mem: process rss ${_mb(rss)} · peak ${_mb(peak)}')
      ..write(_runModeLine());
    if (report != null) {
      final heap = report.heap;
      final nonHeap = rss - heap.heapCapacity - heap.externalUsage;
      out
        ..write('\n  dart heap   used ${_mb(heap.heapUsed)}')
        ..write(' / capacity ${_mb(heap.heapCapacity)}')
        ..write(' · external ${_mb(heap.externalUsage)}')
        ..write(
          '\n              (used includes uncollected garbage —'
          ' /mem gc shows live-only)',
        );
      if (nonHeap > 0) {
        out.write(
          '\n  non-heap    ~${_mb(nonHeap)}'
          ' (VM runtime, code, stacks; rss − capacity − external)',
        );
      }
      if (report.classes.isNotEmpty) {
        out.write('\n  top classes by current bytes:');
        for (final stat in report.classes.take(_topClasses)) {
          out.write(
            '\n    ${stat.className.padRight(28)}'
            ' ${_mb(stat.bytes, digits: 2).padLeft(9)}'
            '   ${_thousands(stat.instances)} instances',
          );
        }
      }
    }
    out.write(_bufferSection(state));
    if (report != null) {
      final tree = await inspector.processMemoryTree();
      if (tree != null) {
        out.write('\n  vm breakdown:');
        _renderTree(out, tree.children, indent: 4, depthLeft: 2);
      }
    }
    state.transcript.system(out.toString());
    if (report == null) _hint(state);
    return CommandResult.ok;
  }

  Future<CommandResult> _gc(AppState state) async {
    final beforeRss = _currentRss();
    final before = await inspector.report();
    if (before == null) {
      _hint(state);
      return CommandResult.ok;
    }
    final after = await inspector.report(forceGc: true);
    final afterRss = _currentRss();
    if (after == null) {
      state.transcript.error(
        'mem: GC failed${inspector.lastError == null ? '' : ' — ${inspector.lastError}'}',
      );
      return CommandResult.ok;
    }
    final out = StringBuffer('mem: full GC forced')
      ..write(
        '\n  ${''.padRight(11)} ${'before'.padLeft(9)} ${'after'.padLeft(11)} ${'Δ'.padLeft(11)}',
      )
      ..write(_gcRow('rss', beforeRss, afterRss))
      ..write(_gcRow('heap used', before.heap.heapUsed, after.heap.heapUsed))
      ..write(
        _gcRow('external', before.heap.externalUsage, after.heap.externalUsage),
      );
    state.transcript.system(out.toString());
    return CommandResult.ok;
  }

  String _gcRow(String label, int before, int after) =>
      '\n  ${label.padRight(11)} ${_mb(before).padLeft(9)}'
      ' ${_mb(after).padLeft(11)} ${_signedMb(after - before).padLeft(11)}';

  Future<CommandResult> _diff(AppState state) async {
    final rss = _currentRss();
    final report = await inspector.report();
    final next = _MemSnapshot(
      takenAt: DateTime.now(),
      rss: rss,
      heap: report?.heap,
      classBytes: {
        for (final stat in report?.classes ?? const <HeapClassStatEntity>[])
          stat.key: stat.bytes,
      },
    );
    final prev = _snapshot;
    _snapshot = next;
    if (prev == null) {
      state.transcript.system(
        'mem: snapshot stored (rss ${_mb(rss)})'
        ' — run /mem diff again to see growth.',
      );
      return CommandResult.ok;
    }

    final out = StringBuffer(
      'mem: growth since snapshot (${_elapsed(next.takenAt.difference(prev.takenAt))} ago)',
    )..write(_diffRow('rss', prev.rss, next.rss));
    final prevHeap = prev.heap;
    final nextHeap = next.heap;
    if (prevHeap != null && nextHeap != null) {
      out
        ..write(_diffRow('heap used', prevHeap.heapUsed, nextHeap.heapUsed))
        ..write(
          _diffRow('external', prevHeap.externalUsage, nextHeap.externalUsage),
        );
    }

    final deltas = <String, int>{};
    for (final key in {...prev.classBytes.keys, ...next.classBytes.keys}) {
      final delta = (next.classBytes[key] ?? 0) - (prev.classBytes[key] ?? 0);
      if (delta.abs() >= 1024) deltas[key] = delta;
    }
    if (deltas.isNotEmpty) {
      final ranked = deltas.entries.toList()
        ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
      out.write('\n  top class deltas:');
      for (final entry in ranked.take(_topClasses)) {
        final className = entry.key.split('|').last;
        out.write(
          '\n    ${className.padRight(28)} ${_signedMb(entry.value).padLeft(9)}',
        );
      }
    }
    state.transcript.system(out.toString());
    return CommandResult.ok;
  }

  String _diffRow(String label, int before, int after) =>
      '\n  ${label.padRight(10)} ${_mb(before).padLeft(8)} → ${_mb(after).padLeft(8)}'
      '   ${_signedMb(after - before)}';

  /// UTF-16 size estimate of every retained transcript line, plus a rough
  /// per-line object overhead. An estimate by design — labeled as such.
  String _bufferSection(AppState state) {
    final out = StringBuffer('\n  internal buffers (estimate, UTF-16):')
      ..write(_bufferRow('system transcript', state.transcript));
    for (final tab in state.runController.tabs) {
      out.write(_bufferRow(tab.label, tab.transcript));
    }
    return out.toString();
  }

  String _bufferRow(String label, Transcript transcript) {
    final bytes = transcript.lines.fold<int>(
      0,
      (sum, line) => sum + line.text.length * 2 + 48,
    );
    return '\n    ${label.padRight(24)}'
        ' ${'${transcript.lines.length}'.padLeft(6)} lines'
        '   ~${_mb(bytes, digits: 2)}';
  }

  /// Names the VM mode the process runs under, because it dominates the
  /// numbers: a JIT run (`dart run` / kernel snapshot) carries the kernel,
  /// front-end, and JIT-compiled code in-process — RSS and heap read far
  /// higher than the installed AOT exe running the same session.
  String _runModeLine() {
    final script = _scriptUri();
    final mode = script.endsWith('.dart')
        ? 'JIT (dart run) — VM/code overhead inflated vs installed frun exe'
        : script.endsWith('.snapshot')
        ? 'JIT (kernel snapshot) — VM/code overhead inflated vs installed frun exe'
        : 'AOT (compiled exe)';
    return '\n  mode        $mode';
  }

  void _hint(AppState state) {
    final error = inspector.lastError;
    state.transcript.warn(
      '  heap detail unavailable — it needs the VM service, which the compiled'
      ' exe cannot enable\n'
      '  (DART_VM_OPTIONS rejects --enable-vm-service on AOT builds).'
      ' Run from source instead:\n'
      '    dart run --enable-vm-service=0 bin/frun.dart\n'
      '    (JIT runs carry ~200 MB of VM/kernel overhead the exe does not —'
      ' compare like with like)'
      '${error == null ? '' : '\n    last error: $error'}',
    );
  }

  void _renderTree(
    StringBuffer out,
    List<ProcessMemoryNodeEntity> nodes, {
    required int indent,
    required int depthLeft,
  }) {
    if (depthLeft == 0) return;
    final sorted = [...nodes]
      ..sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    for (final node in sorted) {
      out.write(
        '\n${''.padRight(indent)}${node.name.padRight(28 - (indent - 4))}'
        ' ${_mb(node.sizeBytes).padLeft(9)}',
      );
      _renderTree(
        out,
        node.children,
        indent: indent + 2,
        depthLeft: depthLeft - 1,
      );
    }
  }

  static const _topClasses = 10;

  static String _mb(int bytes, {int digits = 1}) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(digits)} MB';

  static String _signedMb(int bytes) =>
      '${bytes < 0 ? '-' : '+'}${_mb(bytes.abs())}';

  static String _thousands(int n) => n.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );

  static String _elapsed(Duration d) {
    if (d.inMinutes >= 1) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    return '${d.inSeconds}s';
  }
}

/// Point-in-time baseline captured by `mem diff`.
class _MemSnapshot {
  _MemSnapshot({
    required this.takenAt,
    required this.rss,
    required this.heap,
    required this.classBytes,
  });

  final DateTime takenAt;
  final int rss;
  final SelfHeapUsageEntity? heap;

  /// [HeapClassStatEntity.key] → retained bytes at snapshot time.
  final Map<String, int> classBytes;
}
