import 'dart:io';

import 'package:frun/src/data/datasources/config_datasource.dart';
import 'package:frun/src/data/datasources/config_store.dart';
import 'package:frun/src/data/repositories/config_repository_impl.dart';
import 'package:frun/src/data/services/isolate_manager.dart';
import 'package:frun/src/domain/entities/app_config.dart';
import 'package:frun/src/domain/entities/flutter_project.dart';
import 'package:frun/src/domain/value_objects/config_values.dart';
import 'package:frun/src/presentation/app/app_state.dart';
import 'package:frun/src/presentation/app/commands/clear_command.dart';
import 'package:frun/src/presentation/app/commands/command_registry.dart';
import 'package:frun/src/presentation/app/commands/config_command.dart';
import 'package:frun/src/presentation/app/commands/copy_command.dart';
import 'package:frun/src/presentation/app/commands/help_command.dart';
import 'package:frun/src/presentation/app/commands/isolates_command.dart';
import 'package:frun/src/presentation/app/commands/quit_command.dart';
import 'package:frun/src/presentation/app/transcript.dart';
import 'package:frun/src/presentation/di/dependencies.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temp;
  late ConfigStore store;
  late AppState state;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('frun_cmd_');
    store = ConfigStore(overridePath: p.join(temp.path, 'cfg.yaml'));
    state = AppState(
      project: FlutterProjectEntity(
        root: temp.path,
        name: 'demo',
        workspaceRoot: temp.path,
        watchRoot: temp.path,
        hasVsCodeFolder: false,
        hasZedFolder: false,
      ),
      config: AppConfigEntity.defaults(),
      deps: Dependencies(),
    );
    state.deps.configRepository = ConfigRepositoryImpl(ConfigDataSource(store));
  });

  tearDown(() => temp.deleteSync(recursive: true));

  test('CommandRegistry suggestion matches by prefix', () {
    final reg = CommandRegistry()
      ..register(QuitCommand())
      ..register(ClearCommand())
      ..register(ConfigCommand());
    reg.register(HelpCommand(reg));
    expect(
      reg.suggestions('c').map((c) => c.name),
      containsAll(['clear', 'config']),
    );
    expect(reg.lookup('q'), isA<QuitCommand>());
    expect(reg.lookup('h'), isA<HelpCommand>());
  });

  test('/quit sets shouldQuit', () async {
    final res = await QuitCommand().run(const [], state);
    expect(res.shouldQuit, isTrue);
  });

  test('/clear empties the transcript', () async {
    state.transcript.info('a');
    state.transcript.info('b');
    await ClearCommand().run(const [], state);
    expect(state.transcript.lines, isEmpty);
  });

  test('/copy grabs the whole transcript', () async {
    state.transcript.info('line one');
    state.transcript.info('line two');
    String? captured;
    final res = await CopyCommand((text) async {
      captured = text;
      return true;
    }).run(const [], state);
    expect(res.shouldQuit, isFalse);
    expect(captured, 'line one\nline two');
    final sys = state.transcript.lines
        .where((l) => l.level == TranscriptLevel.system)
        .toList();
    expect(sys.last.text, contains('Copied 2 lines'));
  });

  test('/copy on empty transcript warns', () async {
    var called = false;
    await CopyCommand((text) async {
      called = true;
      return true;
    }).run(const [], state);
    expect(called, isFalse);
    final warns = state.transcript.lines
        .where((l) => l.level == TranscriptLevel.warn)
        .toList();
    expect(warns, isNotEmpty);
  });

  test('/config set persists changes', () async {
    await ConfigCommand().run(['set', 'ide', 'zed'], state);
    expect(state.config.ide, FrunIde.zed);
    expect(store.load().ide, FrunIde.zed);
  });

  test('/config set diagnostics_on_boot persists changes', () async {
    await ConfigCommand().run(['set', 'diagnostics_on_boot', 'on'], state);
    expect(state.config.diagnosticsOnBoot, isTrue);
    expect(store.load().diagnosticsOnBoot, isTrue);
  });

  test('/config set with unknown key warns', () async {
    await ConfigCommand().run(['set', 'nope', 'val'], state);
    final warns = state.transcript.lines
        .where((l) => l.level == TranscriptLevel.warn)
        .toList();
    expect(warns, isNotEmpty);
  });

  test('/isolates opens lifecycle panel', () async {
    state.showDiagnosticsPanel = true;
    final command = IsolatesCommand(
      state.deps.isolateManager,
      state.deps.ideLauncher,
    );

    await command.run(const [], state);

    expect(state.showIsolatesPanel, isTrue);
    expect(state.showDiagnosticsPanel, isFalse);
  });

  test('/isolates list still prints isolate rows', () async {
    final manager = IsolateManager(
      isolates: <IsolateInfo>[
        IsolateInfo(
          id: 'isolates/1234567890',
          name: 'main',
          status: IsolateStatus.running,
        ),
      ],
    );
    final localState = AppState(
      project: state.project,
      config: AppConfigEntity.defaults(),
      deps: Dependencies(isolateManager: manager),
    );
    final command = IsolatesCommand(
      localState.deps.isolateManager,
      localState.deps.ideLauncher,
    );

    await command.run(const ['list'], localState);

    final text = localState.transcript.lines.map((l) => l.text).join('\n');
    expect(text, contains('Isolates:'));
    expect(text, contains('main'));
    expect(text, contains('running'));
  });
}
