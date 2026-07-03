import 'package:dart_tui/dart_tui.dart';
import 'package:frun/src/data/services/isolate_manager.dart';
import 'package:frun/src/data/services/project_detector.dart';
import 'package:frun/src/domain/entities/app_config.dart';
import 'package:frun/src/domain/entities/diagnostic.dart';
import 'package:frun/src/domain/value_objects/config_values.dart';
import 'package:frun/src/presentation/app/app_state.dart';
import 'package:frun/src/presentation/app/commands/command_registry.dart';
import 'package:frun/src/presentation/di/dependencies.dart';
import 'package:frun/src/presentation/tui/frun_app.dart';
import 'package:test/test.dart';

void main() {
  group('TUI transcript performance', () {
    test('scroll-only frames reuse wrapped transcript layout', () {
      final h = _harness();
      for (var i = 0; i < 60; i++) {
        h.state.transcript.info('line $i');
      }

      h.model.view();
      final builds = h.model.debugLayoutBuilds;
      expect(builds, greaterThan(0));

      h.wheelUp();
      h.model.view();
      expect(h.model.debugLayoutBuilds, builds);
    });

    test('forced repaint reuses visible link cache for unchanged window', () {
      final h = _harness();
      for (var i = 0; i < 20; i++) {
        h.state.transcript.info('lib/main.dart:${i + 1}:1');
      }

      h.model.view();
      final builds = h.model.debugVisibleLinkBuilds;
      expect(builds, greaterThan(0));

      for (var i = 0; i < 5; i++) {
        h.model.view();
      }
      expect(h.model.debugVisibleLinkBuilds, builds);
    });

    test('bottom-follow mode stays at bottom when output appends', () {
      final h = _harness();
      for (var i = 0; i < 30; i++) {
        h.state.transcript.info('line $i');
      }

      h.model.view();
      h.state.transcript.info('line 30');
      h.model.view();

      expect(h.model.debugTranscriptScroll, 0);
    });

    test('append while scrolled up preserves viewport anchor', () {
      final h = _harness();
      for (var i = 0; i < 30; i++) {
        h.state.transcript.info('line $i');
      }

      h.model.view();
      h.wheelUp();
      h.model.view();
      final before = h.model.debugTranscriptScroll;
      expect(before, 3);

      h.state.transcript.info('line 30');
      h.state.transcript.info('line 31');
      h.model.view();

      expect(h.model.debugTranscriptScroll, before + 2);
    });

    test('append while scrolled up stays anchored when scrollback trims', () {
      final h = _harness(scrollbackLines: 30);
      for (var i = 0; i < 30; i++) {
        h.state.transcript.info('line $i');
      }

      h.model.view();
      h.wheelUp();
      h.model.view();
      final before = h.model.debugTranscriptScroll;
      expect(before, 3);

      h.state.transcript.info('line 30');
      h.model.view();

      expect(h.model.debugTranscriptScroll, before + 1);
    });

    test('wheel bursts clamp on short transcripts', () {
      final h = _harness();
      h.state.transcript.info('only line');
      h.model.view();

      for (var i = 0; i < 100; i++) {
        h.wheelUp();
      }

      expect(h.model.debugTranscriptScroll, 0);
    });

    test('appends extend the row buffer in place without copying', () {
      final h = _harness();
      for (var i = 0; i < 60; i++) {
        h.state.transcript.info('line $i');
      }

      h.model.view();
      final identity = h.model.debugDisplayRowsBufferIdentity;
      final copies = h.model.debugRowBufferCopies;

      for (var i = 0; i < 5; i++) {
        h.state.transcript.info('extra $i');
        h.model.view();
      }

      expect(h.model.debugDisplayRowsBufferIdentity, identity);
      expect(h.model.debugRowBufferCopies, copies);
    });

    test('appends at a full ring buffer avoid survivor copies', () {
      final h = _harness(scrollbackLines: 30);
      for (var i = 0; i < 30; i++) {
        h.state.transcript.info('line $i');
      }

      h.model.view();
      final copies = h.model.debugRowBufferCopies;

      // Every append now also trims one line off the top; the head pointer
      // advances instead of copying the survivors (compaction threshold is
      // not reached within 10 appends).
      for (var i = 0; i < 10; i++) {
        h.state.transcript.info('overflow $i');
        h.model.view();
      }

      expect(h.model.debugRowBufferCopies, copies);
    });

    test('sustained trimming past compaction matches a fresh layout', () {
      final h = _harness(scrollbackLines: 30);
      for (var i = 0; i < 100; i++) {
        h.state.transcript.info('line $i');
        h.model.view();
      }

      final fresh = _harness(scrollbackLines: 30);
      for (var i = 0; i < 100; i++) {
        fresh.state.transcript.info('line $i');
      }

      expect(
        _plain(h.model.view().content),
        _plain(fresh.model.view().content),
      );
    });

    test('lowering scrollback mid-session matches a fresh layout', () {
      final h = _harness();
      for (var i = 0; i < 80; i++) {
        h.state.transcript.info('line $i');
      }
      h.model.view();

      h.state.transcript.maxLines = 25;
      h.model.view();
      h.state.transcript.info('after shrink');
      h.model.view();

      final fresh = _harness(scrollbackLines: 25);
      for (var i = 0; i < 80; i++) {
        fresh.state.transcript.info('line $i');
      }
      fresh.state.transcript.info('after shrink');

      expect(
        _plain(h.model.view().content),
        _plain(fresh.model.view().content),
      );
    });

    test('repeated searches reuse the lowercase row mirror', () {
      final h = _harness(editorMode: FrunEditorMode.vim);
      for (var i = 0; i < 40; i++) {
        h.state.transcript.info('line $i');
      }
      h.model.view();

      // Empty-input escape drops into transcript-cursor mode; `/…<enter>`
      // runs a transcript search.
      h.key(KeyCode.escape);
      h.model.view();
      h.search('line');
      h.model.view();

      final builds = h.model.debugSearchLowerBuilds;
      expect(builds, greaterThan(0));
      expect(h.model.debugSearchBuilds, greaterThan(0));

      // A different query re-matches but reuses the lowercase mirror.
      final matchBuilds = h.model.debugSearchBuilds;
      h.search('9');
      h.model.view();
      expect(h.model.debugSearchBuilds, greaterThan(matchBuilds));
      expect(h.model.debugSearchLowerBuilds, builds);

      // Appended rows only extend the mirror's tail — no full rebuild.
      h.state.transcript.info('line 40');
      h.search('40');
      h.model.view();
      expect(h.model.debugSearchLowerBuilds, builds);
    });

    test('diagnostic counters recompute once per diagnostics revision', () {
      final h = _harness();
      h.state.transcript.info('hello');
      h.state.diagnostics = const <DiagnosticEntity>[
        DiagnosticEntity(
          filePath: 'lib/a.dart',
          line: 1,
          column: 1,
          severity: DiagnosticSeverity.error,
          message: 'broken',
        ),
        DiagnosticEntity(
          filePath: 'lib/b.dart',
          line: 2,
          column: 1,
          severity: DiagnosticSeverity.warning,
          message: 'meh',
        ),
      ];

      h.model.view();
      h.model.view();
      expect(h.model.debugDiagCountsBuilds, 1);

      h.state.diagnostics = const <DiagnosticEntity>[
        DiagnosticEntity(
          filePath: 'lib/a.dart',
          line: 1,
          column: 1,
          severity: DiagnosticSeverity.error,
          message: 'broken',
        ),
      ];
      h.model.view();
      expect(h.model.debugDiagCountsBuilds, 2);
    });

    test('isolate panel renders lifecycle controls', () {
      final h = _harness(
        width: 120,
        height: 24,
        isolates: <IsolateInfo>[
          IsolateInfo(
            id: 'isolates/12345678901234567890',
            name: 'main',
            status: IsolateStatus.running,
          ),
          IsolateInfo(
            id: 'isolates/22222222222222222222',
            name: 'worker',
            status: IsolateStatus.paused,
            pauseReason: 'PauseBreakpoint',
          ),
        ],
      );
      h.state.showIsolatesPanel = true;

      final content = _plain(h.model.view().content);

      expect(content, contains('Isolates'));
      expect(content, contains('main'));
      expect(content, contains('worker'));
      expect(content, contains('pause'));
      expect(content, contains('resume'));
      expect(content, contains('step'));
      expect(content, contains('kill'));
    });

    test('isolate panel keyboard navigation and close', () {
      final h = _harness(
        isolates: <IsolateInfo>[
          IsolateInfo(id: 'a', name: 'main', status: IsolateStatus.running),
          IsolateInfo(id: 'b', name: 'worker', status: IsolateStatus.paused),
        ],
      );
      h.state.showIsolatesPanel = true;

      h.keyRune('j');
      expect(h.model.debugIsolateSelectedIndex, 1);

      h.keyRune('k');
      expect(h.model.debugIsolateSelectedIndex, 0);

      h.key(KeyCode.escape);
      expect(h.state.showIsolatesPanel, isFalse);
    });
  });
}

_Harness _harness({
  int width = 80,
  int height = 20,
  int? scrollbackLines,
  List<IsolateInfo> isolates = const <IsolateInfo>[],
  FrunEditorMode? editorMode,
}) {
  final state = AppState(
    project: FlutterProject(
      root: '.',
      name: 'test',
      workspaceRoot: '.',
      watchRoot: '.',
      hasVsCodeFolder: false,
      hasZedFolder: false,
    ),
    config: editorMode == null
        ? AppConfigEntity.defaults()
        : AppConfigEntity.defaults().copyWith(editorMode: editorMode),
    deps: Dependencies(isolateManager: IsolateManager(isolates: isolates)),
  );
  if (scrollbackLines != null) {
    state.transcript.maxLines = scrollbackLines;
  }
  final model = FrunModel(
    state: state,
    registry: CommandRegistry(),
    onQuit: () {},
  );
  model.update(WindowSizeMsg(width, height));
  return _Harness(state, model);
}

final class _Harness {
  _Harness(this.state, this.model);

  final AppState state;
  final FrunModel model;

  void wheelUp() {
    model.update(
      MouseWheelMsg(const Mouse(x: 0, y: 0, button: MouseButton.wheelUp)),
    );
  }

  void keyRune(String text) {
    model.update(KeyPressMsg(TeaKey(code: KeyCode.rune, text: text)));
  }

  void key(KeyCode code) {
    model.update(KeyPressMsg(TeaKey(code: code)));
  }

  /// Types `/pattern<enter>` — a transcript search when the model is in
  /// transcript-cursor mode (vim editor mode, empty input, after escape).
  void search(String pattern) {
    keyRune('/');
    for (final ch in pattern.split('')) {
      keyRune(ch);
    }
    key(KeyCode.enter);
  }
}

String _plain(String text) => text.replaceAll(RegExp(r'\x1B\[[0-9;]*m'), '');
