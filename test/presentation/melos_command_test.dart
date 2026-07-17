import 'dart:async';
import 'dart:io';

import 'package:frun/src/core/result.dart';
import 'package:frun/src/data/repositories/melos_repository_impl.dart';
import 'package:frun/src/domain/domain.dart';
import 'package:frun/src/presentation/app/app_state.dart';
import 'package:frun/src/presentation/app/commands/melos_command.dart';
import 'package:frun/src/presentation/di/dependencies.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Fake repository whose [run] stream is driven by the test; records whether
/// the subscription was cancelled (which is what kills the melos process).
class _FakeMelosRepository implements MelosRepository {
  final controller = StreamController<MelosRunEvent>();
  bool cancelled = false;

  static const command = MelosCommandEntity(
    name: 'bootstrap',
    description: 'Install dependencies',
    kind: MelosCommandKind.builtin,
    melosArgs: ['bootstrap'],
  );

  @override
  Future<Result<MelosFailure, List<MelosCommandEntity>>>
  discoverCommands() async => Result.success(const [command]);

  @override
  Stream<MelosRunEvent> run(MelosCommandEntity command) {
    controller.onCancel = () => cancelled = true;
    return controller.stream;
  }
}

void main() {
  late Directory temp;
  late AppState state;

  AppState buildState(String root) {
    final project = FlutterProjectEntity(
      root: root,
      name: 'workspace',
      workspaceRoot: root,
      watchRoot: root,
      hasVsCodeFolder: false,
      hasZedFolder: false,
    );
    return AppState(
      project: project,
      config: AppConfigEntity.defaults(),
      deps: Dependencies()..melosRepository = MelosRepositoryImpl(project),
    );
  }

  setUp(() => temp = Directory.systemTemp.createTempSync('frun_melos_cmd_'));
  tearDown(() => temp.deleteSync(recursive: true));

  void writePubspec(String content) =>
      File(p.join(temp.path, 'pubspec.yaml')).writeAsStringSync(content);

  test('no-arg opens the picker in a melos workspace', () async {
    writePubspec('''
name: workspace
melos:
  scripts:
    analyze: dart analyze
''');
    state = buildState(temp.path);

    await MelosCommand().run(const [], state);

    expect(state.melosChoices, isNotEmpty);
    expect(state.hasActivePicker, isTrue);
    expect(
      state.melosChoices.map((c) => c.name),
      containsAll(['bootstrap', 'clean', 'analyze']),
    );
  });

  test('warns and opens no picker in a non-melos project', () async {
    writePubspec('name: solo\n');
    state = buildState(temp.path);

    await MelosCommand().run(const [], state);

    expect(state.melosChoices, isEmpty);
    expect(
      state.transcript.lines.map((l) => l.text).join('\n'),
      contains('No melos config found'),
    );
  });

  test('unknown token reports an error', () async {
    writePubspec('''
name: workspace
melos:
  scripts:
    analyze: dart analyze
''');
    state = buildState(temp.path);

    await MelosCommand().run(const ['nope'], state);

    expect(state.melosChoices, isEmpty);
    expect(
      state.transcript.lines.map((l) => l.text).join('\n'),
      contains('No melos command matches'),
    );
  });

  group('run subscription lifecycle', () {
    late _FakeMelosRepository repo;

    AppState buildFakeState() {
      repo = _FakeMelosRepository();
      return AppState(
        project: FlutterProjectEntity(
          root: temp.path,
          name: 'workspace',
          workspaceRoot: temp.path,
          watchRoot: temp.path,
          hasVsCodeFolder: false,
          hasZedFolder: false,
        ),
        config: AppConfigEntity.defaults(),
        deps: Dependencies()..melosRepository = repo,
      );
    }

    test('running a command registers a cancellable subscription', () async {
      state = buildFakeState();

      await MelosCommand().run(const ['bootstrap'], state);
      await pumpEventQueue();

      expect(state.melosRunSubs, hasLength(1));
      expect(repo.cancelled, isFalse);
    });

    test('MelosRunExit deregisters the subscription', () async {
      state = buildFakeState();

      await MelosCommand().run(const ['bootstrap'], state);
      repo.controller.add(const MelosRunExit(0));
      await pumpEventQueue();

      expect(state.melosRunSubs, isEmpty);
    });

    test('cancelMelosRuns cancels the stream (killing the process)', () async {
      state = buildFakeState();

      await MelosCommand().run(const ['bootstrap'], state);
      await pumpEventQueue();
      await state.cancelMelosRuns();

      expect(repo.cancelled, isTrue);
      expect(state.melosRunSubs, isEmpty);
    });

    test('melos cancel command cancels in-flight runs', () async {
      state = buildFakeState();

      await MelosCommand().run(const ['bootstrap'], state);
      await pumpEventQueue();
      await MelosCommand().run(const ['cancel'], state);

      expect(repo.cancelled, isTrue);
      expect(state.melosRunSubs, isEmpty);
      expect(
        state.transcript.lines.map((l) => l.text).join('\n'),
        contains('Cancelled 1 melos command'),
      );
    });
  });
}
