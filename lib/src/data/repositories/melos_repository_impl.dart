import '../../core/result.dart';
import '../../domain/entities/flutter_project.dart';
import '../../domain/entities/melos_command.dart';
import '../../domain/entities/melos_run_event.dart';
import '../../domain/failures/melos_failure.dart';
import '../../domain/repositories/melos_repository.dart';
import '../datasources/melos_runner.dart';
import '../services/melos_config_reader.dart';

class MelosRepositoryImpl implements MelosRepository {
  MelosRepositoryImpl(
    this._project, {
    MelosConfigReader configReader = const MelosConfigReader(),
    MelosRunner runner = const MelosRunner(),
  }) : _configReader = configReader,
       _runner = runner;

  final FlutterProjectEntity _project;
  final MelosConfigReader _configReader;
  final MelosRunner _runner;

  static const _builtins = <MelosCommandEntity>[
    MelosCommandEntity(
      name: 'bootstrap',
      description: 'Install & link all package dependencies',
      kind: MelosCommandKind.builtin,
      melosArgs: <String>['bootstrap'],
    ),
    MelosCommandEntity(
      name: 'clean',
      description: 'Clean workspace & remove IDE/build artifacts',
      kind: MelosCommandKind.builtin,
      melosArgs: <String>['clean'],
    ),
  ];

  @override
  Future<Result<MelosFailure, List<MelosCommandEntity>>>
  discoverCommands() async {
    try {
      final workspace = _configReader.read(_project.root);
      if (workspace == null) {
        return Result.success(const <MelosCommandEntity>[]);
      }
      return Result.success(<MelosCommandEntity>[
        ..._builtins,
        ...workspace.scripts,
      ]);
    } catch (e, st) {
      return Result.failure(
        MelosFailure(message: e.toString(), cause: e, stackTrace: st),
      );
    }
  }

  @override
  Stream<MelosRunEvent> run(MelosCommandEntity command) {
    final workspace = _configReader.read(_project.root);
    final root = workspace?.root ?? _project.workspaceRoot;
    return _runner.run(root, command.melosArgs);
  }
}
