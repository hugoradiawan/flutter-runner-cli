import 'dart:async';

import '../../core/result.dart';
import '../../domain/entities/diagnostic.dart';
import '../../domain/failures/analysis_failure.dart';
import '../../domain/params/diagnostics_filter_params.dart';
import '../../domain/repositories/diagnostics_repository.dart';
import '../datasources/analysis_server.dart';
import '../datasources/dart_analyze_runner.dart';
import '../datasources/diagnostics_store.dart';
import '../models/diagnostic.dart';
import '../services/live_diagnostics.dart';
import '../services/todo_diagnostics.dart';

/// Diagnostics from two sources behind one domain contract: the live analysis
/// server and the on-disk cache ([DiagnosticsStore]).
///
/// The cache lets [cachedDiagnostics] seed the counters instantly on launch.
/// Once [bindServer] wires the live server, every diagnostics burst is written
/// back through to the cache (debounced) so the next launch seeds fresh totals.
/// Constructed cache-only at the composition root, then bound once the analysis
/// server has started.
class DiagnosticsRepositoryImpl implements DiagnosticsRepository {
  DiagnosticsRepositoryImpl(
    this._cache, {
    String? projectRoot,
    DartAnalyzeRunner? analyzeRunner,
  }) : _projectRoot = projectRoot,
       _analyzeRunner = analyzeRunner;

  final DiagnosticsStore _cache;
  final String? _projectRoot;
  final DartAnalyzeRunner? _analyzeRunner;
  DartAnalysisServer? _server;
  LiveDiagnosticsCoordinator? _live;
  Timer? _saveDebounce;

  /// Attach the live analysis server (after it has started) and begin writing
  /// its diagnostics through to the cache. The subscription self-cancels its
  /// debounce when the server closes its diagnostics stream on shutdown.
  void bindServer(DartAnalysisServer server) {
    _server = server;
    server.diagnostics.listen(
      _scheduleSave,
      onDone: () => _saveDebounce?.cancel(),
    );
  }

  /// Debounce disk writes — analysis settles in bursts.
  void _scheduleSave(List<DiagnosticModel> items) {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 1), () {
      try {
        _cache.save(items);
      } catch (_) {
        /* best-effort cache */
      }
    });
  }

  /// Attach the live pipeline coordinator. Once bound, [watchDiagnostics] and
  /// [getDiagnostics] serve the merged analyzer + TODO view instead of the raw
  /// analyzer stream/snapshot.
  void bindLiveDiagnostics(LiveDiagnosticsCoordinator coordinator) {
    _live = coordinator;
  }

  @override
  List<DiagnosticEntity> cachedDiagnostics() => _cache.load();

  @override
  Stream<List<DiagnosticEntity>> watchDiagnostics(
    DiagnosticsFilterParams params,
  ) {
    final live = _live;
    if (live != null) {
      return live.merged.map((raw) => _applyFilter(raw, params));
    }
    final server = _server;
    if (server == null) return const Stream.empty();
    return server.diagnostics.map((raw) => _applyFilter(raw, params));
  }

  @override
  Future<Result<AnalysisFailure, List<DiagnosticEntity>>> getDiagnostics(
    DiagnosticsFilterParams params,
  ) async {
    final server = _server;
    if (server == null) {
      return Result.success(const <DiagnosticEntity>[]);
    }
    try {
      final live = _live;
      final snapshot = live == null
          ? server.snapshot
          : DiagnosticEntity.merge(server.snapshot, live.todos);
      return Result.success(_applyFilter(snapshot, params));
    } catch (e, st) {
      return Result.failure(
        AnalysisFailure(message: e.toString(), cause: e, stackTrace: st),
      );
    }
  }

  @override
  Future<Result<AnalysisFailure, List<DiagnosticEntity>>>
  analyzeProject() async {
    final runner = _analyzeRunner;
    final root = _projectRoot;
    if (runner == null || root == null) {
      return Result.failure(
        const AnalysisFailure(
          message: 'dart analyze is not available in this session.',
        ),
      );
    }
    final List<DiagnosticEntity> parsed;
    try {
      parsed = await runner.analyze(projectRoot: root);
    } on DartAnalyzeException catch (e) {
      return Result.failure(AnalysisFailure(message: e.message, cause: e));
    }
    return Result.success(
      DiagnosticEntity.merge(parsed, await _currentTodos()),
    );
  }

  /// Review-marker diagnostics for the analyze merge: the live index when it
  /// is seeded, otherwise a fresh isolate scan (a synchronous whole-tree walk
  /// would block the UI thread).
  Future<List<DiagnosticEntity>> _currentTodos() async {
    final live = _live;
    if (live != null && live.todoReady) return live.todos;
    return scanDartTodoDiagnosticsInIsolate(root: _projectRoot!);
  }

  List<DiagnosticEntity> _applyFilter(
    List<DiagnosticEntity> raw,
    DiagnosticsFilterParams params,
  ) {
    var result = raw;
    if (params.category != null) {
      result = result.where((d) => d.category == params.category).toList();
    }
    if (params.text != null && params.text!.isNotEmpty) {
      final q = params.text!.toLowerCase();
      result = result
          .where(
            (d) =>
                d.message.toLowerCase().contains(q) ||
                d.filePath.toLowerCase().contains(q),
          )
          .toList();
    }
    return result;
  }
}
