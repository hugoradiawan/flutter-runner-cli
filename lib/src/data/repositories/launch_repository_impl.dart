import 'dart:io';

import '../../core/result.dart';
import '../../domain/entities/flutter_project.dart';
import '../../domain/entities/launch_entry.dart';
import '../../domain/failures/launch_failure.dart';
import '../../domain/repositories/launch_repository.dart';
import '../models/launch_config.dart';
import '../services/main_scanner.dart';

class LaunchRepositoryImpl implements LaunchRepository {
  LaunchRepositoryImpl(this._project);

  final FlutterProjectEntity _project;

  @override
  Future<Result<LaunchFailure, List<LaunchEntryEntity>>>
  discoverLaunchEntries() async {
    try {
      final launchJson = LaunchConfigParser.parseFile(
        File(_project.launchJsonPath),
        workspaceFolder: _project.workspaceRoot,
      );
      final scanned = MainScanner.scan(_project.libDir);
      return Result.success(MainScanner.merge(launchJson, scanned));
    } catch (e, st) {
      return Result.failure(
        LaunchFailure(message: e.toString(), cause: e, stackTrace: st),
      );
    }
  }
}
