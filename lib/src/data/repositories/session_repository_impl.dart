import 'dart:async' show unawaited;

import '../../ca/result.dart';
import '../datasources/app_session.dart';
import '../../domain/entities/run_session.entity.dart';
import '../../domain/failures/session_failure.dart';
import '../../domain/params/reload.params.dart';
import '../../domain/params/run.params.dart';
import '../../domain/repositories/session_repository.dart';
import '../../project/launch_config.dart';

class SessionRepositoryImpl implements ISessionRepository {
  SessionRepositoryImpl({
    required this.projectRoot,
    this.flutterExecutable,
    Map<String, String>? environment,
    AppRunSession? Function(int tabId)? sessionLookup,
  }) : _environment = environment,
       _externalLookup = sessionLookup;

  final String projectRoot;
  final String? flutterExecutable;
  final Map<String, String>? _environment;
  final AppRunSession? Function(int tabId)? _externalLookup;

  final Map<int, AppRunSession> _sessions = <int, AppRunSession>{};
  int _nextId = 1;

  AppRunSession? _sessionFor(int tabId) =>
      _sessions[tabId] ?? _externalLookup?.call(tabId);

  @override
  Future<Result<SessionFailure, RunSessionEntity>> launch(RunParams params) async {
    try {
      final entry = LaunchEntry(
        name: params.entry.name,
        program: params.entry.program,
        cwd: params.entry.cwd,
        deviceId: params.entry.deviceId,
        flutterMode: params.entry.flutterMode,
        flavor: params.entry.flavor,
        args: params.entry.args,
        toolArgs: params.entry.toolArgs,
      );
      final session = await AppRunSession.start(
        projectRoot: projectRoot,
        entry: entry,
        deviceId: params.device.id,
        flutterExecutable: flutterExecutable,
        environment: _environment,
      );
      final tabId = _nextId++;
      _sessions[tabId] = session;
      unawaited(session.exitCode.whenComplete(() => _sessions.remove(tabId)));
      return Result.success(
        RunSessionEntity(
          tabId: tabId,
          entry: params.entry,
          deviceId: params.device.id,
          isRunning: true,
          devToolsUrl: session.devToolsUri,
        ),
      );
    } catch (e, st) {
      return Result.failure(
        SessionFailure(message: e.toString(), cause: e, stackTrace: st),
      );
    }
  }

  @override
  Future<Result<SessionFailure, void>> hotReload(ReloadParams params) async {
    final session = _sessionFor(params.tabId);
    if (session == null) {
      return Result.failure(
        SessionFailure(message: 'No session for tab ${params.tabId}'),
      );
    }
    try {
      await session.hotReload();
      return Result.success(null);
    } catch (e, st) {
      return Result.failure(
        SessionFailure(message: e.toString(), cause: e, stackTrace: st),
      );
    }
  }

  @override
  Future<Result<SessionFailure, void>> hotRestart(ReloadParams params) async {
    final session = _sessionFor(params.tabId);
    if (session == null) {
      return Result.failure(
        SessionFailure(message: 'No session for tab ${params.tabId}'),
      );
    }
    try {
      await session.hotRestart();
      return Result.success(null);
    } catch (e, st) {
      return Result.failure(
        SessionFailure(message: e.toString(), cause: e, stackTrace: st),
      );
    }
  }

  @override
  Future<Result<SessionFailure, void>> stop(ReloadParams params) async {
    final session = _sessionFor(params.tabId);
    if (session == null) {
      return Result.failure(
        SessionFailure(message: 'No session for tab ${params.tabId}'),
      );
    }
    try {
      await session.stop();
      _sessions.remove(params.tabId);
      return Result.success(null);
    } catch (e, st) {
      return Result.failure(
        SessionFailure(message: e.toString(), cause: e, stackTrace: st),
      );
    }
  }

  @override
  Stream<String> watchLogs(int tabId) {
    final session = _sessionFor(tabId);
    if (session == null) return const Stream.empty();
    return session.events
        .where((e) => e.name == 'app.log')
        .map((e) => e.params['log'] as String? ?? '');
  }
}

