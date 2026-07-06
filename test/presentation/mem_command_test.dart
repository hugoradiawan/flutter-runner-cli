import 'dart:io';

import 'package:frun/src/domain/entities/app_config.dart';
import 'package:frun/src/domain/entities/flutter_project.dart';
import 'package:frun/src/domain/entities/self_memory.dart';
import 'package:frun/src/domain/ports/self_memory_inspector.dart';
import 'package:frun/src/presentation/app/app_state.dart';
import 'package:frun/src/presentation/app/commands/mem_command.dart';
import 'package:frun/src/presentation/app/transcript.dart';
import 'package:frun/src/presentation/di/dependencies.dart';
import 'package:test/test.dart';

class FakeSelfMemoryInspector implements SelfMemoryInspector {
  bool available = true;
  SelfMemoryReportEntity? nextReport;
  ProcessMemoryNodeEntity? tree;
  final List<bool> recordedForceGc = <bool>[];

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<SelfMemoryReportEntity?> report({bool forceGc = false}) async {
    if (!available) return null;
    recordedForceGc.add(forceGc);
    return nextReport;
  }

  @override
  Future<ProcessMemoryNodeEntity?> processMemoryTree() async => tree;

  @override
  String? get lastError => null;

  @override
  Future<void> dispose() async {}
}

SelfMemoryReportEntity report({
  int heapUsed = 12 << 20,
  int external = 1 << 20,
  Map<String, int> classBytes = const {'TranscriptLine': 1 << 20},
}) => SelfMemoryReportEntity(
  heap: SelfHeapUsageEntity(
    heapUsed: heapUsed,
    heapCapacity: 24 << 20,
    externalUsage: external,
  ),
  classes: [
    for (final entry in classBytes.entries)
      HeapClassStatEntity(
        className: entry.key,
        libraryUri: 'package:frun/x.dart',
        bytes: entry.value,
        instances: 1200,
      ),
  ],
  gcPerformed: false,
);

void main() {
  late Directory temp;
  late FakeSelfMemoryInspector fake;
  late AppState state;
  late MemCommand command;
  var rssValue = 84 << 20;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('frun_mem_');
    fake = FakeSelfMemoryInspector()..nextReport = report();
    rssValue = 84 << 20;
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
      deps: Dependencies(selfMemoryInspector: fake),
    );
    command = MemCommand(
      fake,
      currentRss: () => rssValue,
      peakRss: () => 91 << 20,
    );
  });

  tearDown(() => temp.deleteSync(recursive: true));

  String allText() => state.transcript.lines.map((l) => l.text).join('\n');

  test('/mem prints heap, top classes, and buffer estimates', () async {
    state.transcript.info('hello');
    await command.run(const [], state);
    final text = allText();
    expect(text, contains('process rss 84.0 MB'));
    expect(text, contains('dart heap   used 12.0 MB'));
    expect(text, contains('TranscriptLine'));
    expect(text, contains('instances'));
    expect(text, contains('internal buffers'));
    expect(text, contains('system transcript'));
  });

  test('/mem without a self VM service still shows rss and hints', () async {
    fake.available = false;
    await command.run(const [], state);
    final text = allText();
    expect(text, contains('process rss 84.0 MB'));
    expect(text, contains('--enable-vm-service'));
    expect(text, isNot(contains('dart heap')));
    expect(
      state.transcript.lines.any((l) => l.level == TranscriptLevel.warn),
      isTrue,
    );
  });

  test('/mem renders the vm breakdown tree when available', () async {
    fake.tree = const ProcessMemoryNodeEntity(
      name: 'process',
      sizeBytes: 80 << 20,
      children: [
        ProcessMemoryNodeEntity(
          name: 'vm',
          sizeBytes: 30 << 20,
          children: [
            ProcessMemoryNodeEntity(
              name: 'dart heap',
              sizeBytes: 24 << 20,
              children: [],
            ),
          ],
        ),
      ],
    );
    await command.run(const [], state);
    final text = allText();
    expect(text, contains('vm breakdown:'));
    expect(text, contains('dart heap'));
  });

  test('/mem gc measures before and after a forced GC', () async {
    final rotating = _RotatingInspector([
      report(heapUsed: 12 << 20),
      report(heapUsed: 6 << 20),
    ]);
    final gcCommand = MemCommand(
      rotating,
      currentRss: () => rssValue,
      peakRss: () => 91 << 20,
    );
    await gcCommand.run(const ['gc'], state);
    expect(rotating.recordedForceGc, [false, true]);
    final text = allText();
    expect(text, contains('full GC forced'));
    expect(text, contains('before'));
    expect(text, contains('-6.0 MB'));
  });

  test('/mem gc without a service prints the enable hint', () async {
    fake.available = false;
    await command.run(const ['gc'], state);
    expect(allText(), contains('--enable-vm-service'));
  });

  test('/mem diff stores a snapshot then reports growth', () async {
    fake.nextReport = report(classBytes: {'TranscriptLine': 1 << 20});
    await command.run(const ['diff'], state);
    expect(allText(), contains('snapshot stored'));

    rssValue = 96 << 20;
    fake.nextReport = report(
      heapUsed: 18 << 20,
      classBytes: {'TranscriptLine': 3 << 20},
    );
    await command.run(const ['diff'], state);
    final text = allText();
    expect(text, contains('growth since snapshot'));
    expect(text, contains('+12.0 MB')); // rss delta
    expect(text, contains('+6.0 MB')); // heap delta
    expect(text, contains('TranscriptLine'));
    expect(text, contains('+2.0 MB')); // class delta
  });

  test('/mem diff works rss-only when heap detail is unavailable', () async {
    fake.available = false;
    await command.run(const ['diff'], state);
    rssValue = 90 << 20;
    await command.run(const ['diff'], state);
    final text = allText();
    expect(text, contains('growth since snapshot'));
    expect(text, contains('+6.0 MB'));
    expect(text, isNot(contains('heap used')));
  });

  test('/mem with an unknown subcommand prints usage', () async {
    await command.run(const ['bogus'], state);
    final warns = state.transcript.lines
        .where((l) => l.level == TranscriptLevel.warn)
        .map((l) => l.text);
    expect(warns.join(), contains('Usage: /mem [gc|diff]'));
  });

  test('buffer estimate reflects transcript contents', () async {
    for (var i = 0; i < 5; i++) {
      state.transcript.info('line $i');
    }
    await command.run(const [], state);
    // 5 seeded lines are retained when the command output is appended.
    expect(allText(), contains(RegExp(r'system transcript\s+5 lines')));
  });
}

/// Returns reports in sequence so gc can observe shrinkage between the
/// before (forceGc:false) and after (forceGc:true) measurements.
class _RotatingInspector implements SelfMemoryInspector {
  _RotatingInspector(this._reports);

  final List<SelfMemoryReportEntity> _reports;
  var _next = 0;
  final List<bool> recordedForceGc = <bool>[];

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<SelfMemoryReportEntity?> report({bool forceGc = false}) async {
    recordedForceGc.add(forceGc);
    return _reports[_next++ % _reports.length];
  }

  @override
  Future<ProcessMemoryNodeEntity?> processMemoryTree() async => null;

  @override
  String? get lastError => null;

  @override
  Future<void> dispose() async {}
}
