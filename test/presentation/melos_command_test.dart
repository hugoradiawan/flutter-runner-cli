import 'dart:io';

import 'package:frun/src/data/repositories/melos_repository_impl.dart';
import 'package:frun/src/domain/entities/app_config.dart';
import 'package:frun/src/domain/entities/flutter_project.dart';
import 'package:frun/src/presentation/app/app_state.dart';
import 'package:frun/src/presentation/app/commands/melos_command.dart';
import 'package:frun/src/presentation/di/dependencies.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

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
    expect(state.melosChoices.map((c) => c.name), containsAll(['bootstrap', 'clean', 'analyze']));
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
}
