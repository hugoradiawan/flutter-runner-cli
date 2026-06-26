import 'dart:async';

import '../../core/result.dart';
import '../../domain/entities/diagnostic.dart';
import '../../domain/failures/analysis_failure.dart';
import '../../domain/params/diagnostics_filter_params.dart';
import '../../domain/repositories/diagnostics_repository.dart';
import '../datasources/analysis_server.dart';
import '../datasources/diagnostics_store.dart';
import '../models/diagnostic.dart';

/// Diagnostics from two sources behind one domain contract: the live analysis
/// server and the on-disk cache ([DiagnosticsStore]).
///
/// The cache lets [cachedDiagnostics] seed the counters instantly on launch.
/// Once [bindServer] wires the live server, every diagnostics burst is written
/// back through to the cache (debounced) so the next launch seeds fresh totals.
/// Constructed cache-only at the composition root, then bound once the analysis
/// server has started.
class DiagnosticsRepositoryImpl implements DiagnosticsRepository {
  DiagnosticsRepositoryImpl(this._cache);

  final DiagnosticsStore _cache;
  DartAnalysisServer? _server;
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

  @override
  List<DiagnosticEntity> cachedDiagnostics() => _cache.load();

  @override
  Stream<List<DiagnosticEntity>> watchDiagnostics(
    DiagnosticsFilterParams params,
  ) {
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
      return Result.success(_applyFilter(server.snapshot, params));
    } catch (e, st) {
      return Result.failure(
        AnalysisFailure(message: e.toString(), cause: e, stackTrace: st),
      );
    }
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
