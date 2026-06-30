import 'package:dart_tui/dart_tui.dart';
import 'package:frun/src/data/services/project_detector.dart';
import 'package:frun/src/domain/entities/app_config.dart';
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
  });
}

_Harness _harness({int width = 80, int height = 20, int? scrollbackLines}) {
  final state = AppState(
    project: FlutterProject(
      root: '.',
      name: 'test',
      workspaceRoot: '.',
      watchRoot: '.',
      hasVsCodeFolder: false,
      hasZedFolder: false,
    ),
    config: AppConfigEntity.defaults(),
    deps: Dependencies(),
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
}
