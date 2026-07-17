import 'dart:io';

import 'package:frun/src/data/datasources/melos_runner.dart';
import 'package:frun/src/domain/entities/melos_run_event.dart';
import 'package:test/test.dart';

import 'fake_process.dart';

void main() {
  late FakeProcess process;
  late MelosRunner runner;
  late List<String> startedArgs;

  setUp(() {
    process = FakeProcess();
    startedArgs = [];
    runner = MelosRunner(
      starter:
          (
            String executable,
            List<String> args, {
            String? workingDirectory,
            bool runInShell = false,
          }) async {
            startedArgs = args;
            return process;
          },
    );
  });

  test('maps stdout/stderr lines with the right isError flag', () async {
    final events = <MelosRunEvent>[];
    final done = runner.run('/repo', ['bootstrap']).forEach(events.add);

    await pumpEventQueue();
    process.emitStdout('resolving...');
    process.emitStderr('warning: thing');
    await process.exit(0);
    await done;

    expect(startedArgs, ['bootstrap']);
    expect(events, hasLength(3));
    expect((events[0] as MelosRunLine).text, 'resolving...');
    expect((events[0] as MelosRunLine).isError, isFalse);
    expect((events[1] as MelosRunLine).isError, isTrue);
    expect((events[2] as MelosRunExit).code, 0);
  });

  test('exit event carries the failure code after pipes drain', () async {
    final events = <MelosRunEvent>[];
    final done = runner.run('/repo', ['run', 'lint']).forEach(events.add);

    await pumpEventQueue();
    process.emitStderr('lint failed');
    await process.exit(2);
    await done;

    final exit = events.last as MelosRunExit;
    expect(exit.code, 2);
    expect(exit.ok, isFalse);
  });

  test('a start failure emits an error line then MelosRunExit(null)', () async {
    final failing = MelosRunner(
      starter:
          (
            String executable,
            List<String> args, {
            String? workingDirectory,
            bool runInShell = false,
          }) async => throw ProcessException('melos', args, 'not found'),
    );

    final events = await failing.run('/repo', ['bootstrap']).toList();

    expect(events, hasLength(2));
    final line = events.first as MelosRunLine;
    expect(line.isError, isTrue);
    expect(line.text, contains('Failed to start melos'));
    expect((events.last as MelosRunExit).code, isNull);
  });

  test('cancelling the subscription kills the process', () async {
    final sub = runner.run('/repo', ['bootstrap']).listen((_) {});
    await pumpEventQueue();

    await sub.cancel();

    expect(process.killed, isTrue);
  });
}
